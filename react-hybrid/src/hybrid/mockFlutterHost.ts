import {
  HYBRID_PROTOCOL_VERSION,
  isFinancialMutationCommand,
  type HybridCommandAction,
  type HybridRequestEnvelope,
  type HybridUiPreferences,
  type HybridWorkspaceSnapshot,
} from "./contracts";
import { createHybridHomeFixtureSnapshot } from "./homeFixture";

const MOCK_PREFS_STORAGE_KEY = "nasqo-hybrid-mock-ui-prefs-v1";

export interface MockBridgeLogEntry {
  action: HybridCommandAction;
  requestId: string;
  idempotencyKey?: string;
  payload: unknown;
  timestampMs: number;
}

declare global {
  interface Window {
    __nasqoMockBridgeLog?: MockBridgeLogEntry[];
    __nasqoEmitMockHostEvent?: (event: string, payload?: unknown) => void;
  }
}

function readStoredMockPrefs(): HybridUiPreferences {
  try {
    const raw = window.sessionStorage.getItem(MOCK_PREFS_STORAGE_KEY);
    if (!raw) return { themeMode: "light" };
    return JSON.parse(raw) as HybridUiPreferences;
  } catch {
    return { themeMode: "light" };
  }
}

function writeStoredMockPrefs(prefs: HybridUiPreferences): void {
  try {
    window.sessionStorage.setItem(MOCK_PREFS_STORAGE_KEY, JSON.stringify(prefs));
  } catch {
    // Ignore storage errors in restricted contexts
  }
}

/**
 * Installs an opt-in Flutter bridge simulator ONLY when explicitly requested via `?mockFlutter=1`
 * AND no real Flutter host bridge is attached.
 *
 * Production Android WebView boots without `?mockFlutter=1` and fails honestly if Flutter is absent.
 */
export function installMockFlutterHostIfRequested(): boolean {
  if (typeof window === "undefined") return false;
  if (window.NasqoFlutterBridge || window.flutter_inappwebview) return false;

  const params = new URLSearchParams(window.location.search);
  if (params.get("mockFlutter") !== "1") return false;

  const readOnlyFinancial = params.get("allowWrites") !== "1";
  const snapshot: HybridWorkspaceSnapshot = createHybridHomeFixtureSnapshot();
  snapshot.uiPreferences = {
    ...snapshot.uiPreferences,
    ...readStoredMockPrefs(),
  };
  snapshot.capabilities = {
    ...snapshot.capabilities,
    readOnlyFinancial,
  };

  const log: MockBridgeLogEntry[] = [];
  window.__nasqoMockBridgeLog = log;
  window.__nasqoEmitMockHostEvent = (event: string, payload: unknown = {}) => {
    window.__nasqoHybridReceive?.({
      protocolVersion: HYBRID_PROTOCOL_VERSION,
      kind: "event",
      event,
      payload,
      timestampMs: Date.now(),
    });
  };

  const reply = (
    requestId: string,
    action: HybridCommandAction,
    ok: boolean,
    data?: unknown,
    error?: { code: string; message: string; retryable?: boolean },
  ) => {
    window.setTimeout(() => {
      window.__nasqoHybridReceive?.({
        protocolVersion: HYBRID_PROTOCOL_VERSION,
        kind: "response",
        requestId,
        action,
        ok,
        ...(ok ? { data } : { error }),
        timestampMs: Date.now(),
      });
    }, 10);
  };

  window.NasqoFlutterBridge = {
    postMessage: (serialized: string) => {
      const req = JSON.parse(serialized) as HybridRequestEnvelope;
      log.push({
        action: req.action,
        requestId: req.requestId,
        idempotencyKey: req.idempotencyKey,
        payload: req.payload,
        timestampMs: Date.now(),
      });

      if (readOnlyFinancial && isFinancialMutationCommand(req.action)) {
        reply(req.requestId, req.action, false, undefined, {
          code: "UNAUTHORIZED_ACTION",
          message: "الوضع المالي للقراءة فقط في محاكي الدفعة الأولى.",
        });
        return;
      }

      switch (req.action) {
        case "getSnapshot":
          reply(req.requestId, req.action, true, snapshot);
          return;
        case "saveUiPreferences": {
          const incoming = (req.payload as { preferences?: HybridUiPreferences })?.preferences ?? {};
          snapshot.uiPreferences = {
            ...snapshot.uiPreferences,
            ...incoming,
          };
          writeStoredMockPrefs(snapshot.uiPreferences);
          reply(req.requestId, req.action, true, { saved: true, uiPreferences: snapshot.uiPreferences });
          return;
        }
        case "changeCurrency": {
          const p = req.payload as { currency?: string };
          if (p.currency) snapshot.activeCurrency = p.currency;
          reply(req.requestId, req.action, true, { ok: true });
          return;
        }
        case "navigate":
        case "goBack":
        case "openInvoice":
        case "openVoucher":
        case "openAccountStatement":
        case "showMessage":
          reply(req.requestId, req.action, true, { ok: true });
          return;
        default:
          reply(req.requestId, req.action, true, { ok: true });
      }
    },
  };

  return true;
}
