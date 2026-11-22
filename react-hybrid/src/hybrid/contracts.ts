import type {
  AccountCategory,
  AccountGroupRecord,
  AccountRecord,
  CashboxRecord,
  CurrencyRecord,
  InventoryItemRecord,
  InvoiceLineInput,
  LedgerEntryRecord,
  WarehouseRecord,
  WorkspaceSettings,
} from "../types";
import type { ErpWorkspaceData } from "../erp";
import type { ExtendedAppSettings } from "../utils/appSettings";
import type {
  DashboardWidgetId,
  HomeMetricId,
  HomeTileLayout,
  PinnedFavoriteItem,
} from "../utils/dashboardPrefs";
import type { ThemeMode } from "../utils/theme";

export const HYBRID_PROTOCOL_VERSION = "1.0.0" as const;

export const HYBRID_BRIDGE_CHANNEL_NAME = "NasqoFlutterBridge" as const;

/**
 * Strict allowlist of commands React is permitted to dispatch to Flutter.
 * Direct SQL execution, shell commands, arbitrary filesystem paths, and secret reads
 * are explicitly forbidden and rejected at runtime before crossing the bridge.
 */
export const HYBRID_ALLOWED_COMMANDS = [
  // Core navigation, UI preferences, and native device actions
  "navigate",
  "goBack",
  "openLegacyRecovery",
  "getSnapshot",
  "changeCurrency",
  "saveUiPreferences",
  "openInvoice",
  "openVoucher",
  "openAccountStatement",
  "printDocument",
  "exportPdf",
  "pickFile",
  "showMessage",
  // Accounting, accounts, inventory, and reports (persisted exclusively by Dart/SQLite)
  "saveWorkspaceSettings",
  "saveAccountGroup",
  "saveCurrency",
  "deleteCurrency",
  "saveAccount",
  "deleteAccount",
  "createLedgerEntry",
  "updateLedgerEntry",
  "setLedgerDeleted",
  "permanentlyDeleteLedger",
  "saveWarehouse",
  "createInventoryItem",
  "updateInventoryItem",
  "deleteInventoryItem",
  "importInventoryItems",
  "batchUpdateInventoryItems",
  "getInventoryMovementsReport",
  "getCashboxesReport",
  "getInvoiceDetail",
  "getProductPriceStats",
  "saveErpData",
  "backupWorkspace",
  "restoreWorkspace",
  "resetWorkspace",
  "googleDriveAction",
] as const;

export type HybridCommandAction = (typeof HYBRID_ALLOWED_COMMANDS)[number];

const ALLOWED_COMMAND_SET = new Set<string>(HYBRID_ALLOWED_COMMANDS);

/**
 * Commands that mutate financial/accounting state and require an idempotencyKey
 * plus duplicate in-flight submission protection.
 */
export const FINANCIAL_MUTATION_COMMANDS: ReadonlySet<HybridCommandAction> = new Set([
  "createLedgerEntry",
  "updateLedgerEntry",
  "setLedgerDeleted",
  "permanentlyDeleteLedger",
  "saveAccount",
  "deleteAccount",
  "saveAccountGroup",
  "saveCurrency",
  "deleteCurrency",
  "saveWarehouse",
  "createInventoryItem",
  "updateInventoryItem",
  "deleteInventoryItem",
  "importInventoryItems",
  "batchUpdateInventoryItems",
  "restoreWorkspace",
  "resetWorkspace",
]);

/**
 * Host-initiated events pushed from Flutter into React WebView.
 */
export const HYBRID_HOST_EVENTS = [
  "snapshotUpdated",
  "routeChanged",
  "backPressed",
  "themeChanged",
  "currencyChanged",
  "uiPreferencesUpdated",
  "serviceError",
] as const;

export type HybridHostEventType = (typeof HYBRID_HOST_EVENTS)[number];

const ALLOWED_HOST_EVENT_SET = new Set<string>(HYBRID_HOST_EVENTS);

/**
 * Forbidden payload keys that indicate attempted SQL or OS command injection.
 */
const FORBIDDEN_PAYLOAD_KEYS = new Set([
  "sql",
  "rawSql",
  "execSql",
  "sqliteQuery",
  "shellCommand",
  "commandLine",
  "evalCode",
  "__proto__",
  "constructor",
  "prototype",
]);

export interface HybridUiPreferences {
  themeMode?: ThemeMode;
  brandColor?: string;
  extendedSettings?: Partial<ExtendedAppSettings>;
  homeTileLayout?: HomeTileLayout;
  homeMetricOrder?: HomeMetricId[];
  widgetOrder?: DashboardWidgetId[];
  favorites?: PinnedFavoriteItem[];
  hapticsEnabled?: boolean;
  readNotifIds?: string[];
  dismissedNotifIds?: string[];
  lastBackupIso?: string | null;
}

export interface HybridCapabilities {
  offlineReady: boolean;
  printingSupported: boolean;
  pdfExportSupported: boolean;
  filePickerSupported: boolean;
  googleDriveConfigured: boolean;
  whatsappShareSupported: boolean;
  /** When true (Batch 1 Home delivery), financial write commands from JS are blocked. */
  readOnlyFinancial?: boolean;
}

export interface HybridWorkspaceSnapshot {
  workspaceId: string;
  userEmail?: string;
  workspace: WorkspaceSettings | null;
  currencies: CurrencyRecord[];
  accountGroups: AccountGroupRecord[];
  accounts: AccountRecord[];
  cashboxes: CashboxRecord[];
  ledger: LedgerEntryRecord[];
  warehouses: WarehouseRecord[];
  inventory: InventoryItemRecord[];
  erpData?: ErpWorkspaceData;
  uiPreferences?: HybridUiPreferences;
  capabilities?: Partial<HybridCapabilities>;
  activeRoute?: string;
  activeCurrency?: string;
  snapshotVersion?: number;
}

export interface HybridPrintPayload {
  title: string;
  kind: "statement" | "invoice" | "inventory" | "purchases" | "trial-balance" | "report";
  accountId?: string;
  entryId?: string;
  allCurrencies?: boolean;
  htmlSnapshot?: string;
}

export interface HybridExportPdfPayload {
  filename: string;
  title: string;
  kind: "statement" | "invoice" | "inventory" | "purchases" | "trial-balance" | "report";
  accountId?: string;
  entryId?: string;
  allCurrencies?: boolean;
  base64Pdf?: string;
}

export interface HybridPickFileRequest {
  purpose: "restore-backup" | "import-items" | "import-accounts-csv" | "company-logo";
  accept: string[];
}

export interface HybridPickFileResult {
  cancelled?: boolean;
  fileName: string;
  mimeType: string;
  sizeBytes: number;
  base64Content: string;
}

export interface HybridCommandPayloadMap {
  navigate: { route: string; params?: Record<string, string | number | boolean | undefined> };
  openLegacyRecovery: Record<string, never>;
  goBack: { currentRoute?: string; stackDepth?: number };
  getSnapshot: { workspaceId?: string; forceRefresh?: boolean };
  changeCurrency: { scope: "dashboard" | "category" | "statement" | "report"; targetId?: string; currency: string };
  saveUiPreferences: { preferences: HybridUiPreferences };
  openInvoice: {
    intent: "invoice" | "return" | "quote" | "order";
    accountId?: string;
    entryId?: string;
    kindOverride?: "purchase" | "sale";
  };
  openVoucher: { accountId?: string; entryId?: string };
  openAccountStatement: { accountId: string; currency?: string };
  printDocument: HybridPrintPayload;
  exportPdf: HybridExportPdfPayload;
  pickFile: HybridPickFileRequest;
  showMessage: { message: string; level?: "info" | "success" | "warning" | "error" };
  saveWorkspaceSettings: { workspaceId: string; updates: Partial<WorkspaceSettings> };
  saveAccountGroup: { workspaceId: string; payload: Partial<AccountGroupRecord> & { name: string } };
  saveCurrency: { workspaceId: string; payload: Partial<CurrencyRecord> & { name: string } };
  deleteCurrency: { workspaceId: string; currencyId: number };
  saveAccount: {
    workspaceId: string;
    payload: Partial<AccountRecord> & { name: string; category: AccountCategory; currency: string };
    accountId?: string;
  };
  deleteAccount: { workspaceId: string; accountId: string };
  createLedgerEntry: {
    workspaceId: string;
    payload: Partial<LedgerEntryRecord> & { accountId: string; accountName: string; lines?: InvoiceLineInput[] };
  };
  updateLedgerEntry: {
    workspaceId: string;
    entryId: string;
    payload: Partial<LedgerEntryRecord> & { accountId: string; accountName: string };
  };
  setLedgerDeleted: { workspaceId: string; entryId: string; deleted: boolean };
  permanentlyDeleteLedger: { workspaceId: string; entryId: string };
  saveWarehouse: { workspaceId: string; payload: Partial<WarehouseRecord> & { name: string }; warehouseId?: string };
  createInventoryItem: { workspaceId: string; payload: Partial<InventoryItemRecord> & { name: string } };
  updateInventoryItem: { workspaceId: string; itemId: string; updates: Partial<InventoryItemRecord> };
  deleteInventoryItem: { workspaceId: string; itemId: string };
  importInventoryItems: {
    workspaceId: string;
    items: Array<Partial<InventoryItemRecord> & { name: string }>;
    mode?: "upsert" | "insert-only";
  };
  batchUpdateInventoryItems: {
    workspaceId: string;
    updates: Array<{ id: string; data: Partial<InventoryItemRecord> }>;
  };
  getInventoryMovementsReport: {
    workspaceId: string;
    options?: {
      warehouseId?: string;
      currency?: string;
      search?: string;
      fromDate?: string;
      toDate?: string;
      profitBasis?: "avg" | "cost" | "last";
      itemId?: string;
    };
  };
  getCashboxesReport: {
    workspaceId: string;
    options?: { currency?: string; fromDate?: string; toDate?: string; includeInactive?: boolean };
  };
  getInvoiceDetail: { workspaceId: string; entryId: string };
  getProductPriceStats: { workspaceId: string; itemId: string };
  saveErpData: { workspaceId: string; data: ErpWorkspaceData };
  backupWorkspace: { workspaceId: string; backupName?: string; target: "local" | "cloud" };
  restoreWorkspace: { workspaceId: string; fileName: string; format: "json" | "sqlite" | "sql"; base64Content: string };
  resetWorkspace: { workspaceId: string; mode: "empty" | "demo" };
  googleDriveAction: { operation: string; args?: Record<string, unknown> };
}

export interface HybridRequestEnvelope<A extends HybridCommandAction = HybridCommandAction> {
  protocolVersion: typeof HYBRID_PROTOCOL_VERSION;
  kind: "request";
  requestId: string;
  action: A;
  payload: HybridCommandPayloadMap[A];
  timestampMs: number;
  idempotencyKey?: string;
}

export interface HybridErrorPayload {
  code:
    | "INVALID_REQUEST"
    | "UNAUTHORIZED_ACTION"
    | "VALIDATION_ERROR"
    | "DUPLICATE_REQUEST"
    | "NOT_FOUND"
    | "SERVICE_UNAVAILABLE"
    | "TIMEOUT"
    | "INTERNAL_ERROR";
  message: string;
  retryable?: boolean;
  details?: Record<string, unknown>;
}

export interface HybridResponseEnvelope<T = unknown> {
  protocolVersion: typeof HYBRID_PROTOCOL_VERSION;
  kind: "response";
  requestId: string;
  action?: HybridCommandAction;
  ok: boolean;
  data?: T;
  error?: HybridErrorPayload;
  timestampMs?: number;
}

export interface HybridHostEventEnvelope<T = unknown> {
  protocolVersion: typeof HYBRID_PROTOCOL_VERSION;
  kind: "event";
  event: HybridHostEventType;
  payload: T;
  timestampMs?: number;
}

export type HybridInboundMessage = HybridResponseEnvelope | HybridHostEventEnvelope;

export function isAllowedHybridCommand(action: unknown): action is HybridCommandAction {
  return typeof action === "string" && ALLOWED_COMMAND_SET.has(action);
}

export function isFinancialMutationCommand(action: HybridCommandAction): boolean {
  return FINANCIAL_MUTATION_COMMANDS.has(action);
}

export function isAllowedHostEvent(event: unknown): event is HybridHostEventType {
  return typeof event === "string" && ALLOWED_HOST_EVENT_SET.has(event);
}

function containsForbiddenKeys(value: unknown, depth = 0): string | null {
  if (depth > 8 || value === null || typeof value !== "object") return null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const hit = containsForbiddenKeys(item, depth + 1);
      if (hit) return hit;
    }
    return null;
  }
  for (const key of Object.keys(value as Record<string, unknown>)) {
    if (FORBIDDEN_PAYLOAD_KEYS.has(key)) return key;
    const hit = containsForbiddenKeys((value as Record<string, unknown>)[key], depth + 1);
    if (hit) return hit;
  }
  return null;
}

export function validateHybridRequestEnvelope(
  envelope: unknown,
): { valid: true; value: HybridRequestEnvelope } | { valid: false; reason: string } {
  if (!envelope || typeof envelope !== "object" || Array.isArray(envelope)) {
    return { valid: false, reason: "الرسالة يجب أن تكون كائن JSON صالحًا." };
  }
  const rec = envelope as Record<string, unknown>;
  if (rec.protocolVersion !== HYBRID_PROTOCOL_VERSION) {
    return { valid: false, reason: `إصدار البروتوكول غير مدعوم: ${String(rec.protocolVersion)}` };
  }
  if (rec.kind !== "request") {
    return { valid: false, reason: "نوع الرسالة الصادرة يجب أن يكون request." };
  }
  if (typeof rec.requestId !== "string" || rec.requestId.trim().length < 4 || rec.requestId.length > 128) {
    return { valid: false, reason: "معرف الطلب (requestId) غير صالح." };
  }
  if (!isAllowedHybridCommand(rec.action)) {
    return { valid: false, reason: `الأمر غير مسموح به في الجسر: ${String(rec.action)}` };
  }
  if (!rec.payload || typeof rec.payload !== "object" || Array.isArray(rec.payload)) {
    return { valid: false, reason: "بيانات الطلب (payload) يجب أن تكون كائنًا." };
  }
  const forbiddenKey = containsForbiddenKeys(rec.payload);
  if (forbiddenKey) {
    return { valid: false, reason: `تم حظر حقل غير مسموح به أمنيًا: ${forbiddenKey}` };
  }
  if (isFinancialMutationCommand(rec.action)) {
    if (typeof rec.idempotencyKey !== "string" || rec.idempotencyKey.trim().length < 6) {
      return { valid: false, reason: "العمليات المالية تتطلب مفتاح عدم التكرار (idempotencyKey)." };
    }
  }
  return { valid: true, value: rec as unknown as HybridRequestEnvelope };
}

export function validateHybridInboundMessage(
  raw: unknown,
): { valid: true; value: HybridInboundMessage } | { valid: false; reason: string } {
  let parsed: unknown = raw;
  if (typeof raw === "string") {
    try {
      parsed = JSON.parse(raw);
    } catch {
      return { valid: false, reason: "تعذر قراءة JSON الوارد من Flutter." };
    }
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { valid: false, reason: "الرسالة الواردة ليست كائنًا صالحًا." };
  }
  const rec = parsed as Record<string, unknown>;
  if (rec.protocolVersion !== HYBRID_PROTOCOL_VERSION) {
    return { valid: false, reason: `إصدار بروتوكول غير متوافق: ${String(rec.protocolVersion)}` };
  }
  if (rec.kind === "response") {
    if (typeof rec.requestId !== "string" || !rec.requestId.trim()) {
      return { valid: false, reason: "الرد يفتقد requestId." };
    }
    if (typeof rec.ok !== "boolean") {
      return { valid: false, reason: "الرد يفتقد حقل ok المنطقي." };
    }
    return { valid: true, value: rec as unknown as HybridResponseEnvelope };
  }
  if (rec.kind === "event") {
    if (!isAllowedHostEvent(rec.event)) {
      return { valid: false, reason: `حدث غير مسموح به من المضيف: ${String(rec.event)}` };
    }
    return { valid: true, value: rec as unknown as HybridHostEventEnvelope };
  }
  return { valid: false, reason: "نوع الرسالة الواردة غير معروف." };
}

export function validateHybridSnapshot(
  raw: unknown,
): { valid: true; value: HybridWorkspaceSnapshot } | { valid: false; reason: string } {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { valid: false, reason: "لقطة البيانات الواردة من Flutter ليست كائن JSON صالحًا." };
  }
  const rec = raw as Record<string, unknown>;
  if (typeof rec.workspaceId !== "string" || !rec.workspaceId.trim()) {
    return { valid: false, reason: "لقطة البيانات تفتقد معرف مساحة العمل (workspaceId)." };
  }
  const requiredArrays = [
    "currencies",
    "accountGroups",
    "accounts",
    "cashboxes",
    "ledger",
    "warehouses",
    "inventory",
  ] as const;
  for (const field of requiredArrays) {
    if (!Array.isArray(rec[field])) {
      return { valid: false, reason: `الحقل الإلزامي (${field}) في لقطة البيانات يجب أن يكون مصفوفة.` };
    }
  }
  if (rec.workspace !== null && rec.workspace !== undefined && typeof rec.workspace !== "object") {
    return { valid: false, reason: "بيانات المنشأة (workspace) غير صالحة." };
  }
  const forbidden = containsForbiddenKeys(rec);
  if (forbidden) {
    return { valid: false, reason: `تم رفض لقطة البيانات لاحتوائها على حقل غير مسموح به: ${forbidden}` };
  }
  return { valid: true, value: rec as unknown as HybridWorkspaceSnapshot };
}

let idempotencyCounter = 0;

export function createIdempotencyKey(action: HybridCommandAction, hint = ""): string {
  idempotencyCounter += 1;
  const cleanHint = hint.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 24);
  const rand = Math.random().toString(36).slice(2, 8);
  return `idem_${action}_${cleanHint ? `${cleanHint}_` : ""}${Date.now()}_${idempotencyCounter}_${rand}`;
}
