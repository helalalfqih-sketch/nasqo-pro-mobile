import {
  createIdempotencyKey,
  HYBRID_BRIDGE_CHANNEL_NAME,
  HYBRID_PROTOCOL_VERSION,
  isAllowedHybridCommand,
  isFinancialMutationCommand,
  validateHybridInboundMessage,
  validateHybridRequestEnvelope,
  type HybridCommandAction,
  type HybridCommandPayloadMap,
  type HybridErrorPayload,
  type HybridHostEventEnvelope,
  type HybridHostEventType,
  type HybridRequestEnvelope,
  type HybridResponseEnvelope,
} from "./contracts";

export class HybridBridgeError extends Error {
  readonly code: HybridErrorPayload["code"];
  readonly retryable: boolean;

  constructor(code: HybridErrorPayload["code"], message: string, retryable = false) {
    super(message);
    this.name = "HybridBridgeError";
    this.code = code;
    this.retryable = retryable;
  }
}

export type HybridBridgeTransport = {
  postMessage: (serializedJson: string) => void;
};

declare global {
  interface Window {
    /** Existing Android WebViewCompat JavaScript bridge from Commit 0d734ca (HybridHomeView.kt). */
    NasqoHome?: {
      postMessage: (message: string) => void;
      addEventListener?: (type: "message", listener: (event: { data?: unknown }) => void) => void;
      onmessage?: ((event: { data?: unknown }) => void) | null;
    };
    NasqoFlutterBridge?: {
      postMessage: (message: string) => void;
    };
    flutter_inappwebview?: {
      callHandler: (handlerName: string, ...args: unknown[]) => unknown;
    };
    __nasqoHybridReceive?: (rawMessage: unknown) => boolean;
    __nasqoHybridReady?: boolean;
  }
}

type PendingRequest = {
  action: HybridCommandAction;
  resolve: (value: unknown) => void;
  reject: (reason: Error) => void;
  timer: ReturnType<typeof setTimeout>;
  lockKey?: string;
  retrySlot?: string;
};

type HostEventListener = (payload: unknown, envelope: HybridHostEventEnvelope) => void;

export interface InvokeOptions {
  timeoutMs?: number;
  idempotencyKey?: string;
  /** Logical operation fingerprint used to block duplicate concurrent financial writes. */
  dedupeKey?: string;
}

const DEFAULT_TIMEOUT_MS = 15_000;
const HEAVY_OPERATION_TIMEOUT_MS = 35_000;

export class NasqoHybridBridge {
  private seq = 0;
  private pending = new Map<string, PendingRequest>();
  private activeFinancialLocks = new Set<string>();
  private eventListeners = new Map<HybridHostEventType, Set<HostEventListener>>();
  private customTransport: HybridBridgeTransport | null = null;
  private boundToWindow = false;
  private boundNasqoHomeRef: Window["NasqoHome"] | null = null;
  private readOnlyFinancialMode = false;

  constructor() {
    this.bindGlobalReceiver();
  }

  bindGlobalReceiver(): void {
    if (typeof window === "undefined") return;
    if (!this.boundToWindow) {
      this.boundToWindow = true;
      window.__nasqoHybridReceive = (rawMessage: unknown) => this.handleInbound(rawMessage);
    }
    if (
      window.NasqoHome &&
      typeof window.NasqoHome.addEventListener === "function" &&
      this.boundNasqoHomeRef !== window.NasqoHome
    ) {
      this.boundNasqoHomeRef = window.NasqoHome;
      window.NasqoHome.addEventListener("message", (event) => {
        if (event && event.data !== undefined) {
          this.handleInbound(event.data);
        }
      });
    }
  }

  /**
   * Client-side UX/defense-in-depth guard only.
   * Dart MUST independently enforce command authorization, and SQLite MUST enforce
   * atomic transactions with UNIQUE(idempotency_key) to prevent duplicate posting.
   */
  setReadOnlyFinancialMode(enabled: boolean): void {
    this.readOnlyFinancialMode = enabled;
  }

  isReadOnlyFinancialMode(): boolean {
    return this.readOnlyFinancialMode;
  }

  setTransportForTesting(transport: HybridBridgeTransport | null): void {
    this.customTransport = transport;
  }

  getActiveTransportName(): "custom" | "NasqoHome" | "NasqoFlutterBridge" | "flutter_inappwebview" | "none" {
    if (this.customTransport) return "custom";
    if (typeof window === "undefined") return "none";
    if (window.NasqoHome && typeof window.NasqoHome.postMessage === "function") return "NasqoHome";
    if (window.NasqoFlutterBridge && typeof window.NasqoFlutterBridge.postMessage === "function") {
      return "NasqoFlutterBridge";
    }
    if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === "function") {
      return "flutter_inappwebview";
    }
    return "none";
  }

  hasNativeTransport(): boolean {
    return this.getActiveTransportName() !== "none";
  }

  private resolveTransport(): HybridBridgeTransport | null {
    if (this.customTransport) return this.customTransport;
    if (typeof window === "undefined") return null;
    if (window.NasqoHome && typeof window.NasqoHome.postMessage === "function") {
      this.bindGlobalReceiver();
      return {
        postMessage: (json) => window.NasqoHome!.postMessage(json),
      };
    }
    if (window.NasqoFlutterBridge && typeof window.NasqoFlutterBridge.postMessage === "function") {
      return {
        postMessage: (json) => window.NasqoFlutterBridge!.postMessage(json),
      };
    }
    if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === "function") {
      return {
        postMessage: (json) => {
          void window.flutter_inappwebview!.callHandler(HYBRID_BRIDGE_CHANNEL_NAME, json);
        },
      };
    }
    return null;
  }

  private nextRequestId(action: HybridCommandAction): string {
    this.seq += 1;
    const rand = Math.random().toString(36).slice(2, 7);
    return `req_${action}_${Date.now()}_${this.seq}_${rand}`;
  }

  isFinancialOperationInFlight(dedupeKey: string): boolean {
    return this.activeFinancialLocks.has(dedupeKey);
  }

  async invoke<A extends HybridCommandAction, R = unknown>(
    action: A,
    payload: HybridCommandPayloadMap[A],
    options: InvokeOptions = {},
  ): Promise<R> {
    if (!isAllowedHybridCommand(action)) {
      throw new HybridBridgeError("UNAUTHORIZED_ACTION", `الأمر غير مصرح به: ${String(action)}`);
    }

    const isFinancial = isFinancialMutationCommand(action);
    if (isFinancial && this.readOnlyFinancialMode) {
      throw new HybridBridgeError(
        "UNAUTHORIZED_ACTION",
        "في هذه الدفعة تبقى العمليات المالية للقراءة والعرض فقط؛ الترحيل يتم حصريًا عبر Flutter وSQLite.",
        false,
      );
    }
    const lockKey = isFinancial ? options.dedupeKey || `${action}:${JSON.stringify(payload)}` : undefined;
    if (lockKey && this.activeFinancialLocks.has(lockKey)) {
      throw new HybridBridgeError(
        "DUPLICATE_REQUEST",
        "العملية قيد التنفيذ بالفعل — تم منع تكرار الترحيل المالي.",
        false,
      );
    }

    const idempotencyKey = isFinancial
      ? options.idempotencyKey || createIdempotencyKey(action)
      : options.idempotencyKey;

    const requestId = this.nextRequestId(action);
    const envelope: HybridRequestEnvelope<A> = {
      protocolVersion: HYBRID_PROTOCOL_VERSION,
      kind: "request",
      requestId,
      action,
      payload,
      timestampMs: Date.now(),
      ...(idempotencyKey ? { idempotencyKey } : {}),
    };

    const validation = validateHybridRequestEnvelope(envelope);
    if (!validation.valid) {
      throw new HybridBridgeError("VALIDATION_ERROR", validation.reason, false);
    }

    const transport = this.resolveTransport();
    if (!transport) {
      throw new HybridBridgeError(
        "SERVICE_UNAVAILABLE",
        "جسر تطبيق Flutter غير متصل حاليًا؛ تعذر تنفيذ العملية.",
        true,
      );
    }

    const timeoutMs =
      options.timeoutMs ??
      (action === "restoreWorkspace" || action === "backupWorkspace" || action === "pickFile" || action === "importInventoryItems"
        ? HEAVY_OPERATION_TIMEOUT_MS
        : DEFAULT_TIMEOUT_MS);

    if (lockKey) {
      this.activeFinancialLocks.add(lockKey);
    }

    // Persist only the operation digest and its opaque key. A WebView restart
    // or lost reply must retry the same native transaction.
    let retrySlot: string | undefined;
    if (isFinancial && !this.customTransport && typeof window !== "undefined") {
      try {
        const canonical = JSON.stringify([action, payload], (_, value) =>
          value && typeof value === "object" && !Array.isArray(value)
            ? Object.fromEntries(Object.keys(value).sort().map(key => [key, value[key]])) : value);
        const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical)));
        retrySlot = "nasqo:pending:" + Array.from(hash, b => b.toString(16).padStart(2, "0")).join("");
        envelope.idempotencyKey = localStorage.getItem(retrySlot) || idempotencyKey;
        localStorage.setItem(retrySlot, envelope.idempotencyKey!);
      } catch {
        if (lockKey) this.activeFinancialLocks.delete(lockKey);
        throw new HybridBridgeError("SERVICE_UNAVAILABLE", "تعذر حفظ مفتاح إعادة المحاولة على الجهاز.", true);
      }
    }

    return new Promise<R>((resolve, reject) => {
      const timer = setTimeout(() => {
        const entry = this.pending.get(requestId);
        if (!entry) return;
        this.pending.delete(requestId);
        if (entry.lockKey) this.activeFinancialLocks.delete(entry.lockKey);
        reject(
          new HybridBridgeError(
            "TIMEOUT",
            "انتهت مهلة انتظار تأكيد الخدمة من تطبيق Flutter. يرجى التحقق من السجل قبل إعادة المحاولة.",
            true,
          ),
        );
      }, timeoutMs);

      this.pending.set(requestId, {
        action,
        resolve: resolve as (value: unknown) => void,
        reject,
        timer,
        lockKey,
        retrySlot,
      });

      try {
        transport.postMessage(JSON.stringify(envelope));
      } catch (err) {
        clearTimeout(timer);
        this.pending.delete(requestId);
        if (lockKey) this.activeFinancialLocks.delete(lockKey);
        reject(
          new HybridBridgeError(
            "SERVICE_UNAVAILABLE",
            err instanceof Error ? err.message : "فشل إرسال الرسالة عبر جسر Flutter.",
            true,
          ),
        );
      }
    });
  }

  /** Fire-and-forget notification for non-critical UI telemetry like route transitions. */
  notify<A extends HybridCommandAction>(action: A, payload: HybridCommandPayloadMap[A]): void {
    if (!this.hasNativeTransport()) return;
    void this.invoke(action, payload, { timeoutMs: 4000 }).catch(() => {
      // Non-blocking UI notification; ignore host unavailability
    });
  }

  handleInbound(rawMessage: unknown): boolean {
    const validated = validateHybridInboundMessage(rawMessage);
    if (!validated.valid) {
      return false;
    }

    const msg = validated.value;
    if (msg.kind === "response") {
      return this.resolveResponse(msg);
    }

    const listeners = this.eventListeners.get(msg.event);
    if (listeners) {
      for (const listener of listeners) {
        try {
          listener(msg.payload, msg);
        } catch {
          // Isolate listener errors
        }
      }
    }
    return true;
  }

  private resolveResponse(msg: HybridResponseEnvelope): boolean {
    const entry = this.pending.get(msg.requestId);
    if (!entry) return false;

    clearTimeout(entry.timer);
    this.pending.delete(msg.requestId);
    if (entry.lockKey) {
      this.activeFinancialLocks.delete(entry.lockKey);
    }

    if (entry.retrySlot && (msg.ok || msg.error?.code === "VALIDATION_ERROR" || msg.error?.code === "UNAUTHORIZED_ACTION")) {
      try { localStorage.removeItem(entry.retrySlot); } catch { /* An uncleared key still replays safely. */ }
    }
    if (msg.ok) {
      entry.resolve(msg.data);
    } else {
      const errCode = msg.error?.code ?? "INTERNAL_ERROR";
      const errMsg = msg.error?.message || "رفضت خدمة Flutter تنفيذ العملية.";
      entry.reject(new HybridBridgeError(errCode, errMsg, Boolean(msg.error?.retryable)));
    }
    return true;
  }

  onHostEvent<T = unknown>(
    event: HybridHostEventType,
    listener: (payload: T, envelope: HybridHostEventEnvelope) => void,
  ): () => void {
    let set = this.eventListeners.get(event);
    if (!set) {
      set = new Set();
      this.eventListeners.set(event, set);
    }
    const wrapped: HostEventListener = (payload, env) => listener(payload as T, env);
    set.add(wrapped);
    return () => {
      set?.delete(wrapped);
    };
  }

  resetForTesting(): void {
    for (const entry of this.pending.values()) {
      clearTimeout(entry.timer);
    }
    this.pending.clear();
    this.activeFinancialLocks.clear();
    this.eventListeners.clear();
    this.customTransport = null;
    this.readOnlyFinancialMode = false;
  }
}

export const hybridBridge = new NasqoHybridBridge();
