import { initializeApp } from "firebase/app";
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
  type User,
} from "firebase/auth";
import firebaseConfig from "../firebase-applet-config.json";
import { hydrateErpWorkspaceCache, type ErpWorkspaceData } from "./erp";
import { runWithBrandLoader } from "./utils/brandLoaderBus";
import type {
  AccountCategory,
  AccountGroupRecord,
  AccountRecord,
  CashboxRecord,
  CurrencyCode,
  CurrencyRecord,
  InventoryItemRecord,
  LedgerEntryRecord,
  WarehouseRecord,
  WorkspaceSettings,
} from "./types";

const app = initializeApp(firebaseConfig);
// Identity-only Firebase Auth (optional Google Sign-In & per-file Google Drive token).
// All accounting, inventory, ERP, and archive data live exclusively in the server SQLite DB.
export const auth = getAuth(app);

export enum OperationType {
  CREATE = "create",
  UPDATE = "update",
  DELETE = "delete",
  LIST = "list",
  GET = "get",
  WRITE = "write",
}

export interface FirestoreErrorInfo {
  error: string;
  operationType: OperationType;
  path: string | null;
}

export function handleFirestoreError(
  error: unknown,
  _operationType: OperationType,
  _path: string | null,
): never {
  throw error instanceof Error ? error : new Error(String(error));
}

export const GOOGLE_WORKSPACE_SCOPES = [
  "https://www.googleapis.com/auth/drive.file",
] as const;

let cachedGoogleAccessToken: string | null = null;
const googleTokenListeners = new Set<(token: string | null) => void>();

function notifyGoogleTokenListeners() {
  for (const listener of googleTokenListeners) {
    listener(cachedGoogleAccessToken);
  }
}

export function getGoogleAccessToken(): string | null {
  return cachedGoogleAccessToken;
}

export function hasGoogleAccessToken(): boolean {
  return Boolean(cachedGoogleAccessToken);
}

export function clearGoogleAccessToken(): void {
  if (cachedGoogleAccessToken !== null) {
    cachedGoogleAccessToken = null;
    notifyGoogleTokenListeners();
  }
}

export function subscribeGoogleAccessToken(listener: (token: string | null) => void): () => void {
  googleTokenListeners.add(listener);
  listener(cachedGoogleAccessToken);
  return () => {
    googleTokenListeners.delete(listener);
  };
}

export function getConnectedGoogleAccountInfo(): {
  email: string | null;
  displayName: string | null;
  photoURL: string | null;
} {
  const current = auth.currentUser;
  if (!current) {
    return { email: null, displayName: null, photoURL: null };
  }
  return {
    email: current.email,
    displayName: current.displayName,
    photoURL: current.photoURL,
  };
}

function buildGoogleDriveProvider(): GoogleAuthProvider {
  const provider = new GoogleAuthProvider();
  for (const scope of GOOGLE_WORKSPACE_SCOPES) {
    provider.addScope(scope);
  }
  provider.setCustomParameters({ prompt: "select_account" });
  return provider;
}

onAuthStateChanged(auth, (user) => {
  if (!user) {
    clearGoogleAccessToken();
  }
});

export async function signInWithGoogle(): Promise<User> {
  return runWithBrandLoader("جاري تسجيل الدخول...", async () => {
    // Ordinary login only needs Google identity. Do NOT request Drive scopes here:
    // sensitive/restricted Drive permissions belong to the separate Drive flow.
    const provider = new GoogleAuthProvider();
    provider.setCustomParameters({ prompt: "select_account" });
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const result = await Promise.race([
        signInWithPopup(auth, provider),
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error("انتهت مهلة نافذة تسجيل الدخول. أغلق أي نافذة معلقة وأعد المحاولة.")),
            45_000,
          );
        }),
      ]);
      // A previously cached Drive token must never carry over to a new sign-in.
      clearGoogleAccessToken();
      return result.user;
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  });
}

export async function connectGoogleDrive(): Promise<{ user: User; accessToken: string }> {
  return runWithBrandLoader("جاري الاتصال بـ Google Drive...", async () => {
    const provider = buildGoogleDriveProvider();
    const result = await signInWithPopup(auth, provider);
    const credential = GoogleAuthProvider.credentialFromResult(result);
    const token = credential?.accessToken ?? null;
    if (!token) {
      throw new Error("لم يتم استلام رمز وصول Google Drive من نافذة المصادقة.");
    }
    cachedGoogleAccessToken = token;
    notifyGoogleTokenListeners();
    return { user: result.user, accessToken: token };
  });
}

export async function signOutUser(): Promise<void> {
  return runWithBrandLoader("جاري تسجيل الخروج...", async () => {
    clearGoogleAccessToken();
    await signOut(auth);
  });
}

export const LOCAL_WORKSPACE_UID = "local-erp-workspace";
const LOCAL_SESSION_STORAGE_KEY = "nasqo-local-session-active";

export function isLocalWorkspaceSession(): boolean {
  if (typeof window === "undefined") return false;
  try {
    return window.localStorage.getItem(LOCAL_SESSION_STORAGE_KEY) === "1";
  } catch {
    return false;
  }
}

export function setLocalWorkspaceSession(active: boolean): void {
  if (typeof window === "undefined") return;
  try {
    if (active) {
      window.localStorage.setItem(LOCAL_SESSION_STORAGE_KEY, "1");
    } else {
      window.localStorage.removeItem(LOCAL_SESSION_STORAGE_KEY);
    }
  } catch {
    // Ignore storage errors
  }
}

export type UnifiedDbImportRecord = {
  id: string;
  sourceName: string;
  sourceFormat: string;
  sourceSha256: string;
  tablesCount: number;
  totalRows: number;
  importedAt: string;
  notes?: Record<string, unknown>;
};

export type UnifiedDbStats = {
  engine: string;
  dbName: string;
  schemaVersion: number;
  tablesCount: number;
  fileSizeBytes: number;
  accountsCount: number;
  ledgerCount: number;
  invoiceLinesCount: number;
  warehousesCount: number;
  inventoryCount: number;
  archivedCount: number;
  transfersCount: number;
  offersCount: number;
  erpModulesSaved: boolean;
  lastSyncedAt: string | null;
  imports?: UnifiedDbImportRecord[];
};

export type UnifiedInvoiceLine = {
  id: number;
  lineKind: "item" | "free";
  inventoryItemId: string | null;
  itemName: string;
  sku: string;
  warehouseName: string;
  price: number;
  quantity: number;
  total: number;
  discount: number;
  bonus: number;
  unit: string;
  unitNum: number;
  details: string;
  expiryDate: string;
};

export type UnifiedInvoiceDetail = {
  entry: LedgerEntryRecord;
  lines: UnifiedInvoiceLine[];
};

export type ArchiveSummaryPayload = {
  stats: UnifiedDbStats;
  docTypeSummary: {
    docType: number;
    typeLabel: string;
    count: number;
    totalDain: number;
    totalMadin: number;
    cashSettledCount: number;
  }[];
  archivedDocs: Record<string, unknown>[];
  transfers: Record<string, unknown>[];
};

export type UnifiedTableMeta = {
  name: string;
  rowsCount: number;
  columns: { name: string; type: string; pk: boolean; nullable: boolean }[];
};

type WorkspaceBundle = {
  workspace: WorkspaceSettings;
  currencies?: CurrencyRecord[];
  accountGroups?: AccountGroupRecord[];
  accounts: AccountRecord[];
  cashboxes?: CashboxRecord[];
  ledger: LedgerEntryRecord[];
  warehouses: WarehouseRecord[];
  inventory: InventoryItemRecord[];
  erpData: ErpWorkspaceData;
  backups: { id: string; name: string; exportedAtIso: string }[];
  stats: UnifiedDbStats;
};

type WorkspaceCallbacks = {
  onWorkspace: (ws: WorkspaceSettings | null) => void;
  onCurrencies?: (currencies: CurrencyRecord[]) => void;
  onAccountGroups?: (groups: AccountGroupRecord[]) => void;
  onAccounts: (accounts: AccountRecord[]) => void;
  onLedger: (entries: LedgerEntryRecord[]) => void;
  onWarehouses: (warehouses: WarehouseRecord[]) => void;
  onInventory: (items: InventoryItemRecord[]) => void;
  onCashboxes?: (cashboxes: CashboxRecord[]) => void;
  onError?: (error: Error) => void;
};

export class UncertainWriteError extends Error {
  readonly uncertain = true;
  readonly verificationStatus: "synced" | "unreachable";
  constructor(message: string, verificationStatus: "synced" | "unreachable") {
    super(message);
    this.name = "UncertainWriteError";
    this.verificationStatus = verificationStatus;
  }
}

class ServerHttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = "ServerHttpError";
    this.status = status;
  }
}

// Always map interactive sessions to the single authoritative SQLite workspace
// so Google Sign-In and Quick Entry share the exact same single SQL database.
function effectiveUid(_uid?: string): string {
  return LOCAL_WORKSPACE_UID;
}

function apiBase(): string {
  if (typeof window === "undefined") return "/api/db";
  const baseUrl = new URL((import.meta as { env?: { BASE_URL?: string } }).env?.BASE_URL ?? "/", window.location.origin);
  return new URL("api/db", baseUrl).pathname.replace(/\/$/, "");
}

async function dbFetch<T>(
  subPath: string,
  init?: RequestInit,
  timeoutMs = 12_000,
  options?: { mutating?: boolean },
): Promise<T> {
  const method = (init?.method ?? "GET").toUpperCase();
  const isMutating = options?.mutating ?? (method !== "GET" && method !== "HEAD");
  const controller = new AbortController();
  const externalSignal = init?.signal;
  const onExternalAbort = () => controller.abort();
  if (externalSignal) {
    if (externalSignal.aborted) controller.abort();
    else externalSignal.addEventListener("abort", onExternalAbort, { once: true });
  }
  const timer = globalThis.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${apiBase()}${subPath}`, {
      ...init,
      signal: controller.signal,
      cache: "no-store",
      headers: {
        ...(typeof init?.body === "string" ? { "Content-Type": "application/json" } : {}),
        ...(init?.headers ?? {}),
      },
    });
    // Keep the AbortController active while reading the entire response stream
    // so a hung/stalled JSON body also triggers timeout cleanly.
    const rawText = await response.text();
    let payload: unknown;
    try {
      payload = rawText ? (JSON.parse(rawText) as unknown) : {};
    } catch {
      if (!response.ok) {
        const msg =
          response.status === 413
            ? "حجم ملف النسخة الاحتياطية يتجاوز الحد المسموح للطلب المباشر."
            : response.status === 404
              ? "خدمة حفظ السجلات غير متاحة حاليًا."
              : response.status === 502 || response.status === 503 || response.status === 504
                ? "الخادم مشغول حاليًا، يرجى المحاولة بعد لحظات."
                : "تعذر قراءة استجابة الخادم، يرجى إعادة المحاولة.";
        throw new ServerHttpError(response.status, msg);
      }
      throw new Error("استجابة الخادم غير صالحة.");
    }
    if (!response.ok) {
      const errMsg =
        payload && typeof payload === "object" && "error" in payload && typeof (payload as { error?: unknown }).error === "string"
          ? (payload as { error: string }).error
          : "تعذر الاتصال بخدمة حفظ السجلات.";
      throw new ServerHttpError(response.status, errMsg);
    }
    return payload as T;
  } catch (err) {
    if (err instanceof ServerHttpError) {
      throw err;
    }
    const isAbortOrNetwork =
      (err instanceof Error && err.name === "AbortError") ||
      err instanceof TypeError ||
      (err instanceof Error && /network|abort|failed to fetch|timed?out|load failed/i.test(err.message));

    if (isMutating && isAbortOrNetwork && !externalSignal?.aborted) {
      let verifiedSynced = false;
      try {
        await refreshWorkspaceFromServer(LOCAL_WORKSPACE_UID, undefined, 5_000);
        verifiedSynced = true;
      } catch {
        verifiedSynced = false;
      }
      throw new UncertainWriteError(
        verifiedSynced
          ? "النتيجة غير مؤكدة: انتهت المهلة أو انقطع الاتصال بعد إرسال العملية. تم تحديث الحالة من الخادم — تحقّق من السجل قبل إعادة المحاولة."
          : "النتيجة غير مؤكدة: انتهت مهلة الاتصال بالخادم وتعذر التحقق من إتمام العملية. تحقّق من الحالة أولًا قبل إعادة المحاولة.",
        verifiedSynced ? "synced" : "unreachable",
      );
    }

    if (err instanceof Error && err.name === "AbortError" && !externalSignal?.aborted) {
      throw new Error("انتهت مهلة الاتصال وقراءة البيانات من الخادم. يرجى إعادة المحاولة.");
    }
    throw err;
  } finally {
    globalThis.clearTimeout(timer);
    if (externalSignal) externalSignal.removeEventListener("abort", onExternalAbort);
  }
}

let activeBundle: WorkspaceBundle | null = null;
let activeBundleSignature = "";
let activeRefreshPromise: Promise<WorkspaceBundle> | null = null;
let syncTimerId: ReturnType<typeof setInterval> | null = null;
let syncWindowListenersAttached = false;
let lastBackgroundSyncAt = 0;
const workspaceListeners = new Set<WorkspaceCallbacks>();
const statsListeners = new Set<(stats: UnifiedDbStats) => void>();

function computeBundleSignature(bundle: WorkspaceBundle): string {
  return JSON.stringify({
    workspace: bundle.workspace,
    currencies: bundle.currencies ?? [],
    accountGroups: bundle.accountGroups ?? [],
    cashboxes: bundle.cashboxes ?? [],
    accounts: bundle.accounts,
    warehouses: bundle.warehouses,
    inventory: bundle.inventory,
    ledger: bundle.ledger,
    erpData: bundle.erpData,
    backups: bundle.backups,
  });
}

function applyBundle(bundle: WorkspaceBundle, forceNotify = false) {
  const nextSig = computeBundleSignature(bundle);
  const changed = forceNotify || nextSig !== activeBundleSignature || !activeBundle;
  activeBundle = bundle;
  activeBundleSignature = nextSig;
  if (!changed) {
    for (const listener of statsListeners) {
      listener(bundle.stats);
    }
    return;
  }
  hydrateErpWorkspaceCache(LOCAL_WORKSPACE_UID, bundle.erpData);
  const sortedAccounts = [...bundle.accounts].sort((a, b) => a.sortOrder - b.sortOrder || a.codeNumber - b.codeNumber);
  const sortedWarehouses = [...bundle.warehouses].sort((a, b) => a.codeNumber - b.codeNumber);
  const sortedInventory = [...bundle.inventory].sort((a, b) => a.name.localeCompare(b.name, "ar"));

  for (const cb of workspaceListeners) {
    cb.onWorkspace(bundle.workspace);
    cb.onCurrencies?.(bundle.currencies ?? []);
    cb.onAccountGroups?.(bundle.accountGroups ?? []);
    cb.onAccounts(sortedAccounts);
    cb.onLedger(bundle.ledger);
    cb.onWarehouses(sortedWarehouses);
    cb.onInventory(sortedInventory);
    cb.onCashboxes?.(bundle.cashboxes ?? []);
  }
  for (const listener of statsListeners) {
    listener(bundle.stats);
  }
}

export async function refreshWorkspaceFromServer(
  uid: string,
  displayName?: string | null,
  timeoutMs = 12_000,
): Promise<WorkspaceBundle> {
  if (activeRefreshPromise) return activeRefreshPromise;
  const targetUid = effectiveUid(uid);
  const qs = displayName ? `?displayName=${encodeURIComponent(displayName)}` : "";
  const reqPromise = dbFetch<WorkspaceBundle>(
    `/workspace/${encodeURIComponent(targetUid)}${qs}`,
    undefined,
    timeoutMs,
    { mutating: false },
  ).then((bundle) => {
    lastBackgroundSyncAt = Date.now();
    applyBundle(bundle);
    return bundle;
  });
  activeRefreshPromise = reqPromise;
  try {
    return await reqPromise;
  } finally {
    if (activeRefreshPromise === reqPromise) {
      activeRefreshPromise = null;
    }
  }
}

export async function ensureWorkspaceSeeded(uid: string, displayName?: string | null): Promise<void> {
  await refreshWorkspaceFromServer(uid, displayName);
}

const triggerCrossSessionSync = (forceCheckHidden = true) => {
  if (forceCheckHidden && typeof document !== "undefined" && document.hidden) return;
  if (workspaceListeners.size === 0) return;
  if (Date.now() - lastBackgroundSyncAt < 800) return;
  void refreshWorkspaceFromServer(LOCAL_WORKSPACE_UID).catch(() => {
    // Background refresh leaves already-loaded state intact when temporarily unreachable
  });
};

const onWindowFocusSync = () => triggerCrossSessionSync(false);
const onVisibilitySync = () => triggerCrossSessionSync(true);

function attachCrossSessionSyncListeners() {
  if (typeof window === "undefined") return;
  if (!syncWindowListenersAttached) {
    window.addEventListener("focus", onWindowFocusSync);
    if (typeof document !== "undefined") {
      document.addEventListener("visibilitychange", onVisibilitySync);
    }
    syncWindowListenersAttached = true;
  }
  if (syncTimerId === null) {
    syncTimerId = setInterval(() => {
      triggerCrossSessionSync(true);
    }, 8_000);
  }
}

function detachCrossSessionSyncListenersIfIdle() {
  if (workspaceListeners.size > 0) return;
  if (typeof window !== "undefined" && syncWindowListenersAttached) {
    window.removeEventListener("focus", onWindowFocusSync);
    if (typeof document !== "undefined") {
      document.removeEventListener("visibilitychange", onVisibilitySync);
    }
    syncWindowListenersAttached = false;
  }
  if (syncTimerId !== null) {
    clearInterval(syncTimerId);
    syncTimerId = null;
  }
}

export function subscribeWorkspace(uid: string, callbacks: WorkspaceCallbacks): () => void {
  workspaceListeners.add(callbacks);
  attachCrossSessionSyncListeners();
  if (activeBundle) {
    const snap = activeBundle;
    queueMicrotask(() => {
      if (!workspaceListeners.has(callbacks)) return;
      callbacks.onWorkspace(snap.workspace);
      callbacks.onCurrencies?.(snap.currencies ?? []);
      callbacks.onAccountGroups?.(snap.accountGroups ?? []);
      callbacks.onAccounts([...snap.accounts].sort((a, b) => a.sortOrder - b.sortOrder || a.codeNumber - b.codeNumber));
      callbacks.onLedger(snap.ledger);
      callbacks.onWarehouses([...snap.warehouses].sort((a, b) => a.codeNumber - b.codeNumber));
      callbacks.onInventory([...snap.inventory].sort((a, b) => a.name.localeCompare(b.name, "ar")));
      callbacks.onCashboxes?.(snap.cashboxes ?? []);
    });
  } else {
    void refreshWorkspaceFromServer(uid).catch((err) => {
      const normalized = err instanceof Error ? err : new Error("تعذر تحميل مساحة العمل.");
      for (const listener of workspaceListeners) {
        listener.onError?.(normalized);
      }
    });
  }
  return () => {
    workspaceListeners.delete(callbacks);
    detachCrossSessionSyncListenersIfIdle();
  };
}

export function subscribeUnifiedDbStats(listener: (stats: UnifiedDbStats) => void): () => void {
  statsListeners.add(listener);
  if (activeBundle?.stats) listener(activeBundle.stats);
  return () => {
    statsListeners.delete(listener);
  };
}

export async function getUnifiedDbStats(uid = LOCAL_WORKSPACE_UID): Promise<UnifiedDbStats> {
  return dbFetch<UnifiedDbStats>(`/status?uid=${encodeURIComponent(effectiveUid(uid))}`);
}

export async function saveWorkspaceSettings(
  uid: string,
  updates: Partial<Omit<WorkspaceSettings, "id" | "ownerId">> & WorkspaceSettings,
): Promise<void> {
  return runWithBrandLoader("جاري حفظ إعدادات النظام...", async () => {
    const { workspace } = await dbFetch<{ workspace: WorkspaceSettings }>(`/workspace/${encodeURIComponent(effectiveUid(uid))}`, {
      method: "PUT",
      body: JSON.stringify(updates),
    });
    if (activeBundle) {
      applyBundle({ ...activeBundle, workspace });
    }
  });
}

export async function saveAccountGroup(
  uid: string,
  group: { id?: number; name: string; category?: AccountCategory; currencyCode?: CurrencyCode; sortOrder?: number },
): Promise<AccountGroupRecord> {
  return runWithBrandLoader("جاري حفظ مجموعة الحسابات...", async () => {
    const { group: saved } = await dbFetch<{ group: AccountGroupRecord }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/groups`,
      {
        method: "POST",
        body: JSON.stringify({ group }),
      },
    );
    if (activeBundle) {
      const existing = activeBundle.accountGroups ?? [];
      const idx = existing.findIndex((g) => g.id === saved.id);
      const next = idx >= 0 ? existing.map((g) => (g.id === saved.id ? saved : g)) : [...existing, saved];
      applyBundle({ ...activeBundle, accountGroups: next });
    }
    return saved;
  });
}

export async function saveCurrencyRecord(
  uid: string,
  currency: {
    id?: number;
    name: string;
    symbol?: string;
    nameSecondary?: string;
    ratePrimary?: number;
    rateSecondary?: number;
  },
): Promise<CurrencyRecord[]> {
  return runWithBrandLoader("جاري حفظ بيانات العملة...", async () => {
    const { currencies } = await dbFetch<{ currency: CurrencyRecord; currencies: CurrencyRecord[] }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/currencies`,
      {
        method: "POST",
        body: JSON.stringify({ currency }),
      },
    );
    if (activeBundle) {
      applyBundle({ ...activeBundle, currencies });
    }
    return currencies;
  });
}

export async function deleteCurrencyRecord(
  uid: string,
  currencyId: number,
): Promise<CurrencyRecord[]> {
  return runWithBrandLoader("جاري حذف العملة...", async () => {
    const { currencies } = await dbFetch<{ ok: boolean; currencies: CurrencyRecord[] }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/currencies/${encodeURIComponent(String(currencyId))}`,
      {
        method: "DELETE",
      },
    );
    if (activeBundle) {
      applyBundle({ ...activeBundle, currencies });
    }
    return currencies;
  });
}

export async function createOrUpdateAccount(
  uid: string,
  account: Partial<AccountRecord> & { name: string },
  existingId?: string,
): Promise<string> {
  return runWithBrandLoader("جاري حفظ بيانات الحساب...", async () => {
    const { account: saved } = await dbFetch<{ account: AccountRecord }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/accounts`,
      {
        method: "POST",
        body: JSON.stringify({ account, existingId }),
      },
    );
    if (activeBundle) {
      const next = [...activeBundle.accounts];
      const idx = next.findIndex((a) => a.id === saved.id);
      if (idx >= 0) next[idx] = saved;
      else next.push(saved);
      applyBundle({
        ...activeBundle,
        accounts: next,
        stats: { ...activeBundle.stats, accountsCount: next.length },
      });
    }
    return saved.id;
  });
}

export async function fetchProductPriceStats(
  uid: string,
  itemId: string,
): Promise<{ minPrice: number; maxPrice: number; lastPrice: number; txCount: number }> {
  return dbFetch<{ minPrice: number; maxPrice: number; lastPrice: number; txCount: number }>(
    `/workspace/${encodeURIComponent(effectiveUid(uid))}/products/${encodeURIComponent(itemId)}/prices`,
  );
}

export async function createLedgerEntry(
  uid: string,
  entry: Partial<LedgerEntryRecord> & { accountId: string; accountName: string },
): Promise<string> {
  return runWithBrandLoader("جاري حفظ العملية المالية...", async () => {
    const { entry: saved, inventory: nextInventory } = await dbFetch<{
      entry: LedgerEntryRecord;
      inventory?: InventoryItemRecord[];
    }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/ledger`,
      {
        method: "POST",
        body: JSON.stringify({ entry }),
      },
    );
    if (activeBundle) {
      const next = [...activeBundle.ledger, saved];
      applyBundle({
        ...activeBundle,
        ledger: next,
        inventory: nextInventory ?? activeBundle.inventory,
        stats: {
          ...activeBundle.stats,
          ledgerCount: next.length,
          invoiceLinesCount:
            activeBundle.stats.invoiceLinesCount + (entry.lines?.length ?? 0),
        },
      });
    }
    return saved.id;
  });
}

export async function updateLedgerEntry(
  uid: string,
  entryId: string,
  entry: Partial<LedgerEntryRecord> & { accountId: string; accountName: string },
): Promise<LedgerEntryRecord> {
  return runWithBrandLoader("جاري تحديث العملية المالية...", async () => {
    const { entry: saved, inventory: nextInventory, invoiceLinesCount } = await dbFetch<{
      entry: LedgerEntryRecord;
      inventory?: InventoryItemRecord[];
      invoiceLinesCount?: number;
    }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/ledger/${encodeURIComponent(entryId)}`,
      {
        method: "PATCH",
        body: JSON.stringify({ entry }),
      },
    );
    if (activeBundle) {
      const next = activeBundle.ledger.map((e) => (e.id === entryId ? saved : e));
      applyBundle({
        ...activeBundle,
        ledger: next,
        inventory: nextInventory ?? activeBundle.inventory,
        stats: {
          ...activeBundle.stats,
          ...(typeof invoiceLinesCount === "number" ? { invoiceLinesCount } : {}),
        },
      });
    }
    return saved;
  });
}

export async function setLedgerDeleted(uid: string, entryId: string, deleted: boolean): Promise<void> {
  return runWithBrandLoader(deleted ? "جاري نقل السجل إلى المهملات..." : "جاري استعادة السجل...", async () => {
    const { inventory: nextInventory } = await dbFetch<{ ok: boolean; inventory?: InventoryItemRecord[] }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/ledger/${encodeURIComponent(entryId)}/deleted`,
      {
        method: "PATCH",
        body: JSON.stringify({ deleted }),
      },
    );
    if (activeBundle) {
      const next = activeBundle.ledger.map((e) => (e.id === entryId ? { ...e, deleted } : e));
      applyBundle({
        ...activeBundle,
        ledger: next,
        inventory: nextInventory ?? activeBundle.inventory,
      });
    }
  });
}

export type InventoryMovementItemRow = {
  id: string;
  code: number | null;
  name: string;
  sku: string;
  unit: string;
  unit2: string;
  count2: number | null;
  warehouseId: string;
  currencyCode?: string;
  expiryDate?: string;
  openingQty?: number;
  periodNetQty?: number;
  buyQty: number;
  sellQty: number;
  transferInQty: number;
  transferOutQty: number;
  buyTotal: number;
  sellTotal: number;
  availableQty: number;
  unitCost: number;
  remainingValue: number;
  profit: number;
  avgCost: number;
  sellingPrice?: number;
  catalogQuantity: number;
  quantityUnverified: boolean;
  hasMovement: boolean;
};

export async function fetchInventoryMovementsReport(
  uid: string,
  params?: {
    warehouseId?: string;
    itemId?: string;
    fromDate?: string;
    toDate?: string;
    currency?: string;
    profitBasis?: "avg" | "cost" | "last";
  },
): Promise<{
  warehouses: Array<{ id: string; name: string }>;
  warehouseStocks: Array<{
    inventoryItemId: string;
    warehouseId: string;
    warehouseName: string;
    purchasesQty: number;
    salesQty: number;
    salesReturnQty: number;
    purchaseReturnQty: number;
    transferInQty: number;
    transferOutQty: number;
    netComputedQty: number;
  }>;
  itemRows: InventoryMovementItemRow[];
  totals: {
    totalSales: number;
    totalPurchases: number;
    totalProfit: number;
    totalRemainingValue: number;
    activeItemsCount: number;
    profitBasis: "avg" | "cost" | "last";
  };
  totalsByCurrency?: Array<{
    currency: string;
    totalSales: number;
    totalPurchases: number;
    totalProfit: number;
    totalRemainingValue: number;
    totalRemainingQty: number;
    activeItemsCount: number;
  }>;
  movements: Array<{
    source: "invoice" | "transfer";
    refId: string;
    entryNumber?: number;
    date: string;
    label: string;
    accountName: string;
    warehouseName: string;
    quantity: number;
    unit: string;
    unitNum: number;
    baseQuantity: number;
    effectQty: number;
    price: number;
    total: number;
  }>;
  anomalies: {
    unverifiedItemsCount: number;
    unresolvedTransfersCount: number;
    unresolvedTransfers: Array<{
      id: number;
      transferDate: string;
      transferType: number;
      rawFromStoreId: number | null;
      rawToStoreId: number | null;
      details: string;
      linesCount: number;
    }>;
    negativeComputedItems: Array<{ id: string; name: string; netComputedQty: number }>;
  };
}> {
  const qs = new URLSearchParams();
  if (params?.warehouseId) qs.set("warehouseId", params.warehouseId);
  if (params?.itemId) qs.set("itemId", params.itemId);
  if (params?.fromDate) qs.set("fromDate", params.fromDate);
  if (params?.toDate) qs.set("toDate", params.toDate);
  if (params?.currency) qs.set("currency", params.currency);
  if (params?.profitBasis) qs.set("profitBasis", params.profitBasis);
  const suffix = qs.toString() ? `?${qs.toString()}` : "";
  return dbFetch(`/workspace/${encodeURIComponent(effectiveUid(uid))}/inventory/report${suffix}`);
}

export async function fetchCashboxesReport(
  uid: string,
  params?: { currency?: string; fromDate?: string; toDate?: string },
): Promise<{
  cashboxes: Array<{
    id: number;
    name: string;
    currencyCode: string;
    state?: number;
    boxType?: number;
    sortOrder?: number;
    isActive?: boolean;
    legacyId?: number;
    totalIn: number;
    totalOut: number;
    netBalance: number;
    entryCount: number;
  }>;
  reconciliation?: {
    currencyFilter: string;
    fromDate: string | null;
    toDate: string | null;
    linkedCashboxesNet: number;
    unlinkedCashIn: number;
    unlinkedCashOut: number;
    unlinkedCashNet: number;
    unlinkedCashCount: number;
    totalCashNet: number;
    activeCount: number;
    inactiveCount: number;
    totalsByCurrency?: Array<{
      currency: string;
      linkedCashboxesNet: number;
      unlinkedCashIn: number;
      unlinkedCashOut: number;
      unlinkedCashNet: number;
      unlinkedCashCount: number;
      totalCashNet: number;
    }>;
  };
}> {
  const qs = new URLSearchParams();
  if (params?.currency) qs.set("currency", params.currency);
  if (params?.fromDate) qs.set("fromDate", params.fromDate);
  if (params?.toDate) qs.set("toDate", params.toDate);
  const suffix = qs.toString() ? `?${qs.toString()}` : "";
  return dbFetch(`/workspace/${encodeURIComponent(effectiveUid(uid))}/cashboxes/report${suffix}`);
}

export async function deleteAccount(uid: string, accountId: string): Promise<void> {
  return runWithBrandLoader("جاري حذف الحساب...", async () => {
    await dbFetch<{ ok: boolean }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/accounts/${encodeURIComponent(accountId)}`,
      { method: "DELETE" },
    );
    if (activeBundle) {
      const next = activeBundle.accounts.filter((a) => a.id !== accountId);
      applyBundle({
        ...activeBundle,
        accounts: next,
        stats: { ...activeBundle.stats, accountsCount: next.length },
      });
    }
  });
}

export async function permanentlyDeleteLedger(uid: string, entryId: string): Promise<void> {
  return runWithBrandLoader("جاري حذف السجل نهائيًا...", async () => {
    const { inventory: nextInventory } = await dbFetch<{ ok: boolean; inventory?: InventoryItemRecord[] }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/ledger/${encodeURIComponent(entryId)}`,
      { method: "DELETE" },
    );
    if (activeBundle) {
      const next = activeBundle.ledger.filter((e) => e.id !== entryId);
      applyBundle({
        ...activeBundle,
        ledger: next,
        inventory: nextInventory ?? activeBundle.inventory,
        stats: { ...activeBundle.stats, ledgerCount: next.length },
      });
    }
  });
}

export async function saveWarehouse(
  uid: string,
  warehouse: Partial<WarehouseRecord> & { name: string },
  _allWarehouses: readonly WarehouseRecord[],
  existingId?: string,
): Promise<string> {
  return runWithBrandLoader("جاري حفظ بيانات المخزن...", async () => {
    const { warehouse: saved } = await dbFetch<{ warehouse: WarehouseRecord }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/warehouses`,
      {
        method: "POST",
        body: JSON.stringify({ warehouse, existingId }),
      },
    );
    if (activeBundle) {
      let next = activeBundle.warehouses.map((w) => (saved.isDefault ? { ...w, isDefault: w.id === saved.id } : w));
      const idx = next.findIndex((w) => w.id === saved.id);
      if (idx >= 0) next[idx] = saved;
      else next = [...next, saved];
      applyBundle({
        ...activeBundle,
        warehouses: next,
        stats: { ...activeBundle.stats, warehousesCount: next.length },
      });
    }
    return saved.id;
  });
}

export async function createInventoryItem(
  uid: string,
  item: Partial<InventoryItemRecord> & { name: string; warehouseId?: string },
): Promise<string> {
  return runWithBrandLoader("جاري حفظ بيانات الصنف...", async () => {
    const { item: saved } = await dbFetch<{ item: InventoryItemRecord }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/inventory`,
      {
        method: "POST",
        body: JSON.stringify({ item }),
      },
    );
    if (activeBundle) {
      const next = [...activeBundle.inventory, saved];
      applyBundle({
        ...activeBundle,
        inventory: next,
        stats: { ...activeBundle.stats, inventoryCount: next.length },
      });
    }
    return saved.id;
  });
}

export async function importInventoryItemsBatch(
  uid: string,
  items: readonly (Partial<InventoryItemRecord> & { name: string; warehouseId?: string })[],
  options?: { mode?: "upsert" | "skip"; warehouseId?: string },
): Promise<{ inserted: number; updated: number; skipped: number; total: number }> {
  return runWithBrandLoader("جاري استيراد الأصناف إلى قاعدة البيانات...", async () => {
    const res = await dbFetch<{
      inserted: number;
      updated: number;
      skipped: number;
      total: number;
      inventory: InventoryItemRecord[];
    }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/inventory/import`,
      {
        method: "POST",
        body: JSON.stringify({
          items,
          mode: options?.mode ?? "upsert",
          warehouseId: options?.warehouseId,
        }),
      },
      60_000,
    );
    if (activeBundle) {
      applyBundle({
        ...activeBundle,
        inventory: res.inventory,
        stats: { ...activeBundle.stats, inventoryCount: res.inventory.length },
      });
    }
    return {
      inserted: res.inserted,
      updated: res.updated,
      skipped: res.skipped,
      total: res.total,
    };
  });
}

export async function deleteInventoryCatalogItem(
  uid: string,
  itemId: string,
): Promise<void> {
  return runWithBrandLoader("جاري حذف الصنف...", async () => {
    await dbFetch<{ ok: boolean }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/inventory/${encodeURIComponent(itemId)}`,
      {
        method: "DELETE",
      },
    );
    if (activeBundle) {
      const next = activeBundle.inventory.filter((i) => i.id !== itemId);
      applyBundle({
        ...activeBundle,
        inventory: next,
        stats: { ...activeBundle.stats, inventoryCount: next.length },
      });
    }
  });
}

export async function updateInventoryCatalog(
  uid: string,
  itemId: string,
  item: Partial<InventoryItemRecord> & { name: string },
): Promise<InventoryItemRecord> {
  return runWithBrandLoader("جاري تحديث بطاقة الصنف...", async () => {
    const { item: saved } = await dbFetch<{ item: InventoryItemRecord }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/inventory/${encodeURIComponent(itemId)}/catalog`,
      {
        method: "PATCH",
        body: JSON.stringify({ item }),
      },
    );
    if (activeBundle) {
      applyBundle({
        ...activeBundle,
        inventory: activeBundle.inventory.map((i) => (i.id === itemId ? { ...i, ...saved } : i)),
      });
    }
    return saved;
  });
}

export async function updateInventoryItem(
  uid: string,
  itemId: string,
  item: Partial<InventoryItemRecord> & { name: string; warehouseId: string },
): Promise<void> {
  return runWithBrandLoader("جاري تحديث رصيد الصنف...", async () => {
    await dbFetch<{ ok: boolean }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/inventory/${encodeURIComponent(itemId)}`,
      {
        method: "PATCH",
        body: JSON.stringify({ item }),
      },
    );
    await refreshWorkspaceFromServer(uid);
  });
}

export async function batchUpdateInventoryItems(
  uid: string,
  updates: readonly {
    item: InventoryItemRecord;
    quantity?: number;
    avgCost?: number;
    sellingPrice?: number;
    minThreshold?: number;
    quantityUnverified?: boolean;
  }[],
): Promise<void> {
  if (!updates.length) return;
  return runWithBrandLoader("جاري تحديث حركة المخزون...", async () => {
    await dbFetch<{ ok: boolean }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/inventory/batch`,
      {
        method: "PATCH",
        body: JSON.stringify({ updates }),
      },
    );
    await refreshWorkspaceFromServer(uid);
  });
}

export async function createCloudBackupRecord(
  uid: string,
  payload: {
    name: string;
    accountsCount: number;
    ledgerCount: number;
    warehousesCount: number;
    inventoryCount: number;
    exportedAtIso: string;
  },
): Promise<string> {
  return runWithBrandLoader("جاري توثيق النسخة السحابية...", async () => {
    const { id } = await dbFetch<{ id: string }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/backups`,
      {
        method: "POST",
        body: JSON.stringify(payload),
      },
    );
    return id;
  });
}

export async function syncLocalWorkspaceToIndexedDb(
  uid: string,
  _liveData?: unknown,
): Promise<void> {
  // Unified SQLite replaces IndexedDB completely; refresh live state from server SQLite.
  return runWithBrandLoader("جاري مزامنة وتحديث البيانات...", () =>
    refreshWorkspaceFromServer(uid).then(() => undefined),
  );
}

export async function resetLocalWorkspaceDatabase(uid = LOCAL_WORKSPACE_UID): Promise<void> {
  return runWithBrandLoader("جاري تفريغ قاعدة البيانات...", async () => {
    const bundle = await dbFetch<WorkspaceBundle>(`/workspace/${encodeURIComponent(effectiveUid(uid))}/reset`, {
      method: "POST",
      body: JSON.stringify({ confirmation: "RESET:" + effectiveUid(uid) }),
    });
    applyBundle(bundle);
  });
}

export async function seedDemoWorkspace(uid = LOCAL_WORKSPACE_UID): Promise<void> {
  return runWithBrandLoader("جاري تجهيز البيانات التجريبية...", async () => {
    const { bundle } = await dbFetch<{ bundle: WorkspaceBundle }>(`/workspace/${encodeURIComponent(effectiveUid(uid))}/seed-demo`, {
      method: "POST",
    });
    applyBundle(bundle);
  });
}

export async function fetchInvoiceFromDatabase(uid: string, entryId: string): Promise<LedgerEntryRecord | null> {
  try {
    const detail = await fetchInvoiceDetailWithLines(uid, entryId);
    return detail.entry;
  } catch {
    return null;
  }
}

export async function fetchInvoiceDetailWithLines(uid: string, entryId: string): Promise<UnifiedInvoiceDetail> {
  return dbFetch<UnifiedInvoiceDetail>(
    `/workspace/${encodeURIComponent(effectiveUid(uid))}/invoices/${encodeURIComponent(entryId)}`,
  );
}

export async function fetchHistoricalInvoicesPage(
  uid: string,
  opts: { q?: string; role?: string; accountId?: string; limit?: number; offset?: number } = {},
): Promise<{ total: number; limit: number; offset: number; invoices: LedgerEntryRecord[] }> {
  const params = new URLSearchParams();
  if (opts.q) params.set("q", opts.q);
  if (opts.role) params.set("role", opts.role);
  if (opts.accountId) params.set("accountId", opts.accountId);
  if (opts.limit) params.set("limit", String(opts.limit));
  if (opts.offset !== undefined) params.set("offset", String(opts.offset));
  return dbFetch(`/workspace/${encodeURIComponent(effectiveUid(uid))}/invoices?${params.toString()}`);
}

export async function fetchAccountLegacyMoves(
  uid: string,
  accountId: string,
): Promise<{ moves: LedgerEntryRecord[]; invoicesCount: number; vouchersCount: number }> {
  return dbFetch(
    `/workspace/${encodeURIComponent(effectiveUid(uid))}/accounts/${encodeURIComponent(accountId)}/legacy-moves`,
  );
}

export async function fetchArchiveSummary(uid: string): Promise<ArchiveSummaryPayload> {
  return dbFetch<ArchiveSummaryPayload>(`/workspace/${encodeURIComponent(effectiveUid(uid))}/archive-summary`);
}

const CHUNKED_UPLOAD_THRESHOLD_BYTES = 6 * 1024 * 1024;
const RESTORE_CHUNK_BYTES = 4 * 1024 * 1024;

function decodeBase64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function uploadRestoreBytesChunked<T>(
  uid: string,
  bytes: Uint8Array,
  commitBody: Record<string, unknown>,
  mutating = true,
): Promise<T> {
  const ws = encodeURIComponent(effectiveUid(uid));
  const { uploadId } = await dbFetch<{ uploadId: string }>(
    `/workspace/${ws}/restore/upload/init`,
    { method: "POST" },
    15_000,
    { mutating: false },
  );
  for (let offset = 0; offset < bytes.byteLength; offset += RESTORE_CHUNK_BYTES) {
    const slice = bytes.subarray(offset, Math.min(bytes.byteLength, offset + RESTORE_CHUNK_BYTES));
    const chunkBody = slice.buffer.slice(slice.byteOffset, slice.byteOffset + slice.byteLength) as ArrayBuffer;
    await dbFetch<{ ok: boolean }>(
      `/workspace/${ws}/restore/upload/${encodeURIComponent(uploadId)}/chunk`,
      {
        method: "POST",
        headers: { "Content-Type": "application/octet-stream", "X-NASQO-CSRF": "1" },
        body: chunkBody,
      },
      30_000,
      { mutating: false },
    );
  }
  return dbFetch<T>(
    `/workspace/${ws}/restore/upload/${encodeURIComponent(uploadId)}/commit`,
    {
      method: "POST",
      body: JSON.stringify(commitBody),
    },
    120_000,
    { mutating },
  );
}

export async function importSmartProSqlIntoServer(
  uid: string,
  sqlText: string,
  fileName: string,
  replaceExisting = true,
) {
  return runWithBrandLoader(`جاري استيراد ${fileName}...`, async () => {
    const utf8Bytes = new TextEncoder().encode(sqlText);
    const res =
      utf8Bytes.byteLength > CHUNKED_UPLOAD_THRESHOLD_BYTES
        ? await uploadRestoreBytesChunked<{ report: Record<string, unknown>; bundle: WorkspaceBundle }>(
            uid,
            utf8Bytes,
            { kind: "sql", fileName, replaceExisting },
            true,
          )
        : await dbFetch<{ report: Record<string, unknown>; bundle: WorkspaceBundle }>(
            `/workspace/${encodeURIComponent(effectiveUid(uid))}/import/smartpro-sql`,
            {
              method: "POST",
              body: JSON.stringify({ sqlText, fileName, replaceExisting }),
            },
            120_000,
          );
    applyBundle(res.bundle);
    return res.report;
  });
}

export async function importSqliteBytesIntoServer(
  uid: string,
  bytes: Uint8Array,
  fileName: string,
  mode: "inspect" | "import" | "restore",
  groupCategories?: Record<string, AccountCategory>,
  replaceExisting?: boolean,
) {
  const label =
    mode === "inspect"
      ? `جاري فحص ${fileName}...`
      : mode === "restore"
        ? `جاري استعادة ${fileName}...`
        : `جاري استيراد ودمج ${fileName}...`;
  return runWithBrandLoader(label, async () => {
    if (bytes.byteLength > CHUNKED_UPLOAD_THRESHOLD_BYTES) {
      const res = await uploadRestoreBytesChunked<Record<string, unknown>>(
        uid,
        bytes,
        {
          kind: "sqlite",
          fileName,
          mode,
          groupCategories,
          ...(replaceExisting !== undefined ? { replaceExisting } : {}),
        },
        mode !== "inspect",
      );
      if (res.bundle) {
        applyBundle(res.bundle as WorkspaceBundle, true);
      }
      return res;
    }

    let binary = "";
    const step = 0x8000;
    for (let i = 0; i < bytes.length; i += step) {
      binary += String.fromCharCode(...bytes.subarray(i, i + step));
    }
    return importSqliteLegacyIntoServer(uid, btoa(binary), fileName, mode, groupCategories, replaceExisting);
  });
}

export async function importSqliteLegacyIntoServer(
  uid: string,
  base64: string,
  fileName: string,
  mode: "inspect" | "import" | "restore",
  groupCategories?: Record<string, AccountCategory>,
  replaceExisting?: boolean,
) {
  const label =
    mode === "inspect"
      ? `جاري فحص ${fileName}...`
      : mode === "restore"
        ? `جاري استعادة ${fileName}...`
        : `جاري استيراد ${fileName}...`;
  return runWithBrandLoader(label, async () => {
    const res =
      base64.length > Math.ceil((CHUNKED_UPLOAD_THRESHOLD_BYTES * 4) / 3)
        ? await uploadRestoreBytesChunked<Record<string, unknown>>(
            uid,
            decodeBase64ToBytes(base64),
            {
              kind: "sqlite",
              fileName,
              mode,
              groupCategories,
              ...(replaceExisting !== undefined ? { replaceExisting } : {}),
            },
            mode !== "inspect",
          )
        : await dbFetch<Record<string, unknown>>(
            `/workspace/${encodeURIComponent(effectiveUid(uid))}/import/sqlite-legacy`,
            {
              method: "POST",
              body: JSON.stringify({
                base64,
                fileName,
                mode,
                groupCategories,
                ...(replaceExisting !== undefined ? { replaceExisting } : {}),
              }),
            },
            mode === "inspect" ? 20_000 : 120_000,
            { mutating: mode !== "inspect" },
          );
    if (res.bundle) {
      applyBundle(res.bundle as WorkspaceBundle, true);
    }
    return res;
  });
}

export async function restoreJsonBackupIntoServer(
  uid: string,
  payload: Record<string, unknown>,
) {
  return runWithBrandLoader("جاري استعادة النسخة الاحتياطية...", async () => {
    const bodyStr = JSON.stringify({ payload });
    const res =
      bodyStr.length > CHUNKED_UPLOAD_THRESHOLD_BYTES
        ? await uploadRestoreBytesChunked<{ restored: Record<string, number>; bundle: WorkspaceBundle }>(
            uid,
            new TextEncoder().encode(JSON.stringify(payload)),
            { kind: "json", fileName: "backup.json" },
            true,
          )
        : await dbFetch<{ restored: Record<string, number>; bundle: WorkspaceBundle }>(
            `/workspace/${encodeURIComponent(effectiveUid(uid))}/restore/json`,
            {
              method: "POST",
              body: bodyStr,
            },
            120_000,
          );
    applyBundle(res.bundle, true);
    return res;
  });
}

export async function mergeLegacyMasterBatch(
  uid: string,
  payload: {
    accounts: readonly AccountRecord[];
    warehouses: readonly WarehouseRecord[];
    inventory: readonly InventoryItemRecord[];
  },
): Promise<{ accountsAdded: number; warehousesAdded: number; inventoryAdded: number }> {
  return runWithBrandLoader("جاري دمج الحسابات والأصناف...", async () => {
    const out = await dbFetch<{ accountsAdded: number; warehousesAdded: number; inventoryAdded: number }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/legacy/merge-master`,
      {
        method: "POST",
        body: JSON.stringify(payload),
      },
    );
    await refreshWorkspaceFromServer(uid);
    return out;
  });
}

export async function postLegacyLedgerBatch(
  uid: string,
  entries: readonly LedgerEntryRecord[],
): Promise<{ added: number; skippedDuplicates: number }> {
  return runWithBrandLoader("جاري ترحيل القيود...", async () => {
    const out = await dbFetch<{ added: number; skippedDuplicates: number }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/legacy/post-entries`,
      {
        method: "POST",
        body: JSON.stringify({ entries }),
      },
    );
    await refreshWorkspaceFromServer(uid);
    return out;
  });
}

export async function rollbackLegacyLivePrefix(
  uid: string,
  prefix: string,
): Promise<{ accountsRemoved: number; warehousesRemoved: number; inventoryRemoved: number; ledgerRemoved: number }> {
  return runWithBrandLoader("جاري التراجع عن الدفعة...", async () => {
    const out = await dbFetch<{ accountsRemoved: number; warehousesRemoved: number; inventoryRemoved: number; ledgerRemoved: number }>(
      `/workspace/${encodeURIComponent(effectiveUid(uid))}/legacy/rollback/${encodeURIComponent(prefix)}`,
      { method: "POST" },
    );
    await refreshWorkspaceFromServer(uid);
    return out;
  });
}

export async function downloadUnifiedSqliteFile(
  uid = LOCAL_WORKSPACE_UID,
  timeoutMs = 15_000,
): Promise<void> {
  return runWithBrandLoader("جاري تصدير النسخة الاحتياطية الكاملة...", async () => {
    const controller = new AbortController();
    const timer = globalThis.setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetch(
        `${apiBase()}/workspace/${encodeURIComponent(effectiveUid(uid))}/export/sqlite`,
        { signal: controller.signal, cache: "no-store" },
      );
      if (!res.ok) throw new Error("تعذر تصدير النسخة الاحتياطية الكاملة.");
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `nasqo-unified-${new Date().toISOString().slice(0, 10)}.sqlite`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (err) {
      if (err instanceof Error && err.name === "AbortError") {
        throw new Error("انتهت مهلة تحميل النسخة الاحتياطية. يرجى إعادة المحاولة.");
      }
      throw err;
    } finally {
      globalThis.clearTimeout(timer);
    }
  });
}

export async function fetchUnifiedJsonExport(uid = LOCAL_WORKSPACE_UID): Promise<unknown> {
  return runWithBrandLoader("جاري تجهيز النسخة الاحتياطية...", () =>
    dbFetch<unknown>(`/workspace/${encodeURIComponent(effectiveUid(uid))}/export/json`),
  );
}

export async function listUnifiedSqliteTables(uid = LOCAL_WORKSPACE_UID): Promise<{ tables: UnifiedTableMeta[]; stats: UnifiedDbStats }> {
  return dbFetch<{ tables: UnifiedTableMeta[]; stats: UnifiedDbStats }>(
    `/workspace/${encodeURIComponent(effectiveUid(uid))}/tables`,
  );
}

export async function queryUnifiedSqliteTable(
  uid: string,
  table: string,
  q = "",
  limit = 40,
  offset = 0,
): Promise<{ table: string; columns: string[]; total: number; rows: Record<string, unknown>[] }> {
  const params = new URLSearchParams({ q, limit: String(limit), offset: String(offset) });
  return dbFetch(`/workspace/${encodeURIComponent(effectiveUid(uid))}/tables/${encodeURIComponent(table)}?${params.toString()}`);
}
