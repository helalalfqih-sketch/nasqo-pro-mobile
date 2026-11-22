import {
  createEmptyErpData,
  hydrateErpWorkspaceCache,
  type ErpWorkspaceData,
} from "../erp";
import { runWithBrandLoader } from "../utils/brandLoaderBus";
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
} from "../types";
import { hybridBridge, HybridBridgeError } from "./bridge";
import {
  createIdempotencyKey,
  type HybridWorkspaceSnapshot,
} from "./contracts";
import type { User } from "./firebaseAuthStub";

export const LOCAL_WORKSPACE_UID = "local-erp-workspace";

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

export class UncertainWriteError extends Error {
  readonly uncertain = true;
  readonly verificationStatus: "synced" | "unreachable";

  constructor(message: string, verificationStatus: "synced" | "unreachable") {
    super(message);
    this.name = "UncertainWriteError";
    this.verificationStatus = verificationStatus;
  }
}

export const GOOGLE_WORKSPACE_SCOPES = [
  "https://www.googleapis.com/auth/drive.file",
] as const;

let cachedHybridUser: User = {
  uid: LOCAL_WORKSPACE_UID,
  email: "offline@nasqo.local",
  displayName: "نسقو برو — Android المحلي",
  photoURL: null,
};

export const auth = {
  get currentUser(): User | null {
    return cachedHybridUser;
  },
};

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

export function subscribeGoogleAccessToken(
  listener: (token: string | null) => void,
): () => void {
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
  return {
    email: cachedHybridUser.email ?? null,
    displayName: cachedHybridUser.displayName ?? null,
    photoURL: cachedHybridUser.photoURL ?? null,
  };
}

export async function signInWithGoogle(): Promise<User> {
  return cachedHybridUser;
}

export async function connectGoogleDrive(): Promise<{ user: User; accessToken: string }> {
  return runWithBrandLoader("جاري الاتصال بخدمة Google Drive عبر Flutter...", async () => {
    const res = await hybridBridge.invoke<
      "googleDriveAction",
      { connected?: boolean; email?: string; displayName?: string; accessToken?: string }
    >("googleDriveAction", { operation: "connect" });

    if (res?.email) {
      cachedHybridUser = {
        ...cachedHybridUser,
        email: res.email,
        displayName: res.displayName ?? cachedHybridUser.displayName,
      };
    }
    const token = res?.accessToken || (res?.connected ? "flutter-managed-drive-session" : "");
    if (!token) {
      throw new Error("خدمة Google Drive غير مفعّلة في تطبيق Flutter حاليًا.");
    }
    cachedGoogleAccessToken = token;
    notifyGoogleTokenListeners();
    return { user: cachedHybridUser, accessToken: token };
  });
}

export async function signOutUser(): Promise<void> {
  clearGoogleAccessToken();
  if (hybridBridge.hasNativeTransport()) {
    await hybridBridge
      .invoke("googleDriveAction", { operation: "disconnect" })
      .catch(() => undefined);
  }
}

export function isLocalWorkspaceSession(): boolean {
  return true;
}

export function setLocalWorkspaceSession(_active: boolean): void {
  // Always local offline workspace in Flutter Hybrid mode.
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

type WorkspaceBundle = {
  workspace: WorkspaceSettings;
  currencies: CurrencyRecord[];
  accountGroups: AccountGroupRecord[];
  accounts: AccountRecord[];
  cashboxes: CashboxRecord[];
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

let activeBundle: WorkspaceBundle | null = null;
const workspaceListeners = new Set<WorkspaceCallbacks>();
const statsListeners = new Set<(stats: UnifiedDbStats) => void>();
let snapshotEventBound = false;

function defaultWorkspaceSettings(workspaceId = LOCAL_WORKSPACE_UID): WorkspaceSettings {
  return {
    id: workspaceId,
    ownerId: workspaceId,
    companyName: "نسقو برو ERP",
    defaultCurrency: "ريال",
    whatsappProvider: "nasqo",
    whatsappInstantEnabled: false,
    whatsappPhone: "",
  };
}

function buildStatsFromSnapshot(snap: HybridWorkspaceSnapshot): UnifiedDbStats {
  return {
    engine: "Flutter Dart SQLite (Hybrid Bridge)",
    dbName: `${snap.workspaceId || LOCAL_WORKSPACE_UID}.sqlite`,
    schemaVersion: snap.snapshotVersion ?? 1,
    tablesCount: 12,
    fileSizeBytes: 0,
    accountsCount: snap.accounts.length,
    ledgerCount: snap.ledger.length,
    invoiceLinesCount: snap.ledger.reduce((acc, e) => acc + (e.lines?.length ?? 0), 0),
    warehousesCount: snap.warehouses.length,
    inventoryCount: snap.inventory.length,
    archivedCount: 0,
    transfersCount: snap.ledger.filter((e) => e.kind === "transfer").length,
    offersCount: snap.ledger.filter((e) => e.kind === "quote").length,
    erpModulesSaved: Boolean(snap.erpData),
    lastSyncedAt: new Date().toISOString(),
  };
}

function normalizeSnapshotToBundle(snap: HybridWorkspaceSnapshot): WorkspaceBundle {
  const workspace = snap.workspace ?? defaultWorkspaceSettings(snap.workspaceId);
  const erpData = snap.erpData ?? createEmptyErpData();
  if (snap.userEmail) {
    cachedHybridUser = {
      ...cachedHybridUser,
      email: snap.userEmail,
    };
  }
  return {
    workspace,
    currencies: Array.isArray(snap.currencies) ? snap.currencies : [],
    accountGroups: Array.isArray(snap.accountGroups) ? snap.accountGroups : [],
    accounts: Array.isArray(snap.accounts) ? snap.accounts : [],
    cashboxes: Array.isArray(snap.cashboxes) ? snap.cashboxes : [],
    ledger: Array.isArray(snap.ledger) ? snap.ledger : [],
    warehouses: Array.isArray(snap.warehouses) ? snap.warehouses : [],
    inventory: Array.isArray(snap.inventory) ? snap.inventory : [],
    erpData,
    backups: [],
    stats: buildStatsFromSnapshot(snap),
  };
}

function notifyAllListeners(bundle: WorkspaceBundle) {
  hydrateErpWorkspaceCache(LOCAL_WORKSPACE_UID, bundle.erpData);
  const sortedAccounts = [...bundle.accounts].sort(
    (a, b) => a.sortOrder - b.sortOrder || a.codeNumber - b.codeNumber,
  );
  const sortedWarehouses = [...bundle.warehouses].sort((a, b) => a.codeNumber - b.codeNumber);
  const sortedInventory = [...bundle.inventory].sort((a, b) => a.name.localeCompare(b.name, "ar"));

  for (const cb of workspaceListeners) {
    cb.onWorkspace(bundle.workspace);
    cb.onCurrencies?.(bundle.currencies);
    cb.onAccountGroups?.(bundle.accountGroups);
    cb.onAccounts(sortedAccounts);
    cb.onLedger(bundle.ledger);
    cb.onWarehouses(sortedWarehouses);
    cb.onInventory(sortedInventory);
    cb.onCashboxes?.(bundle.cashboxes);
  }
  for (const listener of statsListeners) {
    listener(bundle.stats);
  }
}

export function applyHybridSnapshot(snap: HybridWorkspaceSnapshot): WorkspaceBundle {
  const bundle = normalizeSnapshotToBundle(snap);
  activeBundle = bundle;
  notifyAllListeners(bundle);
  return bundle;
}

function ensureHostSnapshotSubscription() {
  if (snapshotEventBound) return;
  snapshotEventBound = true;
  hybridBridge.onHostEvent<HybridWorkspaceSnapshot>("snapshotUpdated", (payload) => {
    if (payload && typeof payload === "object" && Array.isArray(payload.accounts)) {
      applyHybridSnapshot(payload);
    }
  });
}

function maybeApplyReturnedSnapshot(result: unknown): void {
  if (!result || typeof result !== "object") return;
  const rec = result as Record<string, unknown>;
  if (rec.snapshot && typeof rec.snapshot === "object") {
    applyHybridSnapshot(rec.snapshot as HybridWorkspaceSnapshot);
  }
}

function mapBridgeError(err: unknown): Error {
  if (err instanceof HybridBridgeError) {
    if (err.code === "TIMEOUT") {
      return new UncertainWriteError(err.message, "unreachable");
    }
    return new Error(err.message);
  }
  return err instanceof Error ? err : new Error("تعذر إتمام العملية عبر خدمة Flutter.");
}

export async function refreshWorkspaceFromServer(
  uid: string = LOCAL_WORKSPACE_UID,
  _displayName?: string | null,
  timeoutMs = 15_000,
): Promise<WorkspaceBundle> {
  ensureHostSnapshotSubscription();
  try {
    const snap = await hybridBridge.invoke<"getSnapshot", HybridWorkspaceSnapshot>(
      "getSnapshot",
      { workspaceId: uid || LOCAL_WORKSPACE_UID, forceRefresh: true },
      { timeoutMs },
    );
    return applyHybridSnapshot(snap);
  } catch (err) {
    throw mapBridgeError(err);
  }
}

export async function ensureWorkspaceSeeded(
  uid: string = LOCAL_WORKSPACE_UID,
  displayName?: string | null,
): Promise<void> {
  await refreshWorkspaceFromServer(uid, displayName);
}

export function subscribeWorkspace(uid: string, callbacks: WorkspaceCallbacks): () => void {
  ensureHostSnapshotSubscription();
  workspaceListeners.add(callbacks);

  if (activeBundle) {
    const snap = activeBundle;
    queueMicrotask(() => {
      if (!workspaceListeners.has(callbacks)) return;
      callbacks.onWorkspace(snap.workspace);
      callbacks.onCurrencies?.(snap.currencies);
      callbacks.onAccountGroups?.(snap.accountGroups);
      callbacks.onAccounts(
        [...snap.accounts].sort((a, b) => a.sortOrder - b.sortOrder || a.codeNumber - b.codeNumber),
      );
      callbacks.onLedger(snap.ledger);
      callbacks.onWarehouses([...snap.warehouses].sort((a, b) => a.codeNumber - b.codeNumber));
      callbacks.onInventory([...snap.inventory].sort((a, b) => a.name.localeCompare(b.name, "ar")));
      callbacks.onCashboxes?.(snap.cashboxes);
    });
  } else {
    void refreshWorkspaceFromServer(uid).catch((err) => {
      const normalized = err instanceof Error ? err : new Error("تعذر تحميل البيانات من Flutter.");
      callbacks.onError?.(normalized);
    });
  }

  return () => {
    workspaceListeners.delete(callbacks);
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
  if (!activeBundle) {
    await refreshWorkspaceFromServer(uid);
  }
  return activeBundle!.stats;
}

export async function saveWorkspaceSettings(
  uid: string,
  updates: Partial<Omit<WorkspaceSettings, "id" | "ownerId">> & WorkspaceSettings,
): Promise<void> {
  return runWithBrandLoader("جاري حفظ إعدادات النظام...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "saveWorkspaceSettings",
        { workspace?: WorkspaceSettings; snapshot?: HybridWorkspaceSnapshot }
      >("saveWorkspaceSettings", { workspaceId: uid || LOCAL_WORKSPACE_UID, updates });
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && res?.workspace) {
        activeBundle = { ...activeBundle, workspace: res.workspace };
        notifyAllListeners(activeBundle);
      }
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function saveAccountGroup(
  uid: string,
  group: { id?: number; name: string; category?: AccountCategory; currencyCode?: CurrencyCode; sortOrder?: number },
): Promise<AccountGroupRecord> {
  return runWithBrandLoader("جاري حفظ مجموعة الحسابات...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "saveAccountGroup",
        { group: AccountGroupRecord; snapshot?: HybridWorkspaceSnapshot }
      >(
        "saveAccountGroup",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, payload: group },
        { idempotencyKey: createIdempotencyKey("saveAccountGroup", group.name) },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && res?.group) {
        const idx = activeBundle.accountGroups.findIndex((g) => g.id === res.group.id);
        const next =
          idx >= 0
            ? activeBundle.accountGroups.map((g) => (g.id === res.group.id ? res.group : g))
            : [...activeBundle.accountGroups, res.group];
        activeBundle = { ...activeBundle, accountGroups: next };
        notifyAllListeners(activeBundle);
      }
      return res.group;
    } catch (err) {
      throw mapBridgeError(err);
    }
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
    try {
      const res = await hybridBridge.invoke<
        "saveCurrency",
        { currencies: CurrencyRecord[]; snapshot?: HybridWorkspaceSnapshot }
      >(
        "saveCurrency",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, payload: currency },
        { idempotencyKey: createIdempotencyKey("saveCurrency", currency.name) },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && Array.isArray(res?.currencies)) {
        activeBundle = { ...activeBundle, currencies: res.currencies };
        notifyAllListeners(activeBundle);
      }
      return res?.currencies ?? activeBundle?.currencies ?? [];
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function deleteCurrencyRecord(
  uid: string,
  currencyId: number,
): Promise<CurrencyRecord[]> {
  return runWithBrandLoader("جاري حذف العملة...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "deleteCurrency",
        { currencies: CurrencyRecord[]; snapshot?: HybridWorkspaceSnapshot }
      >(
        "deleteCurrency",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, currencyId },
        { idempotencyKey: createIdempotencyKey("deleteCurrency", String(currencyId)) },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && Array.isArray(res?.currencies)) {
        activeBundle = { ...activeBundle, currencies: res.currencies };
        notifyAllListeners(activeBundle);
      }
      return res?.currencies ?? activeBundle?.currencies ?? [];
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function createOrUpdateAccount(
  uid: string,
  account: Partial<AccountRecord> & { name: string },
  existingId?: string,
): Promise<string> {
  return runWithBrandLoader("جاري حفظ بيانات الحساب...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "saveAccount",
        { account: AccountRecord; snapshot?: HybridWorkspaceSnapshot }
      >(
        "saveAccount",
        {
          workspaceId: uid || LOCAL_WORKSPACE_UID,
          payload: {
            ...account,
            category: account.category ?? "purchases",
            currency: account.currency ?? "ريال",
          },
          accountId: existingId,
        },
        {
          idempotencyKey: createIdempotencyKey("saveAccount", existingId || account.name),
          dedupeKey: `saveAccount:${existingId ?? "new"}:${account.name.trim()}:${account.category ?? ""}`,
        },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && res?.account) {
        const next = [...activeBundle.accounts];
        const idx = next.findIndex((a) => a.id === res.account.id);
        if (idx >= 0) next[idx] = res.account;
        else next.push(res.account);
        activeBundle = {
          ...activeBundle,
          accounts: next,
          stats: { ...activeBundle.stats, accountsCount: next.length },
        };
        notifyAllListeners(activeBundle);
      }
      return res.account.id;
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function deleteAccount(uid: string, accountId: string): Promise<void> {
  return runWithBrandLoader("جاري حذف الحساب...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "deleteAccount",
        { ok?: boolean; snapshot?: HybridWorkspaceSnapshot }
      >(
        "deleteAccount",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, accountId },
        {
          idempotencyKey: createIdempotencyKey("deleteAccount", accountId),
          dedupeKey: `deleteAccount:${accountId}`,
        },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle) {
        const next = activeBundle.accounts.filter((a) => a.id !== accountId);
        activeBundle = {
          ...activeBundle,
          accounts: next,
          stats: { ...activeBundle.stats, accountsCount: next.length },
        };
        notifyAllListeners(activeBundle);
      }
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function fetchProductPriceStats(
  uid: string,
  itemId: string,
): Promise<{ minPrice: number; maxPrice: number; lastPrice: number; txCount: number }> {
  try {
    return await hybridBridge.invoke<
      "getProductPriceStats",
      { minPrice: number; maxPrice: number; lastPrice: number; txCount: number }
    >("getProductPriceStats", { workspaceId: uid || LOCAL_WORKSPACE_UID, itemId });
  } catch (err) {
    throw mapBridgeError(err);
  }
}

export async function createLedgerEntry(
  uid: string,
  entry: Partial<LedgerEntryRecord> & { accountId: string; accountName: string },
): Promise<string> {
  return runWithBrandLoader("جاري ترحيل العملية المالية...", async () => {
    const fingerprint = [
      entry.kind ?? "voucher",
      entry.accountId,
      entry.amount ?? 0,
      entry.currency ?? "ريال",
      entry.entryDate ?? "",
      entry.documentNumber ?? "",
      entry.details ?? "",
    ].join("|");

    try {
      const res = await hybridBridge.invoke<
        "createLedgerEntry",
        {
          entry: LedgerEntryRecord;
          inventory?: InventoryItemRecord[];
          snapshot?: HybridWorkspaceSnapshot;
        }
      >(
        "createLedgerEntry",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, payload: entry },
        {
          idempotencyKey: entry.id ? `ledger_form_${entry.id}` : createIdempotencyKey("createLedgerEntry", entry.accountId),
          dedupeKey: `createLedgerEntry:${fingerprint}`,
        },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && res?.entry) {
        const next = [...activeBundle.ledger, res.entry];
        activeBundle = {
          ...activeBundle,
          ledger: next,
          inventory: res.inventory ?? activeBundle.inventory,
          stats: {
            ...activeBundle.stats,
            ledgerCount: next.length,
            invoiceLinesCount:
              activeBundle.stats.invoiceLinesCount + (entry.lines?.length ?? 0),
          },
        };
        notifyAllListeners(activeBundle);
      }
      return res.entry.id;
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function updateLedgerEntry(
  uid: string,
  entryId: string,
  entry: Partial<LedgerEntryRecord> & { accountId: string; accountName: string },
): Promise<LedgerEntryRecord> {
  return runWithBrandLoader("جاري تحديث العملية المالية...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "updateLedgerEntry",
        {
          entry: LedgerEntryRecord;
          inventory?: InventoryItemRecord[];
          snapshot?: HybridWorkspaceSnapshot;
        }
      >(
        "updateLedgerEntry",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, entryId, payload: entry },
        {
          idempotencyKey: createIdempotencyKey("updateLedgerEntry", entryId),
          dedupeKey: `updateLedgerEntry:${entryId}`,
        },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && res?.entry) {
        const next = activeBundle.ledger.map((e) => (e.id === entryId ? res.entry : e));
        activeBundle = {
          ...activeBundle,
          ledger: next,
          inventory: res.inventory ?? activeBundle.inventory,
        };
        notifyAllListeners(activeBundle);
      }
      return res.entry;
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function setLedgerDeleted(
  uid: string,
  entryId: string,
  deleted: boolean,
): Promise<void> {
  return runWithBrandLoader(
    deleted ? "جاري نقل السجل إلى المهملات..." : "جاري استعادة السجل...",
    async () => {
      try {
        const res = await hybridBridge.invoke<
          "setLedgerDeleted",
          { inventory?: InventoryItemRecord[]; snapshot?: HybridWorkspaceSnapshot }
        >(
          "setLedgerDeleted",
          { workspaceId: uid || LOCAL_WORKSPACE_UID, entryId, deleted },
          {
            idempotencyKey: createIdempotencyKey("setLedgerDeleted", entryId),
            dedupeKey: `setLedgerDeleted:${entryId}:${deleted}`,
          },
        );
        if (res?.snapshot) {
          applyHybridSnapshot(res.snapshot);
        } else if (activeBundle) {
          const next = activeBundle.ledger.map((e) =>
            e.id === entryId ? { ...e, deleted } : e,
          );
          activeBundle = {
            ...activeBundle,
            ledger: next,
            inventory: res?.inventory ?? activeBundle.inventory,
          };
          notifyAllListeners(activeBundle);
        }
      } catch (err) {
        throw mapBridgeError(err);
      }
    },
  );
}

export async function permanentlyDeleteLedger(uid: string, entryId: string): Promise<void> {
  return runWithBrandLoader("جاري حذف السجل نهائيًا...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "permanentlyDeleteLedger",
        { inventory?: InventoryItemRecord[]; snapshot?: HybridWorkspaceSnapshot }
      >(
        "permanentlyDeleteLedger",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, entryId },
        {
          idempotencyKey: createIdempotencyKey("permanentlyDeleteLedger", entryId),
          dedupeKey: `permanentlyDeleteLedger:${entryId}`,
        },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle) {
        const next = activeBundle.ledger.filter((e) => e.id !== entryId);
        activeBundle = {
          ...activeBundle,
          ledger: next,
          inventory: res?.inventory ?? activeBundle.inventory,
          stats: { ...activeBundle.stats, ledgerCount: next.length },
        };
        notifyAllListeners(activeBundle);
      }
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

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
) {
  try {
    return await hybridBridge.invoke<
      "getInventoryMovementsReport",
      {
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
      }
    >("getInventoryMovementsReport", {
      workspaceId: uid || LOCAL_WORKSPACE_UID,
      options: params,
    });
  } catch (err) {
    throw mapBridgeError(err);
  }
}

export async function fetchCashboxesReport(
  uid: string,
  params?: { currency?: string; fromDate?: string; toDate?: string },
) {
  try {
    return await hybridBridge.invoke<
      "getCashboxesReport",
      {
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
      }
    >("getCashboxesReport", {
      workspaceId: uid || LOCAL_WORKSPACE_UID,
      options: params,
    });
  } catch (err) {
    throw mapBridgeError(err);
  }
}

export async function saveWarehouse(
  uid: string,
  warehouse: Partial<WarehouseRecord> & { name: string },
  _allWarehouses: readonly WarehouseRecord[],
  existingId?: string,
): Promise<string> {
  return runWithBrandLoader("جاري حفظ بيانات المخزن...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "saveWarehouse",
        { warehouse: WarehouseRecord; snapshot?: HybridWorkspaceSnapshot }
      >(
        "saveWarehouse",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, payload: warehouse, warehouseId: existingId },
        { idempotencyKey: createIdempotencyKey("saveWarehouse", existingId || warehouse.name) },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && res?.warehouse) {
        let next = activeBundle.warehouses.map((w) =>
          res.warehouse.isDefault ? { ...w, isDefault: w.id === res.warehouse.id } : w,
        );
        const idx = next.findIndex((w) => w.id === res.warehouse.id);
        if (idx >= 0) next[idx] = res.warehouse;
        else next = [...next, res.warehouse];
        activeBundle = {
          ...activeBundle,
          warehouses: next,
          stats: { ...activeBundle.stats, warehousesCount: next.length },
        };
        notifyAllListeners(activeBundle);
      }
      return res.warehouse.id;
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function createInventoryItem(
  uid: string,
  item: Partial<InventoryItemRecord> & { name: string; warehouseId?: string },
): Promise<string> {
  return runWithBrandLoader("جاري حفظ بيانات الصنف...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "createInventoryItem",
        { item: InventoryItemRecord; snapshot?: HybridWorkspaceSnapshot }
      >(
        "createInventoryItem",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, payload: item },
        { idempotencyKey: createIdempotencyKey("createInventoryItem", item.name) },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && res?.item) {
        const next = [...activeBundle.inventory, res.item];
        activeBundle = {
          ...activeBundle,
          inventory: next,
          stats: { ...activeBundle.stats, inventoryCount: next.length },
        };
        notifyAllListeners(activeBundle);
      }
      return res.item.id;
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function importInventoryItemsBatch(
  uid: string,
  items: readonly (Partial<InventoryItemRecord> & { name: string; warehouseId?: string })[],
  options?: { mode?: "upsert" | "skip"; warehouseId?: string },
): Promise<{ inserted: number; updated: number; skipped: number; total: number }> {
  return runWithBrandLoader("جاري استيراد الأصناف عبر Flutter...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "importInventoryItems",
        {
          inserted: number;
          updated: number;
          skipped: number;
          total: number;
          inventory?: InventoryItemRecord[];
          snapshot?: HybridWorkspaceSnapshot;
        }
      >(
        "importInventoryItems",
        {
          workspaceId: uid || LOCAL_WORKSPACE_UID,
          items: items.map((item) => ({
            ...item,
            warehouseId: item.warehouseId || options?.warehouseId,
          })),
          mode: options?.mode === "skip" ? "insert-only" : "upsert",
        },
        { idempotencyKey: createIdempotencyKey("importInventoryItems", String(items.length)) },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && Array.isArray(res?.inventory)) {
        activeBundle = {
          ...activeBundle,
          inventory: res.inventory,
          stats: { ...activeBundle.stats, inventoryCount: res.inventory.length },
        };
        notifyAllListeners(activeBundle);
      }
      return {
        inserted: res.inserted ?? 0,
        updated: res.updated ?? 0,
        skipped: res.skipped ?? 0,
        total: res.total ?? items.length,
      };
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function deleteInventoryCatalogItem(uid: string, itemId: string): Promise<void> {
  return runWithBrandLoader("جاري حذف الصنف...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "deleteInventoryItem",
        { snapshot?: HybridWorkspaceSnapshot }
      >(
        "deleteInventoryItem",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, itemId },
        { idempotencyKey: createIdempotencyKey("deleteInventoryItem", itemId) },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle) {
        const next = activeBundle.inventory.filter((i) => i.id !== itemId);
        activeBundle = {
          ...activeBundle,
          inventory: next,
          stats: { ...activeBundle.stats, inventoryCount: next.length },
        };
        notifyAllListeners(activeBundle);
      }
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function updateInventoryCatalog(
  uid: string,
  itemId: string,
  item: Partial<InventoryItemRecord> & { name: string },
): Promise<InventoryItemRecord> {
  return runWithBrandLoader("جاري تحديث بطاقة الصنف...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "updateInventoryItem",
        { item: InventoryItemRecord; snapshot?: HybridWorkspaceSnapshot }
      >(
        "updateInventoryItem",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, itemId, updates: item },
        { idempotencyKey: createIdempotencyKey("updateInventoryItem", itemId) },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else if (activeBundle && res?.item) {
        activeBundle = {
          ...activeBundle,
          inventory: activeBundle.inventory.map((i) => (i.id === itemId ? { ...i, ...res.item } : i)),
        };
        notifyAllListeners(activeBundle);
      }
      return res.item;
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function updateInventoryItem(
  uid: string,
  itemId: string,
  item: Partial<InventoryItemRecord> & { name: string; warehouseId: string },
): Promise<void> {
  await updateInventoryCatalog(uid, itemId, item);
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
    try {
      const res = await hybridBridge.invoke<
        "batchUpdateInventoryItems",
        { snapshot?: HybridWorkspaceSnapshot }
      >(
        "batchUpdateInventoryItems",
        {
          workspaceId: uid || LOCAL_WORKSPACE_UID,
          updates: updates.map((u) => ({
            id: u.item.id,
            data: {
              ...(u.quantity !== undefined ? { quantity: u.quantity } : {}),
              ...(u.avgCost !== undefined ? { avgCost: u.avgCost } : {}),
              ...(u.sellingPrice !== undefined ? { sellingPrice: u.sellingPrice } : {}),
              ...(u.minThreshold !== undefined ? { minThreshold: u.minThreshold } : {}),
              ...(u.quantityUnverified !== undefined
                ? { quantityUnverified: u.quantityUnverified }
                : {}),
            },
          })),
        },
        { idempotencyKey: createIdempotencyKey("batchUpdateInventoryItems", String(updates.length)) },
      );
      maybeApplyReturnedSnapshot(res);
      if (!res?.snapshot) {
        await refreshWorkspaceFromServer(uid);
      }
    } catch (err) {
      throw mapBridgeError(err);
    }
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
  return runWithBrandLoader("جاري إنشاء النسخة الاحتياطية عبر Flutter...", async () => {
    try {
      const res = await hybridBridge.invoke<"backupWorkspace", { id?: string }>(
        "backupWorkspace",
        {
          workspaceId: uid || LOCAL_WORKSPACE_UID,
          backupName: payload.name,
          target: "cloud",
        },
      );
      return res?.id ?? `bkp_${Date.now()}`;
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function syncLocalWorkspaceToIndexedDb(
  uid: string,
  _liveData?: unknown,
): Promise<void> {
  return runWithBrandLoader("جاري تحديث البيانات من قاعدة SQLite المحلية...", () =>
    refreshWorkspaceFromServer(uid).then(() => undefined),
  );
}

export async function resetLocalWorkspaceDatabase(uid = LOCAL_WORKSPACE_UID): Promise<void> {
  return runWithBrandLoader("جاري تفريغ قاعدة البيانات المحلية...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "resetWorkspace",
        { snapshot?: HybridWorkspaceSnapshot }
      >(
        "resetWorkspace",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, mode: "empty" },
        { idempotencyKey: createIdempotencyKey("resetWorkspace", "empty") },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else {
        await refreshWorkspaceFromServer(uid);
      }
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function seedDemoWorkspace(uid = LOCAL_WORKSPACE_UID): Promise<void> {
  return runWithBrandLoader("جاري تجهيز البيانات التجريبية...", async () => {
    try {
      const res = await hybridBridge.invoke<
        "resetWorkspace",
        { snapshot?: HybridWorkspaceSnapshot }
      >(
        "resetWorkspace",
        { workspaceId: uid || LOCAL_WORKSPACE_UID, mode: "demo" },
        { idempotencyKey: createIdempotencyKey("resetWorkspace", "demo") },
      );
      if (res?.snapshot) {
        applyHybridSnapshot(res.snapshot);
      } else {
        await refreshWorkspaceFromServer(uid);
      }
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function fetchInvoiceDetailWithLines(
  uid: string,
  entryId: string,
): Promise<UnifiedInvoiceDetail> {
  try {
    return await hybridBridge.invoke<"getInvoiceDetail", UnifiedInvoiceDetail>(
      "getInvoiceDetail",
      { workspaceId: uid || LOCAL_WORKSPACE_UID, entryId },
    );
  } catch (err) {
    throw mapBridgeError(err);
  }
}

export async function fetchInvoiceFromDatabase(
  uid: string,
  entryId: string,
): Promise<LedgerEntryRecord | null> {
  try {
    const detail = await fetchInvoiceDetailWithLines(uid, entryId);
    return detail.entry;
  } catch {
    return null;
  }
}

export async function fetchHistoricalInvoicesPage(
  _uid: string,
  opts: { q?: string; role?: string; accountId?: string; limit?: number; offset?: number } = {},
): Promise<{ total: number; limit: number; offset: number; invoices: LedgerEntryRecord[] }> {
  const all = (activeBundle?.ledger ?? []).filter((e) => !e.deleted && e.kind === "invoice");
  const filtered = all.filter((e) => {
    if (opts.accountId && e.accountId !== opts.accountId) return false;
    if (opts.q) {
      const q = opts.q.trim().toLowerCase();
      if (
        !e.accountName.toLowerCase().includes(q) &&
        !(e.details || "").toLowerCase().includes(q) &&
        !String(e.entryNumber ?? "").includes(q)
      ) {
        return false;
      }
    }
    return true;
  });
  const offset = opts.offset ?? 0;
  const limit = opts.limit ?? 50;
  return {
    total: filtered.length,
    limit,
    offset,
    invoices: filtered.slice(offset, offset + limit),
  };
}

export async function fetchAccountLegacyMoves(
  _uid: string,
  accountId: string,
): Promise<{ moves: LedgerEntryRecord[]; invoicesCount: number; vouchersCount: number }> {
  const moves = (activeBundle?.ledger ?? []).filter(
    (e) => !e.deleted && e.accountId === accountId,
  );
  return {
    moves,
    invoicesCount: moves.filter((m) => m.kind === "invoice").length,
    vouchersCount: moves.filter((m) => m.kind !== "invoice").length,
  };
}

export async function fetchArchiveSummary(uid: string): Promise<ArchiveSummaryPayload> {
  const stats = await getUnifiedDbStats(uid);
  return {
    stats,
    docTypeSummary: [],
    archivedDocs: [],
    transfers: [],
  };
}

function encodeBytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const step = 0x8000;
  for (let i = 0; i < bytes.length; i += step) {
    binary += String.fromCharCode(...bytes.subarray(i, i + step));
  }
  return btoa(binary);
}

export async function importSmartProSqlIntoServer(
  uid: string,
  sqlText: string,
  fileName: string,
  _replaceExisting = true,
) {
  return runWithBrandLoader(`جاري استيراد ${fileName} عبر Flutter...`, async () => {
    try {
      const base64Content = encodeBytesToBase64(new TextEncoder().encode(sqlText));
      const res = await hybridBridge.invoke<
        "restoreWorkspace",
        { report?: Record<string, unknown>; snapshot?: HybridWorkspaceSnapshot }
      >(
        "restoreWorkspace",
        {
          workspaceId: uid || LOCAL_WORKSPACE_UID,
          fileName,
          format: "sql",
          base64Content,
        },
        { idempotencyKey: createIdempotencyKey("restoreWorkspace", fileName) },
      );
      if (res?.snapshot) applyHybridSnapshot(res.snapshot);
      return res?.report ?? { ok: true };
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function importSqliteBytesIntoServer(
  uid: string,
  bytes: Uint8Array,
  fileName: string,
  _mode: "inspect" | "import" | "restore",
  _groupCategories?: Record<string, AccountCategory>,
  _replaceExisting?: boolean,
) {
  return importSqliteLegacyIntoServer(uid, encodeBytesToBase64(bytes), fileName, _mode);
}

export async function importSqliteLegacyIntoServer(
  uid: string,
  base64: string,
  fileName: string,
  _mode: "inspect" | "import" | "restore",
  _groupCategories?: Record<string, AccountCategory>,
  _replaceExisting?: boolean,
) {
  return runWithBrandLoader(`جاري معالجة ${fileName} عبر Flutter...`, async () => {
    try {
      const res = await hybridBridge.invoke<
        "restoreWorkspace",
        Record<string, unknown> & { snapshot?: HybridWorkspaceSnapshot }
      >(
        "restoreWorkspace",
        {
          workspaceId: uid || LOCAL_WORKSPACE_UID,
          fileName,
          format: "sqlite",
          base64Content: base64,
        },
        { idempotencyKey: createIdempotencyKey("restoreWorkspace", fileName) },
      );
      if (res?.snapshot) applyHybridSnapshot(res.snapshot);
      return res;
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function restoreJsonBackupIntoServer(
  uid: string,
  payload: Record<string, unknown>,
) {
  return runWithBrandLoader("جاري استعادة النسخة الاحتياطية عبر Flutter...", async () => {
    try {
      const base64Content = encodeBytesToBase64(
        new TextEncoder().encode(JSON.stringify(payload)),
      );
      const res = await hybridBridge.invoke<
        "restoreWorkspace",
        { restored?: Record<string, number>; snapshot?: HybridWorkspaceSnapshot }
      >(
        "restoreWorkspace",
        {
          workspaceId: uid || LOCAL_WORKSPACE_UID,
          fileName: "backup.json",
          format: "json",
          base64Content,
        },
        { idempotencyKey: createIdempotencyKey("restoreWorkspace", "json") },
      );
      if (res?.snapshot) applyHybridSnapshot(res.snapshot);
      return res;
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function mergeLegacyMasterBatch(
  _uid: string,
  _payload: {
    accounts: readonly AccountRecord[];
    warehouses: readonly WarehouseRecord[];
    inventory: readonly InventoryItemRecord[];
  },
): Promise<{ accountsAdded: number; warehousesAdded: number; inventoryAdded: number }> {
  throw new Error("استيراد الدفعات التراثية يتم مباشرة من خلال خدمة الاستعادة في Flutter.");
}

export async function postLegacyLedgerBatch(
  _uid: string,
  _entries: readonly LedgerEntryRecord[],
): Promise<{ added: number; skippedDuplicates: number }> {
  throw new Error("ترحيل الدفعات التراثية يتم مباشرة من خلال خدمة الاستعادة في Flutter.");
}

export async function rollbackLegacyLivePrefix(
  _uid: string,
  _prefix: string,
): Promise<{
  accountsRemoved: number;
  warehousesRemoved: number;
  inventoryRemoved: number;
  ledgerRemoved: number;
}> {
  throw new Error("التراجع عن الدفعات التراثية يتم من خلال خدمة الاستعادة في Flutter.");
}

export async function downloadUnifiedSqliteFile(uid = LOCAL_WORKSPACE_UID): Promise<void> {
  return runWithBrandLoader("جاري تصدير النسخة الاحتياطية المحلية عبر Flutter...", async () => {
    try {
      await hybridBridge.invoke("backupWorkspace", {
        workspaceId: uid || LOCAL_WORKSPACE_UID,
        backupName: `nasqo-unified-${new Date().toISOString().slice(0, 10)}.sqlite`,
        target: "local",
      });
    } catch (err) {
      throw mapBridgeError(err);
    }
  });
}

export async function fetchUnifiedJsonExport(uid = LOCAL_WORKSPACE_UID): Promise<unknown> {
  if (!activeBundle) {
    await refreshWorkspaceFromServer(uid);
  }
  return {
    exportedAtIso: new Date().toISOString(),
    workspace: activeBundle?.workspace,
    currencies: activeBundle?.currencies ?? [],
    accountGroups: activeBundle?.accountGroups ?? [],
    accounts: activeBundle?.accounts ?? [],
    cashboxes: activeBundle?.cashboxes ?? [],
    ledger: activeBundle?.ledger ?? [],
    warehouses: activeBundle?.warehouses ?? [],
    inventory: activeBundle?.inventory ?? [],
    erpData: activeBundle?.erpData ?? createEmptyErpData(),
  };
}

export async function listUnifiedSqliteTables(
  uid = LOCAL_WORKSPACE_UID,
): Promise<{ tables: UnifiedTableMeta[]; stats: UnifiedDbStats }> {
  const stats = await getUnifiedDbStats(uid);
  return { tables: [], stats };
}

export async function queryUnifiedSqliteTable(
  _uid: string,
  table: string,
): Promise<{ table: string; columns: string[]; total: number; rows: Record<string, unknown>[] }> {
  return { table, columns: [], total: 0, rows: [] };
}


// QA website-backup import uses the Android file picker. File bytes and the
// scratch SQLite never cross the WebView bridge.
export type NativeWebsiteBackupPreview = {
  cancelled?: boolean;
  fileName?: string;
  bytes?: number;
  format?: "JSON" | "SQLite";
  sourceVersion?: number;
  sourceSha256?: string;
  integrity?: string;
  previewToken?: string;
  restorable?: boolean;
  reason?: string;
  counts?: Record<string, number>;
  unsupportedRecords?: Record<string, number>;
  trial?: Record<string, unknown>;
};

export async function pickNativeWebsiteBackup(uid = LOCAL_WORKSPACE_UID): Promise<NativeWebsiteBackupPreview> {
  return hybridBridge.invoke<"pickFile", NativeWebsiteBackupPreview>("pickFile",
    { workspaceId: uid, purpose: "restore-backup" }, {timeoutMs: 120000});
}

export async function restoreNativeWebsiteBackup(
  uid: string, previewToken: string,
): Promise<{restored?: boolean; cancelled?: boolean; replayed?: boolean; snapshot?: HybridWorkspaceSnapshot}> {
  const result = await hybridBridge.invoke<"restoreWorkspace", {
    restored?: boolean; cancelled?: boolean; replayed?: boolean;
    snapshot?: HybridWorkspaceSnapshot
  }>("restoreWorkspace", {
    workspaceId: uid || LOCAL_WORKSPACE_UID,
    previewToken,
  }, {idempotencyKey: createIdempotencyKey("restoreWorkspace", previewToken), timeoutMs: 120000});
  if (result?.snapshot) applyHybridSnapshot(result.snapshot);
  return result;
}
