import {
  createContext,
  useCallback,
  lazy,
  Suspense,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ChangeEvent,
  type ComponentType,
  type DragEvent,
  type MutableRefObject,
  type PointerEvent as ReactPointerEvent,
} from "react";
import { createPortal } from "react-dom";
import { AnimatePresence, motion } from "motion/react";
import { onAuthStateChanged, type User } from "firebase/auth";
import { APP_ICON_URL } from "./utils/appBrand";
import {
  ActivityLogIcon,
  ArrowDownIcon,
  ArrowLeftIcon,
  ArrowRightIcon,
  ArrowUpIcon,
  BackpackIcon,
  BarChartIcon,
  BellIcon,
  BookmarkFilledIcon,
  BookmarkIcon,
  CameraIcon,
  CardStackIcon,
  ChatBubbleIcon,
  CheckCircledIcon,
  CheckIcon,
  ChevronDownIcon,
  ChevronLeftIcon,
  Cross2Icon,
  CubeIcon,
  DownloadIcon,
  DragHandleDots2Icon,
  DrawingPinFilledIcon,
  DrawingPinIcon,
  ExclamationTriangleIcon,
  FilePlusIcon,
  FileTextIcon,
  GearIcon,
  GlobeIcon,
  HamburgerMenuIcon,
  HomeIcon,
  InfoCircledIcon,
  LayersIcon,
  LockClosedIcon,
  MagnifyingGlassIcon,
  MixIcon,
  MixerHorizontalIcon,
  MobileIcon,
  PaperPlaneIcon,
  Pencil1Icon,
  PersonIcon,
  PlusIcon,
  ReaderIcon,
  ReloadIcon,
  ResetIcon,
  RocketIcon,
  Share1Icon,
  SwitchIcon,
  TableIcon,
  TrashIcon,
} from "@radix-ui/react-icons";
import {
  FlowStack,
  KeyboardInput,
  MobileScroll,
  BottomSheet,
  useKeyboard,
  useScreenPortal,
  type FlowControls,
  type FlowScreen,
} from "./mobile";
import { ErrorBoundary } from "./components/ErrorBoundary";
import { BackupNameModal } from "./components/BackupNameModal";
import { DashboardScreen } from "./components/DashboardScreen";
import { ExpenseCategorySelector } from "./components/ExpenseCategorySelector";
import { GoogleDriveModal } from "./components/GoogleDriveModal";
import { GoogleSignInButton } from "./components/GoogleSignInButton";
import { InventoryBulkEditBar } from "./components/InventoryBulkEditBar";
import { NotificationCenter } from "./components/NotificationCenter";
import { PrintOptionsModal } from "./components/PrintOptionsModal";

import { SystemSettingsPage } from "./components/SystemSettingsPage";
import { TransferModal } from "./components/TransferModal";
import { ReportsHubModal } from "./components/ReportsHubModal";
import { WhatsAppIcon } from "./components/WhatsAppIcon";






import {
  loadErpWorkspaceData,
  saveErpWorkspaceData,
  subscribeErpCache,
  type ErpModuleId,
  type ErpWorkspaceData,
} from "./erp";
import {
  accountMatchesQuery,
  amountToArabicWords,
  buildCsvContent,
  buildWhatsAppMessageUrl,
  computeAccountGroupsSummary,
  computeAccountSummary,
  computeCategoryTotals,
  computeDashboardSummary,
  computeInventorySummary,
  computeStatementRows,
  computeTrialBalanceReport,
  computeWorkspaceNotifications,
  formatAmount,
  formatSignedSmartBalance,
  isBackupOverdue,
  limitSelectAccounts,
  matchesArabicSearch,
  maxNumericField,
  normalizeArabicSearch,
  parseArabicNumber,
  rankAccountSearchMatches,
  type WorkspaceNotification,
} from "./accounting";
import {
  auth,
  connectGoogleDrive,
  createCloudBackupRecord,
  createInventoryItem,
  createLedgerEntry,
  createOrUpdateAccount,
  deleteCurrencyRecord,
  deleteInventoryCatalogItem,
  downloadUnifiedSqliteFile,
  ensureWorkspaceSeeded,
  fetchCashboxesReport,
  fetchInventoryMovementsReport,
  fetchInvoiceDetailWithLines,
  fetchProductPriceStats,
  fetchUnifiedJsonExport,
  getGoogleAccessToken,
  importSmartProSqlIntoServer,
  importSqliteBytesIntoServer,
  isLocalWorkspaceSession,
  LOCAL_WORKSPACE_UID,
  permanentlyDeleteLedger,
  refreshWorkspaceFromServer,
  resetLocalWorkspaceDatabase,
  restoreJsonBackupIntoServer,
  saveAccountGroup,
  saveCurrencyRecord,
  saveWarehouse,
  saveWorkspaceSettings,
  setLedgerDeleted,
  setLocalWorkspaceSession,
  signInWithGoogle,
  signOutUser,
  subscribeWorkspace,
  UncertainWriteError,
  updateInventoryCatalog,
  updateInventoryItem,
  updateLedgerEntry,
  seedDemoWorkspace,
  type UnifiedInvoiceLine,
} from "./firebase";
import {
  findOrCreateDriveFolder,
  uploadFileToDrive,
  DriveAuthExpiredError,
} from "./services/googleDrive";
import {
  CURRENCIES,
  type AccountCategory,
  type AccountGroupRecord,
  type AccountRecord,
  type CashboxRecord,
  type CurrencyCode,
  type CurrencyRecord,
  type InventoryItemRecord,
  type InvoiceLineInput,
  type LedgerEntryRecord,
  type WarehouseRecord,
  type WorkspaceSettings,
} from "./types";
import {
  applyCardAppearanceSettings,
  readExtendedSettings,
  writeExtendedSettings,
  type ExtendedAppSettings,
} from "./utils/appSettings";
import { BRAND_COLOR_PRESETS, useBrandColor } from "./utils/brandColor";
import {
  buildLocalBackupDownloadName,
  extractBackupCollections,
  inspectBackupBytes,
} from "./utils/backupFormat";
import { describeGoogleSignInError } from "./utils/authError";
import { exportSummaryAsPngImage } from "./utils/canvasExport";
import {
  DEFAULT_HOME_METRIC_ORDER,
  DEFAULT_HOME_TILE_LAYOUT,
  getVisibleOrderedHomeTiles,
  isDefaultHomeTileLayout,
  moveHomeTile,
  readHomeMetricOrder,
  readHomeTileLayout,
  readLastBackupIso,
  readPinnedFavorites,
  readWidgetOrder,
  recordLastBackupNow,
  stepHomeTile,
  toggleHideHomeTile,
  togglePinHomeTile,
  toggleToneHomeTile,
  writeHomeMetricOrder,
  writeHomeTileLayout,
  writePinnedFavorites,
  writeWidgetOrder,
  type DashboardWidgetId,
  type HomeMetricId,
  type HomeTileId,
  type HomeTileLayout,
  type HomeTileTone,
  type PinnedFavoriteItem,
} from "./utils/dashboardPrefs";
import {
  buildInvoicePdfSummaryData,
  buildInvoiceSummaryPdfBytes,
  generatePrintableInvoicePdfFromDatabase,
} from "./utils/exportPdf";
import { readHapticsEnabled, triggerHaptic, writeHapticsEnabled } from "./utils/haptics";
import { useThemeMode, type ThemeMode } from "./utils/theme";
import { OutlinedAmountField } from "./components/OutlinedAmountField";
import { GlobalNasqoBrandLoader, NasqoBrandLoader } from "./components/NasqoBrandLoader";
import { runWithBrandLoader } from "./utils/brandLoaderBus";

type IconComponent = ComponentType<{ className?: string }>;
type SheetKind = "filters" | "export" | "notifications" | null;
type OverlayKind =
  | "account-picker"
  | "transaction"
  | "account-create-compact"
  | "account-create-extended"
  | "invoice"
  | "trash"
  | "settings"
  | "inventory-add"
  | "notifications"
  | "qr-scanner"
  | "print-options"
  | "backup-name"
  | "google-drive"
  | "full-sqlite-import"
  | "transfer"
  | "trial-balance"
  | "account-groups"
  | "chart-of-accounts"
  | "cashboxes-report"
  | "reports-hub"
  | "currencies-manager"
  | "confirm-reset"
  | null;
type AccountCreateMode = "compact" | "extended";
type ExportKind = "statement" | "inventory" | "purchases";
type InvoiceIntent = "invoice" | "return" | "quote" | "order";
type DrawerTarget =
  | "dashboard"
  | "purchases"
  | "settings"
  | "whatsapp"
  | "shop"
  | "warehouses"
  | "inventory-report"
  | "items"
  | "quotes"
  | "orders"
  | "accounts"
  | "currency"
  | "trash"
  | "daily-journal"
  | "analytics-dashboard"
  | ErpModuleId;

type LiveWorkspaceState = {
  uid: string;
  userEmail: string;
  workspace: WorkspaceSettings | null;
  currencies: CurrencyRecord[];
  currencyCodes: string[];
  accountGroups: AccountGroupRecord[];
  accounts: AccountRecord[];
  cashboxes: CashboxRecord[];
  ledger: LedgerEntryRecord[];
  warehouses: WarehouseRecord[];
  inventory: InventoryItemRecord[];
  categoryCurrencies: Partial<Record<AccountCategory, string>>;
  setCategoryCurrency: (category: AccountCategory, currency: string) => void;
  statementCurrencies: Record<string, string>;
  setStatementCurrency: (accountId: string, currency: string) => void;
  activeStatementAccountId: string | null;
  setActiveStatementAccountId: (accountId: string | null) => void;
  statementFilter: {
    docKind: "all" | "invoice" | "voucher" | "return" | "quote" | "order";
    sortOrder: "asc" | "desc";
    period: string;
    fromDate: string;
    toDate: string;
    showPreviousBalance: boolean | null;
  };
  setStatementFilter: (
    next:
      | {
          docKind: "all" | "invoice" | "voucher" | "return" | "quote" | "order";
          sortOrder: "asc" | "desc";
          period: string;
          fromDate: string;
          toDate: string;
          showPreviousBalance: boolean | null;
        }
      | ((prev: {
          docKind: "all" | "invoice" | "voucher" | "return" | "quote" | "order";
          sortOrder: "asc" | "desc";
          period: string;
          fromDate: string;
          toDate: string;
          showPreviousBalance: boolean | null;
        }) => {
          docKind: "all" | "invoice" | "voucher" | "return" | "quote" | "order";
          sortOrder: "asc" | "desc";
          period: string;
          fromDate: string;
          toDate: string;
          showPreviousBalance: boolean | null;
        }),
  ) => void;
  erpData: ErpWorkspaceData;
  updateErpData: (next: ErpWorkspaceData) => void;
  openErpModule: (moduleId: ErpModuleId) => void;
  syncing: boolean;
  syncError: string | null;
  retryingSync: boolean;
  retrySync: () => Promise<void>;
  flowRef: MutableRefObject<FlowControls | null>;
  openDrawer: () => void;
  openSheet: (kind: Exclude<SheetKind, null>) => void;
  openAccountPicker: () => void;
  openQuickSearch: () => void;
  openAccountEdit: (account?: AccountRecord) => void;
  openTransaction: (account?: AccountRecord, editingEntry?: LedgerEntryRecord) => void;
  openAccountCreate: (mode?: AccountCreateMode, defaultCategory?: AccountCategory) => void;
  openInvoice: (defaultCategory?: AccountCategory, intent?: InvoiceIntent) => void;
  openVendorInvoice: (account?: AccountRecord, intent?: InvoiceIntent) => void;
  openInvoiceEdit: (entry: LedgerEntryRecord, account?: AccountRecord) => void;
  openDashboardMenu: () => void;
  openOptionsMenu: () => void;
  resetWorkspaceToEmptyNow: () => void;
  seedDemoWorkspaceNow: () => void;
  openExportMenu: (kind?: ExportKind, account?: AccountRecord) => void;
  openPrintOptions: (kind?: ExportKind, account?: AccountRecord) => void;
  openBackupModal: () => void;
  openGoogleDriveModal: () => void;
  openFullSqliteImport: () => void;
  openTransferModal: (accountId?: string) => void;
  openTrialBalance: () => void;
  openAccountGroups: () => void;
  openChartOfAccounts: () => void;
  openCashboxesReport: () => void;
  openReportsHub: () => void;
  openCurrenciesManager: () => void;
  openInventoryAdd: () => void;
  openInventoryEdit: (item: InventoryItemRecord) => void;
  openSettings: () => void;
  openTrash: () => void;
  openNotifications: () => void;
  openQrScanner: () => void;
  openWhatsAppPicker: () => void;
  unreadNotificationsCount: number;
  themeMode: ThemeMode;
  setThemeMode: (mode: ThemeMode) => void;
  brandColor: string;
  setBrandColor: (hex: string) => void;
  resetBrandColor: () => void;
  hapticsEnabled: boolean;
  setHapticsEnabled: (enabled: boolean) => void;
  extendedSettings: ExtendedAppSettings;
  setExtendedSettings: (next: ExtendedAppSettings) => void;
  widgetOrder: DashboardWidgetId[];
  setWidgetOrder: (order: DashboardWidgetId[]) => void;
  homeMetricOrder: HomeMetricId[];
  setHomeMetricOrder: (order: HomeMetricId[]) => void;
  favorites: PinnedFavoriteItem[];
  pinFavorite: (item: PinnedFavoriteItem) => void;
  unpinFavorite: (id: string) => void;
  launchFavorite: (item: PinnedFavoriteItem) => void;
  lastBackupIso: string | null;
  showToast: (message: string, durationMs?: number) => void;
  runWithLoader: <T>(label: string, task: () => Promise<T>) => Promise<T>;
  triggerJsonBackup: () => void;
  triggerJsonRestore: () => void;
  triggerCsvImport: () => void;
  handleSignOut: () => void;
};

const WorkspaceContext = createContext<LiveWorkspaceState | null>(null);

function useWorkspace(): LiveWorkspaceState {
  const ctx = useContext(WorkspaceContext);
  if (!ctx) {
    throw new Error("useWorkspace must be used inside WorkspaceContext.Provider");
  }
  return ctx;
}

function downloadFile(filename: string, content: string, mimeType: string) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function triggerPrintWithLoader(label = "جاري تجهيز الطباعة...") {
  void runWithBrandLoader(
    label,
    () => {
      window.print();
    },
    { preDelayMs: 320, minDurationMs: 420 },
  );
}

async function shareOrCopyText(title: string, text: string, showToast: (msg: string) => void) {
  await runWithBrandLoader(
    "جاري تجهيز المشاركة...",
    async () => {
      try {
        if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
          await navigator.share({ title, text });
          return;
        }
      } catch {
        // Fallback to clipboard below when user cancels or share fails
      }
      try {
        if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
          await navigator.clipboard.writeText(text);
          showToast("تم نسخ الملخص إلى الحافظة للمشاركة");
          return;
        }
      } catch {
        // Ignore clipboard error in restricted frames
      }
      showToast("تم تجهيز نص الملخص للمشاركة");
    },
    { minDurationMs: 420 },
  );
}

async function openWhatsAppChat(
  account: AccountRecord | undefined,
  message: string,
  showToast: (msg: string) => void,
) {
  await runWithBrandLoader(
    account?.name ? `جاري فتح واتساب لمراسلة ${account.name}...` : "جاري فتح واتساب...",
    async () => {
      triggerHaptic("light");
      try {
        if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
          await navigator.clipboard.writeText(message);
        }
      } catch {
        // Ignore clipboard restriction inside sandboxed frames
      }
      const waUrl = buildWhatsAppMessageUrl(account?.phone, message);
      if (typeof document !== "undefined") {
        const link = document.createElement("a");
        link.href = waUrl;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
      }
      if (account?.phone) {
        showToast(`جاري فتح واتساب لمراسلة ${account.name}`);
      } else {
        showToast("تم تجهيز رسالة واتساب ونسخها — اختر جهة الاتصال داخل واتساب");
      }
    },
    { preDelayMs: 280, minDurationMs: 440 },
  );
}

function buildAccountBalanceMessage(
  account: AccountRecord,
  balance: number,
  tone: "credit" | "debit" | "neutral",
  companyName?: string,
  ext?: ExtendedAppSettings,
): string {
  const creditLabel = ext?.creditBalanceLabel?.trim() || "له";
  const debitLabel = ext?.debitBalanceLabel?.trim() || "عليه";
  const directionLabel = tone === "credit" ? creditLabel : tone === "debit" ? debitLabel : "متزن";
  const formattedAbs = ext?.useTwoDecimals
    ? `${formatAmount(Math.abs(balance))}.00`
    : formatAmount(Math.abs(balance));
  const signedText = `${formattedAbs}${tone === "credit" ? "-" : ""}`;
  const intro = ext?.messageIntro?.trim() ? `${ext.messageIntro.trim()}\n` : "";
  const outro = ext?.messageOutro?.trim() ? `\n${ext.messageOutro.trim()}` : "";
  return `${intro}السلام عليكم ${account.name}، تحية طيبة من ${companyName || "نسقو برو"}. صافي الرصيد الحالي: ${signedText} ${account.currency} (${directionLabel}).${outro}`;
}

function categoryTitle(category: AccountCategory): string {
  const map: Record<AccountCategory, string> = {
    purchases: "المشتريات",
    sales: "المبيعات",
    clients: "العملاء",
    employees: "الموظفين",
    transfers: "الحوالات",
    shop: "المحل",
  };
  return map[category];
}

export default function Prototype() {
  return (
    <ErrorBoundary>
      <NasqoProductionShell />
    </ErrorBoundary>
  );
}

function createLocalUserProfile(): User {
  return {
    uid: LOCAL_WORKSPACE_UID,
    email: "account@nasqo.local",
    displayName: "مساحة العمل المتكاملة",
  } as User;
}

const FullSqliteImportModal = lazy(() => import("./components/FullSqliteImportModal").then((mod) => ({ default: mod.FullSqliteImportModal })));
const QrScannerModal = lazy(() => import("./components/QrScannerModal").then((mod) => ({ default: mod.QrScannerModal })));
const ErpHubScreen = lazy(() => import("./components/erp/ErpHubScreen").then((mod) => ({ default: mod.ErpHubScreen })));
const ErpFinanceScreen = lazy(() => import("./components/erp/ErpFinanceScreen").then((mod) => ({ default: mod.ErpFinanceScreen })));
const ErpHrScreen = lazy(() => import("./components/erp/ErpHrScreen").then((mod) => ({ default: mod.ErpHrScreen })));
const ErpCrmPosScreen = lazy(() => import("./components/erp/ErpCrmPosScreen").then((mod) => ({ default: mod.ErpCrmPosScreen })));
const ErpProcurementScreen = lazy(() => import("./components/erp/ErpProcurementScreen").then((mod) => ({ default: mod.ErpProcurementScreen })));
const ErpManufacturingScreen = lazy(() => import("./components/erp/ErpManufacturingScreen").then((mod) => ({ default: mod.ErpManufacturingScreen })));
const SmartProControlScreen = lazy(() => import("./components/erp/SmartProControlScreen").then((mod) => ({ default: mod.SmartProControlScreen })));

function NasqoProductionShell() {
  const [user, setUser] = useState<User | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [authBusy, setAuthBusy] = useState(false);
  const [authError, setAuthError] = useState("");
  const [sqliteAccess, setSqliteAccess] = useState<"checking" | "ready" | "locked" | "unconfigured" | "error">("checking");
  const [sqlitePassword, setSqlitePassword] = useState("");
  const [sqliteLoginBusy, setSqliteLoginBusy] = useState(false);
  const [sqliteLoginError, setSqliteLoginError] = useState("");
  const [workspaceReady, setWorkspaceReady] = useState(false);
  const [primaryMode, setPrimaryMode] = useState<"checking" | "off" | "on" | "error">("checking");
  const [startupError, setStartupError] = useState("");
  const [cloudInitializationError, setCloudInitializationError] = useState("");
  const localStartPending = useRef<Promise<void> | null>(null);
  const { mode: themeMode, setMode: setThemeMode } = useThemeMode();
  const { brandColor, setBrandColor, resetBrandColor } = useBrandColor();

  const sqliteAuthBase = useMemo(() =>
    new URL("api/db/auth/", new URL(import.meta.env.BASE_URL, window.location.origin)).pathname, []);

  useEffect(() => {
    const abort = new AbortController();
    const timer = window.setTimeout(() => abort.abort(), 10_000);
    void fetch(sqliteAuthBase + "status", { signal: abort.signal, cache: "no-store" })
      .then((response) => {
        if (!response.ok) throw new Error("SQLite auth unavailable");
        return response.json() as Promise<{ mode: string; authenticated: boolean }>;
      })
      .then((status) => {
        if (abort.signal.aborted) return;
        setSqliteAccess(status.mode === "unconfigured" ? "unconfigured" :
          status.authenticated ? "ready" : "locked");
      })
      .catch(() => { if (!abort.signal.aborted) setSqliteAccess("error"); })
      .finally(() => window.clearTimeout(timer));
    return () => { abort.abort(); window.clearTimeout(timer); };
  }, [sqliteAuthBase]);

  const loginToSqlite = async () => {
    setSqliteLoginBusy(true);
    setSqliteLoginError("");
    const abort = new AbortController();
    const timer = window.setTimeout(() => abort.abort(), 15_000);
    try {
      const response = await fetch(sqliteAuthBase + "login", {
        method: "POST",
        credentials: "same-origin",
        signal: abort.signal,
        headers: { "Content-Type": "application/json", "X-NASQO-CSRF": "1" },
        body: JSON.stringify({ password: sqlitePassword }),
      });
      const body = await response.json().catch(() => ({})) as { error?: string };
      if (!response.ok) throw new Error(body.error || "تعذر تسجيل الدخول.");
      setSqlitePassword("");
      setSqliteAccess("ready");
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        setSqliteLoginError("انتهت مهلة التحقق من الدخول؛ تحقق من الاتصال وأعد المحاولة.");
      } else {
        setSqliteLoginError(error instanceof Error ? error.message : String(error));
      }
    } finally {
      window.clearTimeout(timer);
      setSqliteLoginBusy(false);
    }
  };

  // The database switch is server-controlled. A previously active primary
  // database must never silently fall back to browser/Firestore writes when
  // the central API is unreachable.
  useEffect(() => {
    const abort = new AbortController();
    const timer = window.setTimeout(() => abort.abort(), 5000);
    const statusUrl = new URL("api/smartpro/status", new URL(import.meta.env.BASE_URL, window.location.origin));
    void fetch(statusUrl, { signal: abort.signal, cache: "no-store" })
      .then((response) => {
        if (!response.ok) throw new Error("database status unavailable");
        return response.json() as Promise<{ primary?: boolean }>;
      })
      .then(({ primary }) => {
        if (abort.signal.aborted) return;
        if (primary) {
          window.localStorage.setItem("nasqo-smartpro-primary-active", "1");
          setPrimaryMode("on");
        } else {
          window.localStorage.removeItem("nasqo-smartpro-primary-active");
          setPrimaryMode("off");
        }
      })
      .catch(() => {
        if (!abort.signal.aborted || !window.localStorage.getItem("nasqo-smartpro-primary-active")) {
          setPrimaryMode(window.localStorage.getItem("nasqo-smartpro-primary-active") ? "error" : "off");
        } else {
          setPrimaryMode("error");
        }
      })
      .finally(() => window.clearTimeout(timer));
    return () => { abort.abort(); window.clearTimeout(timer); };
  }, []);

  const enterLocalWorkspace = useCallback(async () => {
    if (primaryMode !== "off" || sqliteAccess !== "ready") return;
    setLocalWorkspaceSession(true);
    const localUser = createLocalUserProfile();
    setUser(localUser);
    setAuthReady(true);
    setWorkspaceReady(false);
    setStartupError("");
    // React StrictMode and fast double-taps must not start parallel migrations.
    let pending = localStartPending.current;
    if (!pending) {
      pending = ensureWorkspaceSeeded(localUser.uid, localUser.displayName);
      localStartPending.current = pending;
      void pending.then(
        () => { if (localStartPending.current === pending) localStartPending.current = null; },
        () => { if (localStartPending.current === pending) localStartPending.current = null; },
      );
    }
    try {
      await pending;
      setWorkspaceReady(true);
    } catch (error) {
      // Do not unlock accounting writes against a stale localStorage fallback.
      setStartupError(error instanceof Error ? error.message : "تعذر فتح سجلات التطبيق؛ أغلق النوافذ الأخرى وأعد المحاولة.");
    }
  }, [primaryMode, sqliteAccess]);

  useEffect(() => {
    if (!authReady || !user || workspaceReady || primaryMode !== "off") return;
    // Only show a real failure, never a speculative "old tab" alarm at 5s.
    const deadline = window.setTimeout(() => {
      setStartupError((previous) => previous ||
        "لم يكتمل استرجاع البيانات المحلية. يمكن إعادة محاولة فتحها دون حذف أي سجل.");
    }, 12_000);
    return () => window.clearTimeout(deadline);
  }, [authReady, user, workspaceReady, primaryMode]);

  useEffect(() => {
    const wantsAutostart =
      typeof window !== "undefined" &&
      new URLSearchParams(window.location.search).get("autostart") === "1";

    if (primaryMode === "checking" || primaryMode === "error") return;

    // The single SQLite workspace is not Google/Firestore. A stale Firebase
    // session must never replace the local SQLite user or block its writes.
    if (primaryMode === "off") {
      if (sqliteAccess === "ready") {
        void enterLocalWorkspace();
      }
      return;
    }

    const fallbackTimer = window.setTimeout(() => {
      setAuthReady(true);
    }, 1000);

    const unsub = onAuthStateChanged(auth, async (nextUser) => {
      window.clearTimeout(fallbackTimer);
      if (nextUser) {
        setLocalWorkspaceSession(false);
        setUser(nextUser);
        setAuthReady(true);
        // Identity is ready. Do not hold the entire mobile UI hostage to
        // getDoc/getDocs/seed writes over a slow mobile network.
        setWorkspaceReady(true);
        setStartupError("");
        setCloudInitializationError("");
        // Legacy central SmartPro mode uses its own server; never seed cloud
        // data from this authentication listener.
      } else if (primaryMode === "on" || (!wantsAutostart && !isLocalWorkspaceSession())) {
        setUser(null);
        setAuthReady(true);
        setWorkspaceReady(false);
        setStartupError("");
        setCloudInitializationError("");
      }
    });
    return () => {
      window.clearTimeout(fallbackTimer);
      unsub();
    };
  }, [enterLocalWorkspace, primaryMode, sqliteAccess]);

  const handleSignIn = async () => {
    setAuthBusy(true);
    setAuthError("");
    setLocalWorkspaceSession(false);
    try {
      await signInWithGoogle();
    } catch (err) {
      setAuthError(describeGoogleSignInError(err));
    } finally {
      setAuthBusy(false);
    }
  };

  if (sqliteAccess !== "ready") {
    return (
      <div className="nasqo-app" dir="rtl">
        <div className="auth-gate-shell auth-gate-single-panel">
          <main className="auth-gate-main">
            <section className="auth-card">
              <h1>نسقو برو — تسجيل الدخول</h1>
              {sqliteAccess === "checking" ? <p role="status">جارٍ التحقق من صلاحية الدخول...</p> : null}
              {sqliteAccess === "locked" ? (
                <>
                  <p>أدخل كلمة مرور المدير للوصول إلى النظام.</p>
                  <KeyboardInput type="password" aria-label="كلمة مرور المدير"
                    placeholder="كلمة مرور المدير" value={sqlitePassword}
                    onChange={(event) => setSqlitePassword(event.target.value)} />
                  {sqliteLoginError ? <p role="alert" className="auth-error">{sqliteLoginError}</p> : null}
                  <button className="auth-google-btn" disabled={sqliteLoginBusy || !sqlitePassword}
                    onClick={() => void loginToSqlite()} data-testid="sqlite-admin-login">
                    {sqliteLoginBusy ? "جارٍ التحقق..." : "دخول"}
                  </button>
                </>
              ) : null}
              {sqliteAccess === "unconfigured" ? <p role="alert" className="auth-error">
                يجب إعداد كلمة مرور المدير ومفتاح الجلسة في إعدادات الخادم قبل الاستخدام عبر الإنترنت.
              </p> : null}
              {sqliteAccess === "error" ? (
                <>
                  <p role="alert" className="auth-error">تعذر الاتصال بالخادم المحلي دون تغيير البيانات.</p>
                  <button className="auth-google-btn" onClick={() => window.location.reload()}>إعادة المحاولة</button>
                </>
              ) : null}
            </section>
          </main>
        </div>
      </div>
    );
  }

  if (primaryMode === "error") {
    return (
      <div className="nasqo-app" dir="rtl">
        <div className="auth-gate-shell auth-gate-single-panel">
          <main className="auth-gate-main">
            <section className="auth-card">
              <h1>تعذر الاتصال بالإدارة المركزية</h1>
              <p role="alert">لن يتم فتح السجلات المحلية بدلًا من النظام المركزي حتى لا تتوزع التعديلات بين حسابين.</p>
              <button className="auth-google-btn" onClick={() => window.location.reload()}>إعادة الاتصال</button>
            </section>
          </main>
        </div>
      </div>
    );
  }

  if (!authReady || (user && !workspaceReady)) {
    return (
      <div className="nasqo-app" dir="rtl">
        <div className="auth-gate-shell">
          <header className="app-header dashboard-header">
            <div className="header-brand">
              <span className="brand-mark" aria-hidden="true">
                <img src={APP_ICON_URL} alt="" className="app-brand-icon-img" draggable={false} />
              </span>
              <span className="header-copy">
                <strong>نسقو برو</strong>
              </span>
            </div>
          </header>
          <main className="auth-gate-main">
            <section className="auth-card">
              {startupError ? (
                <>
                  <span className="drawer-hero-mark">
                    <img src={APP_ICON_URL} alt="شعار نسقو برو" className="app-brand-icon-img" draggable={false} />
                  </span>
                  <h1>تعذر فتح مساحة العمل</h1>
                  <p role="alert" className="auth-error" data-testid="startup-storage-error">{startupError}</p>
                  <button
                    type="button"
                    className="auth-google-btn"
                    data-testid="startup-retry-button"
                    onClick={() => {
                      if (user?.uid === LOCAL_WORKSPACE_UID) void enterLocalWorkspace();
                      else window.location.reload();
                    }}
                  >
                    <ReloadIcon /> إعادة المحاولة دون حذف البيانات
                  </button>
                  <p>إذا كانت هناك نافذة أخرى للنظام مفتوحة، أغلقها أولًا. لا تمسح بيانات المتصفح أو ذاكرة التطبيق.</p>
                </>
              ) : (
                <>
                  <NasqoBrandLoader size="lg" label="جاري تحميل النظام..." testId="startup-brand-loader" />
                  <p>يتم تجهيز بيانات العمل المحفوظة بأمان.</p>
                </>
              )}
            </section>
          </main>
        </div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="nasqo-app" dir="rtl">
        <div className="auth-gate-shell">
          <header className="app-header dashboard-header">
            <div className="header-brand">
              <span className="brand-mark" aria-hidden="true">
                <img src={APP_ICON_URL} alt="" className="app-brand-icon-img" draggable={false} />
              </span>
              <span className="header-copy">
                <strong>نسقو برو</strong>
                <small>إدارة الحسابات والمبيعات والمخزون</small>
              </span>
            </div>
          </header>
          <main className="auth-gate-main">
            <section className="auth-card">
              <span className="drawer-hero-mark">
                <img src={APP_ICON_URL} alt="شعار نسقو برو" className="app-brand-icon-img" draggable={false} />
              </span>
              <h1>نسقو برو — إدارة الأعمال والحسابات</h1>
              <p>
                أدر الحسابات، الفواتير، المشتريات والمبيعات، الموارد البشرية والرواتب، والمخازن في نظام واحد متكامل.
              </p>
              {authError ? (
                <p className="auth-error" role="alert">
                  {authError}
                </p>
              ) : null}
              {primaryMode === "off" ? (
                <button
                  className="auth-google-btn"
                  onClick={() => void enterLocalWorkspace()}
                  data-testid="local-erp-signin-button"
                >
                  <RocketIcon />
                  <span>الدخول السريع — بدء العمل</span>
                </button>
              ) : (
                <p>سجّل الدخول باستخدام حساب Google المخوّل للوصول إلى صلاحياتك.</p>
              )}
              {primaryMode === "on" ? <div className="auth-gsi-wrap">
                <GoogleSignInButton
                  onClick={() => void handleSignIn()}
                  disabled={authBusy}
                  label={authBusy ? "جاري تسجيل الدخول..." : "Sign in with Google"}
                  testId="google-signin-button"
                  fullWidth
                />
              </div> : null}
            </section>
          </main>
        </div>
        <GlobalNasqoBrandLoader />
      </div>
    );
  }

  if (primaryMode === "on") {
    return (
      <div className="nasqo-app" dir="rtl">
        <Suspense fallback={<NasqoBrandLoader size="md" label="جاري فتح الإدارة المركزية..." />}>
          <SmartProControlScreen key={user.uid} />
        </Suspense>
        <GlobalNasqoBrandLoader />
      </div>
    );
  }

  return (
    <AuthenticatedWorkspace
      key={user.uid}
      user={user}
      cloudInitializationError={cloudInitializationError}
      onLocalSignOut={() => {
        setLocalWorkspaceSession(false);
        setUser(null);
        setWorkspaceReady(false);
        void fetch(sqliteAuthBase + "logout", {
          method: "POST",
          credentials: "same-origin",
          headers: { "X-NASQO-CSRF": "1" },
        })
          .then(() => fetch(sqliteAuthBase + "status", { cache: "no-store" }))
          .then((r) => (r.ok ? (r.json() as Promise<{ mode: string; authenticated: boolean }>) : null))
          .then((status) => {
            if (!status) return;
            setSqliteAccess(
              status.mode === "unconfigured" ? "unconfigured" : status.authenticated ? "ready" : "locked",
            );
          })
          .catch(() => {});
      }}
      themeMode={themeMode}
      setThemeMode={setThemeMode}
      brandColor={brandColor}
      setBrandColor={setBrandColor}
      resetBrandColor={resetBrandColor}
    />
  );
}

function AuthenticatedWorkspace({
  user,
  cloudInitializationError,
  onLocalSignOut,
  themeMode,
  setThemeMode,
  brandColor,
  setBrandColor,
  resetBrandColor,
}: {
  user: User;
  cloudInitializationError: string;
  onLocalSignOut: () => void;
  themeMode: ThemeMode;
  setThemeMode: (mode: ThemeMode) => void;
  brandColor: string;
  setBrandColor: (hex: string) => void;
  resetBrandColor: () => void;
}) {
  const [workspace, setWorkspace] = useState<WorkspaceSettings | null>(null);
  const [currencies, setCurrencies] = useState<CurrencyRecord[]>([]);
  const [accountGroups, setAccountGroups] = useState<AccountGroupRecord[]>([]);
  const [accounts, setAccounts] = useState<AccountRecord[]>([]);
  const [cashboxes, setCashboxes] = useState<CashboxRecord[]>([]);
  const [ledger, setLedger] = useState<LedgerEntryRecord[]>([]);
  const [warehouses, setWarehouses] = useState<WarehouseRecord[]>([]);
  const [inventory, setInventory] = useState<InventoryItemRecord[]>([]);
  const [categoryCurrencies, setCategoryCurrencies] = useState<Partial<Record<AccountCategory, string>>>({});
  const [statementCurrencies, setStatementCurrencies] = useState<Record<string, string>>({});
  const [activeStatementAccountId, setActiveStatementAccountId] = useState<string | null>(null);
  const [statementFilter, setStatementFilter] = useState<{
    docKind: "all" | "invoice" | "voucher" | "return" | "quote" | "order";
    sortOrder: "asc" | "desc";
    period: string;
    fromDate: string;
    toDate: string;
    showPreviousBalance: boolean | null;
  }>({
    docKind: "all",
    sortOrder: "desc",
    period: "الكل",
    fromDate: "",
    toDate: "",
    showPreviousBalance: null,
  });
  const [erpData, setErpData] = useState<ErpWorkspaceData>(() => loadErpWorkspaceData(user.uid));
  const [syncFlags, setSyncFlags] = useState({ accounts: false, ledger: false, inventory: false });
  const [syncError, setSyncError] = useState<string | null>(null);
  const [inventoryEditing, setInventoryEditing] = useState<InventoryItemRecord | undefined>();
  const [retryingSync, setRetryingSync] = useState(false);

  const [drawerOpen, setDrawerOpen] = useState(false);
  const [sheet, setSheet] = useState<SheetKind>(null);
  const [overlay, setOverlay] = useState<OverlayKind>(null);
  const [pickerMode, setPickerMode] = useState<"statement" | "edit" | "whatsapp" | "search">("statement");
  const [editingAccount, setEditingAccount] = useState<AccountRecord | undefined>();
  const [accountCreateCategory, setAccountCreateCategory] = useState<AccountCategory>("purchases");
  const [transactionTarget, setTransactionTarget] = useState<{
    account?: AccountRecord;
    editingEntry?: LedgerEntryRecord;
  }>({});
  const [exportState, setExportState] = useState<{
    open: boolean;
    kind: ExportKind;
    account?: AccountRecord;
  }>({ open: false, kind: "statement" });
  const [dashboardMenuOpen, setDashboardMenuOpen] = useState(false);
  const [optionsMenuOpen, setOptionsMenuOpen] = useState(false);
  const [invoiceSeed, setInvoiceSeed] = useState<{
    account?: AccountRecord;
    editingEntry?: LedgerEntryRecord;
    intent: InvoiceIntent;
    kindOverride?: "purchase" | "sale";
    revision: number;
  }>({ intent: "invoice", revision: 0 });
  const returnOverlay = useRef<OverlayKind>(null);
  const [toast, setToast] = useState<string | null>(null);
  const toastTimer = useRef<number | null>(null);
  const flowRef = useRef<FlowControls | null>(null);
  const keyboard = useKeyboard();
  const jsonRestoreInputRef = useRef<HTMLInputElement>(null);
  const csvImportInputRef = useRef<HTMLInputElement>(null);

  const [printContext, setPrintContext] = useState<{
    kind: ExportKind;
    account?: AccountRecord;
  }>({ kind: "statement" });
  const [transferAccountId, setTransferAccountId] = useState<string | undefined>();
  const [extendedSettings, setExtendedSettingsState] = useState<ExtendedAppSettings>(() => {
    const initial = readExtendedSettings();
    applyCardAppearanceSettings(initial);
    return initial;
  });
  const [hapticsEnabled, setHapticsEnabledState] = useState<boolean>(() => readHapticsEnabled());
  const [widgetOrder, setWidgetOrderState] = useState<DashboardWidgetId[]>(() => readWidgetOrder());
  const [homeMetricOrder, setHomeMetricOrderState] = useState<HomeMetricId[]>(() => readHomeMetricOrder());
  const [favorites, setFavoritesState] = useState<PinnedFavoriteItem[]>(() => readPinnedFavorites());
  const [lastBackupIso, setLastBackupIso] = useState<string | null>(() => readLastBackupIso());
  const [readNotifIds, setReadNotifIds] = useState<Set<string>>(() => {
    try {
      const saved = window.localStorage.getItem("nasqo-read-notifs");
      return new Set(saved ? (JSON.parse(saved) as string[]) : []);
    } catch {
      return new Set();
    }
  });
  const [dismissedNotifIds, setDismissedNotifIds] = useState<Set<string>>(() => {
    try {
      const saved = window.localStorage.getItem("nasqo-dismissed-notifs");
      return new Set(saved ? (JSON.parse(saved) as string[]) : []);
    } catch {
      return new Set();
    }
  });

  useEffect(() => {
    applyCardAppearanceSettings(extendedSettings);
  }, [extendedSettings]);

  const setExtendedSettings = useCallback((next: ExtendedAppSettings) => {
    writeExtendedSettings(next);
    applyCardAppearanceSettings(next);
    setExtendedSettingsState(next);
  }, []);

  const setHapticsEnabled = useCallback((enabled: boolean) => {
    writeHapticsEnabled(enabled);
    setHapticsEnabledState(enabled);
    if (enabled) triggerHaptic("light");
  }, []);

  const setWidgetOrder = useCallback((order: DashboardWidgetId[]) => {
    writeWidgetOrder(order);
    setWidgetOrderState(order);
  }, []);

  const setHomeMetricOrder = useCallback((order: HomeMetricId[]) => {
    writeHomeMetricOrder(order);
    setHomeMetricOrderState(order);
  }, []);

  const pinFavorite = useCallback((item: PinnedFavoriteItem) => {
    triggerHaptic("pin");
    setFavoritesState((prev) => {
      if (prev.some((f) => f.id === item.id)) return prev;
      const next = [item, ...prev];
      writePinnedFavorites(next);
      return next;
    });
  }, []);

  const unpinFavorite = useCallback((id: string) => {
    triggerHaptic("light");
    setFavoritesState((prev) => {
      const next = prev.filter((f) => f.id !== id);
      writePinnedFavorites(next);
      return next;
    });
  }, []);

  useEffect(() => {
    setErpData(loadErpWorkspaceData(user.uid));
    return subscribeErpCache((next) => {
      setErpData(next);
    });
  }, [user.uid]);

  const updateErpData = useCallback(
    (next: ErpWorkspaceData) => {
      setErpData(next);
      saveErpWorkspaceData(user.uid, next);
    },
    [user.uid],
  );



  useEffect(() => {
    const unsub = subscribeWorkspace(user.uid, {
      onWorkspace: (ws) => {
        setSyncError(null);
        setWorkspace(ws);
      },
      onCurrencies: setCurrencies,
      onAccountGroups: setAccountGroups,
      onAccounts: (list) => {
        setSyncError(null);
        setAccounts(list);
        setSyncFlags((prev) => (prev.accounts ? prev : { ...prev, accounts: true }));
      },
      onLedger: (list) => {
        setLedger(list);
        setSyncFlags((prev) => (prev.ledger ? prev : { ...prev, ledger: true }));
      },
      onWarehouses: setWarehouses,
      onCashboxes: setCashboxes,
      onInventory: (list) => {
        setInventory(list);
        setSyncFlags((prev) => (prev.inventory ? prev : { ...prev, inventory: true }));
      },
      onError: (err) => {
        setSyncError(err.message || "تعذر تحميل البيانات.");
      },
    });
    return unsub;
  }, [user.uid]);

  const runWithLoader = useCallback(
    async <T,>(label: string, task: () => Promise<T>): Promise<T> =>
      runWithBrandLoader(label, task),
    [],
  );

  const showToast = useCallback((message: string, durationMs = 2600) => {
    if (toastTimer.current) window.clearTimeout(toastTimer.current);
    setToast(message);
    toastTimer.current = window.setTimeout(() => setToast(null), durationMs);
  }, []);

  const retrySync = useCallback(async () => {
    setRetryingSync(true);
    try {
      await runWithLoader("جاري مزامنة وتحديث البيانات...", () =>
        refreshWorkspaceFromServer(user.uid),
      );
      setSyncError(null);
      showToast("تم تحديث البيانات بنجاح");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "تعذر الاتصال بالنظام.";
      setSyncError(msg);
      showToast(msg, 5000);
    } finally {
      setRetryingSync(false);
    }
  }, [runWithLoader, showToast, user.uid]);

  const dismissKeyboard = useCallback(() => {
    keyboard.hide();
    const activeElement = document.activeElement;
    if (activeElement instanceof HTMLElement) activeElement.blur();
  }, [keyboard]);

  const openSheet = useCallback((kind: Exclude<SheetKind, null>) => {
    dismissKeyboard();
    setSheet(kind);
  }, [dismissKeyboard]);

  const openDrawer = useCallback(() => {
    dismissKeyboard();
    setDrawerOpen(true);
  }, [dismissKeyboard]);

  const openAccountPicker = useCallback(() => {
    dismissKeyboard();
    setExportState((s) => ({ ...s, open: false }));
    setPickerMode("statement");
    setOverlay("account-picker");
  }, [dismissKeyboard]);

  const openQuickSearch = useCallback(() => {
    dismissKeyboard();
    setExportState((s) => ({ ...s, open: false }));
    setPickerMode("search");
    setOverlay("account-picker");
  }, [dismissKeyboard]);

  const openWhatsAppPicker = useCallback(() => {
    triggerHaptic("light");
    dismissKeyboard();
    setExportState((s) => ({ ...s, open: false }));
    setPickerMode("whatsapp");
    setOverlay("account-picker");
  }, [dismissKeyboard]);

  const openAccountEdit = useCallback(
    (account?: AccountRecord) => {
      dismissKeyboard();
      if (account) {
        setEditingAccount(account);
        setOverlay("account-create-extended");
        return;
      }
      setPickerMode("edit");
      setOverlay("account-picker");
    },
    [dismissKeyboard],
  );

  const openTransaction = useCallback(
    (account?: AccountRecord, editingEntry?: LedgerEntryRecord) => {
      dismissKeyboard();
      setTransactionTarget({ account: account ?? accounts[0], editingEntry });
      setOverlay("transaction");
    },
    [accounts, dismissKeyboard],
  );

  const openAccountCreate = useCallback(
    (mode: AccountCreateMode = "compact", defaultCategory: AccountCategory = "purchases") => {
      dismissKeyboard();
      setEditingAccount(undefined);
      setAccountCreateCategory(defaultCategory);
      setOverlay(mode === "extended" ? "account-create-extended" : "account-create-compact");
    },
    [dismissKeyboard],
  );

  const openInvoice = useCallback(
    (defaultCategory?: AccountCategory, intent: InvoiceIntent = "invoice") => {
      dismissKeyboard();
      const matchingAccount =
        (defaultCategory ? accounts.find((a) => a.category === defaultCategory) : undefined) ?? accounts[0];
      const kindOverride =
        defaultCategory === "sales" ? "sale" : defaultCategory === "purchases" ? "purchase" : undefined;
      setInvoiceSeed((value) => ({
        account: matchingAccount,
        editingEntry: undefined,
        intent,
        kindOverride,
        revision: value.revision + 1,
      }));
      setOverlay("invoice");
    },
    [accounts, dismissKeyboard],
  );

  const openVendorInvoice = useCallback(
    (account?: AccountRecord, intent: InvoiceIntent = "invoice") => {
      dismissKeyboard();
      const targetAccount = account ?? accounts[0];
      setInvoiceSeed((value) => ({
        account: targetAccount,
        editingEntry: undefined,
        intent,
        kindOverride: targetAccount ? (targetAccount.category === "sales" ? "sale" : "purchase") : undefined,
        revision: value.revision + 1,
      }));
      setOverlay("invoice");
    },
    [accounts, dismissKeyboard],
  );

  const openInvoiceEdit = useCallback(
    (entry: LedgerEntryRecord, account?: AccountRecord) => {
      dismissKeyboard();
      const targetAccount = account ?? accounts.find((a) => a.id === entry.accountId) ?? accounts[0];
      const entryIntent: InvoiceIntent =
        entry.kind === "quote"
          ? "quote"
          : entry.kind === "order"
            ? "order"
            : entry.kind === "return"
              ? "return"
              : "invoice";
      const kindOverride: "purchase" | "sale" =
        entry.kind === "return"
          ? entry.direction === "debit"
            ? "purchase"
            : "sale"
          : entry.direction === "credit"
            ? "purchase"
            : "sale";
      setInvoiceSeed((value) => ({
        account: targetAccount,
        editingEntry: entry,
        intent: entryIntent,
        kindOverride,
        revision: value.revision + 1,
      }));
      setOverlay("invoice");
    },
    [accounts, dismissKeyboard],
  );

  const openDashboardMenu = useCallback(() => {
    dismissKeyboard();
    setOptionsMenuOpen(false);
    setDashboardMenuOpen((value) => !value);
  }, [dismissKeyboard]);

  const openOptionsMenu = useCallback(() => {
    dismissKeyboard();
    setDashboardMenuOpen(false);
    setOptionsMenuOpen((value) => !value);
  }, [dismissKeyboard]);

  const resetWorkspaceToEmptyNow = useCallback(() => {
    dismissKeyboard();
    setOptionsMenuOpen(false);
    setOverlay("confirm-reset");
  }, [dismissKeyboard]);

  const seedDemoWorkspaceNow = useCallback(async () => {
    dismissKeyboard();
    setOptionsMenuOpen(false);
    try {
      await runWithLoader("جاري تجهيز البيانات التجريبية...", () =>
        seedDemoWorkspace(user.uid),
      );
      triggerHaptic("success");
      showToast("تم تحميل بيانات تجريبية في قاعدة البيانات بنجاح.");
    } catch (err) {
      showToast(err instanceof Error ? err.message : "تعذر تحميل البيانات التجريبية.");
    }
  }, [dismissKeyboard, runWithLoader, showToast, user.uid]);

  const confirmResetWorkspaceDatabase = useCallback(async () => {
    try {
      await runWithLoader("جاري تفريغ قاعدة البيانات...", () =>
        resetLocalWorkspaceDatabase(user.uid),
      );
      setOverlay(null);
      triggerHaptic("success");
      showToast("تم تفريغ البيانات بعد التأكيد.");
    } catch (err) {
      showToast(err instanceof Error ? err.message : "تعذر تفريغ البيانات.");
    }
  }, [runWithLoader, showToast, user.uid]);

  const closeOverlay = useCallback(() => {
    dismissKeyboard();
    setOverlay(returnOverlay.current);
    returnOverlay.current = null;
  }, [dismissKeyboard]);

  const openExportMenu = useCallback(
    (kind: ExportKind = "statement", account?: AccountRecord) => {
      dismissKeyboard();
      setExportState((s) => ({ open: !s.open, kind, account }));
    },
    [dismissKeyboard],
  );

  const openPrintOptions = useCallback(
    (kind: ExportKind = "statement", account?: AccountRecord) => {
      dismissKeyboard();
      setExportState((s) => ({ ...s, open: false }));
      setPrintContext({ kind, account });
      setOverlay("print-options");
    },
    [dismissKeyboard],
  );

  const openBackupModal = useCallback(() => {
    dismissKeyboard();
    setOverlay("backup-name");
  }, [dismissKeyboard]);

  const openGoogleDriveModal = useCallback(() => {
    dismissKeyboard();
    setOverlay("google-drive");
  }, [dismissKeyboard]);

  const openFullSqliteImport = useCallback(() => {
    dismissKeyboard();
    setOverlay("full-sqlite-import");
  }, [dismissKeyboard]);

  const setCategoryCurrency = useCallback((category: AccountCategory, currency: string) => {
    setCategoryCurrencies((prev) => ({ ...prev, [category]: currency }));
  }, []);

  const setStatementCurrency = useCallback((accountId: string, currency: string) => {
    setStatementCurrencies((prev) => ({ ...prev, [accountId]: currency }));
  }, []);

  const openTransferModal = useCallback(
    (accountId?: string) => {
      dismissKeyboard();
      setTransferAccountId(accountId);
      setOverlay("transfer");
    },
    [dismissKeyboard],
  );

  const openTrialBalance = useCallback(() => {
    dismissKeyboard();
    setOverlay("trial-balance");
  }, [dismissKeyboard]);

  const openAccountGroups = useCallback(() => {
    dismissKeyboard();
    setOverlay("account-groups");
  }, [dismissKeyboard]);

  const openChartOfAccounts = useCallback(() => {
    dismissKeyboard();
    setOverlay("chart-of-accounts");
  }, [dismissKeyboard]);

  const openCashboxesReport = useCallback(() => {
    dismissKeyboard();
    setOverlay("cashboxes-report");
  }, [dismissKeyboard]);

  const openReportsHub = useCallback(() => {
    dismissKeyboard();
    setOverlay("reports-hub");
  }, [dismissKeyboard]);

  const openCurrenciesManager = useCallback(() => {
    dismissKeyboard();
    setOverlay("currencies-manager");
  }, [dismissKeyboard]);

  const currencyCodes = useMemo<string[]>(() => {
    const names = currencies.map((c) => c.name.trim()).filter(Boolean);
    return names.length > 0 ? Array.from(new Set(names)) : ["ريال"];
  }, [currencies]);

  const buildBackupJsonString = useCallback(
    (backupName: string, exportedAt: string = new Date().toISOString()) => {
      const payload = {
        format: "nasqo-pro-erp-backup",
        version: 2,
        name: backupName,
        exportedAt,
        workspace,
        accountGroups,
        cashboxes,
        accounts,
        ledger,
        warehouses,
        inventory,
        erpData,
      };
      return JSON.stringify(payload, null, 2);
    },
    [accountGroups, accounts, cashboxes, erpData, inventory, ledger, warehouses, workspace],
  );

  const saveLocalNamedBackup = useCallback(
    async (backupName: string) => {
      await runWithLoader("جاري تجهيز وتصدير النسخة الاحتياطية...", async () => {
        const exportedAt = new Date().toISOString();
        const fileName = buildLocalBackupDownloadName(backupName);
        try {
          const serverExport = await fetchUnifiedJsonExport(user.uid);
          const merged =
            serverExport && typeof serverExport === "object"
              ? { ...(serverExport as Record<string, unknown>), name: backupName, exportedAt }
              : JSON.parse(buildBackupJsonString(backupName, exportedAt));
          downloadFile(
            fileName,
            JSON.stringify(merged, null, 2),
            "application/json;charset=utf-8",
          );
          const savedIso = recordLastBackupNow(exportedAt);
          setLastBackupIso(savedIso);
          triggerHaptic("success");
          showToast(`تم تنزيل النسخة الاحتياطية الكاملة: ${fileName}`);
        } catch (err) {
          triggerHaptic("warning");
          showToast(
            err instanceof Error && err.message
              ? `تعذر تصدير النسخة الاحتياطية: ${err.message}`
              : "تعذر تصدير النسخة الاحتياطية الكاملة.",
            6000,
          );
        }
      });
    },
    [buildBackupJsonString, runWithLoader, showToast, user.uid],
  );

  const saveCloudNamedBackup = useCallback(
    async (backupName: string) => {
      await runWithLoader("جاري رفع النسخة الاحتياطية إلى Google Drive...", async () => {
        const exportedAtIso = new Date().toISOString();
        const fileName = buildLocalBackupDownloadName(backupName);
        let token = getGoogleAccessToken();
        if (!token) {
          const authResult = await connectGoogleDrive();
          token = authResult.accessToken;
        }
        try {
          const folder = await findOrCreateDriveFolder(token, "NASQO Pro Backups");
          await uploadFileToDrive(token, {
            name: fileName,
            content: buildBackupJsonString(backupName, exportedAtIso),
            mimeType: "application/json",
            parentId: folder.id,
            description: "نسخة احتياطية كاملة لنظام نسقو برو ERP",
          });
        } catch (err) {
          if (err instanceof DriveAuthExpiredError) {
            const authResult = await connectGoogleDrive();
            const folder = await findOrCreateDriveFolder(authResult.accessToken, "NASQO Pro Backups");
            await uploadFileToDrive(authResult.accessToken, {
              name: fileName,
              content: buildBackupJsonString(backupName, exportedAtIso),
              mimeType: "application/json",
              parentId: folder.id,
              description: "نسخة احتياطية كاملة لنظام نسقو برو ERP",
            });
          } else {
            showToast(
              err instanceof Error
                ? `تعذر الرفع إلى Google Drive: ${err.message}`
                : "تعذر الرفع إلى Google Drive",
            );
            throw err;
          }
        }
        await createCloudBackupRecord(user.uid, {
          name: backupName,
          accountsCount: accounts.length,
          ledgerCount: ledger.length,
          warehousesCount: warehouses.length,
          inventoryCount: inventory.length,
          exportedAtIso,
        });
        const savedIso = recordLastBackupNow(exportedAtIso);
        setLastBackupIso(savedIso);
        showToast(`تم حفظ النسخة في Google Drive: ${fileName}`);
      });
    },
    [
      accounts.length,
      buildBackupJsonString,
      inventory.length,
      ledger.length,
      runWithLoader,
      showToast,
      user.uid,
      warehouses.length,
    ],
  );

  const triggerJsonBackup = useCallback(() => {
    openBackupModal();
  }, [openBackupModal]);

  const triggerJsonRestore = useCallback(() => {
    jsonRestoreInputRef.current?.click();
  }, []);

  const triggerCsvImport = useCallback(() => {
    csvImportInputRef.current?.click();
  }, []);

  const restoreBackupFromBytes = useCallback(
    async (bytes: Uint8Array, fileName: string) => {
      await runWithLoader(`جارٍ استعادة ${fileName} وتجهيز النظام...`, async () => {
        try {
          let effectiveBytes = bytes;
          if (
            effectiveBytes.length >= 2 &&
            effectiveBytes[0] === 0x1f &&
            effectiveBytes[1] === 0x8b &&
            typeof DecompressionStream !== "undefined"
          ) {
            try {
              const copy = new Uint8Array(effectiveBytes);
              const ds = new DecompressionStream("gzip");
              const buf = await new Response(new Blob([copy]).stream().pipeThrough(ds)).arrayBuffer();
              effectiveBytes = new Uint8Array(buf);
            } catch {
              // Fall through with original bytes if not a valid gzip stream
            }
          }
          const inspection = inspectBackupBytes(effectiveBytes, fileName);

          if (inspection.kind === "encrypted") {
            triggerHaptic("warning");
            showToast(
              `الملف ${fileName} مشفّر بكلمة مرور؛ يرجى تصدير نسخة غير مشفرة لإتمام الاستعادة`,
            );
            return;
          }

          if (inspection.kind === "zip") {
            triggerHaptic("warning");
            showToast(
              `الملف ${fileName} مضغوط؛ فك الضغط أولًا ثم اختر ملف النسخة الاحتياطية بالداخل`,
            );
            return;
          }

          if (inspection.kind === "sql") {
            const report = await importSmartProSqlIntoServer(user.uid, inspection.sqlText, fileName, true);
            const imported = (report.imported as Record<string, number>) ?? {};
            triggerHaptic("success");
            showToast(
              `تمت استعادة ${fileName} بنجاح (الصناديق: ${imported.accountGroups ?? 0} • الحسابات: ${imported.accounts ?? 0} • القيود: ${imported.ledgerEntries ?? 0} • الأصناف: ${imported.inventoryItems ?? 0})`,
            );
            return;
          }

          if (inspection.kind === "sqlite") {
            const res = await importSqliteBytesIntoServer(user.uid, effectiveBytes, fileName, "restore", undefined, true);
            const added = (res.result as { added?: Record<string, number> } | undefined)?.added ?? {};
            triggerHaptic("success");
            showToast(
              `تمت استعادة ${fileName} وتجهيز النظام بنجاح (الصناديق: ${added.accountGroups ?? 0} • الحسابات: ${added.accounts ?? 0} • الحركات: ${added.ledger ?? 0} • الأصناف: ${added.inventory ?? 0})`,
            );
            return;
          }

          if (inspection.kind === "invalid-json") {
            triggerHaptic("warning");
            showToast(`تم رفض الملف ${fileName}: ${inspection.reason}`, 6000);
            return;
          }

          if (inspection.kind !== "json") {
            triggerHaptic("warning");
            showToast("تعذر قراءة ملف النسخة الاحتياطية — اختر ملف نسخة احتياطية صالح", 5000);
            return;
          }

          const jsonRes = await restoreJsonBackupIntoServer(
            user.uid,
            inspection.payload as Record<string, unknown>,
          );
          const r = jsonRes.restored ?? {};
          triggerHaptic("success");
          showToast(
            `تمت استعادة ${fileName} بالكامل (المجموعات: ${r.accountGroups ?? 0} • الحسابات: ${r.accounts ?? 0} • القيود: ${r.ledger ?? 0} • البنود: ${r.invoiceLines ?? 0} • الأصناف: ${r.inventory ?? 0})`,
          );
        } catch (err) {
          triggerHaptic("warning");
          if (err instanceof UncertainWriteError) {
            showToast(err.message, 7500);
          } else {
            showToast(
              err instanceof Error && err.message
                ? `تعذر استعادة النسخة: ${err.message}`
                : "تعذر قراءة ملف النسخة الاحتياطية — تأكد من سلامة الملف",
              5500,
            );
          }
        }
      });
    },
    [runWithLoader, showToast, user.uid],
  );

  const handleJsonFileRestore = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    const buffer = await file.arrayBuffer();
    await restoreBackupFromBytes(new Uint8Array(buffer), file.name);
  };

  const handleCsvAccountImport = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    await runWithLoader("جاري استيراد الحسابات من الملف...", async () => {
      try {
        const text = await file.text();
        const lines = text
          .replace(/^\uFEFF/, "")
          .split(/\r?\n/)
          .map((l) => l.trim())
          .filter(Boolean);
        let imported = 0;
        for (let i = 1; i < lines.length; i += 1) {
          const cols = lines[i].split(",").map((c) => c.replace(/^"|"$/g, "").trim());
          const name = cols[0];
          if (!name) continue;
          const phone = cols[1] ?? "";
          const openingBalance = parseArabicNumber(cols[2] ?? "0");
          await createOrUpdateAccount(user.uid, {
            name,
            phone,
            openingBalance,
            openingDirection: "credit",
            category: "purchases",
            codeNumber: accounts.length + imported + 10,
          });
          imported += 1;
        }
        showToast(`تم استيراد ${imported} حساب من الملف`);
      } catch {
        showToast("تعذر استيراد ملف الحسابات");
      }
    });
  };

  const handleSignOut = useCallback(async () => {
    setDrawerOpen(false);
    if (user.uid === LOCAL_WORKSPACE_UID) {
      onLocalSignOut();
      return;
    }
    await signOutUser();
  }, [onLocalSignOut, user.uid]);

  const syncing = !(syncFlags.accounts && syncFlags.ledger && syncFlags.inventory);

  const notifications = useMemo(
    () =>
      computeWorkspaceNotifications(accounts, ledger, warehouses, inventory, workspace, new Date(), {
        lastBackupIso,
      }).filter((n) => !dismissedNotifIds.has(n.id)),
    [accounts, dismissedNotifIds, inventory, lastBackupIso, ledger, warehouses, workspace],
  );

  const unreadNotificationsCount = useMemo(
    () => notifications.filter((n) => !readNotifIds.has(n.id)).length,
    [notifications, readNotifIds],
  );

  const handleMarkNotificationRead = useCallback((id: string) => {
    setReadNotifIds((prev) => {
      const next = new Set(prev);
      next.add(id);
      try {
        window.localStorage.setItem("nasqo-read-notifs", JSON.stringify([...next]));
      } catch {
        // Ignore
      }
      return next;
    });
  }, []);

  const handleMarkAllNotificationsRead = useCallback(() => {
    setReadNotifIds((prev) => {
      const next = new Set(prev);
      notifications.forEach((n) => next.add(n.id));
      try {
        window.localStorage.setItem("nasqo-read-notifs", JSON.stringify([...next]));
      } catch {
        // Ignore
      }
      return next;
    });
  }, [notifications]);

  const handleDismissNotification = useCallback((id: string) => {
    setDismissedNotifIds((prev) => {
      const next = new Set(prev);
      next.add(id);
      try {
        window.localStorage.setItem("nasqo-dismissed-notifs", JSON.stringify([...next]));
      } catch {
        // Ignore
      }
      return next;
    });
  }, []);

  const handleSelectNotification = useCallback(
    (notif: WorkspaceNotification) => {
      setOverlay(null);
      if (notif.targetType === "invoice" && notif.targetId) {
        flowRef.current?.push(cashInvoicePreviewScreen(notif.targetId));
      } else if (notif.targetType === "account" && notif.targetId) {
        flowRef.current?.push(supplierScreen(notif.targetId));
      } else if (notif.targetType === "inventory") {
        flowRef.current?.push(inventoryReportScreen());
      } else if (notif.targetType === "settings") {
        flowRef.current?.push(systemSettingsScreen());
      }
    },
    [],
  );

  const launchFavorite = useCallback(
    (fav: PinnedFavoriteItem) => {
      triggerHaptic("light");
      const flow = flowRef.current;
      const t = fav.target;
      if (t.kind === "route" && flow) {
        if (t.route === "inventory-report") flow.push(inventoryReportScreen());
        else if (t.route === "daily-journal") flow.push(dailyJournalScreen());
        else if (t.route === "purchases") flow.push(purchasesScreen("purchases"));
        else if (t.route === "sales") flow.push(purchasesScreen("sales"));
        else if (t.route === "currency") flow.push(currencyScreen());
        else if (t.route === "shop") flow.push(shopScreen());
      } else if (t.kind === "account" && flow) {
        flow.push(supplierScreen(t.accountId));
      } else if (t.kind === "action") {
        if (t.action === "new-invoice") openInvoice("sales");
        else if (t.action === "new-purchase") openInvoice("purchases");
        else if (t.action === "new-contact") openAccountCreate("extended", "clients");
        else if (t.action === "qr-scan") {
          dismissKeyboard();
          setOverlay("qr-scanner");
        }
      }
    },
    [dismissKeyboard, openAccountCreate, openInvoice],
  );

  const openErpModule = useCallback(
    (moduleId: ErpModuleId) => {
      dismissKeyboard();
      flowRef.current?.push(erpModuleScreen(moduleId));
    },
    [dismissKeyboard],
  );

  const ctx = useMemo<LiveWorkspaceState>(
    () => ({
      uid: user.uid,
      userEmail: user.email ?? "",
      workspace,
      currencies,
      currencyCodes,
      accountGroups,
      accounts,
      cashboxes,
      ledger,
      warehouses,
      inventory,
      categoryCurrencies,
      setCategoryCurrency,
      statementCurrencies,
      setStatementCurrency,
      activeStatementAccountId,
      setActiveStatementAccountId,
      statementFilter,
      setStatementFilter,
      erpData,
      updateErpData,
      openErpModule,
      syncing,
      syncError,
      retryingSync,
      retrySync,
      flowRef,
      openDrawer,
      openSheet,
      openAccountPicker,
      openQuickSearch,
      openAccountEdit,
      openTransaction,
      openAccountCreate,
      openInvoice,
      openVendorInvoice,
      openInvoiceEdit,
      openDashboardMenu,
      openOptionsMenu,
      resetWorkspaceToEmptyNow,
      seedDemoWorkspaceNow,
      openExportMenu,
      openPrintOptions,
      openBackupModal,
      openGoogleDriveModal,
      openFullSqliteImport,
      openTransferModal,
      openTrialBalance,
      openAccountGroups,
      openChartOfAccounts,
      openCashboxesReport,
      openReportsHub,
      openCurrenciesManager,
      openInventoryAdd: () => {
        setInventoryEditing(undefined);
        setOverlay("inventory-add");
      },
      openInventoryEdit: (item: InventoryItemRecord) => {
        dismissKeyboard();
        setInventoryEditing(item);
        setOverlay("inventory-add");
      },
      openSettings: () => {
        dismissKeyboard();
        if (flowRef.current) {
          flowRef.current.push(systemSettingsScreen());
        } else {
          setOverlay("settings");
        }
      },
      openTrash: () => setOverlay("trash"),
      openNotifications: () => {
        triggerHaptic("light");
        dismissKeyboard();
        setOverlay("notifications");
      },
      openQrScanner: () => {
        triggerHaptic("light");
        dismissKeyboard();
        setOverlay("qr-scanner");
      },
      openWhatsAppPicker,
      unreadNotificationsCount,
      themeMode,
      setThemeMode,
      brandColor,
      setBrandColor,
      resetBrandColor,
      hapticsEnabled,
      setHapticsEnabled,
      extendedSettings,
      setExtendedSettings,
      widgetOrder,
      setWidgetOrder,
      homeMetricOrder,
      setHomeMetricOrder,
      favorites,
      pinFavorite,
      unpinFavorite,
      launchFavorite,
      lastBackupIso,
      showToast,
      runWithLoader,
      triggerJsonBackup,
      triggerJsonRestore,
      triggerCsvImport,
      handleSignOut,
    }),
    [
      accountGroups,
      accounts,
      activeStatementAccountId,
      brandColor,
      cashboxes,
      categoryCurrencies,
      currencies,
      currencyCodes,
      statementFilter,
      dismissKeyboard,
      erpData,
      extendedSettings,
      favorites,
      handleSignOut,
      hapticsEnabled,
      homeMetricOrder,
      inventory,
      lastBackupIso,
      launchFavorite,
      ledger,
      openAccountCreate,
      openAccountEdit,
      openAccountGroups,
      openAccountPicker,
      openQuickSearch,
      openBackupModal,
      openCashboxesReport,
      openReportsHub,
      openChartOfAccounts,
      openCurrenciesManager,
      openGoogleDriveModal,
      openFullSqliteImport,
      openDashboardMenu,
      openOptionsMenu,
      resetWorkspaceToEmptyNow,
      seedDemoWorkspaceNow,
      openDrawer,
      openErpModule,
      openExportMenu,
      openInvoice,
      openInvoiceEdit,
      openPrintOptions,
      openSheet,
      openTransaction,
      openTransferModal,
      openTrialBalance,
      openVendorInvoice,
      openWhatsAppPicker,
      pinFavorite,
      resetBrandColor,
      setBrandColor,
      setCategoryCurrency,
      setExtendedSettings,
      setHapticsEnabled,
      setHomeMetricOrder,
      setStatementCurrency,
      statementFilter,
      setThemeMode,
      setWidgetOrder,
      showToast,
      runWithLoader,
      statementCurrencies,
      syncing,
      syncError,
      retryingSync,
      retrySync,
      themeMode,
      triggerCsvImport,
      triggerJsonBackup,
      triggerJsonRestore,
      unpinFavorite,
      unreadNotificationsCount,
      updateErpData,
      user.email,
      user.uid,
      warehouses,
      widgetOrder,
      workspace,
    ],
  );

  const initial = useMemo(() => dashboardScreen(), []);

  const navigateFromDrawer = (target: DrawerTarget) => {
    setDrawerOpen(false);
    if (target === "dashboard") {
      flowRef.current?.reset(dashboardScreen());
      return;
    }
    if (
      target === "erp-hub" ||
      target === "erp-finance" ||
      target === "erp-hr" ||
      target === "erp-crm" ||
      target === "erp-procurement" ||
      target === "erp-manufacturing"
    ) {
      flowRef.current?.push(erpModuleScreen(target));
      return;
    }
    if (target === "accounts") {
      openAccountGroups();
      return;
    }
    if (target === "currency") {
      flowRef.current?.push(currencyScreen(accounts[0]?.id));
      return;
    }
    if (target === "quotes" || target === "orders") {
      openVendorInvoice(accounts[0], target === "quotes" ? "quote" : "order");
      return;
    }
    if (target === "warehouses") {
      flowRef.current?.push(warehousesScreen());
      return;
    }
    if (target === "inventory-report") {
      flowRef.current?.push(inventoryReportScreen());
      return;
    }
    if (target === "items") {
      flowRef.current?.push(itemsScreen());
      return;
    }
    if (target === "shop") {
      flowRef.current?.push(shopScreen());
      return;
    }
    if (target === "purchases") {
      flowRef.current?.push(purchasesScreen("purchases"));
      return;
    }
    if (target === "whatsapp") {
      flowRef.current?.push(whatsappSettingsScreen());
      return;
    }
    if (target === "daily-journal") {
      flowRef.current?.push(dailyJournalScreen());
      return;
    }
    if (target === "analytics-dashboard") {
      flowRef.current?.push(analyticsDashboardScreen());
      return;
    }
    if (target === "trash") {
      setOverlay("trash");
      return;
    }
    if (target === "settings") {
      flowRef.current?.push(systemSettingsScreen());
      return;
    }
  };

  const executeExcelExport = (kind: ExportKind, targetAccount?: AccountRecord) => {
    void runWithBrandLoader(
      "جاري تصدير ملف Excel...",
      () => {
        if (kind === "inventory") {
          const csv = buildCsvContent(
            ["الصنف", "الوحدة", "الكمية", "متوسط التكلفة"],
            inventory.map((i) => [i.name, i.unit, i.quantity, i.avgCost]),
          );
          downloadFile("inventory-report.csv", csv, "text/csv;charset=utf-8");
          showToast("تم تصدير تقرير المخزون بصيغة Excel");
        } else if (kind === "purchases") {
          const csv = buildCsvContent(
            ["الحساب", "الهاتف", "سقف المديونية", "عليه", "له", "الرصيد"],
            accounts
              .filter((a) => a.category === "purchases")
              .map((a) => {
                const s = computeAccountSummary(a, ledger);
                return [a.name, a.phone, a.creditLimit, s.debitTotal, s.creditTotal, s.netBalance];
              }),
          );
          downloadFile("purchases-accounts.csv", csv, "text/csv;charset=utf-8");
          showToast("تم تصدير حسابات المشتريات بصيغة Excel");
        } else {
          const targetAcc = targetAccount ?? accounts[0];
          const statement = targetAcc ? computeStatementRows(targetAcc, ledger) : null;
          const csv = buildCsvContent(
            ["الرقم", "التاريخ", "النوع", "المبلغ", "البيان", "الرصيد"],
            (statement?.rows ?? []).map((r) => [r.entryNumber, r.entryDate, r.typeLabel, r.amount, r.details, r.runningBalance]),
          );
          downloadFile(`statement-${targetAcc?.codeNumber ?? "all"}.csv`, csv, "text/csv;charset=utf-8");
          showToast("تم تصدير كشف الحساب بصيغة Excel");
        }
      },
      { minDurationMs: 420 },
    );
  };

  const handlePrintPngExport = (kind: ExportKind, targetAccount?: AccountRecord) => {
    void runWithBrandLoader(
      "جاري تصدير التقرير كصورة...",
      () => {
        const company = workspace?.companyName || "نسقو برو";
        if (kind === "inventory") {
          const invSummary = computeInventorySummary(inventory);
          exportSummaryAsPngImage({
            filename: "nasqo-inventory-report.png",
            companyName: company,
            title: "تقرير حركة المخزون",
            subtitle: `عدد الأصناف: ${invSummary.items.length} | إجمالي القيمة: ${formatAmount(invSummary.totalValue)}`,
            accentColor: extendedSettings.reportColor || brandColor,
            rows: inventory.slice(0, 10).map((i) => [i.name, `${formatAmount(i.quantity)} ${i.unit}`]),
            footerNote: extendedSettings.statementFooterNote,
          });
        } else if (kind === "purchases") {
          const list = accounts.filter((a) => a.category === "purchases");
          exportSummaryAsPngImage({
            filename: "nasqo-purchases-summary.png",
            companyName: company,
            title: "ملخص حسابات المشتريات والموردين",
            subtitle: `إجمالي الحسابات: ${list.length}`,
            accentColor: extendedSettings.reportColor || brandColor,
            rows: list.slice(0, 10).map((a) => {
              const s = computeAccountSummary(a, ledger);
              return [a.name, `${formatAmount(s.netBalance)} ${a.currency}`];
            }),
            footerNote: extendedSettings.statementFooterNote,
          });
        } else {
          const targetAcc = targetAccount ?? accounts[0];
          const statement = targetAcc ? computeStatementRows(targetAcc, ledger) : null;
          exportSummaryAsPngImage({
            filename: `statement-${targetAcc?.codeNumber ?? "all"}.png`,
            companyName: company,
            title: `كشف حساب: ${targetAcc?.name ?? ""}`,
            subtitle: `الصافي: ${formatAmount(statement?.netBalance ?? 0)} ${targetAcc?.currency ?? "ريال"}`,
            accentColor: extendedSettings.reportColor || brandColor,
            rows: (statement?.rows ?? []).slice(0, 10).map((r) => [
              `${r.typeLabel} (#${r.entryNumber})`,
              `${formatAmount(r.amount)} ${r.currency}`,
            ]),
            footerNote: extendedSettings.statementFooterNote,
          });
        }
        showToast("تم تصدير التقرير كصورة PNG بنجاح");
      },
      { minDurationMs: 420 },
    );
  };

  const handleExportAction = (kind: ExportKind, action: "pdf-print" | "pdf-share" | "excel" | "excel-share" | "balance" | "import") => {
    setExportState((s) => ({ ...s, open: false }));
    if (action === "import") {
      triggerCsvImport();
      return;
    }
    if (action === "pdf-print") {
      openPrintOptions(kind, exportState.account);
      return;
    }
    if (action === "balance") {
      triggerPrintWithLoader("جاري تجهيز مصادقة الرصيد للطباعة...");
      return;
    }
    if (action === "excel" || action === "excel-share") {
      executeExcelExport(kind, exportState.account);
      return;
    }
    if (action === "pdf-share") {
      const targetAcc = exportState.account ?? accounts[0];
      const summary = targetAcc ? computeAccountSummary(targetAcc, ledger) : null;
      const text = targetAcc
        ? `كشف حساب: ${targetAcc.name} | الرصيد: ${formatAmount(summary?.netBalance ?? 0)} ${targetAcc.currency}`
        : `تقرير ${workspace?.companyName ?? "نسقو برو"}`;
      void shareOrCopyText("كشف حساب - نسقو برو", text, showToast);
    }
  };

  // Hardware/system Back closes transient UI before navigating the screen stack.
  // At the dashboard the history guard keeps the installed PWA in the app.
  const handleSystemBack = () => {
    if (overlay) { setOverlay(null); return true; }
    if (drawerOpen) { setDrawerOpen(false); return true; }
    if (optionsMenuOpen) { setOptionsMenuOpen(false); return true; }
    if (dashboardMenuOpen) { setDashboardMenuOpen(false); return true; }
    if (exportState.open) { setExportState((current) => ({ ...current, open: false })); return true; }
    if (sheet) { setSheet(null); return true; }
    return false;
  };

  return (
    <WorkspaceContext.Provider value={ctx}>
      <div className="nasqo-app" dir="rtl">
        <FlowStack initial={initial} onSystemBack={handleSystemBack} />
        {user.uid !== LOCAL_WORKSPACE_UID && syncing && cloudInitializationError ? (
          <div className="nasqo-cloud-hydration-lock" role="status" data-testid="cloud-hydration-lock">
            <section>
              <h2>واجهة نسق برو جاهزة</h2>
              <p>{cloudInitializationError || "جارٍ جلب السجلات الحقيقية من حساب Google. التعديل المالي متوقف لحين اكتمال المزامنة؛ لن نعرض بيانات تخمينية."}</p>
              <button type="button" onClick={() => window.location.reload()}>إعادة الاتصال دون حذف البيانات</button>
            </section>
          </div>
        ) : null}
        <AppDrawer
          open={drawerOpen}
          onClose={() => setDrawerOpen(false)}
          onNavigate={navigateFromDrawer}
        />
        <DashboardAddMenu open={dashboardMenuOpen} onClose={() => setDashboardMenuOpen(false)} />
        <HeaderOptionsMenu open={optionsMenuOpen} onClose={() => setOptionsMenuOpen(false)} />
        <ExportSideMenu
          open={exportState.open}
          kind={exportState.kind}
          onClose={() => setExportState((s) => ({ ...s, open: false }))}
          onSelectAction={(action) => handleExportAction(exportState.kind, action)}
        />
        <InvoiceModal
          key={invoiceSeed.revision}
          initialAccount={invoiceSeed.account}
          editingEntry={invoiceSeed.editingEntry}
          intent={invoiceSeed.intent}
          kindOverride={invoiceSeed.kindOverride}
          open={overlay === "invoice"}
          onClose={closeOverlay}
          onAddAccount={() => {
            returnOverlay.current = "invoice";
            openAccountCreate("extended");
          }}
        />
        <AccountPickerModal
          open={overlay === "account-picker"}
          title={
            pickerMode === "edit"
              ? "تعديل بيانات حساب"
              : pickerMode === "whatsapp"
                ? "مراسلة عبر واتساب"
                : pickerMode === "search"
                  ? "البحث السريع"
                  : "كشف حساب"
          }
          onClose={() => setOverlay(null)}
          onAddAccount={() => openAccountCreate("compact")}
          onConfirm={(account) => {
            if (pickerMode === "edit") {
              setEditingAccount(account);
              setOverlay("account-create-compact");
            } else if (pickerMode === "whatsapp") {
              setOverlay(null);
              const s = computeAccountSummary(account, ledger);
              const msg = buildAccountBalanceMessage(
                account,
                s.netBalance,
                s.tone,
                workspace?.companyName,
                extendedSettings,
              );
              void openWhatsAppChat(account, msg, showToast);
            } else {
              setOverlay(null);
              flowRef.current?.push(supplierScreen(account.id));
            }
          }}
        />
        <TransactionModal
          open={overlay === "transaction"}
          initialAccount={transactionTarget.account}
          editingEntry={transactionTarget.editingEntry}
          onClose={() => setOverlay(null)}
        />
        <AccountCreateModal
          key={editingAccount?.id ?? `new-${accountCreateCategory}-${overlay}`}
          initialAccount={editingAccount}
          defaultCategory={accountCreateCategory}
          mode="compact"
          open={overlay === "account-create-compact"}
          onClose={() => setOverlay(null)}
        />
        <AccountCreateModal
          key={editingAccount?.id ?? `ext-${accountCreateCategory}-${overlay}`}
          initialAccount={editingAccount}
          defaultCategory={accountCreateCategory}
          mode="extended"
          open={overlay === "account-create-extended"}
          onClose={closeOverlay}
        />
        <TrashModal open={overlay === "trash"} onClose={() => setOverlay(null)} />
        <TrialBalanceModal open={overlay === "trial-balance"} onClose={() => setOverlay(null)} />
        <AccountGroupsModal open={overlay === "account-groups"} onClose={() => setOverlay(null)} />
        <ChartOfAccountsModal open={overlay === "chart-of-accounts"} onClose={() => setOverlay(null)} />
        <CashboxesReportModal open={overlay === "cashboxes-report"} onClose={() => setOverlay(null)} />
        <ReportsHubModal
          open={overlay === "reports-hub"}
          onClose={() => setOverlay(null)}
          uid={user.uid}
          accounts={accounts}
          ledger={ledger}
          inventory={inventory}
          warehouses={warehouses}
          cashboxes={cashboxes}
          currencyCodes={currencyCodes}
          defaultCurrency={workspace?.defaultCurrency ?? "ريال"}
          onOpenCashboxes={openCashboxesReport}
          onOpenTrialBalance={openTrialBalance}
          onOpenInventoryMovements={() => flowRef.current?.push(inventoryReportScreen())}
        />
        <CurrenciesModal open={overlay === "currencies-manager"} onClose={() => setOverlay(null)} />
        <ResetDatabaseConfirmModal
          open={overlay === "confirm-reset"}
          onClose={() => setOverlay(null)}
          onConfirm={confirmResetWorkspaceDatabase}
        />
        <WorkspaceSettingsModal open={overlay === "settings"} onClose={() => setOverlay(null)} />
        <InventoryItemModal
          open={overlay === "inventory-add"}
          editing={inventoryEditing}
          onClose={() => {
            setOverlay(null);
            setInventoryEditing(undefined);
          }}
        />
        <PrintOptionsModal
          open={overlay === "print-options"}
          subjectLabel={
            printContext.account
              ? `كشف حساب: ${printContext.account.name}`
              : printContext.kind === "inventory"
                ? "تقرير حركة المخزون"
                : printContext.kind === "purchases"
                  ? "تقرير المشتريات والموردين"
                  : undefined
          }
          onClose={() => setOverlay(null)}
          onPrintPdf={(allCurrencies) => {
            triggerPrintWithLoader(
              allCurrencies ? "جاري تجهيز طباعة جميع العملات..." : "جاري تجهيز معاينة الطباعة PDF...",
            );
            showToast(allCurrencies ? "تم فتح معاينة PDF لجميع العملات" : "تم فتح معاينة PDF");
          }}
          onExportExcel={() => executeExcelExport(printContext.kind, printContext.account)}
          onExportImage={() => handlePrintPngExport(printContext.kind, printContext.account)}
          onShare={() => {
            const targetAcc = printContext.account ?? accounts[0];
            const summary = targetAcc ? computeAccountSummary(targetAcc, ledger) : null;
            const text = targetAcc
              ? `كشف حساب: ${targetAcc.name} | الرصيد: ${formatAmount(summary?.netBalance ?? 0)} ${targetAcc.currency}`
              : `تقرير ${workspace?.companyName ?? "نسقو برو"}`;
            void shareOrCopyText("تقرير نسقو برو", text, showToast);
          }}
          onSendWhatsApp={() => {
            const targetAcc = printContext.account ?? accounts[0];
            if (targetAcc) {
              const summary = computeAccountSummary(targetAcc, ledger);
              const msg = buildAccountBalanceMessage(
                targetAcc,
                summary.netBalance,
                summary.tone,
                workspace?.companyName,
                extendedSettings,
              );
              void openWhatsAppChat(targetAcc, msg, showToast);
            } else {
              void openWhatsAppChat(undefined, `تقرير ${workspace?.companyName ?? "نسقو برو"}`, showToast);
            }
          }}
        />
        <BackupNameModal
          open={overlay === "backup-name"}
          onClose={() => setOverlay(null)}
          onSaveLocal={saveLocalNamedBackup}
          onSaveToGoogle={saveCloudNamedBackup}
        />
        <Suspense fallback={<NasqoBrandLoader size="md" label="جاري فتح مركز البيانات..." />}>
        {overlay === "full-sqlite-import" ? (
          <FullSqliteImportModal
          open
          onClose={() => setOverlay(null)}
          workspaceId={user.uid}
          liveWorkspace={workspace}
          liveAccounts={accounts}
          liveWarehouses={warehouses}
          liveInventory={inventory}
          liveLedger={ledger}
          onNotify={showToast}
          />
        ) : null}
        </Suspense>
        <GoogleDriveModal
          open={overlay === "google-drive"}
          onClose={() => setOverlay(null)}
          buildBackupPayloadJson={(backupName) => buildBackupJsonString(backupName)}
          onBackupUploaded={(fileName) => {
            const savedIso = recordLastBackupNow();
            setLastBackupIso(savedIso);
            void createCloudBackupRecord(user.uid, {
              name: fileName,
              accountsCount: accounts.length,
              ledgerCount: ledger.length,
              warehousesCount: warehouses.length,
              inventoryCount: inventory.length,
              exportedAtIso: savedIso,
            });
          }}
          onRestoreBackupBytes={restoreBackupFromBytes}
          onNotify={showToast}
        />
        <TransferModal
          open={overlay === "transfer"}
          uid={user.uid}
          accounts={accounts}
          cashboxes={cashboxes}
          currencyOptions={currencyCodes}
          ledger={ledger}
          defaultAccountId={transferAccountId}
          onClose={() => setOverlay(null)}
          onCreateAccount={() => {
            returnOverlay.current = "transfer";
            openAccountCreate("extended");
          }}
          onNotify={showToast}
          onSendWhatsApp={(account, message) => void openWhatsAppChat(account, message, showToast)}
          onGenerateImage={(data) => {
            void runWithBrandLoader(
              "جاري تصدير صورة سند الحوالة...",
              () => {
                exportSummaryAsPngImage({
                  filename: `nasqo-transfer-${Date.now()}.png`,
                  companyName: workspace?.companyName || "نسقو برو",
                  title: data.title,
                  subtitle: data.subtitle,
                  accentColor: extendedSettings.reportColor || brandColor,
                  rows: data.rows,
                  footerNote: extendedSettings.statementFooterNote,
                });
                showToast("تم تنزيل صورة سند الحوالة بنجاح");
              },
              { minDurationMs: 420 },
            );
          }}
        />
        <NotificationCenter
          open={overlay === "notifications"}
          onClose={() => setOverlay(null)}
          notifications={notifications}
          readIds={readNotifIds}
          onMarkRead={handleMarkNotificationRead}
          onMarkAllRead={handleMarkAllNotificationsRead}
          onDismiss={handleDismissNotification}
          onSelectNotification={handleSelectNotification}
        />
        {overlay === "qr-scanner" ? (
          <Suspense fallback={<NasqoBrandLoader size="md" label="جاري فتح الماسح..." />}>
            <QrScannerModal
          open={overlay === "qr-scanner"}
          onClose={() => setOverlay(null)}
          uid={user.uid}
          inventory={inventory}
          warehouses={warehouses}
          onNotify={showToast}
          onOpenInventoryReport={() => {
            setOverlay(null);
            flowRef.current?.push(inventoryReportScreen());
          }}
            />
          </Suspense>
        ) : null}

        <input
          ref={jsonRestoreInputRef}
          data-testid="restore-backup-file-input"
          type="file"
          accept=".sql,.back,.sqlite,.sqlite3,.db,.json,application/json,application/x-sqlite3,text/plain,application/octet-stream"
          style={{ display: "none" }}
          onChange={handleJsonFileRestore}
        />
        <input
          ref={csvImportInputRef}
          type="file"
          accept=".csv,text/csv"
          style={{ display: "none" }}
          onChange={handleCsvAccountImport}
        />

        <BottomSheet
          open={sheet !== null}
          onOpenChange={(open) => !open && setSheet(null)}
          title={sheetTitle(sheet)}
          description={sheetDescription(sheet)}
          snap={0.6}
        >
          <SheetContent kind={sheet} setKind={setSheet} />
        </BottomSheet>

        <GlobalNasqoBrandLoader logoUrl={extendedSettings.logoDataUrl || undefined} />

        {toast ? (
          <div className="app-toast" role="status" aria-live="polite">
            <CheckCircledIcon />
            <span>{toast}</span>
          </div>
        ) : null}
      </div>
    </WorkspaceContext.Provider>
  );
}

function dashboardScreen(): FlowScreen {
  return {
    id: "dashboard",
    headerHeight: 52,
    header: () => <DashboardHeader />,
    footerHeight: 68,
    footer: (flow) => <DashboardBottomNav flow={flow} />,
    render: (flow) => <DashboardPage flow={flow} />,
  };
}

function DashboardBottomNav({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  const keyboard = useKeyboard();
  const { screenRef } = useScreenPortal();
  const [quickOpen, setQuickOpen] = useState(false);

  useEffect(() => {
    if (!quickOpen) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") setQuickOpen(false);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [quickOpen]);

  const scrollHomeTop = () => {
    setQuickOpen(false);
    triggerHaptic("light");
    const scroller =
      document.querySelector(".dashboard-scroll .mobile-scroll-content") ??
      document.querySelector(".dashboard-scroll");
    if (scroller && typeof (scroller as HTMLElement).scrollTo === "function") {
      (scroller as HTMLElement).scrollTo({ top: 0, behavior: "smooth" });
    }
  };

  const toggleQuickSheet = () => {
    keyboard.hide();
    triggerHaptic(quickOpen ? "light" : "pin");
    setQuickOpen((prev) => !prev);
  };

  const runQuickAction = (action: () => void) => {
    keyboard.hide();
    triggerHaptic("light");
    setQuickOpen(false);
    action();
  };

  const quickActions = [
    {
      id: "transfer",
      label: "حوالة جديدة",
      testId: "home-quick-transfer",
      onClick: () => runQuickAction(() => ctx.openTransferModal()),
      icon: (
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
          <path d="M21 3 10 14" />
          <path d="m21 3-6.5 18a.55.55 0 0 1-1 0L10 14l-7-3.5a.55.55 0 0 1 0-1L21 3Z" />
        </svg>
      ),
    },
    {
      id: "barcode",
      label: "مسح باركود",
      testId: "home-quick-barcode",
      onClick: () => runQuickAction(() => ctx.openQrScanner()),
      icon: (
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
          <path d="M4 8V6a2 2 0 0 1 2-2h2" />
          <path d="M16 4h2a2 2 0 0 1 2 2v2" />
          <path d="M20 16v2a2 2 0 0 1-2 2h-2" />
          <path d="M8 20H6a2 2 0 0 1-2-2v-2" />
          <path d="M7.5 12h9" />
          <path d="M9.5 8.5h5" />
          <path d="M9.5 15.5h5" />
        </svg>
      ),
    },
    {
      id: "invoice",
      label: "فاتورة جديدة",
      testId: "home-quick-invoice",
      onClick: () => runQuickAction(() => ctx.openInvoice()),
      icon: (
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
          <path d="M6 3h12a1 1 0 0 1 1 1v17l-2.5-1.6L14 21l-2-1.6L10 21l-2.5-1.6L5 21V4a1 1 0 0 1 1-1Z" />
          <path d="M9 8.5h6" />
          <path d="M9 12.5h6" />
          <path d="M9 16.5h4" />
        </svg>
      ),
    },
    {
      id: "voucher",
      label: "سند جديد",
      testId: "home-quick-voucher",
      onClick: () => runQuickAction(() => ctx.openTransaction()),
      icon: (
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
          <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8Z" />
          <path d="M14 3v5h5" />
          <path d="M12 11v6" />
          <path d="M9 14h6" />
        </svg>
      ),
    },
  ];

  const backdropPortal = screenRef.current
    ? createPortal(
        <AnimatePresence>
          {quickOpen ? (
            <motion.div
              key="home-quick-backdrop"
              className="home-quick-sheet-backdrop"
              aria-hidden="true"
              data-testid="home-quick-sheet-backdrop"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.24, ease: [0.22, 1, 0.36, 1] }}
              onClick={() => {
                triggerHaptic("light");
                setQuickOpen(false);
              }}
            />
          ) : null}
        </AnimatePresence>,
        screenRef.current,
      )
    : null;

  return (
    <>
      {backdropPortal}
      <nav
        className={`home-bottom-nav${quickOpen ? " quick-open" : ""}`}
        aria-label="الشريط السفلي للشاشة الرئيسية"
        data-testid="home-bottom-nav"
      >
        <AnimatePresence>
          {quickOpen ? (
            <motion.div
              key="home-quick-sheet"
              className="home-quick-sheet"
              role="dialog"
              aria-label="إجراءات سريعة"
              data-testid="home-quick-sheet"
              initial={{ opacity: 0, y: 46, scale: 0.86 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{
                opacity: 0,
                y: 36,
                scale: 0.9,
                transition: { duration: 0.2, ease: [0.32, 0.72, 0, 1] },
              }}
              transition={{
                type: "spring",
                stiffness: 380,
                damping: 27,
                mass: 0.82,
              }}
            >
              <div className="home-quick-sheet-grid">
                {quickActions.map((item, idx) => (
                  <motion.button
                    key={item.id}
                    type="button"
                    className="home-quick-sheet-cell"
                    data-testid={item.testId}
                    initial={{ opacity: 0, y: 14, scale: 0.94 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={{ opacity: 0, y: 8, transition: { duration: 0.12 } }}
                    transition={{
                      type: "spring",
                      stiffness: 420,
                      damping: 26,
                      delay: 0.045 + idx * 0.035,
                    }}
                    whileTap={{ scale: 0.94 }}
                    onClick={item.onClick}
                  >
                    <span className="home-quick-sheet-icon" aria-hidden="true">
                      {item.icon}
                    </span>
                    <span className="home-quick-sheet-label">{item.label}</span>
                  </motion.button>
                ))}
              </div>
            </motion.div>
          ) : null}
        </AnimatePresence>

        <button
          type="button"
          className="home-bottom-nav-item active"
          aria-current="page"
          data-testid="home-nav-home"
          onClick={scrollHomeTop}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true" className="home-bottom-nav-svg">
            <path
              fill="currentColor"
              d="M11.17 3.32a1.3 1.3 0 0 1 1.66 0l7.6 6.38c.36.3.57.75.57 1.22v8.28c0 1-.8 1.8-1.8 1.8h-4.4a.8.8 0 0 1-.8-.8v-4.7a2 2 0 0 0-4 0v4.7a.8.8 0 0 1-.8.8H4.8c-1 0-1.8-.8-1.8-1.8v-8.28c0-.47.21-.92.57-1.22l7.6-6.38Z"
            />
          </svg>
          <span>الرئيسية</span>
        </button>

        <button
          type="button"
          className="home-bottom-nav-item"
          data-testid="home-nav-services"
          onClick={() => {
            setQuickOpen(false);
            triggerHaptic("light");
            flow.push(erpModuleScreen("erp-hub"));
          }}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true" className="home-bottom-nav-svg">
            <path
              fill="currentColor"
              d="M8.5 7V6a3.5 3.5 0 1 1 7 0v1h2.7c1.05 0 1.9.85 1.9 1.9v9.2A2.9 2.9 0 0 1 17.2 21H6.8a2.9 2.9 0 0 1-2.9-2.9V8.9C3.9 7.85 4.75 7 5.8 7h2.7Zm1.8 0h3.4V6a1.7 1.7 0 1 0-3.4 0v1Z"
            />
          </svg>
          <span>الخدمات</span>
        </button>

        <div className="home-bottom-nav-center-slot">
          <motion.button
            type="button"
            className={`home-bottom-nav-fab${quickOpen ? " is-open" : ""}`}
            aria-label={quickOpen ? "إغلاق الإجراءات السريعة" : "الإجراءات السريعة"}
            aria-expanded={quickOpen}
            data-testid="home-nav-center-fab"
            animate={{ scale: quickOpen ? 1.05 : 1, y: quickOpen ? -2 : 0 }}
            whileTap={{ scale: 0.89 }}
            transition={{ type: "spring", stiffness: 440, damping: 24 }}
            onClick={toggleQuickSheet}
          >
            <AnimatePresence mode="wait" initial={false}>
              {quickOpen ? (
                <motion.svg
                  key="fab-close"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                  className="home-bottom-nav-fab-svg"
                  initial={{ opacity: 0, rotate: -90, scale: 0.6 }}
                  animate={{ opacity: 1, rotate: 0, scale: 1 }}
                  exit={{ opacity: 0, rotate: 90, scale: 0.6 }}
                  transition={{ type: "spring", stiffness: 460, damping: 26 }}
                >
                  <path
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.9"
                    strokeLinecap="round"
                    d="M7 7l10 10M17 7 7 17"
                  />
                </motion.svg>
              ) : (
                <motion.svg
                  key="fab-open"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                  className="home-bottom-nav-fab-svg"
                  initial={{ opacity: 0, y: 6, scale: 0.7 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -6, scale: 0.7 }}
                  transition={{ type: "spring", stiffness: 460, damping: 26 }}
                >
                  <path
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="3.1"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    d="M6.8 12.6 12 7.4l5.2 5.2"
                  />
                  <circle cx="12" cy="16.8" r="2.2" fill="currentColor" />
                </motion.svg>
              )}
            </AnimatePresence>
          </motion.button>
        </div>

        <button
          type="button"
          className="home-bottom-nav-item"
          data-testid="home-nav-reports"
          onClick={() => {
            setQuickOpen(false);
            triggerHaptic("light");
            ctx.openReportsHub();
          }}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true" className="home-bottom-nav-svg">
            <circle cx="5.2" cy="7" r="1.7" fill="currentColor" />
            <rect x="9.2" y="5.6" width="10.8" height="2.8" rx="1.4" fill="currentColor" />
            <circle cx="5.2" cy="12.2" r="1.7" fill="currentColor" />
            <rect x="9.2" y="10.8" width="10.8" height="2.8" rx="1.4" fill="currentColor" />
            <circle cx="5.2" cy="17.4" r="1.7" fill="currentColor" />
            <rect x="9.2" y="16" width="10.8" height="2.8" rx="1.4" fill="currentColor" />
          </svg>
          <span>التقارير</span>
        </button>

        <button
          type="button"
          className="home-bottom-nav-item"
          data-testid="home-nav-profile"
          onClick={() => {
            setQuickOpen(false);
            triggerHaptic("light");
            ctx.openSettings();
          }}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true" className="home-bottom-nav-svg">
            <circle cx="12" cy="7.6" r="4" fill="currentColor" />
            <path
              fill="currentColor"
              d="M4.6 19.6c0-3.3 3.3-5.6 7.4-5.6s7.4 2.3 7.4 5.6c0 .8-.65 1.4-1.45 1.4H6.05c-.8 0-1.45-.6-1.45-1.4Z"
            />
          </svg>
          <span>الملف</span>
        </button>
      </nav>
    </>
  );
}

function DashboardHeader() {
  const ctx = useWorkspace();
  const displayTitle =
    !ctx.workspace?.companyName ||
    ctx.workspace.companyName === "نسقو برو" ||
    ctx.workspace.companyName === "نسقو برو ERP"
      ? "نسقو برو"
      : ctx.workspace.companyName;
  return (
    <AppHeader
      className="dashboard-header"
      title={displayTitle}
      subtitle=""
      onMenu={ctx.openDrawer}
      leadingTextActions={[
        {
          label: "خيارات",
          testId: "header-options-btn",
          onClick: ctx.openOptionsMenu,
        },
      ]}
      actions={[
        { label: "واتساب", icon: WhatsAppIcon, onClick: ctx.openWhatsAppPicker },
        { label: "سلة المحذوفات", icon: TrashIcon, onClick: ctx.openTrash },
        { label: "بحث", icon: MagnifyingGlassIcon, onClick: ctx.openQuickSearch },
        {
          label: "التنبيهات",
          icon: BellIcon,
          badge: ctx.unreadNotificationsCount > 0 ? String(ctx.unreadNotificationsCount) : undefined,
          onClick: ctx.openNotifications,
        },
        { label: "إضافة", icon: PlusIcon, onClick: ctx.openDashboardMenu },
      ]}
    />
  );
}

function purchasesScreen(
  category: AccountCategory = "purchases",
  groupId?: number,
  groupTitle?: string,
): FlowScreen {
  return {
    id: `accounts-${category}-${groupId ?? "all"}`,
    headerHeight: 58,
    header: (flow) => <PurchasesHeader flow={flow} category={category} groupTitle={groupTitle} />,
    footerHeight: 54,
    footer: () => <CategoryFinancialFooter category={category} groupId={groupId} />,
    render: (flow) => <PurchasesPage flow={flow} category={category} groupId={groupId} />,
  };
}

function PurchasesHeader({
  flow,
  category,
  groupTitle,
}: {
  flow: FlowControls;
  category: AccountCategory;
  groupTitle?: string;
}) {
  const ctx = useWorkspace();
  return (
    <AppHeader
      title={groupTitle || categoryTitle(category)}
      subtitle=""
      onBack={flow.pop}
      actions={[
        { label: "طباعة", icon: FileTextIcon, onClick: () => ctx.openPrintOptions("purchases") },
        { label: "تصفية", icon: MixerHorizontalIcon, onClick: () => ctx.openSheet("filters") },
        { label: "تصدير المشتريات", icon: DownloadIcon, onClick: () => ctx.openExportMenu("purchases") },
        { label: "بحث", icon: MagnifyingGlassIcon, onClick: ctx.openAccountPicker },
      ]}
    />
  );
}

function CategoryFinancialFooter({ category, groupId }: { category: AccountCategory; groupId?: number }) {
  const ctx = useWorkspace();
  const activeCurrency = ctx.categoryCurrencies[category] ?? ctx.workspace?.defaultCurrency ?? "ريال";
  const currencyFilter = activeCurrency === "الكل" ? undefined : activeCurrency;
  const catAccounts = ctx.accounts.filter((a) =>
    groupId !== undefined ? a.groupId === groupId : a.category === category,
  );
  let debit = 0;
  let credit = 0;
  for (const acc of catAccounts) {
    const s = computeAccountSummary(acc, ctx.ledger, currencyFilter);
    debit += s.debitTotal;
    credit += s.creditTotal;
  }
  const balance = Math.abs(credit - debit);
  return (
    <FinancialFooter
      debit={formatAmount(debit)}
      credit={formatAmount(credit)}
      balance={formatAmount(balance)}
      hidePrimaryAction
      onPrimary={() => ctx.openAccountCreate("extended", category)}
      onMenu={() => ctx.openExportMenu("purchases")}
    />
  );
}

function supplierScreen(accountId: string): FlowScreen {
  const cashMenuControl: MutableRefObject<(() => void) | null> = { current: null };
  const cashSearchControl: MutableRefObject<(() => void) | null> = { current: null };
  return {
    id: `supplier-${accountId}`,
    headerHeight: 58,
    header: (flow) => (
      <SupplierHeader
        flow={flow}
        accountId={accountId}
        onSearch={() => cashSearchControl.current?.()}
      />
    ),
    footerHeight: 54,
    footer: () => (
      <SupplierFooter
        accountId={accountId}
        onCashMenu={() => cashMenuControl.current?.()}
      />
    ),
    render: (flow) => {
      return (
        <SupplierScreenRouter
          flow={flow}
          accountId={accountId}
          menuControl={cashMenuControl}
          searchControl={cashSearchControl}
        />
      );
    },
  };
}

function SupplierHeader({
  flow,
  accountId,
  onSearch,
}: {
  flow: FlowControls;
  accountId: string;
  onSearch: () => void;
}) {
  const ctx = useWorkspace();
  const account = ctx.accounts.find((a) => a.id === accountId) ?? ctx.accounts[0];
  const isCashAccount = Boolean(account?.isCashAccount);
  return (
    <AppHeader
      title={isCashAccount ? `مشتريات ${account.name}` : account?.name || "كشف الحساب"}
      subtitle={isCashAccount ? "" : "كشف حساب"}
      className={isCashAccount ? "cash-statement-header" : ""}
      onBack={flow.pop}
      actions={[
        { label: "طباعة الكشف", icon: FileTextIcon, onClick: () => ctx.openPrintOptions("statement", account) },
        { label: "تصفية", icon: MixerHorizontalIcon, onClick: () => ctx.openSheet("filters") },
        { label: "تصدير", icon: DownloadIcon, onClick: () => ctx.openExportMenu("statement", account) },
        { label: "بحث", icon: MagnifyingGlassIcon, onClick: onSearch },
      ]}
    />
  );
}

function SupplierFooter({
  accountId,
  onCashMenu,
}: {
  accountId: string;
  onCashMenu: () => void;
}) {
  const ctx = useWorkspace();
  const account = ctx.accounts.find((a) => a.id === accountId) ?? ctx.accounts[0];
  if (!account) return null;
  const activeCurrency = ctx.statementCurrencies[account.id] ?? account.currency ?? "ريال";
  const statement = computeStatementRows(account, ctx.ledger, {
    currency: activeCurrency,
    showPreviousBalance: !account.isCashAccount,
  });
  if (account.isCashAccount) {
    return <CashStatementFooter account={account} statement={statement} onMenu={onCashMenu} />;
  }
  return (
    <FinancialFooter
      debit={formatAmount(statement.debitTotal)}
      credit={formatAmount(statement.creditTotal)}
      balance={formatAmount(statement.netBalance)}
      compact
      onPrimary={() => ctx.flowRef.current?.push(simpleEntryScreen(account.id))}
      onMenu={onCashMenu}
    />
  );
}

function SupplierScreenRouter({
  flow,
  accountId,
  menuControl,
  searchControl,
}: {
  flow: FlowControls;
  accountId: string;
  menuControl: MutableRefObject<(() => void) | null>;
  searchControl: MutableRefObject<(() => void) | null>;
}) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const account = ctx.accounts.find((a) => a.id === accountId) ?? ctx.accounts[0];
  if (!account) {
    return (
      <MobileScroll className="app-screen">
        <p className="cash-empty">لم يُعثر على هذا الحساب.</p>
      </MobileScroll>
    );
  }
  return account.isCashAccount ? (
    <CashSupplierPage account={account} menuControl={menuControl} searchControl={searchControl} />
  ) : (
    <SupplierPage account={account} menuControl={menuControl} searchControl={searchControl} />
  );
}

function shopScreen(): FlowScreen {
  return {
    id: "shop",
    headerHeight: 58,
    header: (flow) => <ShopHeader flow={flow} />,
    footerHeight: 54,
    footer: () => <ShopFooter />,
    render: (flow) => <ShopPage flow={flow} />,
  };
}

function ShopHeader({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  return (
    <AppHeader
      title="المحل"
      subtitle=""
      onBack={flow.pop}
      actions={[
        { label: "تصفية", icon: MixerHorizontalIcon, onClick: () => ctx.openSheet("filters") },
        { label: "تصدير", icon: DownloadIcon, onClick: () => ctx.openExportMenu("purchases") },
        { label: "بحث", icon: MagnifyingGlassIcon, onClick: ctx.openAccountPicker },
      ]}
    />
  );
}

function ShopFooter() {
  const ctx = useWorkspace();
  const shopAccounts = ctx.accounts.filter((a) => a.category === "shop");
  let debit = 0;
  let credit = 0;
  for (const a of shopAccounts) {
    const s = computeAccountSummary(a, ctx.ledger);
    debit += s.debitTotal;
    credit += s.creditTotal;
  }
  const balance = Math.abs(credit - debit);
  return (
    <div className="shop-totals">
      <button
        type="button"
        className="shop-totals-action"
        aria-label="تحويل الرصيد"
        onClick={() => ctx.flowRef.current?.push(simpleEntryScreen())}
      >
        <TransferArrowsIcon />
      </button>
      <span>
        عليه: {formatAmount(debit)} · له: {formatAmount(credit)} · الرصيد: {formatAmount(balance)}
      </span>
      <button
        type="button"
        className="shop-totals-menu"
        aria-label="خيارات التصدير"
        onClick={() => ctx.openExportMenu("purchases")}
      >
        <HamburgerMenuIcon />
      </button>
    </div>
  );
}

function ShopPage({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const [period, setPeriod] = useState("الكل");
  const [sortBy, setSortBy] = useState<"date" | "name">("date");
  const [sort, setSort] = useState("تنازلي");
  const [currencyFilter, setCurrencyFilter] = useState<string>(ctx.workspace?.defaultCurrency ?? "ريال");
  const [byCurrency, setByCurrency] = useState(false);
  const [visibleCount, setVisibleCount] = useState(60);

  const periodRange = useMemo(() => computePeriodDateRange(period), [period]);
  const periodLedger = useMemo(() => {
    if (!periodRange.fromDate && !periodRange.toDate) return ctx.ledger;
    return ctx.ledger.filter((e) => {
      const d = e.entryDate || "";
      if (periodRange.fromDate && d < periodRange.fromDate) return false;
      if (periodRange.toDate && d > periodRange.toDate) return false;
      return true;
    });
  }, [ctx.ledger, periodRange.fromDate, periodRange.toDate]);

  const activeCurrencyParam = currencyFilter === "الكل" ? undefined : currencyFilter;
  const shopAccounts = ctx.accounts.filter(
    (a) => a.category === "shop" && (!byCurrency || !activeCurrencyParam || a.currency === activeCurrencyParam),
  );
  const sorted =
    sortBy === "name"
      ? [...shopAccounts].sort((a, b) => a.name.localeCompare(b.name, "ar"))
      : [...shopAccounts];
  const ordered = sort === "تصاعدي" ? [...sorted].reverse() : sorted;

  return (
    <>
      <MobileScroll className="app-screen">
        <main className="shop-page page-with-footer" data-testid="shop-screen">
          <section className="shop-filters">
            <div className="reference-radio-row">
              {["يومي", "شهري", "الكل", "سنوي"].map((item) => (
                <label key={item}>
                  <input type="radio" name="shop-period" checked={period === item} onChange={() => setPeriod(item)} />
                  {item}
                </label>
              ))}
            </div>
            <div className="shop-sort">
              <select
                aria-label="ترتيب الحسابات"
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value === "name" ? "name" : "date")}
              >
                <option value="date">ترتيب حسب التاريخ</option>
                <option value="name">ترتيب حسب الاسم</option>
              </select>
              <div>
                {["تصاعدي", "تنازلي"].map((item) => (
                  <label key={item}>
                    <input type="radio" name="shop-sort" checked={sort === item} onChange={() => setSort(item)} />
                    {item}
                  </label>
                ))}
              </div>
            </div>
            <div className="shop-currency">
              <span>العملة</span>
              <select
                aria-label="عملة حسابات المحل"
                value={currencyFilter}
                onChange={(e) => setCurrencyFilter(e.target.value)}
              >
                <option value="الكل">جميع العملات</option>
                {ctx.currencyCodes.map((c) => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </select>
              <label>
                <input
                  type="checkbox"
                  checked={byCurrency}
                  onChange={(e) => setByCurrency(e.target.checked)}
                />
                حسب العملة
              </label>
            </div>
            <div className="reference-date-strip">
              <ArrowRightIcon />
              <span>
                من <b>{periodRange.fromDate || "البداية"}</b>
              </span>
              <span>
                إلى <b>{periodRange.toDate || new Date().toISOString().slice(0, 10)}</b>
              </span>
              <ArrowLeftIcon />
            </div>
          </section>
          {ordered.slice(0, visibleCount).map((acc) => {
            const s = computeAccountSummary(acc, periodLedger, activeCurrencyParam);
            return (
              <article className="shop-account-card" key={acc.id}>
                <button
                  className="warehouse-icon"
                  aria-label={`عرض ${acc.name}`}
                  onClick={() => flow.push(supplierScreen(acc.id))}
                >
                  <MobileIcon />
                </button>
                <strong>{acc.name}</strong>
                <span>{formatAmount(s.netBalance)}</span>
                <button aria-label={`إضافة سند لـ ${acc.name}`} onClick={() => ctx.openTransaction(acc)}>
                  <PlusIcon />
                </button>
              </article>
            );
          })}
          {ordered.length > visibleCount ? (
            <div className="load-more-list-wrap">
              <button
                type="button"
                className="load-more-list-btn"
                onClick={() => setVisibleCount((v) => v + 80)}
              >
                عرض المزيد (المعروض {visibleCount} من {ordered.length} حساب)
              </button>
            </div>
          ) : null}
        </main>
      </MobileScroll>
      <button
        className="fab fixed-fab"
        aria-label="إنشاء حساب بالمحل"
        onClick={() => ctx.openAccountCreate("extended", "shop")}
      >
        <PlusIcon />
      </button>
    </>
  );
}

function warehousesScreen(): FlowScreen {
  const searchControl: MutableRefObject<(() => void) | null> = { current: null };
  return {
    id: "warehouses",
    headerHeight: 58,
    header: (flow) => (
      <AppHeader
        title="المخازن"
        subtitle=""
        onBack={flow.pop}
        actions={[{ label: "بحث في المخازن", icon: MagnifyingGlassIcon, onClick: () => searchControl.current?.() }]}
      />
    ),
    footerHeight: 26,
    footer: () => <div className="warehouse-bottom-strip" />,
    render: (flow) => <WarehousesPage flow={flow} searchControl={searchControl} />,
  };
}

function WarehousesPage({
  flow,
  searchControl,
}: {
  flow: FlowControls;
  searchControl: MutableRefObject<(() => void) | null>;
}) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const [editing, setEditing] = useState<WarehouseRecord | "new" | null>(null);
  const keyboard = useKeyboard();
  const [searchOpen, setSearchOpen] = useState(false);
  const [search, setSearch] = useState("");
  searchControl.current = () => {
    keyboard.hide();
    setSearchOpen((value) => !value);
    setSearch("");
  };
  const open = (warehouse: WarehouseRecord | "new") => {
    keyboard.hide();
    setEditing(warehouse);
  };
  const close = () => {
    keyboard.hide();
    setEditing(null);
  };

  return (
    <>
      <MobileScroll className="warehouse-scroll">
        <main className="warehouse-page page-with-footer" data-testid="warehouses-screen">
          {searchOpen ? (
            <KeyboardInput
              className="warehouse-search"
              aria-label="اسم المخزن للبحث"
              placeholder="ابحث عن المخزن"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          ) : null}
          {ctx.warehouses.filter((warehouse) => matchesArabicSearch(warehouse.name, search)).length === 0 ? (
            <p className="cash-empty" style={{ textAlign: "center", padding: "32px 16px" }}>
              {search.trim()
                ? "لا توجد مخازن مطابقة للبحث."
                : "لا توجد مخازن مضافة بعد — اضغط زر (+) لإضافة مخزن جديد."}
            </p>
          ) : null}
          {ctx.warehouses
            .filter((warehouse) => matchesArabicSearch(warehouse.name, search))
            .map((warehouse) => (
              <article className="warehouse-card" key={warehouse.id}>
                <button
                  className="warehouse-icon"
                  aria-label={`فتح ${warehouse.name}`}
                  onClick={() => flow.push(inventoryReportScreen(warehouse.id))}
                >
                  <CubeIcon />
                </button>
                <strong>
                  {warehouse.name}
                  {warehouse.isDefault ? " (افتراضي)" : ""}
                </strong>
                <b>{warehouse.codeNumber}</b>
                <div className="warehouse-card-actions">
                  <button aria-label={`تعديل ${warehouse.name}`} onClick={() => open(warehouse)}>
                    <Pencil1Icon />
                  </button>
                  <button
                    aria-label={`تقرير حركة ${warehouse.name}`}
                    onClick={() => flow.push(inventoryReportScreen(warehouse.id))}
                  >
                    <ReaderIcon />
                  </button>
                </div>
              </article>
            ))}
        </main>
      </MobileScroll>
      <button className="fab warehouse-fab" aria-label="إضافة مخزن" onClick={() => open("new")}>
        <PlusIcon />
      </button>
      {editing !== null ? (
        <WarehouseModal
          key={editing === "new" ? "new" : editing.id}
          warehouse={editing === "new" ? undefined : editing}
          onClose={close}
          onSave={async (value) => {
            await saveWarehouse(
              ctx.uid,
              {
                ...value,
                codeNumber:
                  editing === "new"
                    ? maxNumericField(ctx.warehouses, (w) => w.codeNumber, 0) + 1
                    : editing.codeNumber,
              },
              ctx.warehouses,
              editing === "new" ? undefined : editing.id,
            );
            close();
            ctx.showToast("تم حفظ المخزن في قاعدة البيانات");
          }}
        />
      ) : null}
    </>
  );
}

function WarehouseModal({
  warehouse,
  onClose,
  onSave,
}: {
  warehouse?: WarehouseRecord;
  onClose: () => void;
  onSave: (value: { name: string; details: string; isDefault: boolean }) => Promise<void>;
}) {
  const { screenRef } = useScreenPortal();
  const [name, setName] = useState(warehouse?.name ?? "");
  const [details, setDetails] = useState(warehouse?.details ?? "");
  const [isDefault, setIsDefault] = useState(warehouse?.isDefault ?? false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(false);
  const target = screenRef.current?.querySelector(".nasqo-app");
  if (!target) return null;

  const submit = async () => {
    if (!name.trim()) {
      setError(true);
      return;
    }
    setSaving(true);
    try {
      await onSave({ name: name.trim(), details, isDefault });
    } finally {
      setSaving(false);
    }
  };

  return createPortal(
    <div className="center-modal-layer" data-testid="warehouse-modal">
      <button className="center-modal-backdrop" aria-label="إغلاق المخزن" onClick={onClose} />
      <section className="warehouse-modal" role="dialog" aria-modal="true" aria-labelledby="warehouse-title">
        <h2 id="warehouse-title">{warehouse ? "تعديل المخزن" : "مخزن جديد"}</h2>
        <KeyboardInput
          aria-label="اسم المخزن"
          placeholder="أدخل الاسم"
          value={name}
          onChange={(event) => {
            setName(event.target.value);
            setError(false);
          }}
          aria-invalid={error}
        />
        <KeyboardInput
          aria-label="تفاصيل المخزن"
          placeholder="تفاصيل"
          value={details}
          onChange={(event) => setDetails(event.target.value)}
        />
        <label className="warehouse-default">
          <span>اعتماد هذا المخزن كافتراضي</span>
          <input
            className="nasqo-switch"
            type="checkbox"
            role="switch"
            checked={isDefault}
            onChange={(event) => setIsDefault(event.target.checked)}
          />
        </label>
        {error ? (
          <p className="form-error" role="alert">
            أدخل اسم المخزن أولًا
          </p>
        ) : null}
        <div className="form-modal-actions">
          <button className="cancel" onClick={onClose}>
            إلغاء
          </button>
          <button className="save" disabled={saving} onClick={submit}>
            {saving ? "جاري الحفظ..." : "حفظ"}
          </button>
        </div>
      </section>
    </div>,
    target,
  );
}

function ItemsHeader({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  const downloadTemplate = () => {
    const csv = "\uFEFFالاسم,الرمز,الوحدة,متوسط التكلفة,سعر البيع,الوحدة 2,العبوة 2,سعر 2,الوحدة 3,العبوة 3,سعر 3\n";
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "nasqo-items-template.csv";
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    ctx.showToast("تم تحميل نموذج استيراد الأصناف");
  };
  return (
    <AppHeader
      title="الأصناف"
      subtitle=""
      onBack={flow.pop}
      leadingTextActions={[
        {
          label: "نموذج استيراد الأصناف",
          testId: "items-import-template-btn",
          onClick: downloadTemplate,
        },
      ]}
      actions={[
        { label: "حركة المخازن", icon: ActivityLogIcon, onClick: () => flow.push(inventoryReportScreen()) },
        { label: "خيارات الطباعة والتصدير", icon: DownloadIcon, onClick: () => ctx.openExportMenu("inventory") },
      ]}
    />
  );
}

function itemsScreen(): FlowScreen {
  return {
    id: "items-catalog",
    headerHeight: 54,
    header: (flow) => <ItemsHeader flow={flow} />,
    render: (flow) => <ItemsCatalogPage flow={flow} />,
  };
}

function ItemsCatalogPage({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [sku, setSku] = useState("");
  const [unit, setUnit] = useState("حبة");
  const [avgCost, setAvgCost] = useState("");
  const [sellingPrice, setSellingPrice] = useState("");
  const [unit2, setUnit2] = useState("");
  const [count2, setCount2] = useState("");
  const [sprice2, setSprice2] = useState("");
  const [unit3, setUnit3] = useState("");
  const [count3, setCount3] = useState("");
  const [sprice3, setSprice3] = useState("");
  const [defaultUnit, setDefaultUnit] = useState<1 | 2 | 3>(1);
  const [expiryDate, setExpiryDate] = useState("");
  const [currencyCode, setCurrencyCode] = useState<CurrencyCode>("ريال");
  const [isActive, setIsActive] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [pageIndex, setPageIndex] = useState(0);
  const [showAll, setShowAll] = useState(false);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState("");

  const resetForm = useCallback(() => {
    setSelectedId(null);
    setName("");
    setSku("");
    setUnit("حبة");
    setAvgCost("");
    setSellingPrice("");
    setUnit2("");
    setCount2("");
    setSprice2("");
    setUnit3("");
    setCount3("");
    setSprice3("");
    setDefaultUnit(1);
    setExpiryDate("");
    setCurrencyCode("ريال");
    setIsActive(true);
    setFormError("");
  }, []);

  const selectItemForEdit = (item: InventoryItemRecord) => {
    setSelectedId(item.id);
    setName(item.name);
    setSku(item.sku ?? "");
    setUnit(item.unit || "حبة");
    setAvgCost(String(item.avgCost ?? 0));
    setSellingPrice(item.sellingPrice !== undefined ? String(item.sellingPrice) : "");
    setUnit2(item.unit2 ?? "");
    setCount2(item.count2 !== undefined ? String(item.count2) : "");
    setSprice2(item.sprice2 !== undefined ? String(item.sprice2) : "");
    setUnit3(item.unit3 ?? "");
    setCount3(item.count3 !== undefined ? String(item.count3) : "");
    setSprice3(item.sprice3 !== undefined ? String(item.sprice3) : "");
    setDefaultUnit(item.defaultUnit === 2 ? 2 : item.defaultUnit === 3 ? 3 : 1);
    setCurrencyCode((item.currencyCode as CurrencyCode) || "ريال");
    setIsActive(item.isActive !== false);
    setExpiryDate(item.expiryDate ?? "");
    setFormError("");
  };

  const generateBarcode = () => {
    const nextCode = String(1000000000 + Math.floor(Math.random() * 8999999999));
    setSku(nextCode);
  };

  const filteredItems = useMemo(() => {
    const q = normalizeArabicSearch(searchQuery);
    if (!q) return ctx.inventory;
    return ctx.inventory.filter((item) =>
      matchesArabicSearch(
        `${item.legacyId ?? ""} ${item.name} ${item.sku ?? ""} ${item.unit} ${item.unit2 ?? ""} ${item.unit3 ?? ""}`,
        q,
      ),
    );
  }, [ctx.inventory, searchQuery]);

  const pageSize = 15;
  const totalPages = Math.max(1, Math.ceil(filteredItems.length / pageSize));
  const safePage = Math.min(pageIndex, totalPages - 1);
  const visibleItems = useMemo(
    () => (showAll ? filteredItems : filteredItems.slice(safePage * pageSize, (safePage + 1) * pageSize)),
    [filteredItems, safePage, showAll],
  );

  const handleSaveNew = async () => {
    setFormError("");
    const trimmedName = name.trim();
    if (!trimmedName) {
      const msg = "أدخل اسم الصنف أولًا قبل الحفظ.";
      setFormError(msg);
      ctx.showToast(msg);
      return;
    }
    const targetWh = ctx.warehouses.find((w) => w.isDefault)?.id || ctx.warehouses[0]?.id || "";
    setSaving(true);
    try {
      await createInventoryItem(ctx.uid, {
        name: trimmedName,
        sku: sku.trim(),
        unit: unit.trim() || "حبة",
        quantity: 0,
        avgCost: avgCost.trim() ? parseArabicNumber(avgCost) : 0,
        ...(sellingPrice.trim() ? { sellingPrice: parseArabicNumber(sellingPrice) } : {}),
        ...(unit2.trim() ? { unit2: unit2.trim(), count2: parseArabicNumber(count2) || 1, ...(sprice2.trim() ? { sprice2: parseArabicNumber(sprice2) } : {}) } : {}),
        ...(unit3.trim() ? { unit3: unit3.trim(), count3: parseArabicNumber(count3) || 1, ...(sprice3.trim() ? { sprice3: parseArabicNumber(sprice3) } : {}) } : {}),
        defaultUnit,
        currencyCode,
        isActive,
        ...(expiryDate.trim() ? { expiryDate: expiryDate.trim() } : {}),
        warehouseId: targetWh,
        quantityUnverified: false,
      });
      triggerHaptic("success");
      ctx.showToast(`تم حفظ الصنف «${trimmedName}» في سجل الأصناف (بدون حركة مخزنية أو شراء)`);
      resetForm();
    } catch (err) {
      const msg = err instanceof Error ? err.message : "تعذر حفظ الصنف.";
      setFormError(msg);
      ctx.showToast(msg);
    } finally {
      setSaving(false);
    }
  };

  const handleUpdateSelected = async () => {
    if (!selectedId) {
      const msg = "حدد صنفًا من الجدول أولًا لتعديل بياناته.";
      setFormError(msg);
      ctx.showToast(msg);
      return;
    }
    const trimmedName = name.trim();
    if (!trimmedName) {
      const msg = "اسم الصنف مطلوب.";
      setFormError(msg);
      ctx.showToast(msg);
      return;
    }
    setSaving(true);
    setFormError("");
    try {
      await updateInventoryCatalog(ctx.uid, selectedId, {
        name: trimmedName,
        sku: sku.trim(),
        unit: unit.trim() || "حبة",
        avgCost: avgCost.trim() ? parseArabicNumber(avgCost) : 0,
        ...(sellingPrice.trim() ? { sellingPrice: parseArabicNumber(sellingPrice) } : {}),
        unit2: unit2.trim(),
        ...(unit2.trim() ? { count2: parseArabicNumber(count2) || 1, ...(sprice2.trim() ? { sprice2: parseArabicNumber(sprice2) } : {}) } : {}),
        unit3: unit3.trim(),
        ...(unit3.trim() ? { count3: parseArabicNumber(count3) || 1, ...(sprice3.trim() ? { sprice3: parseArabicNumber(sprice3) } : {}) } : {}),
        defaultUnit,
        currencyCode,
        isActive,
        expiryDate: expiryDate.trim(),
      });
      triggerHaptic("success");
      ctx.showToast(`تم تعديل بطاقة الصنف «${trimmedName}» دون المساس بحركة المخزون`);
      resetForm();
    } catch (err) {
      const msg = err instanceof Error ? err.message : "تعذر تعديل الصنف.";
      setFormError(msg);
      ctx.showToast(msg);
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteSelected = async () => {
    if (!selectedId) {
      const msg = "حدد صنفًا من الجدول أولًا لحذفه.";
      setFormError(msg);
      ctx.showToast(msg);
      return;
    }
    setSaving(true);
    setFormError("");
    try {
      await deleteInventoryCatalogItem(ctx.uid, selectedId);
      triggerHaptic("success");
      ctx.showToast("تم حذف الصنف من سجل الأصناف");
      resetForm();
    } catch (err) {
      const msg = err instanceof Error ? err.message : "تعذر حذف الصنف.";
      setFormError(msg);
      ctx.showToast(msg);
    } finally {
      setSaving(false);
    }
  };

  return (
    <MobileScroll className="app-screen">
      <main className="items-catalog-page" data-testid="items-catalog-screen" dir="rtl">
        <section className="items-catalog-form-card" aria-label="بيانات الصنف">
          <div className="items-catalog-form-title">بيانات الصنف</div>
          {formError ? (
            <div className="field-inline-error" role="alert" data-testid="items-catalog-error">
              {formError}
            </div>
          ) : null}

          <div className="items-catalog-top-grid">
            <div className="items-catalog-field">
              <span className="items-lbl blue">إسم الصنف</span>
              <KeyboardInput
                aria-label="إسم الصنف"
                data-testid="catalog-item-name"
                placeholder="أدخل اسم الصنف..."
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>
            <div className="items-catalog-field barcode-field">
              <span className="items-lbl blue">الباركود</span>
              <KeyboardInput
                aria-label="الباركود"
                data-testid="catalog-item-sku"
                placeholder="رقم الباركود"
                value={sku}
                onChange={(e) => setSku(e.target.value)}
              />
              <button
                type="button"
                className="items-barcode-gen-btn"
                aria-label="توليد باركود تلقائي"
                onClick={generateBarcode}
                title="توليد باركود"
              >
                +
              </button>
            </div>
          </div>

          <div className="items-catalog-units-layout">
            {/* Base unit column */}
            <div className="items-base-unit-col">
              <div className="items-catalog-field">
                <span className="items-lbl blue">الوحدة</span>
                <KeyboardInput
                  aria-label="الوحدة الأساسية"
                  data-testid="catalog-item-unit1"
                  placeholder="حبة"
                  value={unit}
                  onChange={(e) => setUnit(e.target.value)}
                />
              </div>
              <div className="items-catalog-field">
                <span className="items-lbl blue">سعر التكلفة</span>
                <KeyboardInput
                  aria-label="سعر التكلفة"
                  data-testid="catalog-item-cost"
                  inputMode="decimal"
                  placeholder="0"
                  value={avgCost}
                  onChange={(e) => setAvgCost(e.target.value)}
                />
              </div>
              <div className="items-catalog-field">
                <span className="items-lbl blue">سعر البيع</span>
                <KeyboardInput
                  aria-label="سعر البيع"
                  data-testid="catalog-item-price1"
                  inputMode="decimal"
                  placeholder="0"
                  value={sellingPrice}
                  onChange={(e) => setSellingPrice(e.target.value)}
                />
              </div>
            </div>

            {/* Optional multi-units orange container */}
            <div className="items-optional-units-box">
              <div className="items-optional-units-banner">وحدات اختيارية يمكنك اضافتها او تجاهلها</div>
              <div className="items-optional-units-grid">
                <div className="items-opt-col">
                  <div className="items-catalog-field">
                    <span className="items-lbl blue">الوحدة ٢</span>
                    <KeyboardInput
                      aria-label="الوحدة 2"
                      data-testid="catalog-item-unit2"
                      placeholder="درزن / باكت"
                      value={unit2}
                      onChange={(e) => setUnit2(e.target.value)}
                    />
                  </div>
                  <div className="items-catalog-field">
                    <span className="items-lbl blue">معامل التحويل</span>
                    <KeyboardInput
                      aria-label="معامل التحويل 2"
                      data-testid="catalog-item-count2"
                      inputMode="decimal"
                      placeholder="عدد الوحدات"
                      value={count2}
                      onChange={(e) => setCount2(e.target.value)}
                    />
                  </div>
                  <div className="items-catalog-field">
                    <span className="items-lbl blue">سعر البيع</span>
                    <KeyboardInput
                      aria-label="سعر البيع 2"
                      data-testid="catalog-item-price2"
                      inputMode="decimal"
                      placeholder="0"
                      value={sprice2}
                      onChange={(e) => setSprice2(e.target.value)}
                    />
                  </div>
                </div>

                <div className="items-opt-col">
                  <div className="items-catalog-field">
                    <span className="items-lbl blue">الوحدة ٣</span>
                    <KeyboardInput
                      aria-label="الوحدة 3"
                      data-testid="catalog-item-unit3"
                      placeholder="كرتون"
                      value={unit3}
                      onChange={(e) => setUnit3(e.target.value)}
                    />
                  </div>
                  <div className="items-catalog-field">
                    <span className="items-lbl blue">معامل التحويل</span>
                    <KeyboardInput
                      aria-label="معامل التحويل 3"
                      data-testid="catalog-item-count3"
                      inputMode="decimal"
                      placeholder="عدد الوحدات"
                      value={count3}
                      onChange={(e) => setCount3(e.target.value)}
                    />
                  </div>
                  <div className="items-catalog-field">
                    <span className="items-lbl blue">سعر البيع</span>
                    <KeyboardInput
                      aria-label="سعر البيع 3"
                      data-testid="catalog-item-price3"
                      inputMode="decimal"
                      placeholder="0"
                      value={sprice3}
                      onChange={(e) => setSprice3(e.target.value)}
                    />
                  </div>
                </div>
              </div>
            </div>

            {/* Side currency & status column */}
            <div className="items-side-meta-col">
              <div className="items-side-box">
                <span className="items-lbl blue full">العملة الافتراضية</span>
                <select
                  aria-label="العملة الافتراضية للصنف"
                  value={currencyCode}
                  onChange={(e) => setCurrencyCode(e.target.value as CurrencyCode)}
                >
                  {ctx.currencyCodes.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </select>
              </div>
              <div className="items-side-box">
                <span className="items-lbl blue full">حالة الصنف</span>
                <div className="items-status-radios">
                  <label>
                    <input type="radio" checked={isActive} onChange={() => setIsActive(true)} /> نشط
                  </label>
                  <label>
                    <input type="radio" checked={!isActive} onChange={() => setIsActive(false)} /> خامل
                  </label>
                </div>
              </div>
            </div>
          </div>

          <div className="items-catalog-defaults-row">
            <span className="items-lbl blue">الافتراضية</span>
            <div className="items-default-unit-radios" role="radiogroup" aria-label="الوحدة الافتراضية">
              <label>
                <input type="radio" checked={defaultUnit === 1} onChange={() => setDefaultUnit(1)} /> الوحدة ١
              </label>
              <label>
                <input type="radio" checked={defaultUnit === 2} onChange={() => setDefaultUnit(2)} /> الوحدة ٢
              </label>
              <label>
                <input type="radio" checked={defaultUnit === 3} onChange={() => setDefaultUnit(3)} /> الوحدة ٣
              </label>
            </div>
            <span className="items-lbl blue">تاريخ الانتهاء</span>
            <input
              type="date"
              className="items-expiry-input"
              aria-label="تاريخ الانتهاء"
              value={expiryDate}
              onChange={(e) => setExpiryDate(e.target.value)}
            />
          </div>

          <div className="items-catalog-actions-row">
            <div className="items-search-box">
              <span className="items-lbl blue">بحث</span>
              <KeyboardInput
                aria-label="البحث في بطاقات الأصناف"
                data-testid="catalog-search-input"
                placeholder="ابحث بالاسم أو الباركود أو الرقم..."
                value={searchQuery}
                onChange={(e) => {
                  setSearchQuery(e.target.value);
                  setPageIndex(0);
                }}
              />
            </div>
            <div className="items-crud-btns">
              <button
                type="button"
                className="items-btn save"
                data-testid="catalog-save-btn"
                disabled={saving}
                onClick={() => void handleSaveNew()}
              >
                حفظ
              </button>
              <button
                type="button"
                className="items-btn edit"
                data-testid="catalog-update-btn"
                disabled={saving || !selectedId}
                onClick={() => void handleUpdateSelected()}
              >
                تعديل
              </button>
              <button
                type="button"
                className="items-btn cancel"
                data-testid="catalog-cancel-btn"
                onClick={resetForm}
              >
                الغاء الأمر
              </button>
            </div>
          </div>
        </section>

        <div className="items-catalog-table-wrap">
          <table className="items-catalog-table" data-testid="items-catalog-table">
            <thead>
              <tr>
                <th>الرقم</th>
                <th>الباركود</th>
                <th>اسم الصنف</th>
                <th>الوحدة1</th>
                <th>سعر التكلفة</th>
                <th>سعر البيع</th>
                <th>الوحدة2</th>
                <th>سعر البيع2</th>
                <th>الوحدة3</th>
                <th>سعر البيع3</th>
                <th>العملة</th>
                <th>الحالة</th>
                <th>الوحدة الافتراضية</th>
              </tr>
            </thead>
            <tbody>
              {visibleItems.length === 0 ? (
                <tr>
                  <td colSpan={13} style={{ textAlign: "center", padding: 18, color: "#64748b" }}>
                    لا توجد أصناف مطابقة — أضف صنفًا جديدًا من نموذج بيانات الصنف أعلاه أو استعد نسخة احتياطية.
                  </td>
                </tr>
              ) : (
                visibleItems.map((item, idx) => {
                  const isSelected = item.id === selectedId;
                  const defUnitName =
                    item.defaultUnit === 2 && item.unit2
                      ? item.unit2
                      : item.defaultUnit === 3 && item.unit3
                        ? item.unit3
                        : item.unit || "حبة";
                  return (
                    <tr
                      key={item.id}
                      data-testid={`catalog-row-${item.id}`}
                      className={isSelected ? "selected" : idx % 2 === 1 ? "alt" : ""}
                      onClick={() => selectItemForEdit(item)}
                    >
                      <td>{item.legacyId ?? safePage * pageSize + idx + 1}</td>
                      <td><bdi>{item.sku || "—"}</bdi></td>
                      <td className="item-name-cell">{item.name}</td>
                      <td>{item.unit || "حبة"}</td>
                      <td>{formatAmount(item.avgCost)}</td>
                      <td>{formatAmount(item.sellingPrice ?? 0)}</td>
                      <td>{item.unit2 || ""}</td>
                      <td>{item.sprice2 ? formatAmount(item.sprice2) : "0"}</td>
                      <td>{item.unit3 || ""}</td>
                      <td>{item.sprice3 ? formatAmount(item.sprice3) : "0"}</td>
                      <td>{item.currencyCode || "ريال"}</td>
                      <td>{item.isActive === false ? "خامل" : "نشط"}</td>
                      <td>{defUnitName}</td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>

        <footer className="items-catalog-footer">
          <div className="items-pagination-bar">
            <button
              type="button"
              className="items-page-btn"
              disabled={showAll || safePage + 1 >= totalPages}
              onClick={() => setPageIndex((p) => Math.min(totalPages - 1, p + 1))}
            >
              الصفحة التالية
            </button>
            <span className="items-page-indicator">
              صفحة رقم {safePage + 1} من {totalPages} ({filteredItems.length} صنف)
            </span>
            <button
              type="button"
              className="items-page-btn"
              disabled={showAll || safePage <= 0}
              onClick={() => setPageIndex((p) => Math.max(0, p - 1))}
            >
              الصفحة السابقة
            </button>
            <button
              type="button"
              className="items-page-btn"
              onClick={() => setShowAll((v) => !v)}
            >
              {showAll ? "تقسيم صفحات" : "عرض الكل"}
            </button>
          </div>
          <div className="items-shortcuts-strip">
            <span>تعديل صنف: F2</span>
            <button
              type="button"
              className="currencies-footer-hint"
              data-testid="catalog-delete-btn"
              onClick={() => void handleDeleteSelected()}
            >
              حذف صنف : DELETE
            </button>
            <span>التنقل : TAB</span>
          </div>
        </footer>
      </main>
    </MobileScroll>
  );
}

function inventoryReportScreen(warehouseId?: string): FlowScreen {
  return {
    id: `inventory-report-${warehouseId ?? "all"}`,
    headerHeight: 58,
    header: (flow) => <InventoryHeader flow={flow} />,
    render: (flow) => <InventoryReportPage flow={flow} initialWarehouseId={warehouseId} />,
  };
}

function InventoryHeader({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  return (
    <AppHeader
      title="حركة المخازن"
      subtitle=""
      onBack={flow.pop}
      leadingTextActions={[
        {
          label: "إكسل",
          testId: "movement-export-excel-btn",
          onClick: () => ctx.openExportMenu("inventory"),
        },
      ]}
      actions={[
        { label: "بطاقات الأصناف", icon: TagPriceIcon, onClick: () => flow.push(itemsScreen()) },
        { label: "طباعة التقرير", icon: FileTextIcon, onClick: () => ctx.openPrintOptions("inventory") },
        { label: "تصدير", icon: DownloadIcon, onClick: () => ctx.openExportMenu("inventory") },
      ]}
    />
  );
}

function InventoryFooter({ initialWarehouseId }: { initialWarehouseId?: string }) {
  const ctx = useWorkspace();
  const activeStockItems = useMemo(
    () =>
      ctx.inventory.filter(
        (i) => Math.abs(i.quantity) > 0.0001 || Math.abs(i.computedQuantity ?? 0) > 0.0001 || i.quantityUnverified,
      ),
    [ctx.inventory],
  );
  const summary = computeInventorySummary(activeStockItems, initialWarehouseId);
  return (
    <div className="inventory-totals">
      <div>
        عدد الأصناف: <b>{summary.items.length}</b>
        {summary.unverifiedCount > 0 ? (
          <span style={{ color: "#b45309", marginRight: 8 }}> (بحاجة لتسوية: {summary.unverifiedCount})</span>
        ) : null}
      </div>
      <div>
        الكمية المعتمدة: <b>{formatAmount(summary.totalQuantity)}</b>　 القيمة:{" "}
        <b>{formatAmount(summary.totalValue)}</b>
      </div>
    </div>
  );
}

function InventoryReportPage({
  flow,
  initialWarehouseId,
}: {
  flow: FlowControls;
  initialWarehouseId?: string;
}) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const { screenRef } = useScreenPortal();
  const [period, setPeriod] = useState("الكل");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const [selectedWarehouseId, setSelectedWarehouseId] = useState(initialWarehouseId ?? "");
  const [selectedCurrency, setSelectedCurrency] = useState("الكل");
  const [profitBasis, setProfitBasis] = useState<"avg" | "cost" | "last">("avg");
  const [onlyMoved, setOnlyMoved] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [activeRowId, setActiveRowId] = useState<string | null>(null);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(() => new Set());
  const [movementReport, setMovementReport] = useState<Awaited<ReturnType<typeof fetchInventoryMovementsReport>> | null>(null);
  const [activeMovementItem, setActiveMovementItem] = useState<InventoryItemRecord | null>(null);
  const [itemMoves, setItemMoves] = useState<Awaited<ReturnType<typeof fetchInventoryMovementsReport>>["movements"]>([]);
  const [loadingMoves, setLoadingMoves] = useState(false);
  const [visibleRowCount, setVisibleRowCount] = useState(80);

  useEffect(() => {
    setVisibleRowCount(80);
  }, [searchQuery, selectedWarehouseId, selectedCurrency, period, onlyMoved]);

  const selectPeriod = (nextPeriod: string) => {
    setPeriod(nextPeriod);
    const bounds = computePeriodDateRange(nextPeriod);
    setFromDate(bounds.fromDate);
    setToDate(bounds.toDate);
  };

  useEffect(() => {
    let active = true;
    void fetchInventoryMovementsReport(ctx.uid, {
      warehouseId: selectedWarehouseId || undefined,
      fromDate: fromDate || undefined,
      toDate: toDate || undefined,
      currency: selectedCurrency !== "الكل" ? selectedCurrency : undefined,
      profitBasis,
    })
      .then((res) => {
        if (active) setMovementReport(res);
      })
      .catch(() => {
        if (active) setMovementReport(null);
      });
    return () => {
      active = false;
    };
  }, [ctx.uid, ctx.ledger, ctx.inventory, fromDate, profitBasis, selectedCurrency, selectedWarehouseId, toDate]);

  const inventoryById = useMemo(() => new Map(ctx.inventory.map((i) => [i.id, i])), [ctx.inventory]);

  const reportRows = useMemo(() => {
    const rawReportRows = movementReport?.itemRows ?? [];
    const seenIds = new Set(rawReportRows.map((r) => r.id));
    const missingFromReport: typeof rawReportRows = ctx.inventory
      .filter((i) => !seenIds.has(i.id) && (!selectedWarehouseId || i.warehouseId === selectedWarehouseId))
      .map((i) => ({
        id: i.id,
        code: i.legacyId ?? null,
        name: i.name,
        sku: i.sku ?? "",
        unit: i.unit || "حبة",
        unit2: i.unit2 ?? "",
        count2: i.count2 ?? null,
        warehouseId: i.warehouseId,
        openingQty: i.quantityUnverified ? 0 : i.quantity,
        periodNetQty: 0,
        buyQty: 0,
        sellQty: 0,
        transferInQty: 0,
        transferOutQty: 0,
        buyTotal: 0,
        sellTotal: 0,
        availableQty: i.quantityUnverified ? 0 : i.quantity,
        unitCost: i.avgCost,
        remainingValue: Math.round((i.quantityUnverified ? 0 : i.quantity) * i.avgCost * 100) / 100,
        profit: 0,
        avgCost: i.avgCost,
        sellingPrice: i.sellingPrice,
        catalogQuantity: i.quantity,
        quantityUnverified: Boolean(i.quantityUnverified),
        hasMovement: false,
      }));
    const baseRows = [...rawReportRows, ...missingFromReport].sort((a, b) =>
      b.name.localeCompare(a.name, "ar"),
    );
    const q = normalizeArabicSearch(searchQuery);
    if (q) {
      return baseRows.filter((row) =>
        matchesArabicSearch(`${row.code ?? ""} ${row.name} ${row.sku} ${row.unit} ${row.id}`, q),
      );
    }
    if (onlyMoved) {
      return baseRows.filter((r) => r.hasMovement || (r.openingQty ?? 0) !== 0);
    }
    return baseRows;
  }, [ctx.inventory, movementReport, onlyMoved, searchQuery, selectedWarehouseId]);
  const showOpeningCol = useMemo(
    () => Boolean(fromDate) || reportRows.some((r) => (r.openingQty ?? 0) !== 0),
    [fromDate, reportRows],
  );
  const totalRemainingQty = useMemo(
    () => Math.round(reportRows.reduce((sum, r) => sum + Number(r.availableQty ?? 0), 0) * 100) / 100,
    [reportRows],
  );

  const fallbackSummary = computeInventorySummary(ctx.inventory, selectedWarehouseId || undefined);
  const bulkTargetItems = useMemo(() => {
    if (reportRows.length > 0) {
      return reportRows.map((r) => inventoryById.get(r.id)).filter(Boolean) as InventoryItemRecord[];
    }
    const q = normalizeArabicSearch(searchQuery);
    return q
      ? fallbackSummary.items.filter((i) =>
          matchesArabicSearch(`${i.name} ${i.sku ?? ""} ${i.legacyId ?? ""} ${i.id} ${i.unit}`, q),
        )
      : fallbackSummary.items;
  }, [fallbackSummary.items, inventoryById, reportRows, searchQuery]);

  const openItemMovements = (item: InventoryItemRecord) => {
    setActiveMovementItem(item);
    setItemMoves([]);
    setLoadingMoves(true);
    void fetchInventoryMovementsReport(ctx.uid, { itemId: item.id })
      .then((res) => setItemMoves(res.movements))
      .catch(() => setItemMoves([]))
      .finally(() => setLoadingMoves(false));
  };

  const toggleItem = (id: string) => {
    triggerHaptic("light");
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleAll = () => {
    const visibleIds = bulkTargetItems.map((i) => i.id);
    const allSelected = visibleIds.length > 0 && visibleIds.every((id) => selectedIds.has(id));
    if (allSelected) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(visibleIds));
    }
  };

  const totals = movementReport?.totals ?? {
    totalSales: 0,
    totalPurchases: 0,
    totalProfit: 0,
    totalRemainingValue: 0,
    activeItemsCount: 0,
    profitBasis,
  };

  const movePortal = screenRef.current?.querySelector(".nasqo-app") ?? document.body;

  return (
    <>
    <MobileScroll className="inventory-report-scroll">
      <main className="inventory-report-page smart-movements-screen" data-testid="inventory-report-screen">
        <section className="smart-movements-top-bar" aria-label="فلتر وإجماليات حركة المخازن">
          {/* Right box: الفلتر */}
          <div className="smart-mv-box filter-box">
            <div className="smart-mv-box-title">الفلتر</div>
            <label className="smart-mv-field">
              <span className="smart-mv-tag">المخزن</span>
              <select
                aria-label="المخزن"
                value={selectedWarehouseId}
                onChange={(event) => {
                  setSelectedWarehouseId(event.target.value);
                  setSelectedIds(new Set());
                }}
              >
                <option value="">جميع المخازن</option>
                {ctx.warehouses.map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="smart-mv-field">
              <span className="smart-mv-tag">العملة</span>
              <select
                aria-label="عملة حركة المخازن"
                value={selectedCurrency}
                onChange={(e) => setSelectedCurrency(e.target.value)}
              >
                <option value="الكل">جميع العملات</option>
                {ctx.currencyCodes.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>
            <label className="smart-mv-field">
              <span className="smart-mv-tag">بحث</span>
              <KeyboardInput
                aria-label="البحث في الأصناف"
                placeholder="ابحث برقم الصنف أو الاسم أو الباركود..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </label>
          </div>

          {/* Center box: الإجماليات */}
          <div className="smart-mv-box totals-box" data-testid="inventory-totals-cards">
            <div className="smart-mv-box-title">الإجماليات</div>
            <div className="smart-mv-total-row">
              <span className="smart-mv-pill sell">بيع</span>
              <strong className="smart-mv-val sell">{formatAmount(totals.totalSales)}</strong>
            </div>
            <div className="smart-mv-total-row">
              <span className="smart-mv-pill buy">شراء</span>
              <strong className="smart-mv-val buy">{formatAmount(totals.totalPurchases)}</strong>
            </div>
            <div className="smart-mv-total-row">
              <span className="smart-mv-pill profit">ربح</span>
              <strong className="smart-mv-val profit">{formatAmount(totals.totalProfit)}</strong>
            </div>
          </div>

          {/* Center-Left box: حساب الارباح حسب */}
          <div className="smart-mv-box profit-basis-box">
            <div className="smart-mv-box-title">حساب الارباح حسب</div>
            <label className="smart-mv-radio">
              <input
                type="radio"
                name="smart-profit-basis"
                checked={profitBasis === "avg"}
                onChange={() => setProfitBasis("avg")}
              />
              <span>متوسط السعر</span>
            </label>
            <label className="smart-mv-radio">
              <input
                type="radio"
                name="smart-profit-basis"
                checked={profitBasis === "cost"}
                onChange={() => setProfitBasis("cost")}
              />
              <span>سعر التكلفة</span>
            </label>
            <label className="smart-mv-radio">
              <input
                type="radio"
                name="smart-profit-basis"
                checked={profitBasis === "last"}
                onChange={() => setProfitBasis("last")}
              />
              <span>اخر سعر</span>
            </label>
          </div>

          {/* Left box: التاريخ */}
          <div className="smart-mv-box date-box">
            <div className="smart-mv-box-title">التاريخ</div>
            <div className="smart-mv-period-radios">
              {(
                [
                  { id: "يومي", label: "يومي" },
                  { id: "الكل", label: "الكلي" },
                  { id: "شهري", label: "شهري" },
                  { id: "سنوي", label: "سنوي" },
                ] as const
              ).map((item) => (
                <label key={item.id}>
                  <input
                    type="radio"
                    name="inventory-period"
                    checked={period === item.id}
                    onChange={() => selectPeriod(item.id)}
                  />
                  {item.label}
                </label>
              ))}
            </div>
            <label className="smart-mv-field date-field">
              <span className="smart-mv-tag">من تاريخ</span>
              <input
                type="date"
                aria-label="حركة المخازن من تاريخ"
                value={fromDate}
                onChange={(e) => {
                  setPeriod("مخصص");
                  setFromDate(e.target.value);
                }}
              />
            </label>
            <label className="smart-mv-field date-field">
              <span className="smart-mv-tag">الى تاريخ</span>
              <input
                type="date"
                aria-label="حركة المخازن إلى تاريخ"
                value={toDate}
                onChange={(e) => {
                  setPeriod("مخصص");
                  setToDate(e.target.value);
                }}
              />
            </label>
          </div>
        </section>

        {selectedIds.size > 0 || searchQuery.trim().length > 0 ? (
          <InventoryBulkEditBar
            uid={ctx.uid}
            items={bulkTargetItems}
            selectedIds={selectedIds}
            onToggleSelectAll={toggleAll}
            onClearSelection={() => setSelectedIds(new Set())}
            onNotify={ctx.showToast}
          />
        ) : null}

        <div className="inventory-table-scroll smart-mv-table-wrap">
          <table className="inventory-table inventory-movements-table smart-mv-grid" data-testid="inventory-movements-table">
            <thead>
              <tr>
                <th scope="col">الرقم</th>
                <th scope="col">اسم الصنف</th>
                {showOpeningCol ? <th scope="col">رصيد سابق</th> : null}
                <th scope="col">كمية الشراء</th>
                <th scope="col">كمية البيع</th>
                <th scope="col">وارد</th>
                <th scope="col">منصرف</th>
                {showOpeningCol ? <th scope="col">صافي الحركة</th> : null}
                <th scope="col">اجمالي الشراء</th>
                <th scope="col">اجمالي البيع</th>
                <th scope="col">الكمية المتوفرة</th>
                <th scope="col">الوحدة</th>
                <th scope="col">اجمالي المتبقي</th>
                <th scope="col">الربح</th>
                <th scope="col">حركة</th>
              </tr>
            </thead>
            <tbody>
              {reportRows.slice(0, visibleRowCount).map((row, idx) => {
                const liveItem = inventoryById.get(row.id);
                const checked = selectedIds.has(row.id);
                const isActiveRow = activeRowId ? activeRowId === row.id : idx === 0;
                const shownAvailable = movementReport ? row.availableQty : (liveItem?.quantity ?? row.availableQty);
                const showSearchDetails = searchQuery.trim().length > 0;
                return (
                  <tr
                    key={row.id}
                    className={
                      isActiveRow
                        ? "smart-mv-row-active"
                        : checked
                          ? "inv-row-selected"
                          : idx % 2 === 1
                            ? "smart-mv-row-alt"
                            : undefined
                    }
                    onClick={() => setActiveRowId(row.id)}
                  >
                    <td>
                      <bdi>{row.code ?? idx + 1}</bdi>
                    </td>
                    <td className="inv-name-col">
                      {row.name}
                      {showSearchDetails && row.sku ? <small className="inv-sku-meta"> ({row.sku})</small> : null}
                    </td>
                    {showOpeningCol ? <td>{formatAmount(row.openingQty ?? 0)}</td> : null}
                    <td>{formatAmount(row.buyQty)}</td>
                    <td>{formatAmount(row.sellQty)}</td>
                    <td>{formatAmount(row.transferInQty)}</td>
                    <td>{formatAmount(row.transferOutQty)}</td>
                    {showOpeningCol ? (
                      <td>
                        {(row.periodNetQty ?? 0) < 0
                          ? `${formatAmount(Math.abs(row.periodNetQty ?? 0))}-`
                          : formatAmount(row.periodNetQty ?? 0)}
                      </td>
                    ) : null}
                    <td>{formatAmount(row.buyTotal)}</td>
                    <td>{formatAmount(row.sellTotal)}</td>
                    <td>
                      <b>{formatAmount(shownAvailable)}</b>
                      {showSearchDetails && liveItem?.quantityUnverified ? (
                        <small style={{ display: "block", color: "#b45309", fontSize: 9.5 }}>بحاجة إلى تسوية</small>
                      ) : null}
                    </td>
                    <td>{row.unit}</td>
                    <td>{formatAmount(row.remainingValue)}</td>
                    <td>
                      {row.profit < 0 ? `${formatAmount(Math.abs(row.profit))}-` : formatAmount(row.profit)}
                    </td>
                    <td className="smart-mv-actions-cell">
                      <input
                        type="checkbox"
                        aria-label={`تحديد ${row.name}`}
                        checked={checked}
                        onChange={() => toggleItem(row.id)}
                        data-testid={`inv-checkbox-${row.id}`}
                      />
                      {liveItem ? (
                        <button
                          type="button"
                          className="inv-move-btn"
                          aria-label={`حركة صنف ${row.name}`}
                          onClick={(e) => {
                            e.stopPropagation();
                            openItemMovements(liveItem);
                          }}
                        >
                          حركة
                        </button>
                      ) : null}
                    </td>
                  </tr>
                );
              })}
              {reportRows.length > visibleRowCount ? (
                <tr>
                  <td colSpan={showOpeningCol ? 15 : 13} style={{ textAlign: "center", padding: 10 }}>
                    <button
                      type="button"
                      className="load-more-list-btn"
                      onClick={() => setVisibleRowCount((v) => v + 100)}
                    >
                      عرض المزيد (المعروض {visibleRowCount} من {reportRows.length} صنف)
                    </button>
                  </td>
                </tr>
              ) : null}
              {reportRows.length === 0 ? (
                <tr>
                  <td colSpan={showOpeningCol ? 15 : 13} style={{ textAlign: "center", padding: 16, color: "#64748b" }}>
                    {movementReport ? (
                      "لا توجد حركات أصناف في النطاق المحدد."
                    ) : (
                      <NasqoBrandLoader size="sm" label="جاري تحميل تقرير حركة المخازن..." />
                    )}
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>

        <footer className="smart-mv-bottom-bar" data-testid="inventory-movements-footer">
          <label className="smart-mv-show-all-toggle">
            <input
              type="checkbox"
              checked={!onlyMoved}
              onChange={(e) => setOnlyMoved(!e.target.checked)}
            />
            <span>إظهار كل أصناف الدليل ({ctx.inventory.length})</span>
          </label>
          <div className="smart-mv-bottom-center">
            كمية المتبقي : <bdi>{formatAmount(totalRemainingQty)}</bdi> | قيمة المتبقي :{" "}
            <bdi>{formatAmount(totals.totalRemainingValue)}</bdi>
          </div>
          <div className="smart-mv-bottom-left">
            عدد السجلات <bdi>{reportRows.length}</bdi>
          </div>
        </footer>
      </main>
    </MobileScroll>
        {activeMovementItem && movePortal
          ? createPortal(
          <div className="center-modal-layer" data-testid="item-movements-modal">
            <button
              className="center-modal-backdrop"
              onClick={() => setActiveMovementItem(null)}
              aria-label="إغلاق حركة الصنف"
            />
            <section
              className="account-groups-modal"
              role="dialog"
              aria-modal="true"
              aria-labelledby="item-moves-title"
              style={{ maxWidth: 560, maxHeight: "82vh", display: "flex", flexDirection: "column" }}
            >
              <header className="smart-modal-header" style={{ flexShrink: 0 }}>
                <button
                  type="button"
                  className="smart-modal-close"
                  onClick={() => setActiveMovementItem(null)}
                  aria-label="إغلاق"
                >
                  <Cross2Icon />
                </button>
                <h2 id="item-moves-title">حركة صنف: {activeMovementItem.name}</h2>
                <span className="smart-modal-spacer" aria-hidden="true" />
              </header>
              <div style={{ padding: "8px 12px", overflowY: "auto", flex: 1, minHeight: 0 }}>
                {loadingMoves ? (
                  <NasqoBrandLoader size="sm" label="جاري جلب سجل الحركات..." />
                ) : itemMoves.length === 0 ? (
                  <p className="cash-empty">لا توجد فواتير أو تحويلات مخزنية مرتبطة بهذا الصنف.</p>
                ) : (
                  <table className="account-groups-table" style={{ width: "100%", fontSize: 11 }}>
                    <thead>
                      <tr>
                        <th>التاريخ</th>
                        <th>النوع</th>
                        <th>الحساب / التحويل</th>
                        <th>المخزن</th>
                        <th>الكمية</th>
                        <th>السعر</th>
                      </tr>
                    </thead>
                    <tbody>
                      {itemMoves.map((mv, idx) => (
                        <tr key={`${mv.refId}-${idx}`}>
                          <td>{mv.date || "—"}</td>
                          <td>
                            {mv.label} {mv.entryNumber ? `#${mv.entryNumber}` : ""}
                          </td>
                          <td>{mv.accountName}</td>
                          <td>{mv.warehouseName}</td>
                          <td style={{ color: mv.effectQty < 0 ? "#dc2626" : "#059669", fontWeight: 700 }}>
                            {formatAmount(mv.quantity)} {mv.unit}
                          </td>
                          <td>{mv.price > 0 ? formatAmount(mv.price) : "—"}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
              <footer className="account-groups-footer" style={{ flexShrink: 0 }}>
                <span>إجمالي الحركات المعروضة: {itemMoves.length}</span>
                <button type="button" className="ag-btn close" onClick={() => setActiveMovementItem(null)}>
                  إغلاق
                </button>
              </footer>
            </section>
          </div>,
          movePortal,
        ) : null}
    </>
  );
}

function analyticsDashboardScreen(): FlowScreen {
  return {
    id: "analytics-dashboard",
    headerHeight: 58,
    header: (flow) => <SimpleAppHeader title="لوحة المبيعات والمخزون" onBack={flow.pop} />,
    render: (flow) => <AnalyticsDashboardPage flow={flow} />,
  };
}

function AnalyticsDashboardPage({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;

  return (
    <DashboardScreen
      companyName={
        !ctx.workspace?.companyName || ctx.workspace.companyName === "نسقو برو ERP"
          ? "نسقو برو"
          : ctx.workspace.companyName
      }
      defaultCurrency={ctx.workspace?.defaultCurrency || "ريال"}
      accounts={ctx.accounts}
      ledger={ctx.ledger}
      warehouses={ctx.warehouses}
      inventory={ctx.inventory}
      loading={ctx.syncing}
      themeMode={ctx.themeMode}
      onChangeThemeMode={ctx.setThemeMode}
      brandColor={ctx.brandColor}
      onChangeBrandColor={ctx.setBrandColor}
      onResetBrandColor={ctx.resetBrandColor}
      hapticsEnabled={ctx.hapticsEnabled}
      onToggleHaptics={ctx.setHapticsEnabled}
      widgetOrder={ctx.widgetOrder}
      onChangeWidgetOrder={ctx.setWidgetOrder}
      favorites={ctx.favorites}
      onPinFavorite={ctx.pinFavorite}
      onUnpinFavorite={ctx.unpinFavorite}
      onLaunchFavorite={ctx.launchFavorite}
      lastBackupIso={ctx.lastBackupIso}
      unreadNotificationsCount={ctx.unreadNotificationsCount}
      onOpenNotifications={ctx.openNotifications}
      onOpenSales={() => flow.push(purchasesScreen("sales"))}
      onOpenSupplier={(accountId) => flow.push(supplierScreen(accountId))}
      onCreateInvoice={() => ctx.openInvoice("sales")}
      onCreatePurchase={() => ctx.openInvoice("purchases")}
      onCreateContact={() => ctx.openAccountCreate("extended", "clients")}
      onOpenQrScanner={ctx.openQrScanner}
      onPreviewInvoice={(entryId) => flow.push(cashInvoicePreviewScreen(entryId))}
      onAddInventoryItem={ctx.openInventoryAdd}
      onUpdateItemThreshold={async (item, newThreshold) => {
        await updateInventoryItem(ctx.uid, item.id, {
          ...item,
          minThreshold: newThreshold,
        });
      }}
      onOpenInventoryReport={() => flow.push(inventoryReportScreen())}
      onOpenDailyJournal={() => flow.push(dailyJournalScreen())}
      onNotify={ctx.showToast}
    />
  );
}

const ERP_SCREEN_TITLES: Record<ErpModuleId, string> = {
  "erp-hub": "مركز الإدارة المتقدمة",
  "erp-finance": "القوائم المالية والأستاذ العام",
  "erp-hr": "الموارد البشرية والرواتب",
  "erp-crm": "المبيعات ونقطة البيع",
  "erp-procurement": "المشتريات وسلسلة التوريد",
  "erp-manufacturing": "التصنيع ومراكز التكلفة",
};

function smartProControlScreen(): FlowScreen {
  return {
    id: "smartpro-control",
    headerHeight: 54,
    header: (flow) => <SimpleAppHeader title="الإدارة المركزية المتقدمة" onBack={flow.pop} />,
    render: () => (
      <Suspense fallback={<NasqoBrandLoader size="md" label="جاري فتح الإدارة المركزية..." />}>
        <SmartProControlScreen />
      </Suspense>
    ),
  };
}

function erpModuleScreen(moduleId: ErpModuleId): FlowScreen {
  return {
    id: `${moduleId}-${Date.now()}`,
    headerHeight: 54,
    header: (flow) => <SimpleAppHeader title={ERP_SCREEN_TITLES[moduleId]} onBack={flow.pop} />,
    render: (flow) => (
      <Suspense fallback={<NasqoBrandLoader size="md" label="جاري فتح الشاشة..." testId="erp-module-loading" />}>
        <ErpModulePage moduleId={moduleId} flow={flow} />
      </Suspense>
    ),
  };
}

function ErpModulePage({ moduleId, flow }: { moduleId: ErpModuleId; flow: FlowControls }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const companyName = ctx.workspace?.companyName || "نسقو برو";
  const currency = ctx.workspace?.defaultCurrency || "ريال";

  if (moduleId === "erp-finance") {
    return (
      <ErpFinanceScreen
        uid={ctx.uid}
        companyName={companyName}
        currency={currency}
        accounts={ctx.accounts}
        ledger={ctx.ledger}
        inventory={ctx.inventory}
        cashboxes={ctx.cashboxes}
        erpData={ctx.erpData}
        onUpdateErpData={ctx.updateErpData}
        onToast={ctx.showToast}
      />
    );
  }
  if (moduleId === "erp-hr") {
    return (
      <ErpHrScreen
        uid={ctx.uid}
        currency={currency}
        accounts={ctx.accounts}
        warehouses={ctx.warehouses}
        erpData={ctx.erpData}
        onUpdateErpData={ctx.updateErpData}
        onToast={ctx.showToast}
      />
    );
  }
  if (moduleId === "erp-crm") {
    return (
      <ErpCrmPosScreen
        uid={ctx.uid}
        currency={currency}
        accounts={ctx.accounts}
        warehouses={ctx.warehouses}
        inventory={ctx.inventory}
        erpData={ctx.erpData}
        onUpdateErpData={ctx.updateErpData}
        onToast={ctx.showToast}
      />
    );
  }
  if (moduleId === "erp-procurement") {
    return (
      <ErpProcurementScreen
        uid={ctx.uid}
        currency={currency}
        accounts={ctx.accounts}
        warehouses={ctx.warehouses}
        inventory={ctx.inventory}
        erpData={ctx.erpData}
        onUpdateErpData={ctx.updateErpData}
        onToast={ctx.showToast}
      />
    );
  }
  if (moduleId === "erp-manufacturing") {
    return (
      <ErpManufacturingScreen
        uid={ctx.uid}
        currency={currency}
        accounts={ctx.accounts}
        ledger={ctx.ledger}
        warehouses={ctx.warehouses}
        inventory={ctx.inventory}
        erpData={ctx.erpData}
        onUpdateErpData={ctx.updateErpData}
        onToast={ctx.showToast}
      />
    );
  }
  return (
    <ErpHubScreen
      uid={ctx.uid}
      workspace={ctx.workspace}
      companyName={companyName}
      currency={currency}
      accounts={ctx.accounts}
      ledger={ctx.ledger}
      warehouses={ctx.warehouses}
      inventory={ctx.inventory}
      erpData={ctx.erpData}
      onUpdateErpData={ctx.updateErpData}
      onOpenModule={(nextId) => flow.push(erpModuleScreen(nextId))}
      onOpenInventory={() => flow.push(inventoryReportScreen())}
      onOpenSmartPro={() => flow.push(smartProControlScreen())}
      onToast={ctx.showToast}
    />
  );
}

function dailyJournalScreen(): FlowScreen {
  return {
    id: "daily-journal",
    headerHeight: 58,
    header: (flow) => <SimpleAppHeader title="الحركة اليومية" onBack={flow.pop} />,
    render: (flow) => <DailyJournalPage flow={flow} />,
  };
}

function DailyJournalPage({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const [searchQuery, setSearchQuery] = useState("");
  const [kindFilter, setKindFilter] = useState<"all" | "invoice" | "voucher" | "transfer" | "other">("all");
  const [visibleCount, setVisibleCount] = useState(60);

  const accountsById = useMemo(
    () => new Map(ctx.accounts.map((a) => [a.id, a])),
    [ctx.accounts],
  );

  const activeEntries = useMemo(
    () =>
      ctx.ledger
        .filter((e) => !e.deleted)
        .sort((a, b) => b.createdAtMs - a.createdAtMs || b.entryNumber - a.entryNumber),
    [ctx.ledger],
  );

  const filteredEntries = useMemo(() => {
    const q = normalizeArabicSearch(searchQuery);
    return activeEntries.filter((item) => {
      if (kindFilter === "invoice") {
        if (item.kind !== "invoice" && item.kind !== "return") return false;
      } else if (kindFilter === "voucher") {
        if (item.kind !== "voucher") return false;
      } else if (kindFilter === "transfer") {
        if (item.kind !== "transfer") return false;
      } else if (kindFilter === "other") {
        if (item.kind === "invoice" || item.kind === "return" || item.kind === "voucher" || item.kind === "transfer") {
          return false;
        }
      }
      if (!q) return true;
      return matchesArabicSearch(
        `${item.entryNumber} ${item.accountName} ${item.details} ${item.typeLabel} ${item.entryDate} ${item.documentNumber} ${item.amount} ${item.currency} ${item.warehouseName}`,
        q,
      );
    });
  }, [activeEntries, kindFilter, searchQuery]);

  useEffect(() => {
    setVisibleCount(60);
  }, [searchQuery, kindFilter]);

  const visibleEntries = useMemo(
    () => filteredEntries.slice(0, visibleCount),
    [filteredEntries, visibleCount],
  );

  const remainingCount = Math.max(0, filteredEntries.length - visibleEntries.length);

  return (
    <MobileScroll className="app-screen">
      <main className="purchases-page page-with-footer" data-testid="daily-journal-screen">
        <div className="list-heading">
          <div>
            <strong>سجل القيود والعمليات</strong>
            <span>
              {filteredEntries.length === activeEntries.length
                ? `جميع الحركات المحفوظة (${activeEntries.length})`
                : `نتائج التصفية: ${filteredEntries.length} من ${activeEntries.length}`}
            </span>
          </div>
          <span className="result-count">{filteredEntries.length}</span>
        </div>

        <section className="daily-journal-toolbar" aria-label="تصفية وبحث الحركة اليومية">
          <div className="daily-journal-search-box">
            <KeyboardInput
              aria-label="بحث في الحركة اليومية"
              data-testid="daily-journal-search"
              placeholder="ابحث باسم الحساب، البيان، الرقم، أو التاريخ..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
            {searchQuery ? (
              <button
                type="button"
                className="daily-journal-search-clear"
                aria-label="مسح البحث"
                onClick={() => setSearchQuery("")}
              >
                <Cross2Icon />
              </button>
            ) : null}
          </div>
          <div className="daily-journal-chips" role="group" aria-label="نوع الحركة">
            {(
              [
                ["all", "الكل"],
                ["invoice", "فواتير"],
                ["voucher", "سندات"],
                ["transfer", "حوالات"],
                ["other", "أخرى"],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                type="button"
                className={`daily-journal-chip${kindFilter === key ? " active" : ""}`}
                aria-pressed={kindFilter === key}
                onClick={() => setKindFilter(key)}
              >
                {label}
              </button>
            ))}
          </div>
        </section>

        {filteredEntries.length === 0 ? (
          <p className="cash-empty">
            {activeEntries.length === 0
              ? "لا توجد حركات مسجلة بعد."
              : "لا توجد حركات مطابقة للبحث أو التصفية الحالية."}
          </p>
        ) : (
          <section className="transactions-list">
            {visibleEntries.map((item) => (
              <article key={item.id} className="transaction-card">
                <div className="transaction-grid">
                  <span className={`transaction-type ${item.direction}`}>{item.typeLabel}</span>
                  <strong className={`transaction-amount ${item.direction}`}>
                    {formatAmount(item.amount)} {item.currency}
                  </strong>
                  <span className="transaction-detail">
                    <b>
                      {item.accountName}
                      {item.details ? ` · ${item.details}` : ""}
                    </b>
                    <time>{item.entryDate}</time>
                    <em>#{item.entryNumber}</em>
                  </span>
                  <span className="transaction-balance">{item.warehouseName || "—"}</span>
                </div>
                <div className="transaction-actions">
                  <button
                    aria-label={`تعديل #${item.entryNumber}`}
                    onClick={() => {
                      const acc = accountsById.get(item.accountId);
                      if (item.kind === "invoice" || item.kind === "return" || item.kind === "quote" || item.kind === "order") {
                        ctx.openInvoiceEdit(item, acc);
                      } else {
                        ctx.openTransaction(acc, item);
                      }
                    }}
                  >
                    <Pencil1Icon />
                  </button>
                  <button
                    aria-label={`معاينة فاتورة #${item.entryNumber}`}
                    onClick={() => flow.push(cashInvoicePreviewScreen(item.id))}
                  >
                    <FileTextIcon />
                  </button>
                  <button
                    type="button"
                    aria-label={`نقل #${item.entryNumber} إلى السلة`}
                    title="نقل إلى سلة المحذوفات"
                    style={{ color: "#c91b08" }}
                    onClick={async () => {
                      await setLedgerDeleted(ctx.uid, item.id, true);
                      triggerHaptic("warning");
                      ctx.showToast(`تم نقل العملية #${item.entryNumber} إلى سلة المحذوفات`);
                    }}
                  >
                    <TrashIcon />
                  </button>
                </div>
              </article>
            ))}
            {remainingCount > 0 ? (
              <div className="load-more-list-wrap">
                <button
                  type="button"
                  className="load-more-list-btn"
                  data-testid="daily-journal-load-more"
                  onClick={() => setVisibleCount((v) => v + 80)}
                >
                  عرض المزيد (المعروض {visibleEntries.length} من {filteredEntries.length} · متبقي {remainingCount})
                </button>
              </div>
            ) : null}
          </section>
        )}
      </main>
    </MobileScroll>
  );
}

type DraftInvoiceRow = {
  rowId: string;
  inventoryItemId?: string;
  itemCode?: string;
  sku?: string;
  itemName: string;
  unit: string;
  unitNum?: 1 | 2 | 3;
  quantity: string;
  price: string;
  discount: string;
};

function stripAutoLineSummary(details: string): string {
  const trimmed = details.trim();
  if (!trimmed) return "";
  if (/^\[.*\]$/s.test(trimmed)) return "";
  return trimmed.replace(/\s*—\s*\[[^\]]*\]\s*$/, "").trim();
}

function unitPriceForProduct(item: InventoryItemRecord, unitNum: 1 | 2 | 3, kind: "purchase" | "sale"): number {
  const c2 = item.count2 && item.count2 > 0 ? item.count2 : 1;
  const c3 = item.count3 && item.count3 > 0 ? item.count3 : 1;
  const mult = unitNum === 2 ? c2 : unitNum === 3 ? c2 * c3 : 1;
  if (kind === "purchase") {
    return item.avgCost > 0 ? Math.round(item.avgCost * mult * 100) / 100 : 0;
  }
  if (unitNum === 2 && item.sprice2 && item.sprice2 > 0) return item.sprice2;
  if (unitNum === 3 && item.sprice3 && item.sprice3 > 0) return item.sprice3;
  const baseSale = item.sellingPrice ?? (item.avgCost > 0 ? Math.round(item.avgCost * 1.25) : 0);
  return Math.round(baseSale * mult * 100) / 100;
}

function InvoiceModal({
  open,
  initialAccount,
  editingEntry,
  intent,
  kindOverride,
  onClose,
  onAddAccount,
}: {
  open: boolean;
  initialAccount?: AccountRecord;
  editingEntry?: LedgerEntryRecord;
  intent: InvoiceIntent;
  kindOverride?: "purchase" | "sale";
  onClose: () => void;
  onAddAccount: () => void;
}) {
  const ctx = useWorkspace();
  const initialContent: "items" | "free" =
    editingEntry?.invoiceContent === "free" ? "free" : "items";
  const initialPayment: "cash" | "credit" = editingEntry
    ? editingEntry.payment === "cash"
      ? "cash"
      : "credit"
    : initialAccount?.isCashAccount
      ? "cash"
      : "credit";
  const initialKind: "purchase" | "sale" =
    kindOverride ?? (initialAccount?.category === "sales" ? "sale" : "purchase");

  const [content, setContent] = useState<"items" | "free">(initialContent);
  const [payment, setPayment] = useState<"cash" | "credit">(initialPayment);
  const [kind, setKind] = useState<"purchase" | "sale">(initialKind);
  const [isReturn, setReturn] = useState(editingEntry ? editingEntry.kind === "return" : intent === "return");
  const [search, setSearch] = useState("");
  const [amount, setAmount] = useState(editingEntry ? String(editingEntry.amount || "") : "");
  const [note, setNote] = useState(editingEntry ? stripAutoLineSummary(editingEntry.details) : "");
  const [documentNumber, setDocumentNumber] = useState(editingEntry?.documentNumber ?? "");
  const [entryNumber, setEntryNumber] = useState(editingEntry ? String(editingEntry.entryNumber) : "");
  const [entryDate, setEntryDate] = useState(
    editingEntry?.entryDate || new Date().toISOString().slice(0, 10),
  );
  const [expenseCategory, setExpenseCategory] = useState(editingEntry?.expenseCategory ?? "");
  const [currency, setCurrency] = useState<CurrencyCode>(
    editingEntry?.currency ?? initialAccount?.currency ?? "ريال",
  );
  const [exchangeRate, setExchangeRate] = useState(
    editingEntry ? String(editingEntry.exchangeRate || 1) : "1",
  );
  const [cashboxId, setCashboxId] = useState<number | undefined>(
    () => editingEntry?.cashboxId ?? ctx.cashboxes[0]?.id,
  );
  const [warehouseId, setWarehouseId] = useState(
    editingEntry?.warehouseId ||
      ctx.warehouses.find((w) => w.isDefault)?.id ||
      ctx.warehouses[0]?.id ||
      "",
  );
  const [accountId, setAccountId] = useState(
    editingEntry?.accountId ?? initialAccount?.id ?? ctx.accounts[0]?.id ?? "",
  );
  const [itemSearch, setItemSearch] = useState("");
  const [rows, setRows] = useState<DraftInvoiceRow[]>([
    { rowId: "row_1", itemName: "", unit: "حبة", unitNum: 1, quantity: "1", price: "", discount: "" },
  ]);
  const [loadingLines, setLoadingLines] = useState(Boolean(editingEntry));
  const [linesLoadedEmpty, setLinesLoadedEmpty] = useState(false);
  const [priceHint, setPriceHint] = useState<{
    name: string;
    minPrice: number;
    maxPrice: number;
    lastPrice: number;
  } | null>(null);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<{
    field: "account" | "items" | "amount" | "line-qty" | "line-price" | "submit";
    rowId?: string;
    message: string;
  } | null>(null);
  const accountSelectRef = useRef<HTMLSelectElement>(null);
  const freeAmountInputRef = useRef<HTMLInputElement>(null);
  const itemSearchInputRef = useRef<HTMLInputElement>(null);
  const rowNameRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const rowQtyRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const rowPriceRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const draftNewEntryIdRef = useRef<string>("");
  const keyboard = useKeyboard();
  const now = useMemo(
    () => new Intl.DateTimeFormat("ar", { weekday: "short", hour: "2-digit", minute: "2-digit" }).format(new Date()),
    [],
  );

  useEffect(() => {
    if (!cashboxId && ctx.cashboxes[0]?.id) {
      setCashboxId(ctx.cashboxes[0].id);
    }
  }, [cashboxId, ctx.cashboxes]);

  useEffect(() => {
    if (!open) {
      setFormError(null);
      return;
    }
    setFormError(null);
    if (!editingEntry) {
      if (!draftNewEntryIdRef.current) {
        draftNewEntryIdRef.current = `inv_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
      }
      setLoadingLines(false);
      setLinesLoadedEmpty(false);
      return;
    }
    let active = true;
    setLoadingLines(true);
    setLinesLoadedEmpty(false);
    void fetchInvoiceDetailWithLines(ctx.uid, editingEntry.id)
      .then((detail) => {
        if (!active) return;
        const lines = detail.lines ?? [];
        if (lines.length > 0) {
          setRows(
            lines.map((l, idx) => {
              const linked = l.inventoryItemId
                ? ctx.inventory.find((i) => i.id === l.inventoryItemId)
                : undefined;
              const uNum = l.unitNum === 2 || l.unitNum === 3 ? l.unitNum : 1;
              return {
                rowId: `line_${l.id ?? idx}`,
                inventoryItemId: l.inventoryItemId ?? undefined,
                itemCode: linked?.legacyId ? String(linked.legacyId) : linked?.id,
                sku: l.sku ?? linked?.sku ?? "",
                itemName: l.itemName || linked?.name || "",
                unit: l.unit || linked?.unit || "حبة",
                unitNum: uNum,
                quantity: String(l.quantity ?? 1),
                price: String(l.price ?? 0),
                discount: l.discount ? String(l.discount) : "",
              };
            }),
          );
          setLinesLoadedEmpty(false);
        } else {
          setLinesLoadedEmpty(true);
        }
      })
      .catch(() => {
        if (active) setLinesLoadedEmpty(true);
      })
      .finally(() => {
        if (active) setLoadingLines(false);
      });
    return () => {
      active = false;
    };
  }, [ctx.inventory, ctx.uid, editingEntry, open]);

  const inventoryById = useMemo(
    () => (open ? new Map(ctx.inventory.map((i) => [i.id, i])) : new Map<string, InventoryItemRecord>()),
    [ctx.inventory, open],
  );

  const matchingInventory = useMemo(() => {
    if (!open) return [];
    const q = normalizeArabicSearch(itemSearch);
    if (!q) return [];
    const sorted = [...ctx.inventory].filter((item) =>
      matchesArabicSearch(
        `${item.name} ${item.sku ?? ""} ${item.legacyId ?? ""} ${item.id} ${item.unit} ${item.unit2 ?? ""} ${item.unit3 ?? ""}`,
        q,
      ),
    );
    sorted.sort((a, b) => {
      const aExact = a.sku?.toLowerCase() === q || String(a.legacyId ?? "") === q ? 0 : 1;
      const bExact = b.sku?.toLowerCase() === q || String(b.legacyId ?? "") === q ? 0 : 1;
      if (aExact !== bExact) return aExact - bExact;
      const aPrefix = normalizeArabicSearch(a.name).startsWith(q) ? 0 : 1;
      const bPrefix = normalizeArabicSearch(b.name).startsWith(q) ? 0 : 1;
      if (aPrefix !== bPrefix) return aPrefix - bPrefix;
      const aWh = warehouseId && a.warehouseId === warehouseId ? 0 : 1;
      const bWh = warehouseId && b.warehouseId === warehouseId ? 0 : 1;
      return aWh - bWh;
    });
    return sorted.slice(0, 10);
  }, [ctx.inventory, itemSearch, open, warehouseId]);

  const matchingAccounts = useMemo(
    () =>
      open
        ? rankAccountSearchMatches(
            ctx.accounts,
            search,
            kind === "sale" ? ["sales", "clients", "shop"] : ["purchases", "shop"],
          )
        : [],
    [ctx.accounts, kind, open, search],
  );

  const parsedLegacyRows = useMemo<DraftInvoiceRow[]>(() => {
    if (!open) return [];
    const sourceText = editingEntry?.details || note || "";
    if (!sourceText) return [];
    const matches: DraftInvoiceRow[] = [];
    const regex = /([^()،,\[\]\n—-]+?)\s*\(\s*([\d٠-٩.,]+)\s*([^()]*?)\s*\)/g;
    let match: RegExpExecArray | null;
    let idx = 0;
    while ((match = regex.exec(sourceText)) !== null) {
      const rawName = match[1].trim();
      const qty = parseArabicNumber(match[2]);
      const rawUnit = match[3].trim() || "حبة";
      if (!rawName || qty <= 0) continue;
      const normName = normalizeArabicSearch(rawName);
      const linked = ctx.inventory.find((i) => normalizeArabicSearch(i.name) === normName);
      const suggestedPrice = linked ? unitPriceForProduct(linked, 1, kind) : 0;
      idx += 1;
      matches.push({
        rowId: `parsed_${Date.now()}_${idx}`,
        inventoryItemId: linked?.id,
        itemCode: linked?.legacyId ? String(linked.legacyId) : linked?.id,
        sku: linked?.sku ?? "",
        itemName: linked?.name || rawName,
        unit: rawUnit,
        unitNum: 1,
        quantity: String(qty),
        price: suggestedPrice > 0 ? String(suggestedPrice) : "",
        discount: "",
      });
    }
    return matches;
  }, [ctx.inventory, editingEntry?.details, kind, note, open]);

  if (!open) return null;

  const selectedAccount = ctx.accounts.find((a) => a.id === accountId) ?? ctx.accounts[0];
  const selectedWarehouse = ctx.warehouses.find((w) => w.id === warehouseId);
  const accountSummary = selectedAccount
    ? computeAccountSummary(selectedAccount, ctx.ledger, currency)
    : null;

  const validLines: InvoiceLineInput[] = rows
    .filter((r) => r.itemName.trim().length > 0 && parseArabicNumber(r.quantity) > 0)
    .map((r) => {
      const qty = parseArabicNumber(r.quantity);
      const price = Math.max(0, parseArabicNumber(r.price));
      const discount = Math.max(0, parseArabicNumber(r.discount));
      return {
        ...(r.inventoryItemId ? { inventoryItemId: r.inventoryItemId } : {}),
        warehouseId: selectedWarehouse?.id ?? "",
        itemName: r.itemName.trim(),
        unit: r.unit.trim() || "حبة",
        unitNum: r.unitNum === 2 || r.unitNum === 3 ? r.unitNum : 1,
        quantity: qty,
        price,
        discount,
        total: Math.round(Math.max(0, qty * price - discount) * 100) / 100,
      };
    });

  const computedItemsTotal = validLines.reduce((sum, l) => sum + l.total, 0);
  const computedItemsDiscount = validLines.reduce((sum, l) => sum + (l.discount ?? 0), 0);
  const computedItemsQty = validLines.reduce((sum, l) => sum + l.quantity, 0);
  const effectiveAmount = content === "items" && validLines.length > 0 ? computedItemsTotal : parseArabicNumber(amount);

  const applyParsedLegacyRows = () => {
    if (parsedLegacyRows.length === 0) return;
    setRows(parsedLegacyRows);
    setLinesLoadedEmpty(false);
    setFormError(null);
    ctx.showToast(`تم استخراج ${parsedLegacyRows.length} صنف من البيان؛ راجع الأسعار ثم احفظ.`);
  };

  const pickProductIntoInvoice = (item: InventoryItemRecord) => {
    const defUnit: 1 | 2 | 3 =
      item.defaultUnit === 2 && item.unit2
        ? 2
        : item.defaultUnit === 3 && item.unit3
          ? 3
          : 1;
    const unitLabel =
      defUnit === 2 && item.unit2
        ? item.unit2
        : defUnit === 3 && item.unit3
          ? item.unit3
          : item.unit || "حبة";
    const suggestedPrice = unitPriceForProduct(item, defUnit, kind);

    setRows((prev) => {
      const emptyIdx = prev.findIndex((r) => !r.itemName.trim());
      const nextRow: DraftInvoiceRow = {
        rowId: emptyIdx >= 0 ? prev[emptyIdx].rowId : `row_${Date.now()}_${Math.random()}`,
        inventoryItemId: item.id,
        itemCode: item.legacyId ? String(item.legacyId) : item.id,
        sku: item.sku ?? "",
        itemName: item.name,
        unit: unitLabel,
        unitNum: defUnit,
        quantity: emptyIdx >= 0 ? prev[emptyIdx].quantity || "1" : "1",
        price: suggestedPrice > 0 ? String(suggestedPrice) : "",
        discount: emptyIdx >= 0 ? prev[emptyIdx].discount || "" : "",
      };
      if (emptyIdx >= 0) {
        return prev.map((r, i) => (i === emptyIdx ? nextRow : r));
      }
      return [...prev, nextRow];
    });
    setItemSearch("");
    setPriceHint({
      name: item.name,
      minPrice: item.avgCost,
      maxPrice: item.sellingPrice ?? item.avgCost,
      lastPrice: suggestedPrice,
    });
    void fetchProductPriceStats(ctx.uid, item.id)
      .then((stats) => {
        if (stats.txCount > 0) {
          setPriceHint({
            name: item.name,
            minPrice: stats.minPrice,
            maxPrice: stats.maxPrice,
            lastPrice: stats.lastPrice || suggestedPrice,
          });
        }
      })
      .catch(() => {
        // Keep local item price hint
      });
  };

  const addEmptyRow = () => {
    setRows((prev) => [
      ...prev,
      { rowId: `row_${Date.now()}_${Math.random()}`, itemName: "", unit: "حبة", unitNum: 1, quantity: "1", price: "", discount: "" },
    ]);
  };

  const updateRow = (rowId: string, patch: Partial<DraftInvoiceRow>) => {
    setRows((prev) => prev.map((r) => (r.rowId === rowId ? { ...r, ...patch } : r)));
  };

  const handleRowUnitNumChange = (row: DraftInvoiceRow, nextUnitNum: 1 | 2 | 3) => {
    const item = row.inventoryItemId ? inventoryById.get(row.inventoryItemId) : undefined;
    if (!item) {
      updateRow(row.rowId, { unitNum: nextUnitNum });
      return;
    }
    const nextUnitName =
      nextUnitNum === 2 && item.unit2
        ? item.unit2
        : nextUnitNum === 3 && item.unit3
          ? item.unit3
          : item.unit || "حبة";
    const nextPrice = unitPriceForProduct(item, nextUnitNum, kind);
    updateRow(row.rowId, {
      unitNum: nextUnitNum,
      unit: nextUnitName,
      ...(nextPrice > 0 ? { price: String(nextPrice) } : {}),
    });
  };

  const removeRow = (rowId: string) => {
    setRows((prev) =>
      prev.length <= 1
        ? [{ rowId: "row_1", itemName: "", unit: "حبة", unitNum: 1, quantity: "1", price: "", discount: "" }]
        : prev.filter((r) => r.rowId !== rowId),
    );
  };

  const handleSave = async (andPrint = false) => {
    const focusInvalid = (
      el: HTMLElement | null | undefined,
      errObj: NonNullable<typeof formError>,
    ) => {
      triggerHaptic("warning");
      setFormError(errObj);
      ctx.showToast(errObj.message, 4500);
      if (el) {
        el.scrollIntoView?.({ block: "center", behavior: "instant" });
        el.focus();
      }
    };

    if (!selectedAccount) {
      focusInvalid(accountSelectRef.current, {
        field: "account",
        message: "أضف حسابًا أو اختر الحساب أولًا قبل حفظ الفاتورة.",
      });
      return;
    }

    if (content === "free") {
      if (parseArabicNumber(amount) <= 0) {
        focusInvalid(freeAmountInputRef.current, {
          field: "amount",
          message: "يجب إدخال إجمالي مبلغ أكبر من صفر قبل حفظ الفاتورة.",
        });
        return;
      }
    } else {
      const namedRows = rows.filter((r) => r.itemName.trim().length > 0);
      if (namedRows.length === 0 && parseArabicNumber(amount) <= 0) {
        const firstRowId = rows[0]?.rowId;
        const focusEl =
          (firstRowId ? rowNameRefs.current[firstRowId] : null) ??
          itemSearchInputRef.current;
        focusInvalid(focusEl, {
          field: "items",
          rowId: firstRowId,
          message: "أضف صنفًا واحدًا على الأقل أو حوّل الفاتورة إلى حرة.",
        });
        return;
      }
      const badQtyRow = namedRows.find((r) => parseArabicNumber(r.quantity) <= 0);
      if (badQtyRow) {
        focusInvalid(rowQtyRefs.current[badQtyRow.rowId], {
          field: "line-qty",
          rowId: badQtyRow.rowId,
          message: `أدخل كمية أكبر من صفر للصنف «${badQtyRow.itemName}».`,
        });
        return;
      }
      if (effectiveAmount <= 0) {
        const badPriceRow = namedRows.find((r) => parseArabicNumber(r.price) <= 0) ?? namedRows[0];
        const focusEl =
          (badPriceRow ? rowPriceRefs.current[badPriceRow.rowId] : null) ??
          freeAmountInputRef.current ??
          itemSearchInputRef.current;
        focusInvalid(focusEl, {
          field: "line-price",
          rowId: badPriceRow?.rowId,
          message: "يجب أن يكون إجمالي الفاتورة أكبر من صفر (تحقّق من السعر).",
        });
        return;
      }
    }

    setFormError(null);
    keyboard.hide();
    setSaving(true);
    try {
      const parsedEntryNum = parseInt(entryNumber.trim(), 10);
      const nextNum =
        editingEntry
          ? Number.isFinite(parsedEntryNum) && parsedEntryNum > 0
            ? parsedEntryNum
            : editingEntry.entryNumber
          : Number.isFinite(parsedEntryNum) && parsedEntryNum > 0
            ? parsedEntryNum
            : maxNumericField(ctx.ledger, (e) => e.entryNumber, 1000) + 1;
      const entryKind =
        intent === "quote" ? "quote" : intent === "order" ? "order" : isReturn ? "return" : "invoice";
      const typeLabel =
        intent === "quote"
          ? "عرض سعر"
          : intent === "order"
            ? "طلبية جديدة"
            : isReturn
              ? kind === "purchase"
                ? "مردود مشتريات"
                : "مردود مبيعات"
              : kind === "purchase"
                ? payment === "cash"
                  ? "ف.ش.نقدي"
                  : "فاتورة شراء آجلة"
                : payment === "cash"
                  ? "فاتورة بيع نقدي"
                  : "فاتورة بيع آجل";
      const direction: "debit" | "credit" =
        kind === "purchase" ? (isReturn ? "debit" : "credit") : isReturn ? "credit" : "debit";

      const itemsSummaryText =
        content === "items" && validLines.length > 0
          ? `[ ${validLines.map((l) => `${l.itemName} (${formatAmount(l.quantity)} ${l.unit})`).join("، ")} ]`
          : "";
      const finalDetails = [note.trim(), itemsSummaryText].filter(Boolean).join(" — ") || typeLabel;
      const cleanDate = entryDate.trim() || new Date().toISOString().slice(0, 10);

      const payload: Partial<LedgerEntryRecord> & { accountId: string; accountName: string } = {
        accountId: selectedAccount.id,
        accountName: selectedAccount.name,
        ...(payment === "cash" && cashboxId ? { cashboxId } : { cashboxId: undefined }),
        kind: entryKind,
        typeLabel,
        payment,
        direction,
        amount: effectiveAmount,
        settledOnReceipt: payment === "cash",
        currency,
        exchangeRate: parseArabicNumber(exchangeRate) || 1,
        details: finalDetails,
        documentNumber: documentNumber.trim() || String(nextNum),
        warehouseId: selectedWarehouse?.id ?? "",
        warehouseName: selectedWarehouse?.name ?? "",
        invoiceContent: content,
        entryNumber: nextNum,
        deleted: editingEntry?.deleted ?? false,
        entryDate: cleanDate,
        lines: content === "items" ? validLines : [],
        ...(kind === "purchase" && expenseCategory ? { expenseCategory } : {}),
      };

      let targetId = editingEntry?.id ?? "";
      if (editingEntry) {
        await updateLedgerEntry(ctx.uid, editingEntry.id, payload);
        triggerHaptic("success");
        onClose();
        ctx.showToast(`تم تعديل ${typeLabel} رقم #${nextNum} بنجاح`);
      } else {
        targetId = await createLedgerEntry(ctx.uid, {
          id: draftNewEntryIdRef.current || undefined,
          ...payload,
        });
        triggerHaptic("success");
        onClose();
        ctx.showToast(`تم حفظ ${typeLabel} رقم #${nextNum} بنجاح`);
      }
      if (andPrint && targetId) {
        ctx.flowRef.current?.push(cashInvoicePreviewScreen(targetId));
      }
    } catch (err) {
      triggerHaptic("warning");
      const msg = err instanceof Error && err.message ? err.message : "تعذر حفظ الفاتورة";
      setFormError({ field: "submit", message: msg });
      ctx.showToast(msg, err instanceof UncertainWriteError ? 7500 : 5000);
    } finally {
      setSaving(false);
    }
  };

  const modalTitleText = `${editingEntry ? "تعديل " : ""}${
    intent === "quote"
      ? editingEntry
        ? "عرض سعر"
        : "عرض سعر جديد"
      : intent === "order"
        ? "طلبية جديدة"
        : isReturn
          ? editingEntry
            ? "مردود"
            : "مردود جديد"
          : kind === "purchase"
            ? editingEntry
              ? "فاتورة شراء"
              : "فاتورة شراء جديدة"
            : editingEntry
              ? "فاتورة بيع"
              : "فاتورة بيع جديدة"
  }${editingEntry ? ` #${editingEntry.entryNumber}` : ""}`;

  return (
    <div className="center-modal-layer" data-testid="invoice-modal">
      <button className="center-modal-backdrop" aria-label="إغلاق الفاتورة" onClick={onClose} />
      <section className="invoice-modal invoice-modal-pro" role="dialog" aria-modal="true" aria-labelledby="invoice-title">
        <header className="invoice-modal-head">
          <div className="invoice-modal-head-title">
            <h2 id="invoice-title">{modalTitleText}</h2>
            <time className="invoice-head-time">
              {now} · {entryDate}
            </time>
          </div>
          <button
            type="button"
            className="invoice-modal-close"
            aria-label="إغلاق"
            onClick={onClose}
          >
            <Cross2Icon />
          </button>
        </header>

        <div className="invoice-modal-body">
          <div className="invoice-radio-bar invoice-segment-row">
            <div className="invoice-radio-group">
              {(
                [
                  ["items", "أصناف"],
                  ["free", "حرة"],
                ] as const
              ).map(([value, label]) => (
                <label key={value} className={content === value ? "active" : ""}>
                  <input
                    type="radio"
                    name="invoice-content"
                    checked={content === value}
                    onChange={() => {
                      setFormError(null);
                      setContent(value);
                    }}
                  />
                  <span>{label}</span>
                </label>
              ))}
            </div>
            <span className="invoice-radio-sep" aria-hidden="true" />
            <div className="invoice-radio-group">
              {(
                [
                  ["cash", "نقدي"],
                  ["credit", "آجل"],
                ] as const
              ).map(([value, label]) => (
                <label className={`${value === "cash" ? "green" : "red"} ${payment === value ? "active" : ""}`} key={value}>
                  <input
                    type="radio"
                    name="invoice-payment"
                    checked={payment === value}
                    onChange={() => setPayment(value)}
                  />
                  <span>{label}</span>
                </label>
              ))}
            </div>
          </div>

          <div className="invoice-radio-bar invoice-kind-bar">
            <label className={`green ${kind === "purchase" ? "active" : ""}`}>
              <input
                type="radio"
                name="invoice-kind"
                checked={kind === "purchase"}
                onChange={() => setKind("purchase")}
              />
              <span>{isReturn ? "مردود شراء" : "فاتورة شراء"}</span>
            </label>
            <label className={`red ${kind === "sale" ? "active" : ""}`}>
              <input
                type="radio"
                name="invoice-kind"
                checked={kind === "sale"}
                onChange={() => setKind("sale")}
              />
              <span>{isReturn ? "مردود بيع" : "فاتورة بيع"}</span>
            </label>
            <button
              type="button"
              className={isReturn ? "return-active" : ""}
              aria-pressed={isReturn}
              onClick={() => setReturn((value) => !value)}
            >
              {isReturn ? "فاتورة جديدة" : "مردود جديد"}
            </button>
          </div>

          <div className="invoice-section-card">
            <div className="invoice-search">
              <KeyboardInput
                aria-label="البحث عن حساب الفاتورة"
                data-testid="invoice-account-search"
                placeholder="ابحث عن الحساب..."
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" && matchingAccounts.length > 0) {
                    event.preventDefault();
                    if (formError?.field === "account") setFormError(null);
                    setAccountId(matchingAccounts[0].id);
                    setSearch("");
                    keyboard.hide();
                  }
                }}
              />
              {search ? (
                <button type="button" aria-label="مسح بحث الفاتورة" onClick={() => setSearch("")}>
                  <Cross2Icon />
                </button>
              ) : (
                <button
                  type="button"
                  className="invoice-search-clear-idle"
                  aria-label="مسح بحث الفاتورة"
                  onClick={() => setSearch("")}
                >
                  <Cross2Icon />
                </button>
              )}
            </div>



            <div className="invoice-account">
              <button type="button" aria-label="إضافة حساب للفاتورة" onClick={onAddAccount}>
                <PlusIcon />
              </button>
              <select
                ref={accountSelectRef}
                aria-label="حساب الفاتورة"
                aria-invalid={formError?.field === "account"}
                value={
                  search.trim()
                    ? (matchingAccounts.find((v) => v.id === accountId)?.id ?? matchingAccounts[0]?.id ?? "")
                    : (selectedAccount?.id ?? "")
                }
                onChange={(event) => {
                  if (formError?.field === "account") setFormError(null);
                  setAccountId(event.target.value);
                  if (search.trim()) setSearch("");
                }}
              >
                {ctx.accounts.length === 0 ? (
                  <option value="">لا توجد حسابات — أضف حسابًا من +</option>
                ) : search.trim() && matchingAccounts.length === 0 ? (
                  <option value="">لا توجد حسابات مطابقة للبحث</option>
                ) : null}
                {(() => {
                  const baseList = search.trim() ? matchingAccounts : ctx.accounts;
                  const { options, truncatedCount } = limitSelectAccounts(baseList, selectedAccount?.id, 150);
                  return (
                    <>
                      {options.map((v) => (
                        <option key={v.id} value={v.id}>
                          {v.name}
                        </option>
                      ))}
                      {truncatedCount > 0 ? (
                        <option value="" disabled>
                          — ابحث أعلاه لعرض باقي الحسابات (+{truncatedCount}) —
                        </option>
                      ) : null}
                    </>
                  );
                })()}
              </select>
            </div>

            {formError?.field === "account" ? (
              <div className="field-inline-error" role="alert" data-testid="invoice-account-error">
                {formError.message}
              </div>
            ) : null}

            {accountSummary ? (
              <div className="invoice-balance-strip" data-testid="invoice-account-balance">
                <span>رصيد الحساب</span>
                <strong className={accountSummary.tone === "credit" ? "credit" : "debit"}>
                  {formatAmount(accountSummary.netBalance)} {currency}{" "}
                  {accountSummary.tone === "credit" ? "(له)" : accountSummary.tone === "debit" ? "(عليه)" : ""}
                </strong>
              </div>
            ) : null}
          </div>

          <div className="invoice-meta-grid">
            <label className="invoice-field-box">
              <span>رقم الفاتورة</span>
              <KeyboardInput
                aria-label="رقم الفاتورة"
                data-testid="invoice-entry-number"
                inputMode="numeric"
                placeholder="تلقائي"
                value={entryNumber}
                onChange={(e) => setEntryNumber(e.target.value)}
              />
            </label>
            <label className="invoice-field-box">
              <span>تاريخ الفاتورة</span>
              <input
                type="date"
                dir="ltr"
                aria-label="تاريخ الفاتورة"
                data-testid="invoice-entry-date"
                value={entryDate}
                onChange={(e) => setEntryDate(e.target.value)}
              />
            </label>
            <label className="invoice-field-box">
              <span>المخزن</span>
              <select
                aria-label="مخزن الفاتورة"
                value={warehouseId}
                onChange={(e) => setWarehouseId(e.target.value)}
              >
                {ctx.warehouses.length === 0 ? <option value="">المخزن الافتراضي</option> : null}
                {ctx.warehouses.map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name}
                  </option>
                ))}
              </select>
            </label>
            {payment === "cash" && ctx.cashboxes.length > 0 ? (
              <label className="invoice-field-box">
                <span>الصندوق</span>
                <select
                  aria-label="صندوق النقدية"
                  value={cashboxId ?? ""}
                  onChange={(e) => setCashboxId(Number(e.target.value))}
                >
                  {ctx.cashboxes.map((cb) => (
                    <option key={cb.id} value={cb.id}>
                      {cb.name}
                    </option>
                  ))}
                </select>
              </label>
            ) : (
              <label className="invoice-field-box">
                <span>رقم المستند</span>
                <KeyboardInput
                  aria-label="رقم مستند الفاتورة"
                  placeholder="تلقائي"
                  value={documentNumber}
                  onChange={(e) => setDocumentNumber(e.target.value)}
                />
              </label>
            )}
            <label className="invoice-field-box">
              <span>العملة</span>
              <select
                aria-label="عملة الفاتورة"
                value={currency}
                onChange={(event) => setCurrency(event.target.value as CurrencyCode)}
              >
                {ctx.currencyCodes.map((c) => (
                  <option key={c}>{c}</option>
                ))}
              </select>
            </label>
            <label className="invoice-field-box">
              <span>سعر الصرف</span>
              <KeyboardInput
                aria-label="سعر صرف الفاتورة"
                inputMode="decimal"
                value={exchangeRate}
                onChange={(e) => setExchangeRate(e.target.value)}
              />
            </label>
          </div>

          {content === "items" ? (
            <section className="invoice-lines-builder" data-testid="invoice-lines-builder">
              <div className="invoice-lines-header">
                <div className="invoice-lines-header-title">
                  <strong>جدول الأصناف</strong>
                  <span className="invoice-lines-badge">{validLines.length} صنف</span>
                </div>
                <button
                  type="button"
                  className="invoice-add-line-btn"
                  onClick={addEmptyRow}
                  aria-label="إضافة سطر صنف"
                >
                  <PlusIcon /> إضافة سطر
                </button>
              </div>

              {loadingLines ? (
                <NasqoBrandLoader size="sm" label="جاري تحميل بنود الفاتورة..." />
              ) : null}

              {!loadingLines && editingEntry && linesLoadedEmpty ? (
                <div className="invoice-legacy-banner">
                  <p>
                    لا توجد بنود أصناف مفصلة محفوظة لهذه الفاتورة (المبلغ الأصلي:{" "}
                    <b>{formatAmount(editingEntry.amount)} {currency}</b>).
                  </p>
                  <div className="invoice-legacy-banner-actions">
                    {parsedLegacyRows.length > 0 ? (
                      <button
                        type="button"
                        className="invoice-legacy-btn primary"
                        onClick={applyParsedLegacyRows}
                      >
                        استخراج {parsedLegacyRows.length} صنف من البيان
                      </button>
                    ) : null}
                    <button
                      type="button"
                      className="invoice-legacy-btn"
                      onClick={() => {
                        setFormError(null);
                        setContent("free");
                        if (!amount) setAmount(String(editingEntry.amount || ""));
                      }}
                    >
                      تحويل لفاتورة حرة
                    </button>
                  </div>
                </div>
              ) : null}

              <div className="invoice-item-search-row">
                <KeyboardInput
                  ref={itemSearchInputRef}
                  data-testid="invoice-item-search"
                  aria-label="بحث عن صنف أو باركود"
                  placeholder="ابحث باسم الصنف أو رقمه أو الباركود..."
                  value={itemSearch}
                  onChange={(e) => {
                    if (formError?.field === "items") setFormError(null);
                    setItemSearch(e.target.value);
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && matchingInventory.length > 0) {
                      e.preventDefault();
                      pickProductIntoInvoice(matchingInventory[0]);
                    }
                  }}
                />
                {itemSearch ? (
                  <button
                    type="button"
                    className="invoice-item-search-clear"
                    aria-label="مسح بحث الصنف"
                    onClick={() => setItemSearch("")}
                  >
                    <Cross2Icon />
                  </button>
                ) : null}
              </div>

              {itemSearch.trim() ? (
                <div
                  className="invoice-item-suggestions"
                  role={matchingInventory.length > 0 ? "listbox" : "status"}
                  aria-label="نتائج الأصناف"
                >
                  {matchingInventory.length === 0 ? (
                    <p className="instant-search-empty">لا توجد أصناف مطابقة لـ «{itemSearch.trim()}»</p>
                  ) : (
                    matchingInventory.map((item) => {
                      const stockQty = item.quantity !== 0 ? item.quantity : (item.computedQuantity ?? item.quantity ?? 0);
                      return (
                        <button
                          type="button"
                          key={item.id}
                          role="option"
                          onClick={() => pickProductIntoInvoice(item)}
                        >
                          <span>
                            <strong>{item.name}</strong>
                            <small> · كمية المخزن: {formatAmount(stockQty)}</small>
                            {item.sku ? <small> · باركود: {item.sku}</small> : null}
                          </span>
                          <b>
                            {formatAmount(unitPriceForProduct(item, 1, kind))} {currency}
                          </b>
                        </button>
                      );
                    })
                  )}
                </div>
              ) : null}

              {priceHint ? (
                <div className="invoice-price-hint" data-testid="invoice-price-hint">
                  <strong>{priceHint.name}:</strong>
                  <span>أقل: {formatAmount(priceHint.minPrice)}</span>
                  <span>أعلى: {formatAmount(priceHint.maxPrice)}</span>
                  <span>آخر سعر: {formatAmount(priceHint.lastPrice)}</span>
                </div>
              ) : null}

              <div className="invoice-lines-list">
                {rows.map((row, rowIndex) => {
                  const qtyNum = parseArabicNumber(row.quantity);
                  const priceNum = parseArabicNumber(row.price);
                  const discNum = Math.max(0, parseArabicNumber(row.discount));
                  const lineNet = Math.max(0, qtyNum * priceNum - discNum);
                  const linkedItem = row.inventoryItemId
                    ? inventoryById.get(row.inventoryItemId)
                    : undefined;
                  const hasMultiUnit = Boolean(linkedItem && (linkedItem.unit2 || linkedItem.unit3));
                  return (
                    <div key={row.rowId} className="invoice-line-card" data-testid="invoice-line-row">
                      <div className="invoice-line-top">
                        <span className="invoice-line-index" aria-hidden="true">
                          {rowIndex + 1}
                        </span>
                        <KeyboardInput
                          ref={(el) => {
                            rowNameRefs.current[row.rowId] = el;
                          }}
                          className="invoice-name-input"
                          aria-label="اسم الصنف"
                          aria-invalid={formError?.field === "items" && formError.rowId === row.rowId}
                          placeholder="اسم الصنف"
                          value={row.itemName}
                          onChange={(e) => {
                            if (formError) setFormError(null);
                            updateRow(row.rowId, { itemName: e.target.value });
                          }}
                        />
                        {hasMultiUnit && linkedItem ? (
                          <select
                            aria-label="وحدة الصنف"
                            className="invoice-unit-input"
                            value={String(row.unitNum ?? 1)}
                            onChange={(e) => {
                              const val = Number(e.target.value);
                              handleRowUnitNumChange(row, val === 2 ? 2 : val === 3 ? 3 : 1);
                            }}
                          >
                            <option value="1">{linkedItem.unit || "حبة"}</option>
                            {linkedItem.unit2 ? (
                              <option value="2">
                                {linkedItem.unit2} ({linkedItem.count2 ?? 1})
                              </option>
                            ) : null}
                            {linkedItem.unit3 ? (
                              <option value="3">
                                {linkedItem.unit3} ({(linkedItem.count2 ?? 1) * (linkedItem.count3 ?? 1)})
                              </option>
                            ) : null}
                          </select>
                        ) : (
                          <KeyboardInput
                            className="invoice-unit-input"
                            aria-label="الوحدة"
                            placeholder="حبة"
                            value={row.unit}
                            onChange={(e) => updateRow(row.rowId, { unit: e.target.value })}
                          />
                        )}
                        <button
                          type="button"
                          className="invoice-remove-line"
                          aria-label="حذف السطر"
                          onClick={() => removeRow(row.rowId)}
                        >
                          <TrashIcon />
                        </button>
                      </div>

                      {(linkedItem || row.sku) ? (
                        <div className="invoice-line-meta">
                          {linkedItem ? <span>كمية المخزن: <b>{formatAmount(linkedItem.quantity !== 0 ? linkedItem.quantity : (linkedItem.computedQuantity ?? linkedItem.quantity ?? 0))}</b></span> : null}
                          {row.sku ? <span>الباركود: <bdi>{row.sku}</bdi></span> : null}
                        </div>
                      ) : null}

                      <div className="invoice-line-nums invoice-line-nums-4">
                        <label>
                          <span>الكمية</span>
                          <KeyboardInput
                            ref={(el) => {
                              rowQtyRefs.current[row.rowId] = el;
                            }}
                            aria-label="كمية الصنف"
                            aria-invalid={formError?.field === "line-qty" && formError.rowId === row.rowId}
                            inputMode="decimal"
                            value={row.quantity}
                            onChange={(e) => {
                              if (formError) setFormError(null);
                              updateRow(row.rowId, { quantity: e.target.value });
                            }}
                          />
                        </label>
                        <label>
                          <span>السعر</span>
                          <KeyboardInput
                            ref={(el) => {
                              rowPriceRefs.current[row.rowId] = el;
                            }}
                            aria-label="سعر الصنف"
                            aria-invalid={formError?.field === "line-price" && formError.rowId === row.rowId}
                            inputMode="decimal"
                            placeholder="0"
                            value={row.price}
                            onChange={(e) => {
                              if (formError) setFormError(null);
                              updateRow(row.rowId, { price: e.target.value });
                            }}
                          />
                        </label>
                        <label>
                          <span>الخصم</span>
                          <KeyboardInput
                            aria-label="خصم السطر"
                            inputMode="decimal"
                            placeholder="0"
                            value={row.discount}
                            onChange={(e) => updateRow(row.rowId, { discount: e.target.value })}
                          />
                        </label>
                        <div className="invoice-line-total">
                          <span>الإجمالي</span>
                          <b>{formatAmount(lineNet)}</b>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>

              <div className="invoice-totals-bar">
                <div className="invoice-total-stat">
                  <span>الكمية</span>
                  <b>{formatAmount(computedItemsQty)}</b>
                </div>
                {computedItemsDiscount > 0 ? (
                  <div className="invoice-total-stat">
                    <span>الخصم</span>
                    <b className="discount-val">{formatAmount(computedItemsDiscount)}</b>
                  </div>
                ) : null}
                <div className="invoice-total-stat grand">
                  <span>الإجمالي</span>
                  <b data-testid="invoice-computed-total">
                    {formatAmount(effectiveAmount)} {currency}
                  </b>
                </div>
              </div>

              {formError &&
              (formError.field === "items" || formError.field === "line-qty" || formError.field === "line-price") ? (
                <div className="field-inline-error" role="alert" data-testid="invoice-line-error">
                  {formError.message}
                </div>
              ) : null}
            </section>
          ) : (
            <div className="invoice-free-amount-wrap">
              <OutlinedAmountField
                label={`المبلغ (${currency})`}
                ariaLabel="إجمالي مبلغ الفاتورة"
                testId="invoice-free-amount"
                inputRef={freeAmountInputRef}
                ariaInvalid={formError?.field === "amount"}
                currency={currency}
                value={amount}
                placeholder="0"
                onChange={(next) => {
                  if (formError?.field === "amount" || formError?.field === "submit") {
                    setFormError(null);
                  }
                  setAmount(next);
                }}
              />
              {formError?.field === "amount" ? (
                <div className="field-inline-error" role="alert" data-testid="invoice-amount-error">
                  {formError.message}
                </div>
              ) : null}
            </div>
          )}

          <label className="invoice-field-box invoice-note-box">
            <span>البيان / الملاحظات</span>
            <KeyboardInput
              aria-label="بيان الفاتورة"
              placeholder="أضف بياناً أو ملاحظة للفاتورة..."
              value={note}
              onChange={(event) => setNote(event.target.value)}
            />
          </label>

          {kind === "purchase" ? (
            <ExpenseCategorySelector
              value={expenseCategory}
              onChange={setExpenseCategory}
              description={note}
              vendorName={selectedAccount?.name ?? ""}
              accountCategory={selectedAccount?.category}
              amount={String(effectiveAmount || amount)}
              currency={currency}
              entryType={payment === "cash" ? "فاتورة شراء نقدي" : "فاتورة شراء آجلة"}
            />
          ) : null}

          {formError ? (
            <div className="field-inline-error" role="alert" data-testid="invoice-validation-error">
              {formError.message}
            </div>
          ) : null}

          {editingEntry && !editingEntry.deleted ? (
            <button
              type="button"
              className="invoice-trash-link"
              data-testid="invoice-trash-btn"
              disabled={saving}
              onClick={async () => {
                setSaving(true);
                try {
                  await setLedgerDeleted(ctx.uid, editingEntry.id, true);
                  triggerHaptic("warning");
                  onClose();
                  ctx.showToast(`تم نقل العملية #${editingEntry.entryNumber} إلى سلة المحذوفات`);
                } catch (err) {
                  ctx.showToast(err instanceof Error ? err.message : "تعذر نقل العملية إلى السلة");
                } finally {
                  setSaving(false);
                }
              }}
            >
              <TrashIcon /> نقل الفاتورة إلى سلة المحذوفات
            </button>
          ) : null}
        </div>

        <footer className="invoice-modal-footer">
          <div className="form-modal-actions form-modal-actions-3">
            <button type="button" className="cancel" onClick={onClose}>
              إلغاء
            </button>
            <button type="button" className="save-print" disabled={saving} onClick={() => void handleSave(true)}>
              حفظ وطباعة
            </button>
            <button type="button" className="save" data-testid="invoice-save-btn" disabled={saving} onClick={() => void handleSave(false)}>
              {saving
                ? "جاري الحفظ..."
                : editingEntry
                  ? "حفظ التعديل"
                  : intent === "quote"
                    ? "حفظ عرض السعر"
                    : intent === "order"
                      ? "حفظ الطلبية"
                      : isReturn
                        ? "حفظ المردود"
                        : "عمل فاتورة"}
            </button>
          </div>
        </footer>
      </section>
    </div>
  );
}

function currencyScreen(accountId?: string): FlowScreen {
  return {
    id: `currency-exchange-${accountId ?? "default"}`,
    headerHeight: 58,
    header: (flow) => <SimpleAppHeader title="صرف عملات" onBack={flow.pop} />,
    render: (flow) => <CurrencyPage flow={flow} initialAccountId={accountId} />,
  };
}

function simpleEntryScreen(toAccountId?: string): FlowScreen {
  return {
    id: `simple-entry-${toAccountId ?? "default"}`,
    headerHeight: 58,
    header: (flow) => (
      <div className="simple-entry-header">
        <SimpleAppHeader title="قيد بسيط" onBack={flow.pop} />
      </div>
    ),
    render: (flow) => <SimpleEntryPage flow={flow} initialToAccountId={toAccountId} />,
  };
}

function whatsappSettingsScreen(): FlowScreen {
  return {
    id: "whatsapp-settings",
    headerHeight: 0,
    render: (flow) => <WhatsAppSettingsPage flow={flow} />,
  };
}

function AppHeader({
  title,
  subtitle,
  onBack,
  onMenu,
  leadingTextActions,
  actions,
  className = "",
}: {
  title: string;
  subtitle: string;
  onBack?: () => void;
  onMenu?: () => void;
  leadingTextActions?: { label: string; testId?: string; onClick: () => void }[];
  className?: string;
  actions: { label: string; icon: IconComponent; badge?: string; onClick: () => void }[];
}) {
  return (
    <div className={`app-header ${className}`}>
      <button
        className="header-icon header-leading"
        onClick={onBack ?? onMenu}
        aria-label={onBack ? "رجوع" : "فتح القائمة"}
      >
        {onBack ? <ArrowRightIcon /> : <HamburgerMenuIcon />}
      </button>
      {leadingTextActions?.map((item) => (
        <button
          key={item.label}
          type="button"
          className="header-text-btn"
          data-testid={item.testId}
          onClick={item.onClick}
        >
          {item.label}
        </button>
      ))}
      <div className="header-brand">
        <span className="brand-mark" aria-hidden="true">
          <img
            src={APP_ICON_URL}
            alt=""
            className="app-brand-icon-img"
            draggable={false}
          />
        </span>
        <span className="header-copy">
          <strong>{title}</strong>
          {subtitle ? <small>{subtitle}</small> : null}
        </span>
      </div>
      <div className="header-actions">
        {actions.map((action) => (
          <button
            key={action.label}
            className="header-icon"
            onClick={action.onClick}
            aria-label={action.label}
          >
            <action.icon />
            {action.badge ? (
              <span className="notification-badge">
                {(() => {
                  const n = typeof action.badge === "number" ? action.badge : Number(action.badge);
                  return Number.isFinite(n) && n > 99 ? "99+" : action.badge;
                })()}
              </span>
            ) : null}
          </button>
        ))}
      </div>
    </div>
  );
}

function SimpleAppHeader({ title, onBack }: { title: string; onBack: () => void }) {
  return (
    <div className="app-header simple-app-header">
      <button className="header-icon" onClick={onBack} aria-label="رجوع">
        <ArrowRightIcon />
      </button>
      <strong>{title}</strong>
    </div>
  );
}

function TransferArrowsIcon() {
  return (
    <span className="transfer-arrows-icon" aria-hidden="true">
      <ArrowRightIcon />
      <ArrowLeftIcon />
    </span>
  );
}

function CartIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="9" cy="20" r="1.5" />
      <circle cx="18" cy="20" r="1.5" />
      <path d="M2 3h3l2.4 11.2a1.5 1.5 0 0 0 1.5 1.2h8.8a1.5 1.5 0 0 0 1.45-1.15L21 7H6" />
    </svg>
  );
}

function PeopleIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="3.5" />
      <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a3.5 3.5 0 0 1 0 6.74" />
    </svg>
  );
}

function ShopIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 9l1.5-5h15L21 9" />
      <path d="M3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0" />
      <path d="M5 10v10h14V10" />
      <path d="M9.5 20v-5h5v5" />
    </svg>
  );
}

function QrScanIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="3" width="7" height="7" rx="1.2" />
      <rect x="14" y="3" width="7" height="7" rx="1.2" />
      <rect x="3" y="14" width="7" height="7" rx="1.2" />
      <path d="M14 14h3v3h-3zM19 14h2v2M14 20h3M19 19v2h2" />
    </svg>
  );
}

function GaugeIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 14l4-4" />
      <path d="M4.6 18a9 9 0 1 1 14.8 0" />
    </svg>
  );
}

function TagPriceIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z" />
      <circle cx="7.5" cy="7.5" r="1.3" fill="currentColor" stroke="none" />
    </svg>
  );
}

function FactoryIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 21V10l6 4V10l6 4V4h4v17H3z" />
      <path d="M7 18h2M12 18h2" />
    </svg>
  );
}

function HomeHeroBuildingArt() {
  return (
    <svg className="home-summary-art" viewBox="0 0 240 130" preserveAspectRatio="xMinYMid slice" aria-hidden="true">
      <defs>
        <linearGradient id="nasqoTowerSky" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#8ed0ff" stopOpacity="0.92" />
          <stop offset="45%" stopColor="#3b82f6" stopOpacity="0.45" />
          <stop offset="100%" stopColor="#ffffff" stopOpacity="0" />
        </linearGradient>
        <linearGradient id="nasqoGlassLeft" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#0e4a86" />
          <stop offset="100%" stopColor="#1e78c8" />
        </linearGradient>
        <linearGradient id="nasqoGlassRight" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#38bdf8" stopOpacity="0.88" />
          <stop offset="100%" stopColor="#0b5ca8" stopOpacity="0.72" />
        </linearGradient>
      </defs>
      <rect width="240" height="130" fill="url(#nasqoTowerSky)" />
      <polygon points="10,130 10,36 74,8 74,130" fill="url(#nasqoGlassLeft)" />
      <polygon points="74,8 134,42 134,130 74,130" fill="url(#nasqoGlassRight)" />
      <g stroke="#bae6fd" strokeOpacity="0.45" strokeWidth="1.2">
        <line x1="26" y1="29" x2="26" y2="130" />
        <line x1="42" y1="22" x2="42" y2="130" />
        <line x1="58" y1="15" x2="58" y2="130" />
        <line x1="90" y1="17" x2="90" y2="130" />
        <line x1="106" y1="26" x2="106" y2="130" />
        <line x1="120" y1="34" x2="120" y2="130" />
        <line x1="10" y1="54" x2="74" y2="27" />
        <line x1="10" y1="74" x2="74" y2="48" />
        <line x1="10" y1="94" x2="74" y2="69" />
        <line x1="10" y1="114" x2="74" y2="90" />
        <line x1="74" y1="27" x2="134" y2="57" />
        <line x1="74" y1="48" x2="134" y2="75" />
        <line x1="74" y1="69" x2="134" y2="93" />
        <line x1="74" y1="90" x2="134" y2="112" />
      </g>
    </svg>
  );
}

function DashboardPage({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const defaultCurr = ctx.workspace?.defaultCurrency ?? "ريال";
  const [groupCurrencyMap, setGroupCurrencyMap] = useState<Record<number, string>>({});
  const [tileLayout, setTileLayout] = useState<HomeTileLayout>(() => readHomeTileLayout());
  const [tileEditMode, setTileEditMode] = useState(false);
  const [selectedTileId, setSelectedTileId] = useState<HomeTileId | null>(null);
  const [draggingTileId, setDraggingTileId] = useState<HomeTileId | null>(null);

  const longPressTimerRef = useRef<number | null>(null);
  const pointerStartRef = useRef<{ x: number; y: number; tileId: HomeTileId } | null>(null);
  const suppressNextClickRef = useRef(false);
  const longTouchClickRef = useRef(false);
  const didDragMoveRef = useRef(false);
  const lastSwapTargetRef = useRef<HomeTileId | null>(null);

  const updateTileLayout = useCallback((updater: (prev: HomeTileLayout) => HomeTileLayout) => {
    setTileLayout((prev) => {
      const next = updater(prev);
      writeHomeTileLayout(next);
      return next;
    });
  }, []);

  const clearLongPressTimer = useCallback(() => {
    if (longPressTimerRef.current !== null) {
      window.clearTimeout(longPressTimerRef.current);
      longPressTimerRef.current = null;
    }
  }, []);

  useEffect(() => {
    return () => clearLongPressTimer();
  }, [clearLongPressTimer]);

  useEffect(() => {
    if (!tileEditMode) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setTileEditMode(false);
        setDraggingTileId(null);
        setSelectedTileId(null);
        writeHomeTileLayout(tileLayout);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [tileEditMode, tileLayout]);

  const groupRows = useMemo(
    () =>
      computeAccountGroupsSummary(
        ctx.accountGroups,
        ctx.accounts,
        ctx.ledger,
        groupCurrencyMap,
        defaultCurr,
      ),
    [ctx.accountGroups, ctx.accounts, ctx.ledger, groupCurrencyMap, defaultCurr],
  );

  type HomeTileDef = {
    id: HomeTileId;
    label: string;
    icon: IconComponent;
    defaultTone: HomeTileTone;
    defaultGroup: "ops-blue" | "ops-amber" | "admin-blue" | "admin-amber";
    testId?: string;
    action: () => void;
  };

  const allTiles: HomeTileDef[] = [
    { id: "new-voucher", label: "سند جديد", icon: FilePlusIcon, defaultTone: "blue", defaultGroup: "ops-blue", action: () => { triggerHaptic("light"); ctx.openTransaction(); } },
    { id: "new-transfer", label: "حوالة جديدة", icon: PaperPlaneIcon, defaultTone: "blue", defaultGroup: "ops-blue", action: () => { triggerHaptic("light"); ctx.openTransferModal(); } },
    { id: "new-invoice", label: "فاتورة جديدة", icon: FileTextIcon, defaultTone: "blue", defaultGroup: "ops-blue", action: () => { triggerHaptic("light"); ctx.openInvoice(); } },
    { id: "new-return", label: "مردود جديد", icon: ReloadIcon, defaultTone: "blue", defaultGroup: "ops-blue", action: () => { triggerHaptic("light"); ctx.openVendorInvoice(ctx.accounts[0], "return"); } },
    { id: "simple-entry", label: "قيد بسيط", icon: MixIcon, defaultTone: "blue", defaultGroup: "ops-blue", action: () => { triggerHaptic("light"); flow.push(simpleEntryScreen()); } },
    { id: "quote", label: "عرض سعر", icon: ReaderIcon, defaultTone: "blue", defaultGroup: "ops-blue", action: () => { triggerHaptic("light"); ctx.openVendorInvoice(ctx.accounts[0], "quote"); } },
    { id: "currency-exchange", label: "صرف عملات", icon: SwitchIcon, defaultTone: "blue", defaultGroup: "ops-blue", action: () => { triggerHaptic("light"); flow.push(currencyScreen()); } },
    { id: "new-order", label: "طلبية جديدة", icon: BackpackIcon, defaultTone: "blue", defaultGroup: "ops-blue", action: () => { triggerHaptic("light"); ctx.openVendorInvoice(ctx.accounts[0], "order"); } },
    { id: "quick-search", label: "البحث السريع", icon: MagnifyingGlassIcon, defaultTone: "amber", defaultGroup: "ops-amber", action: () => { triggerHaptic("light"); ctx.openQuickSearch(); } },
    { id: "daily-journal", label: "الحركة اليومية", icon: ActivityLogIcon, defaultTone: "amber", defaultGroup: "ops-amber", action: () => { triggerHaptic("light"); flow.push(dailyJournalScreen()); } },
    { id: "cashboxes", label: "صناديق النقدية", icon: CardStackIcon, defaultTone: "amber", defaultGroup: "ops-amber", action: () => { triggerHaptic("light"); ctx.openCashboxesReport(); } },
    { id: "statement", label: "كشف حساب", icon: ReaderIcon, defaultTone: "amber", defaultGroup: "ops-amber", action: () => { triggerHaptic("light"); ctx.openAccountPicker(); } },
    { id: "reports", label: "التقارير", icon: BarChartIcon, defaultTone: "amber", defaultGroup: "ops-amber", action: () => { triggerHaptic("light"); ctx.openReportsHub(); } },
    { id: "currencies", label: "العملات", icon: CardStackIcon, defaultTone: "blue", defaultGroup: "admin-blue", action: () => { triggerHaptic("light"); ctx.openCurrenciesManager(); } },
    { id: "account-groups", label: "دليل الحسابات", icon: LayersIcon, defaultTone: "blue", defaultGroup: "admin-blue", action: () => { triggerHaptic("light"); ctx.openAccountGroups(); } },
    { id: "accounts", label: "الحسابات", icon: PeopleIcon, defaultTone: "blue", defaultGroup: "admin-blue", action: () => { triggerHaptic("light"); ctx.openChartOfAccounts(); } },
    { id: "warehouses", label: "المخازن", icon: CubeIcon, defaultTone: "blue", defaultGroup: "admin-blue", action: () => { triggerHaptic("light"); flow.push(warehousesScreen()); } },
    { id: "sales-dashboard", label: "لوحة المبيعات", icon: BarChartIcon, defaultTone: "blue", defaultGroup: "admin-blue", action: () => { triggerHaptic("light"); flow.push(analyticsDashboardScreen()); } },
    { id: "trash", label: "سلة المحذوفات", icon: TrashIcon, defaultTone: "blue", defaultGroup: "admin-blue", action: () => { triggerHaptic("light"); ctx.openTrash(); } },
    { id: "trial-balance", label: "ميزان المراجعة", icon: GaugeIcon, defaultTone: "amber", defaultGroup: "admin-amber", testId: "open-trial-balance-btn", action: () => { triggerHaptic("light"); ctx.openTrialBalance(); } },
    { id: "items", label: "الأصناف", icon: TagPriceIcon, defaultTone: "amber", defaultGroup: "admin-amber", testId: "open-items-btn", action: () => { triggerHaptic("light"); flow.push(itemsScreen()); } },
    { id: "stock-movement", label: "حركة المخزون", icon: ActivityLogIcon, defaultTone: "amber", defaultGroup: "admin-amber", testId: "open-stock-movement-btn", action: () => { triggerHaptic("light"); flow.push(inventoryReportScreen()); } },
    { id: "erp-hub", label: "الإدارة المتقدمة", icon: RocketIcon, defaultTone: "amber", defaultGroup: "admin-amber", testId: "open-erp-hub-btn", action: () => { triggerHaptic("light"); flow.push(erpModuleScreen("erp-hub")); } },
    { id: "settings", label: "الإعدادات", icon: GearIcon, defaultTone: "amber", defaultGroup: "admin-amber", action: () => { triggerHaptic("light"); ctx.openSettings(); } },
  ];

  const tileById = useMemo(() => {
    const map = new Map<HomeTileId, HomeTileDef>();
    for (const item of allTiles) map.set(item.id, item);
    return map;
  }, [allTiles]);

  const { pinnedIds, unpinnedIds } = useMemo(
    () => getVisibleOrderedHomeTiles(tileLayout),
    [tileLayout],
  );
  const pinnedSet = useMemo(() => new Set(tileLayout.pinned), [tileLayout.pinned]);
  const isCustomLayout = tileEditMode || !isDefaultHomeTileLayout(tileLayout);
  const selectedTile = selectedTileId ? tileById.get(selectedTileId) ?? null : null;

  const handleTilePointerDown = (tileId: HomeTileId, e: ReactPointerEvent<HTMLButtonElement>) => {
    if (e.button !== 0 && e.pointerType === "mouse") return;
    const targetEl = e.target as HTMLElement | null;
    if (targetEl?.closest('[data-tile-corner-action="true"]')) return;

    pointerStartRef.current = { x: e.clientX, y: e.clientY, tileId };
    didDragMoveRef.current = false;
    lastSwapTargetRef.current = null;

    if (tileEditMode) {
      try {
        e.currentTarget.setPointerCapture(e.pointerId);
      } catch {
        // Ignore synthetic pointer events without capture support
      }
      return;
    }

    clearLongPressTimer();
    longPressTimerRef.current = window.setTimeout(() => {
      longPressTimerRef.current = null;
      suppressNextClickRef.current = true;
      longTouchClickRef.current = e.pointerType === "touch";
      triggerHaptic("pin");
      setTileEditMode(true);
      setSelectedTileId(tileId);
      ctx.showToast("وضع تحرير البطائق — اسحب للترتيب أو ثبّت المفضلة ثم اضغط تثبيت");
    }, 450);
  };

  const handleTilePointerMove = (tileId: HomeTileId, e: ReactPointerEvent<HTMLButtonElement>) => {
    const start = pointerStartRef.current;
    if (!start || start.tileId !== tileId) return;
    const dist = Math.hypot(e.clientX - start.x, e.clientY - start.y);

    if (!tileEditMode) {
      if (dist > 10) {
        clearLongPressTimer();
        pointerStartRef.current = null;
      }
      return;
    }

    if (dist > 8) {
      didDragMoveRef.current = true;
      if (draggingTileId !== tileId) {
        setDraggingTileId(tileId);
        setSelectedTileId(tileId);
      }
      if (typeof document.elementsFromPoint === "function") {
        const els = document.elementsFromPoint(e.clientX, e.clientY);
        for (const el of els) {
          const tileEl = (el as HTMLElement).closest?.("[data-home-tile-id]") as HTMLElement | null;
          const overId = tileEl?.dataset.homeTileId as HomeTileId | undefined;
          if (overId && overId !== tileId) {
            if (lastSwapTargetRef.current !== overId) {
              lastSwapTargetRef.current = overId;
              triggerHaptic("light");
              updateTileLayout((prev) => moveHomeTile(prev, tileId, overId));
            }
            break;
          }
        }
      }
    }
  };

  const handleTilePointerEnd = (tileId: HomeTileId, e: ReactPointerEvent<HTMLButtonElement>) => {
    clearLongPressTimer();
    if (tileEditMode) {
      try {
        if (e.currentTarget.hasPointerCapture?.(e.pointerId)) {
          e.currentTarget.releasePointerCapture(e.pointerId);
        }
      } catch {
        // Ignore release errors
      }
      if (didDragMoveRef.current) {
        suppressNextClickRef.current = true;
      }
      if (draggingTileId === tileId) {
        setDraggingTileId(null);
      }
    }
    pointerStartRef.current = null;
    lastSwapTargetRef.current = null;
  };

  const finishTileEditMode = () => {
    clearLongPressTimer();
    writeHomeTileLayout(tileLayout);
    setTileEditMode(false);
    setDraggingTileId(null);
    setSelectedTileId(null);
    triggerHaptic("success");
    ctx.showToast("تم تثبيت ترتيب البطائق بنجاح");
  };

  const resetTileLayoutToDefault = () => {
    triggerHaptic("light");
    updateTileLayout(() => DEFAULT_HOME_TILE_LAYOUT);
    setSelectedTileId(null);
    ctx.showToast("تمت استعادة الترتيب الافتراضي للبطائق");
  };

  const renderTileButton = (item: HomeTileDef) => {
    const effectiveTone = tileLayout.toneOverrides[item.id] ?? item.defaultTone;
    const isPinned = pinnedSet.has(item.id);
    const isSelected = tileEditMode && selectedTileId === item.id;
    const isDragging = tileEditMode && draggingTileId === item.id;
    const canHide = item.id !== "settings";

    return (
      <button
        key={item.id}
        type="button"
        data-testid={item.testId ?? `home-tile-${item.id}`}
        data-home-tile-id={item.id}
        data-scroll-drag={tileEditMode ? "ignore" : undefined}
        className={`smart-tile ${effectiveTone}${tileEditMode ? " editing" : ""}${isSelected ? " selected" : ""}${isDragging ? " dragging" : ""}${isPinned ? " pinned" : ""}`}
        onContextMenu={(e) => e.preventDefault()}
        onPointerDown={(e) => handleTilePointerDown(item.id, e)}
        onPointerMove={(e) => handleTilePointerMove(item.id, e)}
        onPointerUp={(e) => handleTilePointerEnd(item.id, e)}
        onPointerCancel={(e) => handleTilePointerEnd(item.id, e)}
        onPointerLeave={() => {
          if (!tileEditMode) clearLongPressTimer();
        }}
        onClick={(e) => {
          const targetEl = e.target as HTMLElement | null;
          if (targetEl?.closest('[data-tile-corner-action="true"]')) return;
          if (suppressNextClickRef.current) {
            suppressNextClickRef.current = false;
            return;
          }
          if (tileEditMode) {
            triggerHaptic("light");
            setSelectedTileId(item.id);
            return;
          }
          item.action();
        }}
      >
        {tileEditMode ? (
          <>
            <span
              role="button"
              tabIndex={0}
              data-tile-corner-action="true"
              data-testid={`tile-pin-${item.id}`}
              className={`smart-tile-corner-btn pin${isPinned ? " active" : ""}`}
              aria-label={isPinned ? `إلغاء تثبيت ${item.label}` : `تثبيت ${item.label} بالأعلى`}
              onClick={(ev) => {
                ev.stopPropagation();
                triggerHaptic("light");
                setSelectedTileId(item.id);
                updateTileLayout((prev) => togglePinHomeTile(prev, item.id));
              }}
              onKeyDown={(ev) => {
                if (ev.key === "Enter" || ev.key === " ") {
                  ev.preventDefault();
                  ev.stopPropagation();
                  updateTileLayout((prev) => togglePinHomeTile(prev, item.id));
                }
              }}
            >
              {isPinned ? <DrawingPinFilledIcon /> : <DrawingPinIcon />}
            </span>
            {canHide ? (
              <span
                role="button"
                tabIndex={0}
                data-tile-corner-action="true"
                data-testid={`tile-hide-${item.id}`}
                className="smart-tile-corner-btn hide"
                aria-label={`إخفاء ${item.label}`}
                onClick={(ev) => {
                  ev.stopPropagation();
                  triggerHaptic("light");
                  if (selectedTileId === item.id) setSelectedTileId(null);
                  updateTileLayout((prev) => toggleHideHomeTile(prev, item.id));
                }}
                onKeyDown={(ev) => {
                  if (ev.key === "Enter" || ev.key === " ") {
                    ev.preventDefault();
                    ev.stopPropagation();
                    updateTileLayout((prev) => toggleHideHomeTile(prev, item.id));
                  }
                }}
              >
                <Cross2Icon />
              </span>
            ) : null}
          </>
        ) : isPinned ? (
          <span className="smart-tile-pin-mark" aria-label="بطاقة مثبّتة" title="مثبّتة">
            <DrawingPinFilledIcon />
          </span>
        ) : null}

        <span className="smart-tile-icon" aria-hidden="true">
          <item.icon />
        </span>
        <span className="smart-tile-label">{item.label}</span>
      </button>
    );
  };

  const defaultOpsBlue = allTiles.filter((t) => t.defaultGroup === "ops-blue");
  const defaultOpsAmber = allTiles.filter((t) => t.defaultGroup === "ops-amber");
  const defaultAdminBlue = allTiles.filter((t) => t.defaultGroup === "admin-blue");
  const defaultAdminAmber = allTiles.filter((t) => t.defaultGroup === "admin-amber");
  const hiddenTiles = tileLayout.hidden
    .map((id) => tileById.get(id))
    .filter((t): t is HomeTileDef => Boolean(t));

  return (
    <>
      <MobileScroll className="app-screen dashboard-scroll smart-workbench-scroll">
        <main
          className={`dashboard-page page-with-footer smart-home-workbench${isCustomLayout ? " custom-tile-layout" : ""}${tileEditMode ? " is-editing-tiles" : ""}`}
          data-testid="dashboard-screen"
          onPointerDownCapture={() => {
            if (longTouchClickRef.current) {
              longTouchClickRef.current = false;
              suppressNextClickRef.current = false;
            }
          }}
          onClickCapture={(event) => {
            // Entering edit mode can move another control under the same finger.
            if (longTouchClickRef.current && event.detail > 0) {
              longTouchClickRef.current = false;
              suppressNextClickRef.current = false;
              event.preventDefault();
              event.stopPropagation();
            }
          }}
        >
          {/* Right / Primary Quick Operations Column */}
          {!isCustomLayout ? (
            <aside className="smart-panel smart-panel-ops" aria-label="العمليات والتقارير">
              <div className="smart-btn-grid">
                {defaultOpsBlue.map((item) => renderTileButton(item))}
              </div>
              <div className="smart-btn-grid">
                {defaultOpsAmber.map((item) => renderTileButton(item))}
              </div>
            </aside>
          ) : (
            <aside className="smart-panel smart-panel-unified" aria-label="بطائق الواجهة الرئيسية">
              {pinnedIds.length > 0 ? (
                <div className="smart-pinned-section" data-testid="home-pinned-tiles">
                  <div className="smart-section-label">
                    <DrawingPinFilledIcon />
                    <span>البطائق المثبّتة</span>
                  </div>
                  <div className="smart-btn-grid">
                    {pinnedIds
                      .map((id) => tileById.get(id))
                      .filter((t): t is HomeTileDef => Boolean(t))
                      .map((item) => renderTileButton(item))}
                  </div>
                </div>
              ) : null}

              {unpinnedIds.length > 0 ? (
                <div className="smart-unpinned-section">
                  {pinnedIds.length > 0 ? (
                    <div className="smart-section-label muted">
                      <span>باقي البطائق</span>
                    </div>
                  ) : null}
                  <div className="smart-btn-grid">
                    {unpinnedIds
                      .map((id) => tileById.get(id))
                      .filter((t): t is HomeTileDef => Boolean(t))
                      .map((item) => renderTileButton(item))}
                  </div>
                </div>
              ) : null}

              {tileEditMode && hiddenTiles.length > 0 ? (
                <div className="smart-hidden-tray" data-testid="home-hidden-tiles-tray">
                  <div className="smart-section-label muted">
                    <span>بطائق مخفية — اضغط لإعادتها</span>
                  </div>
                  <div className="smart-hidden-chips">
                    {hiddenTiles.map((item) => (
                      <button
                        key={item.id}
                        type="button"
                        className="smart-hidden-chip"
                        data-testid={`tile-restore-${item.id}`}
                        onClick={() => {
                          triggerHaptic("light");
                          updateTileLayout((prev) => toggleHideHomeTile(prev, item.id));
                        }}
                      >
                        <PlusIcon />
                        <span>{item.label}</span>
                      </button>
                    ))}
                  </div>
                </div>
              ) : null}
            </aside>
          )}

          {/* Center Live Account Groups Grid */}
          <section className="smart-center-stage" aria-label="مجموعات الحسابات والأرصدة">
            <header className="smart-brand-plaque" data-testid="home-brand-plaque">
              <span className="smart-brand-emblem" aria-hidden="true">
                {ctx.extendedSettings.logoDataUrl ? (
                  <img
                    src={ctx.extendedSettings.logoDataUrl}
                    alt=""
                    className="smart-brand-logo-img"
                    draggable={false}
                  />
                ) : (
                  <img
                    src={APP_ICON_URL}
                    alt=""
                    className="smart-brand-logo-img app-brand-icon-img"
                    draggable={false}
                  />
                )}
              </span>
              <div className="smart-brand-copy">
                <strong>
                  {!ctx.workspace?.companyName || ctx.workspace.companyName === "نسقو برو ERP"
                    ? "نسقو برو"
                    : ctx.workspace.companyName}
                </strong>
                <small>إدارة الحسابات والمبيعات والمخزون</small>
              </div>
              <button
                type="button"
                className="smart-brand-qr"
                onClick={ctx.openQrScanner}
                aria-label="مسح رمز QR"
                data-testid="home-qr-scanner-btn"
              >
                <QrScanIcon />
              </button>
            </header>

            {tileEditMode ? (
              <div className="smart-edit-bar" role="region" aria-label="أدوات تحرير وتثبيت البطائق" data-testid="home-tiles-edit-bar">
                <div className="smart-edit-bar-top">
                  <div className="smart-edit-bar-title">
                    <DrawingPinFilledIcon />
                    <div>
                      <strong>تحرير البطائق</strong>
                      <small>اسحب البطاقة لتغيير مكانها أو اضغط الدبوس للتثبيت</small>
                    </div>
                  </div>
                  <div className="smart-edit-bar-actions">
                    <button
                      type="button"
                      className="smart-edit-btn secondary"
                      data-testid="home-tiles-reset-btn"
                      onClick={resetTileLayoutToDefault}
                    >
                      <ResetIcon />
                      <span>افتراضي</span>
                    </button>
                    <button
                      type="button"
                      className="smart-edit-btn primary"
                      data-testid="home-tiles-save-btn"
                      onClick={finishTileEditMode}
                    >
                      <CheckIcon />
                      <span>تثبيت</span>
                    </button>
                  </div>
                </div>

                {selectedTile ? (
                  <div className="smart-edit-selected-strip" data-testid="home-tiles-selected-controls">
                    <span className="smart-edit-selected-name">{selectedTile.label}</span>
                    <div className="smart-edit-selected-btns">
                      <button
                        type="button"
                        className={pinnedSet.has(selectedTile.id) ? "active" : ""}
                        data-testid="selected-tile-pin-btn"
                        onClick={() => {
                          triggerHaptic("light");
                          updateTileLayout((prev) => togglePinHomeTile(prev, selectedTile.id));
                        }}
                      >
                        {pinnedSet.has(selectedTile.id) ? <DrawingPinFilledIcon /> : <DrawingPinIcon />}
                        <span>{pinnedSet.has(selectedTile.id) ? "مثبّتة" : "تثبيت بالأعلى"}</span>
                      </button>
                      <button
                        type="button"
                        aria-label="تقديم البطاقة"
                        data-testid="selected-tile-prev-btn"
                        onClick={() => {
                          triggerHaptic("light");
                          updateTileLayout((prev) => stepHomeTile(prev, selectedTile.id, -1));
                        }}
                      >
                        <ArrowRightIcon />
                      </button>
                      <button
                        type="button"
                        aria-label="تأخير البطاقة"
                        data-testid="selected-tile-next-btn"
                        onClick={() => {
                          triggerHaptic("light");
                          updateTileLayout((prev) => stepHomeTile(prev, selectedTile.id, 1));
                        }}
                      >
                        <ArrowLeftIcon />
                      </button>
                      <button
                        type="button"
                        data-testid="selected-tile-tone-btn"
                        onClick={() => {
                          triggerHaptic("light");
                          updateTileLayout((prev) =>
                            toggleToneHomeTile(prev, selectedTile.id, selectedTile.defaultTone),
                          );
                        }}
                      >
                        <span>تبديل اللون</span>
                      </button>
                    </div>
                  </div>
                ) : null}
              </div>
            ) : null}

            {ctx.syncError || groupRows.length > 0 || ctx.accounts.length > 0 ? (
              <div className="smart-groups-table-wrap" data-testid="account-groups-table">
                {ctx.syncError ? (
                  <div className="workspace-sync-error" role="alert" data-testid="workspace-sync-error">
                    <strong>تعذر تحميل البيانات</strong>
                    <p>{ctx.syncError}</p>
                    <button
                      type="button"
                      className="smart-tile blue"
                      data-testid="workspace-retry-sync-btn"
                      disabled={ctx.retryingSync}
                      onClick={() => void ctx.retrySync()}
                    >
                      {ctx.retryingSync ? "جاري إعادة المحاولة..." : "إعادة المحاولة"}
                    </button>
                  </div>
                ) : (
                  <table className="smart-groups-table">
                    <thead>
                      <tr>
                        <th scope="col">الرقم</th>
                        <th scope="col">الاسم</th>
                        <th scope="col">الرصيد</th>
                        <th scope="col">العملة</th>
                      </tr>
                    </thead>
                    <tbody>
                      {groupRows.map((row) => {
                        const isNeg = row.netDebitMinusCredit < -0.005;
                        const isPos = row.netDebitMinusCredit > 0.005;
                        const isPurchases = row.legacyId === 2 || row.category === "purchases";
                        return (
                          <tr
                            key={row.id}
                            data-testid={`group-row-${row.legacyId}`}
                            className={isPurchases ? "metric-card-purchases" : undefined}
                          >
                            <td className="smart-col-num">
                              <bdi>{row.legacyId}</bdi>
                            </td>
                            <td className="smart-col-name">
                              <button
                                type="button"
                                onClick={() => {
                                  triggerHaptic("light");
                                  flow.push(purchasesScreen(row.category, row.id, row.name));
                                }}
                              >
                                <span>{row.name}</span>
                                <small>{row.accountCount} حساب</small>
                              </button>
                            </td>
                            <td className={`smart-col-bal ${isNeg ? "neg" : isPos ? "pos" : "zero"}`}>
                              <button
                                type="button"
                                onClick={() => {
                                  triggerHaptic("light");
                                  flow.push(purchasesScreen(row.category, row.id, row.name));
                                }}
                              >
                                <strong>
                                  <bdi>{formatSignedSmartBalance(row.netDebitMinusCredit)}</bdi>
                                </strong>
                              </button>
                            </td>
                            <td className="smart-col-curr">
                              <select
                                aria-label={`عملة ${row.name}`}
                                value={row.currency}
                                onChange={(e) =>
                                  setGroupCurrencyMap((prev) => ({
                                    ...prev,
                                    [row.id]: e.target.value,
                                  }))
                                }
                              >
                                {ctx.currencyCodes.map((c) => (
                                  <option key={c} value={c}>
                                    {c}
                                  </option>
                                ))}
                                <option value="الكل">الكل</option>
                              </select>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                )}
              </div>
            ) : null}
          </section>

          {/* Left Administration & Analytics Column */}
          {!isCustomLayout ? (
            <aside className="smart-panel smart-panel-admin" aria-label="الإدارة والتقارير">
              <div className="smart-btn-grid">
                {defaultAdminBlue.map((item) => renderTileButton(item))}
              </div>
              <div className="smart-btn-grid">
                {defaultAdminAmber.map((item) => renderTileButton(item))}
              </div>
            </aside>
          ) : null}
        </main>
      </MobileScroll>
    </>
  );
}

function PurchasesPage({
  flow,
  category,
  groupId,
}: {
  flow: FlowControls;
  category: AccountCategory;
  groupId?: number;
}) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const [period, setPeriod] = useState("الكل");
  const [sortDirection, setSortDirection] = useState("تنازلي");
  const [sortBy, setSortBy] = useState("date");
  const currencyFilter = ctx.categoryCurrencies[category] ?? ctx.workspace?.defaultCurrency ?? "ريال";
  const [byCurrency, setByCurrency] = useState(false);
  const [createMenuOpen, setCreateMenuOpen] = useState(false);
  const [operationVendor, setOperationVendor] = useState<AccountRecord | null>(null);
  const keyboard = useKeyboard();
  const { screenRef } = useScreenPortal();
  const periods = ["يومي", "شهري", "الكل", "سنوي"];

  const createActions: { label: string; action: () => void }[] = [
    { label: "حساب جديد", action: () => ctx.openAccountCreate("extended", category) },
    { label: "سند جديد", action: () => ctx.openTransaction() },
    { label: "حوالة جديدة", action: () => ctx.openTransferModal() },
    { label: "فاتورة جديدة", action: ctx.openInvoice },
    { label: "قيد بسيط", action: () => flow.push(simpleEntryScreen()) },
    { label: "صرف عملات", action: () => flow.push(currencyScreen()) },
    {
      label: "عرض سعر",
      action: () => ctx.openVendorInvoice(ctx.accounts[0], "quote"),
    },
    {
      label: "طلبية جديدة",
      action: () => ctx.openVendorInvoice(ctx.accounts[0], "order"),
    },
  ];
  const runCreateAction = (action: () => void) => {
    keyboard.hide();
    setCreateMenuOpen(false);
    action();
  };
  const openVendorMenu = (vendor: AccountRecord) => {
    keyboard.hide();
    setCreateMenuOpen(false);
    setOperationVendor(vendor);
  };
  const contextActions = operationVendor
    ? [
        { label: "فاتورة جديدة", action: () => ctx.openVendorInvoice(operationVendor) },
        { label: "مردود جديد", action: () => ctx.openVendorInvoice(operationVendor, "return") },
        { label: "سند جديد", action: () => ctx.openTransaction(operationVendor) },
        { label: "حوالة جديدة", action: () => ctx.openTransferModal(operationVendor.id) },
        { label: "قيد بسيط", action: () => flow.push(simpleEntryScreen(operationVendor.id)) },
        { label: "صرف عملات", action: () => flow.push(currencyScreen(operationVendor.id)) },
        { label: "عرض سعر", action: () => ctx.openVendorInvoice(operationVendor, "quote") },
        { label: "طلبية جديدة", action: () => ctx.openVendorInvoice(operationVendor, "order") },
      ]
    : [];

  const portal = screenRef.current?.querySelector(".nasqo-app");
  const periodRange = useMemo(() => computePeriodDateRange(period), [period]);
  const periodLedger = useMemo(() => {
    if (!periodRange.fromDate && !periodRange.toDate) return ctx.ledger;
    return ctx.ledger.filter((e) => {
      const d = e.entryDate || "";
      if (periodRange.fromDate && d < periodRange.fromDate) return false;
      if (periodRange.toDate && d > periodRange.toDate) return false;
      return true;
    });
  }, [ctx.ledger, periodRange.fromDate, periodRange.toDate]);
  const activeCurrencyParam = currencyFilter === "الكل" ? undefined : currencyFilter;
  const accountsWithCurrencyEntry = useMemo(() => {
    if (!activeCurrencyParam) return null;
    const set = new Set<string>();
    for (const e of periodLedger) {
      if (!e.deleted && e.currency === activeCurrencyParam) {
        set.add(e.accountId);
        if (e.counterpartAccountId) set.add(e.counterpartAccountId);
      }
    }
    return set;
  }, [activeCurrencyParam, periodLedger]);
  const categoryAccounts = ctx.accounts.filter(
    (a) =>
      (groupId !== undefined ? a.groupId === groupId : a.category === category) &&
      (!byCurrency ||
        !activeCurrencyParam ||
        a.currency === activeCurrencyParam ||
        Boolean(accountsWithCurrencyEntry?.has(a.id))),
  );
  const orderedVendors =
    sortBy === "name"
      ? [...categoryAccounts].sort((a, b) => a.name.localeCompare(b.name, "ar"))
      : [...categoryAccounts];
  const visibleVendors = sortDirection === "تنازلي" ? orderedVendors : orderedVendors.reverse();

  return (
    <div className="purchases-layout">
      <section className="purchases-filter-panel" data-testid="purchases-filter-panel">
        <div className="purchases-periods" role="group" aria-label="الفترة">
          {periods.map((item) => (
            <button key={item} aria-pressed={period === item} onClick={() => setPeriod(item)}>
              <span className="period-radio-mark" />
              {item}
            </button>
          ))}
        </div>
        <div className="purchases-sort-row">
          <select
            aria-label="ترتيب المشتريات"
            value={sortBy}
            onChange={(event) => setSortBy(event.target.value)}
          >
            <option value="date">ترتيب حسب التاريخ</option>
            <option value="name">ترتيب حسب الاسم</option>
          </select>
          <div>
            {["تصاعدي", "تنازلي"].map((item) => (
              <button
                key={item}
                aria-pressed={sortDirection === item}
                onClick={() => setSortDirection(item)}
              >
                <span className="period-radio-mark" />
                {item}
              </button>
            ))}
          </div>
        </div>
        <div className="purchases-currency-row">
          <span>العملة</span>
          <select
            aria-label="عملة المشتريات"
            value={currencyFilter}
            onChange={(e) => ctx.setCategoryCurrency(category, e.target.value)}
          >
            <option value="الكل">جميع العملات</option>
            {ctx.currencyCodes.map((c) => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>
          <label>
            <input
              type="checkbox"
              checked={byCurrency}
              onChange={(event) => setByCurrency(event.target.checked)}
            />
            حسابات العملة فقط
          </label>
        </div>
        <div className="reference-date-strip">
          <span>
            من <b>{periodRange.fromDate || "البداية"}</b>
          </span>
          <span>
            إلى <b>{periodRange.toDate || new Date().toISOString().slice(0, 10)}</b>
          </span>
        </div>
      </section>
      <MobileScroll className="app-screen purchases-list-scroll">
        <main className="purchases-page page-with-footer" data-testid="purchases-screen">
          {visibleVendors.length === 0 ? (
            <p className="cash-empty">لا توجد حسابات في هذا القسم حتى الآن — اضغط + لإضافة حساب.</p>
          ) : (
            <section className="vendor-list">
              {visibleVendors.map((vendor) => {
                const summary = computeAccountSummary(
                  vendor,
                  periodLedger,
                  activeCurrencyParam,
                );
                return (
                  <article key={vendor.id} className="vendor-card" data-vendor-id={vendor.codeNumber}>
                    <button
                      className="vendor-call"
                      aria-label={`اتصال بـ ${vendor.name}`}
                      onClick={() => {
                        if (vendor.phone) {
                          window.location.href = `tel:${vendor.phone.replace(/\s+/g, "")}`;
                        } else {
                          ctx.showToast("لا يوجد رقم هاتف مسجل لهذا الحساب");
                        }
                      }}
                    >
                      <MobileIcon />
                    </button>
                    <button
                      className="vendor-open"
                      onClick={() => flow.push(supplierScreen(vendor.id))}
                      aria-label={`فتح كشف ${vendor.name}`}
                    >
                      <span className="vendor-main">
                        <strong>{vendor.name}</strong>
                        <small>سقف المديونية: {formatAmount(vendor.creditLimit)}</small>
                        {vendor.phone ? (
                          <em className={vendor.isCashAccount ? "cash-vendor-phone" : undefined}>
                            {vendor.phone}
                          </em>
                        ) : null}
                      </span>
                      <span className={`vendor-balance ${summary.tone}`}>
                        <strong>
                          {formatAmount(summary.netBalance)}
                          {summary.tone === "credit" ? "-" : ""}
                        </strong>
                      </span>
                    </button>
                    <span className="vendor-actions" role="group" aria-label={`إجراءات ${vendor.name}`}>
                      <button
                        aria-label={`تعديل ${vendor.name}`}
                        onClick={() => ctx.openAccountEdit(vendor)}
                      >
                        <Pencil1Icon />
                      </button>
                      <button
                        aria-label={`رسالة إلى ${vendor.name}`}
                        onClick={() =>
                          void shareOrCopyText(
                            vendor.name,
                            `رصيد ${vendor.name}: ${formatAmount(summary.netBalance)} ${vendor.currency}`,
                            ctx.showToast,
                          )
                        }
                      >
                        <ChatBubbleIcon />
                      </button>
                      <button
                        type="button"
                        className="vendor-whatsapp"
                        data-testid={`vendor-whatsapp-${vendor.codeNumber}`}
                        aria-label={`واتساب ${vendor.name}`}
                        onClick={() =>
                          void openWhatsAppChat(
                            vendor,
                            buildAccountBalanceMessage(
                              vendor,
                              summary.netBalance,
                              summary.tone,
                              ctx.workspace?.companyName,
                              ctx.extendedSettings,
                            ),
                            ctx.showToast,
                          )
                        }
                      >
                        <WhatsAppIcon />
                      </button>
                      <button
                        className="vendor-operation-add"
                        aria-label={`عمليات ${vendor.name}`}
                        onClick={() => openVendorMenu(vendor)}
                      >
                        <PlusIcon />
                      </button>
                      <button
                        className="vendor-count"
                        aria-label={`عرض حركات ${vendor.name}`}
                        onClick={() => flow.push(supplierScreen(vendor.id))}
                      >
                        {summary.entryCount}
                      </button>
                      <span className="vendor-code">{vendor.codeNumber}</span>
                    </span>
                  </article>
                );
              })}
            </section>
          )}
        </main>
      </MobileScroll>
      {createMenuOpen ? (
        <div className="purchase-create-layer">
          <button
            type="button"
            className="context-menu-backdrop"
            aria-label="إغلاق قائمة إنشاء عملية"
            onClick={() => setCreateMenuOpen(false)}
          />
          <div className="purchase-create-menu" data-testid="purchase-create-menu" role="menu" aria-label="قائمة إنشاء عملية">
            {createActions.map((item) => (
              <button key={item.label} role="menuitem" onClick={() => runCreateAction(item.action)}>
                {item.label}
              </button>
            ))}
          </div>
        </div>
      ) : null}
      <button
        className="fab fixed-fab"
        onClick={() => {
          keyboard.hide();
          setCreateMenuOpen((open) => !open);
        }}
        aria-label="إضافة مورد أو عملية"
        aria-expanded={createMenuOpen}
      >
        <PlusIcon />
      </button>
      {operationVendor && portal
        ? createPortal(
            <div className="vendor-menu-layer" data-testid="vendor-operations-menu">
              <button
                className="context-menu-backdrop"
                aria-label="إغلاق عمليات المورد"
                onClick={() => setOperationVendor(null)}
              />
              <aside className="vendor-operations-menu" role="menu" aria-label={`عمليات ${operationVendor.name}`}>
                {contextActions.map((item) => (
                  <button
                    role="menuitem"
                    key={item.label}
                    onClick={() => {
                      setOperationVendor(null);
                      item.action();
                    }}
                  >
                    {item.label}
                  </button>
                ))}
              </aside>
            </div>,
            portal,
          )
        : null}
    </div>
  );
}

function computePeriodDateRange(period: string): { fromDate: string; toDate: string } {
  const today = new Date().toISOString().slice(0, 10);
  if (period === "يومي") return { fromDate: today, toDate: today };
  if (period === "شهري") return { fromDate: `${today.slice(0, 7)}-01`, toDate: today };
  if (period === "سنوي") return { fromDate: `${today.slice(0, 4)}-01-01`, toDate: today };
  return { fromDate: "", toDate: "" };
}

function SupplierPage({
  account,
  menuControl,
  searchControl,
}: {
  account: AccountRecord;
  menuControl: MutableRefObject<(() => void) | null>;
  searchControl: MutableRefObject<(() => void) | null>;
}) {
  const ctx = useWorkspace();
  const keyboard = useKeyboard();
  const { period, fromDate, toDate, docKind, sortOrder } = ctx.statementFilter;
  const showPreviousBalance = ctx.statementFilter.showPreviousBalance ?? true;
  const currency = ctx.statementCurrencies[account.id] ?? account.currency ?? "ريال";
  const [searchOpen, setSearchOpen] = useState(false);
  const [operationsOpen, setOperationsOpen] = useState(false);
  const [query, setQuery] = useState("");
  const periods = ["يومي", "شهري", "سنوي", "الكل"];

  useEffect(() => {
    ctx.setActiveStatementAccountId(account.id);
    return () => ctx.setActiveStatementAccountId(null);
  }, [account.id, ctx.setActiveStatementAccountId]);

  const selectPeriod = (nextPeriod: string) => {
    const bounds = computePeriodDateRange(nextPeriod);
    ctx.setStatementFilter((prev) => ({
      ...prev,
      period: nextPeriod,
      fromDate: bounds.fromDate,
      toDate: bounds.toDate,
    }));
  };

  menuControl.current = () => {
    keyboard.hide();
    setOperationsOpen((open) => !open);
  };
  searchControl.current = () => {
    keyboard.hide();
    setOperationsOpen(false);
    setSearchOpen((v) => !v);
    setQuery("");
  };

  const statement = useMemo(
    () =>
      computeStatementRows(account, ctx.ledger, {
        currency,
        searchQuery: query,
        showPreviousBalance,
        fromDate,
        toDate,
        docKind,
        sortOrder,
      }),
    [account, ctx.ledger, currency, docKind, fromDate, query, showPreviousBalance, sortOrder, toDate],
  );

  return (
    <>
      <MobileScroll className="app-screen">
        <main className="supplier-page page-with-footer" data-testid="supplier-screen">
          <section className="supplier-summary">
            <span className="vendor-avatar summary-avatar" aria-hidden="true">
              {account.name.charAt(0)}
            </span>
            <div className="summary-copy">
              <span>
                {statement.netDirection === "credit"
                  ? "الرصيد له"
                  : statement.netDirection === "debit"
                    ? "الرصيد عليه"
                    : "صافي الرصيد الحالي"}
              </span>
              <strong>
                {formatAmount(statement.netBalance)} {currency === "الكل" ? account.currency : currency}
              </strong>
              <small>سقف المديونية: {formatAmount(account.creditLimit)} {account.currency}</small>
            </div>
            <div className="supplier-summary-actions">
              <button
                type="button"
                className="supplier-whatsapp-btn"
                style={{ background: "var(--nasqo-home-secondary-bg, var(--nasqo-orange, #0891b2))", color: "#fff" }}
                data-testid="supplier-new-invoice-btn"
                aria-label={`فاتورة جديدة لـ ${account.name}`}
                onClick={() => ctx.openVendorInvoice(account)}
              >
                <FilePlusIcon />
                <span>فاتورة</span>
              </button>
              <button
                type="button"
                className="supplier-whatsapp-btn"
                data-testid="supplier-whatsapp-btn"
                aria-label={`إرسال الرصيد عبر واتساب إلى ${account.name}`}
                onClick={() =>
                  void openWhatsAppChat(
                    account,
                    buildAccountBalanceMessage(
                      account,
                      statement.netBalance,
                      statement.netDirection,
                      ctx.workspace?.companyName,
                      ctx.extendedSettings,
                    ),
                    ctx.showToast,
                  )
                }
              >
                <WhatsAppIcon variant="glyph" />
                <span>واتساب</span>
              </button>
            </div>
          </section>
          <section className="statement-controls">
            <div className="statement-select-grid">
              <select
                className="select-box currency-select"
                aria-label="عملة كشف الحساب"
                value={currency}
                onChange={(e) => ctx.setStatementCurrency(account.id, e.target.value)}
              >
                <option value="الكل">جميع العملات</option>
                {ctx.currencyCodes.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
              <select
                className="select-box"
                aria-label="نوع المستند"
                value={docKind}
                onChange={(e) =>
                  ctx.setStatementFilter((prev) => ({
                    ...prev,
                    docKind: e.target.value as "all" | "invoice" | "voucher" | "return" | "quote" | "order",
                  }))
                }
              >
                <option value="all">جميع الحركات والفواتير</option>
                <option value="invoice">الفواتير فقط</option>
                <option value="voucher">السندات فقط</option>
                <option value="return">المردودات فقط</option>
                <option value="quote">عروض الأسعار</option>
                <option value="order">الطلبيات</option>
              </select>
            </div>
            <div className="statement-options">
              <div className="period-tabs compact" role="group" aria-label="فترة كشف الحساب">
                {periods.map((item) => (
                  <button
                    key={item}
                    className={period === item ? "selected" : ""}
                    aria-pressed={period === item}
                    onClick={() => selectPeriod(item)}
                  >
                    {item}
                  </button>
                ))}
              </div>
              <label className="previous-balance">
                <input
                  type="checkbox"
                  checked={showPreviousBalance}
                  onChange={(event) =>
                    ctx.setStatementFilter((prev) => ({ ...prev, showPreviousBalance: event.target.checked }))
                  }
                />{" "}
                رصيد سابق
              </label>
            </div>
            <div className="statement-date-inputs">
              <label>
                <span>من</span>
                <input
                  type="date"
                  dir="ltr"
                  aria-label="من تاريخ"
                  value={fromDate}
                  onChange={(e) => {
                    ctx.setStatementFilter((prev) => ({ ...prev, period: "مخصص", fromDate: e.target.value }));
                  }}
                />
              </label>
              <label>
                <span>إلى</span>
                <input
                  type="date"
                  dir="ltr"
                  aria-label="إلى تاريخ"
                  value={toDate}
                  onChange={(e) => {
                    ctx.setStatementFilter((prev) => ({ ...prev, period: "مخصص", toDate: e.target.value }));
                  }}
                />
              </label>
            </div>
            {searchOpen ? (
              <div className="invoice-search">
                <KeyboardInput
                  aria-label="البحث في حركات الحساب"
                  placeholder="ابحث بالبيان أو الرقم أو المبلغ"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
                <button aria-label="مسح البحث" onClick={() => setQuery("")}>
                  <Cross2Icon />
                </button>
              </div>
            ) : null}
            <div className="statement-date">
              <span>
                الرصيد السابق:{" "}
                <strong>
                  {formatAmount(statement.previousBalance)}
                  {statement.previousDirection === "credit" ? " (له)" : statement.previousDirection === "debit" ? " (عليه)" : ""}
                </strong>
              </span>
              <span>
                الحركات: <strong>{statement.rows.length}</strong>
              </span>
            </div>
          </section>
          <div className="table-heading">
            <span>النوع</span>
            <span>المبلغ</span>
            <span>التفاصيل</span>
            <span>الرصيد</span>
          </div>
          {statement.rows.length === 0 ? (
            <p className="cash-empty">لا توجد حركات مسجلة لهذا الحساب في النطاق المحدد.</p>
          ) : (
            <section className="transactions-list">
              {statement.rows.map((item) => (
                <article key={item.id} className="transaction-card">
                  <div
                    className="transaction-grid"
                    onClick={() => ctx.flowRef.current?.push(cashInvoicePreviewScreen(item.id))}
                    style={{ cursor: "pointer" }}
                  >
                    <span className={`transaction-type ${item.direction}`}>{item.typeLabel}</span>
                    <strong className={`transaction-amount ${item.direction}`}>
                      {formatAmount(item.amount)}
                    </strong>
                    <span className="transaction-detail">
                      <b>{item.details || item.typeLabel}</b>
                      <time>{item.entryDate}</time>
                      <em>
                        #{item.entryNumber}
                        {(item.lineCount ?? 0) > 0 ? (
                          <small className="tx-lines-badge"> · {item.lineCount} بنود</small>
                        ) : null}
                      </em>
                    </span>
                    <span className="transaction-balance">{formatAmount(item.runningBalance)}</span>
                  </div>
                  <div className="transaction-actions">
                    <button
                      aria-label={`تعديل #${item.entryNumber}`}
                      onClick={() => {
                        if (item.kind === "invoice" || item.kind === "return" || item.kind === "quote" || item.kind === "order") {
                          ctx.openInvoiceEdit(item, account);
                        } else {
                          ctx.openTransaction(account, item);
                        }
                      }}
                    >
                      <Pencil1Icon />
                    </button>
                    <button
                      aria-label={`ملف PDF للعملية #${item.entryNumber}`}
                      onClick={() => ctx.flowRef.current?.push(cashInvoicePreviewScreen(item.id))}
                    >
                      <FileTextIcon />
                    </button>
                    <button
                      aria-label={`مشاركة #${item.entryNumber}`}
                      onClick={() =>
                        void shareOrCopyText(
                          `${item.typeLabel} #${item.entryNumber}`,
                          `${account.name} | ${item.typeLabel}: ${formatAmount(item.amount)} ${item.currency} | ${item.details}`,
                          ctx.showToast,
                        )
                      }
                    >
                      <Share1Icon />
                    </button>
                    <button
                      type="button"
                      className="tx-whatsapp"
                      aria-label={`إرسال #${item.entryNumber} عبر واتساب`}
                      onClick={() =>
                        void openWhatsAppChat(
                          account,
                          `${item.typeLabel} #${item.entryNumber} - ${account.name}: ${formatAmount(item.amount)} ${item.currency} (${item.details || item.typeLabel})`,
                          ctx.showToast,
                        )
                      }
                    >
                      <WhatsAppIcon variant="glyph" />
                    </button>
                    <button
                      type="button"
                      aria-label={`نقل #${item.entryNumber} إلى السلة`}
                      title="نقل إلى سلة المحذوفات"
                      style={{ color: "#c91b08" }}
                      onClick={async () => {
                        await setLedgerDeleted(ctx.uid, item.id, true);
                        triggerHaptic("warning");
                        ctx.showToast(`تم نقل العملية #${item.entryNumber} إلى سلة المحذوفات`);
                      }}
                    >
                      <TrashIcon />
                    </button>
                  </div>
                </article>
              ))}
            </section>
          )}
        </main>
      </MobileScroll>
      <button className="fab fixed-fab supplier-fab" onClick={() => ctx.openTransaction(account)} aria-label="إضافة سند">
        <PlusIcon />
      </button>
      {operationsOpen ? <CashOperationsMenu account={account} onClose={() => setOperationsOpen(false)} /> : null}
    </>
  );
}

const cashCurrencyOptions = ["ريال", "عملة 2", "دولار", "جميع العملات بدون مصارفة", "مصارفة الكل بعملة ريال"] as const;
const cashSearchOptions = [
  "الكل",
  "الرقم",
  "البيان",
  "رقم المستند",
  "اسم المرسل",
  "اسم المستلم",
  "اسم الشركة",
  "المبلغ عليه",
  "المبلغ له",
] as const;
type CashSearchMode = (typeof cashSearchOptions)[number];

function CashStatementFooter({
  account,
  statement,
  onMenu,
}: {
  account: AccountRecord;
  statement: ReturnType<typeof computeStatementRows>;
  onMenu: () => void;
}) {
  const ctx = useWorkspace();
  return (
    <div className="cash-statement-footer" data-testid="cash-statement-footer">
      <button
        aria-label="تحويل الرصيد"
        onClick={() => ctx.flowRef.current?.push(simpleEntryScreen(account.id))}
      >
        <TransferArrowsIcon />
      </button>
      <div>
        <span>
          عليه: <bdi>{formatAmount(statement.debitTotal)}</bdi>
        </span>
        <span>
          له: <bdi>{formatAmount(statement.creditTotal)}</bdi>
        </span>
        <span>
          الرصيد عليه: <bdi className="cash-statement-total-balance">{formatAmount(statement.netBalance)}</bdi>
        </span>
      </div>
      <button aria-label="خيارات الرصيد" onClick={onMenu}>
        <HamburgerMenuIcon />
      </button>
    </div>
  );
}

function CashSupplierPage({
  account,
  menuControl,
  searchControl,
}: {
  account: AccountRecord;
  menuControl: MutableRefObject<(() => void) | null>;
  searchControl: MutableRefObject<(() => void) | null>;
}) {
  const ctx = useWorkspace();
  const { period, fromDate, toDate, docKind, sortOrder } = ctx.statementFilter;
  const showPreviousBalance = ctx.statementFilter.showPreviousBalance ?? false;
  const [currency, setCurrency] = useState("ريال");
  const [operationsOpen, setOperationsOpen] = useState(false);
  const [currencyOpen, setCurrencyOpen] = useState(false);
  const [searchMenuOpen, setSearchMenuOpen] = useState(false);
  const [searchMode, setSearchMode] = useState<CashSearchMode>("الكل");
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState("");
  const listRef = useRef<HTMLElement>(null);
  const keyboard = useKeyboard();
  const { screenRef } = useScreenPortal();

  useEffect(() => {
    ctx.setActiveStatementAccountId(account.id);
    return () => ctx.setActiveStatementAccountId(null);
  }, [account.id, ctx.setActiveStatementAccountId]);

  const selectPeriod = (nextPeriod: string) => {
    const bounds = computePeriodDateRange(nextPeriod);
    ctx.setStatementFilter((prev) => ({
      ...prev,
      period: nextPeriod,
      fromDate: bounds.fromDate,
      toDate: bounds.toDate,
    }));
  };

  menuControl.current = () => {
    keyboard.hide();
    setCurrencyOpen(false);
    setSearchMenuOpen(false);
    setOperationsOpen((open) => !open);
  };
  searchControl.current = () => {
    keyboard.hide();
    setCurrencyOpen(false);
    setOperationsOpen(false);
    setSearchMenuOpen((open) => !open);
  };
  useEffect(() => {
    listRef.current?.closest(".mobile-scroll")?.scrollTo({ top: 0 });
  }, [query, currency, searchMode]);

  const statement = useMemo(
    () =>
      computeStatementRows(account, ctx.ledger, {
        currency,
        searchQuery: query,
        searchMode,
        showPreviousBalance,
        fromDate,
        toDate,
        docKind,
        sortOrder,
      }),
    [account, ctx.ledger, currency, docKind, fromDate, query, searchMode, showPreviousBalance, sortOrder, toDate],
  );

  const searchPortal = screenRef.current?.querySelector(".nasqo-app");
  const startDate =
    fromDate ||
    statement.rows[statement.rows.length - 1]?.entryDate ||
    "—";
  const endDate =
    toDate ||
    statement.rows[0]?.entryDate ||
    new Date().toISOString().slice(0, 10);

  return (
    <div
      className={`cash-statement-layout${searchOpen ? " cash-search-active" : ""}`}
      data-testid="cash-statement-screen"
    >
      <section className="cash-statement-filters" data-testid="cash-statement-filters">
        <div className="cash-statement-currency">
          <span>العملة</span>
          <button
            aria-label="عملة كشف المشتريات النقدية"
            data-testid="cash-currency-trigger"
            aria-haspopup="listbox"
            aria-expanded={currencyOpen}
            className={currency.length > 10 ? "long-label" : ""}
            onClick={() => {
              keyboard.hide();
              setSearchMenuOpen(false);
              setOperationsOpen(false);
              setCurrencyOpen((open) => !open);
            }}
          >
            <span>{currency}</span>
            <ChevronDownIcon />
          </button>
        </div>
        <div className="cash-statement-options" role="group" aria-label="فترة كشف المشتريات النقدية">
          {["شهري", "الكل"].map((item) => (
            <button key={item} aria-pressed={period === item} onClick={() => selectPeriod(item)}>
              <span className="period-radio-mark" />
              {item}
            </button>
          ))}
          <label>
            <input
              type="checkbox"
              checked={showPreviousBalance}
              onChange={(event) =>
                ctx.setStatementFilter((prev) => ({ ...prev, showPreviousBalance: event.target.checked }))
              }
            />
            رصيد سابق
          </label>
          <button aria-pressed={period === "سنوي"} onClick={() => selectPeriod("سنوي")}>
            <span className="period-radio-mark" />
            سنوي
          </button>
          <button
            className="cash-statement-filter-button"
            aria-label="تصفية كشف المشتريات النقدية"
            onClick={() => ctx.openSheet("filters")}
          >
            <MixerHorizontalIcon />
          </button>
        </div>
        <div className="cash-statement-date-strip">
          <span>
            من <bdi>{startDate}</bdi>
          </span>
          <span>
            إلى <bdi>{endDate}</bdi>
          </span>
        </div>
      </section>
      {searchOpen ? (
        <div className="cash-search-form">
          <label>
            <span>البحث بواسطة {searchMode}</span>
            <KeyboardInput
              data-testid="cash-search-input"
              aria-label={`البحث بواسطة ${searchMode}`}
              placeholder="اكتب للبحث في الحركات"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              onBlur={() => keyboard.hide()}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  keyboard.hide();
                  event.currentTarget.blur();
                }
              }}
            />
          </label>
          <button
            data-testid="cash-search-clear"
            aria-label="مسح بحث الحركات"
            onClick={() => {
              keyboard.hide();
              setQuery("");
            }}
          >
            <Cross2Icon />
          </button>
          <button
            data-testid="cash-search-close"
            onClick={() => {
              keyboard.hide();
              setSearchOpen(false);
              setQuery("");
              setSearchMode("الكل");
            }}
          >
            إغلاق
          </button>
        </div>
      ) : null}
      <div className="cash-statement-table-heading">
        <span>النوع</span>
        <span>المبلغ</span>
        <span>التفاصيل</span>
        <span>الرصيد</span>
      </div>
      <MobileScroll className="cash-statement-scroll">
        <main ref={listRef} data-testid="supplier-screen" className="cash-statement-list">
          {statement.rows.length === 0 ? (
            <p className="cash-empty" role="status">
              لا توجد حركات تطابق البحث أو العملة المحددة.
            </p>
          ) : null}
          {showPreviousBalance ? (
            <div className="cash-statement-previous" role="status">
              <span>رصيد سابق</span>
              <bdi>{formatAmount(statement.previousBalance)}</bdi>
            </div>
          ) : null}
          {statement.rows.map((item) => (
            <article
              className="cash-statement-row"
              key={item.id}
              data-transaction-id={item.entryNumber}
            >
              <div className="cash-statement-row-main">
                <span className="cash-statement-type">{item.typeLabel}</span>
                <strong className="cash-statement-amount">{formatAmount(item.amount)}</strong>
                <div className="cash-statement-detail">
                  {item.details.split("\n").map((line, i) => (
                    <span key={i}>{line}</span>
                  ))}
                </div>
                <bdi className="cash-statement-balance">{formatAmount(item.runningBalance)}</bdi>
              </div>
              <div className="cash-statement-row-bottom">
                <time dateTime={item.entryDate}>{item.entryDate}</time>
                <span className="cash-statement-id">{item.entryNumber}</span>
                <div className="cash-statement-actions">
                  <button
                    aria-label={`تعديل #${item.entryNumber}`}
                    onClick={() => {
                      if (item.kind === "invoice" || item.kind === "return" || item.kind === "quote" || item.kind === "order") {
                        ctx.openInvoiceEdit(item, account);
                      } else {
                        ctx.openTransaction(account, item);
                      }
                    }}
                  >
                    <Pencil1Icon />
                  </button>
                  <button
                    className="cash-statement-pdf"
                    aria-label={`ملف PDF للعملية #${item.entryNumber}`}
                    onClick={(event) => {
                      event.currentTarget.blur();
                      ctx.flowRef.current?.push(cashInvoicePreviewScreen(item.id));
                    }}
                  >
                    <FileTextIcon />
                  </button>
                  <button
                    aria-label={`مشاركة #${item.entryNumber}`}
                    onClick={() =>
                      void shareOrCopyText(
                        `فاتورة #${item.entryNumber}`,
                        `${account.name} | ${item.typeLabel}: ${formatAmount(item.amount)} | ${item.details}`,
                        ctx.showToast,
                      )
                    }
                  >
                    <Share1Icon />
                  </button>
                  <button
                    type="button"
                    className="tx-whatsapp"
                    aria-label={`إرسال #${item.entryNumber} عبر واتساب`}
                    onClick={() =>
                      void openWhatsAppChat(
                        account,
                        `فاتورة #${item.entryNumber} - ${account.name}: ${formatAmount(item.amount)} ${item.currency} (${item.details})`,
                        ctx.showToast,
                      )
                    }
                  >
                    <WhatsAppIcon variant="glyph" />
                  </button>
                  <button
                    type="button"
                    aria-label={`نقل #${item.entryNumber} إلى السلة`}
                    title="نقل إلى سلة المحذوفات"
                    style={{ color: "#c91b08" }}
                    onClick={async () => {
                      await setLedgerDeleted(ctx.uid, item.id, true);
                      triggerHaptic("warning");
                      ctx.showToast(`تم نقل العملية #${item.entryNumber} إلى سلة المحذوفات`);
                    }}
                  >
                    <TrashIcon />
                  </button>
                </div>
              </div>
            </article>
          ))}
        </main>
      </MobileScroll>
      <button className="fab cash-statement-fab" aria-label="إضافة سند" onClick={() => ctx.openTransaction(account)}>
        <PlusIcon />
      </button>
      {currencyOpen ? (
        <div className="cash-currency-layer">
          <button
            className="context-menu-backdrop"
            aria-label="إغلاق قائمة العملات"
            onClick={() => setCurrencyOpen(false)}
          />
          <div className="cash-currency-menu" data-testid="cash-currency-menu" role="listbox" aria-label="عملات الكشف">
            {cashCurrencyOptions.map((option) => (
              <button
                role="option"
                aria-selected={currency === option}
                key={option}
                onClick={() => {
                  setCurrency(option);
                  setCurrencyOpen(false);
                }}
              >
                {option}
              </button>
            ))}
          </div>
        </div>
      ) : null}
      {searchMenuOpen && searchPortal
        ? createPortal(
            <div className="cash-search-menu-layer">
              <button
                className="context-menu-backdrop"
                aria-label="إغلاق خيارات البحث"
                onClick={() => setSearchMenuOpen(false)}
              />
              <aside className="cash-search-menu" data-testid="cash-search-menu" role="menu" aria-label="خيارات البحث في الحركات">
                {cashSearchOptions.map((mode) => (
                  <button
                    role="menuitem"
                    key={mode}
                    onClick={() => {
                      setSearchMode(mode);
                      setQuery("");
                      setSearchOpen(true);
                      setSearchMenuOpen(false);
                    }}
                  >
                    البحث بواسطة {mode}
                  </button>
                ))}
              </aside>
            </div>,
            searchPortal,
          )
        : null}
      {operationsOpen ? <CashOperationsMenu account={account} onClose={() => setOperationsOpen(false)} /> : null}
    </div>
  );
}

function CashOperationsMenu({ account, onClose }: { account: AccountRecord; onClose: () => void }) {
  const ctx = useWorkspace();
  const { screenRef } = useScreenPortal();
  const target = screenRef.current?.querySelector(".nasqo-app");
  if (!target) return null;
  const actions = [
    { label: "فاتورة جديدة", action: () => ctx.openVendorInvoice(account) },
    { label: "مردود جديد", action: () => ctx.openVendorInvoice(account, "return") },
    { label: "سند جديد", action: () => ctx.openTransaction(account) },
    { label: "حوالة جديدة", action: () => ctx.openTransferModal(account.id) },
    { label: "صرف عملات", action: () => ctx.flowRef.current?.push(currencyScreen(account.id)) },
    { label: "عرض سعر", action: () => ctx.openVendorInvoice(account, "quote") },
    { label: "طلبية جديدة", action: () => ctx.openVendorInvoice(account, "order") },
  ];
  return createPortal(
    <div className="vendor-menu-layer">
      <button className="context-menu-backdrop" aria-label="إغلاق عمليات المشتريات النقدية" onClick={onClose} />
      <aside className="vendor-operations-menu cash-operations-menu" data-testid="cash-operations-menu" role="menu" aria-label="عمليات الحساب">
        {actions.map((item) => (
          <button
            role="menuitem"
            key={item.label}
            onClick={() => {
              onClose();
              item.action();
            }}
          >
            {item.label}
          </button>
        ))}
      </aside>
    </div>,
    target,
  );
}

function SimpleEntryPage({
  flow,
  initialToAccountId,
}: {
  flow: FlowControls;
  initialToAccountId?: string;
}) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const keyboard = useKeyboard();
  const [fromAccountId, setFromAccountId] = useState(ctx.accounts[0]?.id ?? "");
  const [toAccountId, setToAccountId] = useState(
    initialToAccountId ?? ctx.accounts[1]?.id ?? ctx.accounts[0]?.id ?? "",
  );
  const [fromSearch, setFromSearch] = useState("");
  const [toSearch, setToSearch] = useState("");
  const [amount, setAmount] = useState("");
  const [currency, setCurrency] = useState<CurrencyCode>("ريال");
  const [note, setNote] = useState("");
  const [documentNumber, setDocumentNumber] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const fromAcc = ctx.accounts.find((a) => a.id === fromAccountId);
  const toAcc = ctx.accounts.find((a) => a.id === toAccountId);
  const fromSummary = fromAcc ? computeAccountSummary(fromAcc, ctx.ledger) : null;
  const toSummary = toAcc ? computeAccountSummary(toAcc, ctx.ledger) : null;

  const fromOptions = useMemo(
    () => rankAccountSearchMatches(ctx.accounts, fromSearch),
    [ctx.accounts, fromSearch],
  );
  const toOptions = useMemo(
    () => rankAccountSearchMatches(ctx.accounts, toSearch),
    [ctx.accounts, toSearch],
  );

  const swapAccounts = () => {
    keyboard.hide();
    setError("");
    setFromAccountId(toAccountId);
    setToAccountId(fromAccountId);
    setFromSearch(toSearch);
    setToSearch(fromSearch);
  };

  const saveEntry = async () => {
    keyboard.hide();
    const numericAmount = parseArabicNumber(amount);
    if (!fromAcc || !toAcc) {
      triggerHaptic("warning");
      setError("اختر حساب المصدر وحساب الوجهة أولًا.");
      return;
    }
    if (fromAcc.id === toAcc.id) {
      triggerHaptic("warning");
      setError("اختر حسابين مختلفين للقيد.");
      return;
    }
    if (numericAmount <= 0) {
      triggerHaptic("warning");
      setError("أدخل مبلغًا أكبر من صفر.");
      return;
    }
    setSaving(true);
    setError("");
    try {
      const nextNum = Math.max(1000, ...ctx.ledger.map((e) => e.entryNumber)) + 1;
      await createLedgerEntry(ctx.uid, {
        accountId: toAcc.id,
        accountName: toAcc.name,
        counterpartAccountId: fromAcc.id,
        counterpartAccountName: fromAcc.name,
        kind: "simple-entry",
        typeLabel: "قيد بسيط",
        payment: "balance",
        direction: "credit",
        amount: numericAmount,
        currency,
        exchangeRate: 1,
        details: note || `تحويل من ${fromAcc.name} إلى ${toAcc.name}`,
        documentNumber,
        entryNumber: nextNum,
        deleted: false,
        entryDate: new Date().toISOString().slice(0, 10),
      });
      triggerHaptic("success");
      ctx.showToast(`تم حفظ القيد البسيط رقم #${nextNum} بنجاح`);
      flow.pop();
    } finally {
      setSaving(false);
    }
  };

  return (
    <MobileScroll className="app-screen simple-entry-scroll">
      <main className="simple-entry-page" data-testid="simple-entry-screen">
        <time className="simple-entry-time" dateTime={now.toISOString()}>
          <span>{now.toLocaleDateString("ar-SA", { weekday: "long" })}</span>{" "}
          <bdi>
            {now.toLocaleDateString("en-GB")} {now.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", hour12: true })}
          </bdi>
        </time>
        <section className="simple-entry-account-group">
          <div className="simple-entry-search from-search">
            <KeyboardInput
              data-testid="simple-entry-from-search"
              aria-label="البحث عن حساب المصدر"
              placeholder="من حساب (ابحث عن الاسم هنا)"
              value={fromSearch}
              onChange={(event) => {
                setFromSearch(event.target.value);
                setError("");
              }}
              onKeyDown={(event) => {
                if (event.key === "Enter" && fromOptions.length > 0) {
                  event.preventDefault();
                  setFromAccountId(fromOptions[0].id);
                  setFromSearch("");
                  setError("");
                  keyboard.hide();
                }
              }}
            />
            <button
              type="button"
              className="simple-entry-clear"
              data-testid="simple-entry-from-clear"
              aria-label="مسح حساب المصدر"
              onClick={() => {
                setFromSearch("");
                setFromAccountId("");
              }}
            >
              <Cross2Icon />
            </button>
          </div>

          <label className="simple-entry-account-label" htmlFor="simple-entry-from-account">
            أو حدد الحساب من هنا
          </label>
          <select
            id="simple-entry-from-account"
            data-testid="simple-entry-from-account"
            className="simple-entry-account-select"
            aria-label="حساب المصدر"
            value={fromAccountId}
            onChange={(event) => {
              setFromAccountId(event.target.value);
              setFromSearch("");
              setError("");
            }}
          >
            <option value="">{fromOptions.length ? "اختر الحساب" : "لا توجد حسابات مطابقة"}</option>
            {fromOptions.map((v) => (
              <option key={v.id} value={v.id}>
                {v.name}
              </option>
            ))}
          </select>
          <div className="simple-entry-balance">
            الرصيد: <bdi>{formatAmount(fromSummary?.netBalance ?? 0)}</bdi>
          </div>
        </section>
        <section className="simple-entry-account-group">
          <div className="simple-entry-search to-search">
            <button
              type="button"
              className="simple-entry-swap"
              data-testid="simple-entry-swap"
              aria-label="تبديل حساب المصدر والوجهة"
              onClick={swapAccounts}
            >
              <TransferArrowsIcon />
            </button>
            <label>
              <span>إلى حساب (ابحث عن الاسم هنا)</span>
              <KeyboardInput
                data-testid="simple-entry-to-search"
                aria-label="البحث عن حساب الوجهة"
                placeholder={toAcc?.name || "ابحث عن الاسم هنا"}
                value={toSearch}
                onChange={(event) => {
                  setToSearch(event.target.value);
                  setError("");
                }}
                onKeyDown={(event) => {
                  if (event.key === "Enter" && toOptions.length > 0) {
                    event.preventDefault();
                    setToAccountId(toOptions[0].id);
                    setToSearch("");
                    setError("");
                    keyboard.hide();
                  }
                }}
              />
            </label>
            <button
              type="button"
              className="simple-entry-clear"
              data-testid="simple-entry-to-clear"
              aria-label="مسح حساب الوجهة"
              onClick={() => {
                setToSearch("");
                setToAccountId("");
              }}
            >
              <Cross2Icon />
            </button>
          </div>

          <label className="simple-entry-account-label" htmlFor="simple-entry-to-account">
            أو حدد الحساب من هنا
          </label>
          <select
            id="simple-entry-to-account"
            data-testid="simple-entry-to-account"
            className="simple-entry-account-select"
            aria-label="حساب الوجهة"
            value={toAccountId}
            onChange={(event) => {
              setToAccountId(event.target.value);
              setToSearch("");
              setError("");
            }}
          >
            <option value="">{toOptions.length ? "اختر الحساب" : "لا توجد حسابات مطابقة"}</option>
            {toOptions.map((v) => (
              <option key={v.id} value={v.id}>
                {v.name}
              </option>
            ))}
          </select>
          <div className="simple-entry-balance">
            الرصيد: <bdi>{formatAmount(toSummary?.netBalance ?? 0)}</bdi>
          </div>
        </section>
        <div className="simple-entry-amount-row outlined">
          <OutlinedAmountField
            label="المبلغ"
            ariaLabel="مبلغ القيد"
            testId="simple-entry-amount"
            currency={currency}
            value={amount}
            onChange={(next) => {
              setAmount(next);
              setError("");
            }}
            currencySlot={
              <select
                className="simple-entry-currency-inline"
                aria-label="عملة القيد"
                value={currency}
                onChange={(event) => setCurrency(event.target.value as CurrencyCode)}
              >
                {ctx.currencyCodes.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            }
          />
        </div>
        <div className="simple-entry-note-row">
          <KeyboardInput
            data-testid="simple-entry-note"
            aria-label="بيان القيد"
            placeholder="اكتب البيان"
            value={note}
            onChange={(event) => setNote(event.target.value)}
          />
        </div>
        <KeyboardInput
          className="simple-entry-document"
          data-testid="simple-entry-document"
          aria-label="رقم مستند القيد"
          placeholder="رقم المستند"
          value={documentNumber}
          onChange={(event) => setDocumentNumber(event.target.value)}
        />
        {error ? (
          <p className="simple-entry-feedback error" role="alert">
            {error}
          </p>
        ) : null}
        <div className="simple-entry-actions">
          <button className="save" data-testid="simple-entry-save" disabled={saving} onClick={saveEntry}>
            {saving ? "جاري الحفظ..." : "حفظ"}
          </button>
          <button className="cancel" data-testid="simple-entry-cancel" onClick={flow.pop}>
            إلغاء
          </button>
        </div>
      </main>
    </MobileScroll>
  );
}

function CurrencyPage({ flow, initialAccountId }: { flow: FlowControls; initialAccountId?: string }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const keyboard = useKeyboard();
  const [search, setSearch] = useState("");
  const [selectedAccountId, setSelectedAccountId] = useState(initialAccountId ?? ctx.accounts[0]?.id ?? "");
  const [fromCurrency, setFromCurrency] = useState<CurrencyCode>(ctx.currencyCodes[1] ?? ctx.currencyCodes[0] ?? "ريال");
  const [toCurrency, setToCurrency] = useState<CurrencyCode>(ctx.currencyCodes[0] ?? "ريال");
  const [rate, setRate] = useState("530");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [mode, setMode] = useState<"buy" | "sell">("buy");
  const [settlement, setSettlement] = useState<"account" | "cash">("account");
  const [saving, setSaving] = useState(false);

  const selectedAccount = ctx.accounts.find((a) => a.id === selectedAccountId) ?? ctx.accounts[0];
  const parsedAmount = parseArabicNumber(amount);
  const isSameCurrency = fromCurrency === toCurrency;
  const parsedRate = isSameCurrency ? 1 : Math.max(0.0001, parseArabicNumber(rate) || 1);
  const converted = parsedAmount * parsedRate;

  const saveExchange = async () => {
    if (!selectedAccount || parsedAmount <= 0) {
      triggerHaptic("warning");
      ctx.showToast("أدخل المبلغ واختر الحساب أولًا");
      return;
    }
    if (isSameCurrency) {
      triggerHaptic("warning");
      ctx.showToast("اختر عملتين مختلفتين لإتمام عملية صرف العملات (أو أضف عملة من نافذة العملات)");
      return;
    }
    setSaving(true);
    try {
      const nextNum = Math.max(1000, ...ctx.ledger.map((e) => e.entryNumber)) + 1;
      await createLedgerEntry(ctx.uid, {
        accountId: selectedAccount.id,
        accountName: selectedAccount.name,
        kind: "currency",
        typeLabel: mode === "buy" ? "صرف شراء" : "صرف بيع",
        payment: settlement === "cash" ? "cash" : "balance",
        direction: mode === "buy" ? "credit" : "debit",
        amount: converted,
        currency: toCurrency,
        exchangeRate: parsedRate,
        details: note || `صرف ${formatAmount(parsedAmount)} ${fromCurrency} بسعر ${parsedRate} -> ${toCurrency}`,
        entryNumber: nextNum,
        deleted: false,
        entryDate: new Date().toISOString().slice(0, 10),
      });
      triggerHaptic("success");
      ctx.showToast(`تم حفظ عملية الصرف رقم #${nextNum}`);
      flow.pop();
    } finally {
      setSaving(false);
    }
  };

  return (
    <MobileScroll className="app-screen currency-page-scroll">
      <main className="currency-page" data-testid="currency-screen">
        <time className="currency-time">
          اليوم · {new Intl.DateTimeFormat("ar-SA", { hour: "2-digit", minute: "2-digit" }).format(new Date())}
        </time>
        <section className="currency-workspace">
          <div className="currency-search-field">
            <button type="button" aria-label="مسح البحث" onClick={() => setSearch("")}>
              <Cross2Icon />
            </button>
            <label htmlFor="currency-search">
              <span>ابحث عن الاسم هنا</span>
              <KeyboardInput
                id="currency-search"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                onKeyDown={(event) => {
                  const matches = rankAccountSearchMatches(ctx.accounts, search);
                  if (event.key === "Enter" && matches.length > 0) {
                    event.preventDefault();
                    setSelectedAccountId(matches[0].id);
                    setSearch("");
                    keyboard.hide();
                  }
                }}
                placeholder="ابحث عن الاسم هنا"
              />
            </label>
          </div>

          <p className="currency-helper">أو حدد الحساب من هنا</p>
          <div className="currency-account-row">
            <button
              type="button"
              className="currency-account-add"
              data-testid="currency-account-add"
              aria-label="إضافة حساب للصرف"
              onClick={() => ctx.openAccountCreate("extended")}
            >
              <PlusIcon />
            </button>
            <select
              className="currency-account-select"
              aria-label="الحساب"
              value={selectedAccount?.id ?? ""}
              onChange={(e) => {
                setSelectedAccountId(e.target.value);
                if (search.trim()) setSearch("");
              }}
            >
              {(() => {
                const list = search.trim() ? rankAccountSearchMatches(ctx.accounts, search) : ctx.accounts;
                if (list.length === 0) {
                  return <option value="">لا توجد حسابات مطابقة</option>;
                }
                return list.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ));
              })()}
            </select>
          </div>
          <div className="exchange-rate-card">
            <span>
              <small>من</small>
              <select
                className="currency-rate-select"
                aria-label="من عملة"
                value={fromCurrency}
                onChange={(e) => setFromCurrency(e.target.value as CurrencyCode)}
              >
                {ctx.currencyCodes.map((c) => (
                  <option key={c}>{c}</option>
                ))}
              </select>
            </span>
            <ArrowLeftIcon />
            <span className="rate-value">
              <small>سعر الصرف</small>
              <KeyboardInput
                className="currency-rate-input"
                aria-label="سعر الصرف"
                inputMode="decimal"
                value={rate}
                onChange={(e) => setRate(e.target.value)}
              />
            </span>
          </div>
          <div className="currency-entry-outlined">
            <OutlinedAmountField
              id="currency-amount"
              label={`المبلغ (${fromCurrency})`}
              testId="currency-amount"
              currency={fromCurrency}
              value={amount}
              onChange={(next) => setAmount(next)}
            />
          </div>
          <div className="exchange-rate-card">
            <span>
              <small>إلى</small>
              <select
                className="currency-rate-select"
                aria-label="إلى عملة"
                value={toCurrency}
                onChange={(e) => setToCurrency(e.target.value as CurrencyCode)}
              >
                {ctx.currencyCodes.map((c) => (
                  <option key={c}>{c}</option>
                ))}
              </select>
            </span>
            <ArrowLeftIcon />
            <span className="rate-value">
              <small>سعر الصرف</small>
              <strong>{parsedRate}</strong>
            </span>
          </div>
          <div className="currency-result">
            <small>المبلغ المقابل</small>
            <strong>{formatAmount(converted)}</strong>
            <em>{toCurrency}</em>
          </div>
          <div className="currency-entry note-entry">
            <CameraIcon />
            <label htmlFor="currency-note">
              <KeyboardInput
                id="currency-note"
                value={note}
                onChange={(event) => setNote(event.target.value)}
                placeholder="اكتب البيان"
              />
            </label>
            <button aria-label="مسح البيان" onClick={() => setNote("")}>
              <Cross2Icon />
            </button>
          </div>
          <div className="inline-radio-group" aria-label="نوع صرف العملات">
            <label className={mode === "buy" ? "selected green" : "green"}>
              <input type="radio" name="currency-mode" checked={mode === "buy"} onChange={() => setMode("buy")} /> شراء
            </label>
            <label className={mode === "sell" ? "selected red" : "red"}>
              <input type="radio" name="currency-mode" checked={mode === "sell"} onChange={() => setMode("sell")} /> بيع
            </label>
          </div>
          <div className="inline-radio-group settlement-group" aria-label="طريقة المصادقة">
            <label className={settlement === "account" ? "selected" : ""}>
              <input
                type="radio"
                name="settlement"
                checked={settlement === "account"}
                onChange={() => setSettlement("account")}
              />{" "}
              مصادقة في حساب عميل
            </label>
            <label className={settlement === "cash" ? "selected" : ""}>
              <input
                type="radio"
                name="settlement"
                checked={settlement === "cash"}
                onChange={() => setSettlement("cash")}
              />{" "}
              مصادقة نقدية في الصندوق
            </label>
          </div>
          <div className="form-modal-actions currency-actions">
            <button className="cancel" onClick={flow.pop}>
              إلغاء
            </button>
            <button className="save" data-testid="currency-save" disabled={saving} onClick={saveExchange}>
              {saving ? "جاري الحفظ..." : "حفظ"}
            </button>
          </div>
        </section>
      </main>
    </MobileScroll>
  );
}

function WhatsAppSettingsPage({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const [provider, setProvider] = useState<"nasqo" | "external">(ctx.workspace?.whatsappProvider ?? "nasqo");
  const [instantEnabled, setInstantEnabled] = useState(ctx.workspace?.whatsappInstantEnabled ?? false);
  const [phone, setPhone] = useState(ctx.workspace?.whatsappPhone ?? "");
  const [saving, setSaving] = useState(false);

  const saveSettings = async () => {
    if (!ctx.workspace) return;
    setSaving(true);
    try {
      await saveWorkspaceSettings(ctx.uid, {
        ...ctx.workspace,
        whatsappProvider: provider,
        whatsappInstantEnabled: instantEnabled,
        whatsappPhone: phone,
      });
      ctx.showToast("تم حفظ إعدادات إشعارات الواتساب بنجاح");
    } finally {
      setSaving(false);
    }
  };

  return (
    <MobileScroll className="whatsapp-settings-scroll">
      <main className="whatsapp-settings-page" data-testid="whatsapp-settings-screen">
        <button className="whatsapp-back" aria-label="رجوع" onClick={flow.pop}>
          <ArrowLeftIcon />
        </button>
        <section className="whatsapp-brand">
          <span>
            <MobileIcon />
          </span>
          <strong>{ctx.workspace?.companyName || "نسقو برو"}</strong>
          <small>إدارة إشعارات واتساب</small>
        </section>
        <section className="whatsapp-settings-card">
          <h2>
            <ChatBubbleIcon /> إعدادات إشعارات الواتساب
          </h2>
          <div className="provider-choice" role="group" aria-label="مزود خدمة واتساب">
            <button aria-pressed={provider === "external"} onClick={() => setProvider("external")}>
              <span className="radio-dot" /> خدمة خارجية
            </button>
            <button aria-pressed={provider === "nasqo"} onClick={() => setProvider("nasqo")}>
              <span className="radio-dot" /> نسقو برو
            </button>
          </div>
          <label className="settings-toggle">
            <span>تفعيل نظام الرسائل الفورية عبر الواتساب</span>
            <input
              type="checkbox"
              checked={instantEnabled}
              onChange={(event) => setInstantEnabled(event.target.checked)}
            />
          </label>
          <label className="settings-input" htmlFor="whatsapp-phone">
            <PersonIcon />
            <KeyboardInput
              id="whatsapp-phone"
              data-testid="whatsapp-phone"
              inputMode="tel"
              value={phone}
              onChange={(event) => setPhone(event.target.value)}
              placeholder="أدخل رقم الهاتف التجاري"
            />
            {!phone ? <ExclamationTriangleIcon className="warning-icon" /> : null}
          </label>
          <button
            className="whatsapp-save"
            data-testid="whatsapp-save"
            disabled={saving}
            onClick={saveSettings}
          >
            {saving ? "جاري الحفظ..." : "حفظ إعدادات الواتساب"}
          </button>
          <div className="account-info">
            <h3>
              <InfoCircledIcon /> معلومات الحساب
            </h3>
            <p>
              <span>الحساب السحابي:</span>
              <strong>{ctx.userEmail || "مرتبط"}</strong>
            </p>
            <p>
              <span>رقم الواتساب المسجل:</span>
              <strong>{phone || "غير محدد"}</strong>
            </p>
            <p>
              <span>إرسال الإشعارات:</span>
              <strong>{instantEnabled ? "مفعل" : "متوقف"}</strong>
            </p>
          </div>
        </section>
      </main>
    </MobileScroll>
  );
}

function FinancialFooter({
  debit,
  credit,
  balance,
  compact = false,
  hidePrimaryAction = false,
  onPrimary,
  onMenu,
}: {
  debit: string;
  credit: string;
  balance: string;
  compact?: boolean;
  hidePrimaryAction?: boolean;
  onPrimary: () => void;
  onMenu: () => void;
}) {
  const cls = [
    "financial-footer",
    compact ? "compact" : "",
    hidePrimaryAction ? "totals-only" : "",
    "with-balance",
  ]
    .filter(Boolean)
    .join(" ");
  return (
    <div className={cls}>
      {!hidePrimaryAction ? (
        <button
          className="footer-primary-action"
          aria-label={compact ? "تحويل الرصيد" : "إضافة عملية"}
          onClick={onPrimary}
        >
          {compact ? <SwitchIcon /> : <PlusIcon />}
        </button>
      ) : null}
      <div>
        <span>عليه</span>
        <strong>{debit}</strong>
      </div>
      <div>
        <span>له</span>
        <strong>{credit}</strong>
      </div>
      <div>
        <span>الرصيد</span>
        <strong>{balance}</strong>
      </div>
      <button className="footer-menu" aria-label="خيارات الرصيد" onClick={onMenu}>
        <HamburgerMenuIcon />
      </button>
    </div>
  );
}

function AppDrawer({
  open,
  onClose,
  onNavigate,
}: {
  open: boolean;
  onClose: () => void;
  onNavigate: (target: DrawerTarget) => void;
}) {
  const ctx = useWorkspace();
  const sections: {
    title?: string;
    items: { label: string; ariaLabel?: string; icon: IconComponent; target?: DrawerTarget; action?: () => void }[];
  }[] = [
    {
      items: [
        { label: "الرئيسية", icon: HomeIcon, target: "dashboard" },
        { label: "لوحة المبيعات والمخزون", icon: CardStackIcon, target: "analytics-dashboard" },
        { label: "الحركة اليومية", icon: ActivityLogIcon, target: "daily-journal" },
        { label: "الرسائل الفورية واتساب", icon: MobileIcon, target: "whatsapp" },
        { label: "حركة المخزون", icon: ReaderIcon, target: "inventory-report" },
        { label: "عروض الأسعار", icon: FileTextIcon, target: "quotes" },
        { label: "الطلبيات", icon: FilePlusIcon, target: "orders" },
        { label: "سلة المحذوفات", icon: TrashIcon, target: "trash" },
        { label: "الإعدادات", icon: GearIcon, target: "settings" },
      ],
    },
    {
      title: "المخازن",
      items: [
        { label: "المخازن", icon: CubeIcon, target: "warehouses" },
        { label: "الأصناف", icon: BackpackIcon, target: "items" },
        { label: "إضافة صنف", icon: PlusIcon, action: () => { onClose(); ctx.openInventoryAdd(); } },
      ],
    },
    {
      title: "الحسابات",
      items: [
        { label: "دليل الحسابات", icon: LayersIcon, target: "accounts" },
        { label: "جميع الحسابات", icon: PeopleIcon, action: () => { onClose(); ctx.openChartOfAccounts(); } },
        { label: "إدارة العملات", icon: CardStackIcon, action: () => { onClose(); ctx.openCurrenciesManager(); } },
        { label: "صرف عملات", icon: SwitchIcon, target: "currency" },
        { label: "استيراد الحسابات من ملف", icon: TableIcon, action: () => { onClose(); ctx.triggerCsvImport(); } },
      ],
    },
    {
      title: "الإدارة المتقدمة",
      items: [
        { label: "مركز الإدارة المتقدمة", icon: RocketIcon, target: "erp-hub" },
        { label: "القوائم المالية والأستاذ العام", icon: BarChartIcon, target: "erp-finance" },
        { label: "الموارد البشرية والرواتب", icon: PersonIcon, target: "erp-hr" },
        { label: "نقطة البيع ومتابعة العملاء", icon: CardStackIcon, target: "erp-crm" },
        { label: "أوامر الشراء وسلسلة التوريد", icon: BackpackIcon, target: "erp-procurement" },
        { label: "التصنيع ومراكز التكلفة", icon: LayersIcon, target: "erp-manufacturing" },
      ],
    },
    {
      title: "الجلسة",
      items: [
        { label: "تسجيل الخروج", icon: LockClosedIcon, action: ctx.handleSignOut },
      ],
    },
  ];

  return (
    <div className={open ? "drawer-layer open" : "drawer-layer"} aria-hidden={!open}>
      <button className="drawer-backdrop" onClick={onClose} aria-label="إغلاق القائمة" />
      <button className="drawer-toolbar-close" onClick={onClose} aria-label="إغلاق">
        <ArrowRightIcon />
      </button>
      <aside className="app-drawer" aria-label="قائمة نسقو">
        {open ? (
          <MobileScroll className="drawer-scroll">
            <div className="drawer-brand-hero">
              <span className="drawer-hero-mark">
                {ctx.extendedSettings.logoDataUrl ? (
                  <img
                    src={ctx.extendedSettings.logoDataUrl}
                    alt="شعار المنشأة"
                    className="drawer-custom-logo-img"
                    draggable={false}
                  />
                ) : (
                  <img
                    src={APP_ICON_URL}
                    alt="شعار نسقو برو"
                    className="app-brand-icon-img"
                    draggable={false}
                  />
                )}
              </span>
              <strong>
                {!ctx.workspace?.companyName || ctx.workspace.companyName === "نسقو برو ERP"
                  ? "نسقو برو"
                  : ctx.workspace.companyName}
              </strong>
              <small>
                {!ctx.userEmail || ctx.userEmail === "erp@nasqo.local" || ctx.userEmail === "account@nasqo.local"
                  ? "إدارة الحسابات والمبيعات"
                  : ctx.userEmail}
              </small>
            </div>
            <div className="drawer-sections">
              {sections.map((section, index) => (
                <section key={section.title ?? index}>
                  {section.title ? <h3>{section.title}</h3> : null}
                  {section.items.map((item) => (
                    <button
                      key={item.label}
                      aria-label={item.ariaLabel}
                      onClick={() => {
                        if (item.action) {
                          item.action();
                        } else if (item.target) {
                          onNavigate(item.target);
                        }
                      }}
                    >
                      <item.icon />
                      <span>{item.label}</span>
                    </button>
                  ))}
                </section>
              ))}
            </div>
          </MobileScroll>
        ) : null}
      </aside>
    </div>
  );
}

function HeaderOptionsMenu({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ctx = useWorkspace();
  const menuRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!open) return;
    const focusTimer = window.requestAnimationFrame(() => {
      menuRef.current?.focus();
    });
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.preventDefault();
      event.stopPropagation();
      onClose();
      window.requestAnimationFrame(() => {
        const trigger = document.querySelector<HTMLButtonElement>('[data-testid="header-options-btn"]');
        trigger?.focus();
      });
    };
    window.addEventListener("keydown", handleKeyDown, true);
    return () => {
      window.cancelAnimationFrame(focusTimer);
      window.removeEventListener("keydown", handleKeyDown, true);
    };
  }, [open, onClose]);

  if (!open) return null;
  return (
    <div className="options-menu-layer" data-testid="options-menu">
      <button className="context-menu-backdrop" aria-label="إغلاق الخيارات" onClick={onClose} />
      <aside
        ref={menuRef}
        tabIndex={-1}
        className="header-options-menu"
        role="menu"
        aria-label="خيارات النسخ الاحتياطي"
      >
        <button
          role="menuitem"
          type="button"
          className="opt-tile amber"
          data-testid="options-backup-btn"
          onClick={() => {
            onClose();
            void downloadUnifiedSqliteFile(ctx.uid)
              .then(() => ctx.showToast("تم حفظ وتحميل النسخة الاحتياطية بنجاح"))
              .catch((err) => {
                triggerHaptic("warning");
                ctx.showToast(
                  err instanceof Error && err.message
                    ? err.message
                    : "تعذر تحميل ملف النسخة الاحتياطية.",
                  6000,
                );
              });
          }}
        >
          <DownloadIcon aria-hidden="true" />
          <span>نسخ إحتياطي</span>
        </button>
        <button
          role="menuitem"
          type="button"
          className="opt-tile blue"
          data-testid="options-restore-backup-btn"
          onClick={() => {
            onClose();
            ctx.triggerJsonRestore();
          }}
        >
          <ReloadIcon aria-hidden="true" />
          <span>إستعادة نسخة</span>
        </button>
        <div className="opt-menu-divider" role="separator" />
        <button
          role="menuitem"
          type="button"
          className="opt-tile"
          data-testid="options-seed-demo-btn"
          onClick={() => {
            onClose();
            void ctx.seedDemoWorkspaceNow();
          }}
        >
          <TagPriceIcon aria-hidden="true" />
          <span>تحميل بيانات تجريبية</span>
        </button>
        <button
          role="menuitem"
          type="button"
          className="opt-tile danger"
          data-testid="options-reset-db-btn"
          onClick={() => {
            onClose();
            void ctx.resetWorkspaceToEmptyNow();
          }}
        >
          <ExclamationTriangleIcon aria-hidden="true" />
          <span>تفريغ القاعدة</span>
        </button>
      </aside>
    </div>
  );
}

function DashboardAddMenu({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ctx = useWorkspace();
  if (!open) return null;
  const actions = [
    { label: "إضافة حساب جديد", action: () => ctx.openAccountCreate("extended") },
    { label: "تعديل بيانات حساب", action: () => ctx.openAccountEdit() },
    { label: "سند جديد", action: () => ctx.openTransaction() },
    { label: "حوالة جديدة", action: () => ctx.openTransferModal() },
    { label: "فاتورة جديدة", action: () => ctx.openInvoice() },
    { label: "إضافة مردود جديد", action: () => ctx.openVendorInvoice(ctx.accounts[0], "return") },
    { label: "إضافة عرض سعر", action: () => ctx.openVendorInvoice(ctx.accounts[0], "quote") },
    { label: "إضافة طلبية", action: () => ctx.openVendorInvoice(ctx.accounts[0], "order") },
    { label: "قيد بسيط", action: () => ctx.flowRef.current?.push(simpleEntryScreen()) },
    { label: "إضافة صنف للمخزن", action: ctx.openInventoryAdd },
  ];
  return (
    <div className="dashboard-add-layer" data-testid="dashboard-add-menu">
      <button className="context-menu-backdrop" aria-label="إغلاق قائمة الإضافة" onClick={onClose} />
      <aside className="dashboard-add-menu" role="menu" aria-label="إضافة وإدارة الحسابات">
        {actions.map((item) => (
          <button
            role="menuitem"
            key={item.label}
            onClick={() => {
              onClose();
              item.action();
            }}
          >
            {item.label}
          </button>
        ))}
      </aside>
    </div>
  );
}

function ExportSideMenu({
  open,
  kind = "statement",
  onClose,
  onSelectAction,
}: {
  open: boolean;
  kind?: ExportKind;
  onClose: () => void;
  onSelectAction: (action: "pdf-print" | "pdf-share" | "excel" | "excel-share" | "balance" | "import") => void;
}) {
  const items: {
    key: "pdf-print" | "pdf-share" | "excel" | "excel-share" | "balance" | "import";
    label: string;
    icon: IconComponent;
    tone: string;
  }[] = [
    { key: "pdf-print", label: "طباعة / حفظ PDF", icon: FileTextIcon, tone: "pdf" },
    { key: "pdf-share", label: "مشاركة ملخص الرصيد", icon: Share1Icon, tone: "share" },
    { key: "excel", label: "تصدير إلى ملف Excel", icon: TableIcon, tone: "excel" },
    { key: "balance", label: "طباعة مصادقة الرصيد", icon: CardStackIcon, tone: "balance" },
  ];
  if (!open) return null;
  const visibleItems =
    kind === "purchases"
      ? [
          ...items.slice(0, 3),
          { key: "import" as const, label: "استيراد الحسابات من ملف", icon: TableIcon, tone: "excel" },
        ]
      : kind === "inventory"
        ? items.slice(0, 3)
        : items;

  return (
    <div className="export-menu-layer" data-testid="export-menu">
      <button className="export-menu-backdrop" onClick={onClose} aria-label="إغلاق قائمة التصدير" />
      <aside
        className={`export-side-menu ${kind === "inventory" ? "inventory-export-menu" : kind === "purchases" ? "purchases-export-menu" : ""}`}
        aria-label="خيارات التصدير"
      >
        {visibleItems.map((item) => (
          <button key={item.label} onClick={() => onSelectAction(item.key)}>
            <item.icon className={item.tone} />
            <span>{item.label}</span>
          </button>
        ))}
      </aside>
    </div>
  );
}

function AccountPickerModal({
  open,
  title = "كشف حساب",
  onClose,
  onAddAccount,
  onConfirm,
}: {
  open: boolean;
  title?: string;
  onClose: () => void;
  onAddAccount: () => void;
  onConfirm: (account: AccountRecord) => void;
}) {
  const ctx = useWorkspace();
  const [selectedId, setSelectedId] = useState(ctx.accounts[0]?.id ?? "");
  const [optionsOpen, setOptionsOpen] = useState(false);
  const [search, setSearch] = useState("");
  const keyboard = useKeyboard();
  const close = () => {
    keyboard.hide();
    setOptionsOpen(false);
    setSearch("");
    onClose();
  };
  if (!open) return null;
  const selected = ctx.accounts.find((a) => a.id === selectedId) ?? ctx.accounts[0];
  const filteredAccounts = rankAccountSearchMatches(ctx.accounts, search);

  return (
    <div className="center-modal-layer" data-testid="account-picker-modal">
      <button className="center-modal-backdrop" onClick={close} aria-label="إغلاق اختيار الحساب" />
      <section className="account-picker-modal" role="dialog" aria-modal="true" aria-labelledby="account-picker-title">
        <h2 id="account-picker-title">{title}</h2>
        <div className="account-picker-search-wrap">
          <label className="account-picker-search reference-search" htmlFor="account-picker-search">
            <span>ابحث عن الاسم هنا</span>
            <KeyboardInput
              id="account-picker-search"
              aria-label="البحث عن الحساب"
              data-testid="account-picker-search-input"
              value={search}
              onChange={(event) => {
                setSearch(event.target.value);
                setOptionsOpen(true);
              }}
              onKeyDown={(event) => {
                if (event.key === "Enter" && filteredAccounts.length > 0) {
                  event.preventDefault();
                  keyboard.hide();
                  setSelectedId(filteredAccounts[0].id);
                  setSearch("");
                  setOptionsOpen(false);
                }
              }}
            />
          </label>
          {search ? (
            <button
              type="button"
              className="account-picker-clear"
              aria-label="مسح بحث الحساب"
              onClick={() => setSearch("")}
            >
              <Cross2Icon />
            </button>
          ) : null}
        </div>
        <p>أو حدد الحساب من هنا</p>
        <div className="account-select-wrap">
          <div className="account-select-row">
            <button
              className="account-add"
              onClick={() => {
                keyboard.hide();
                setOptionsOpen(false);
                onAddAccount();
              }}
              aria-label="إضافة حساب"
            >
              <PlusIcon />
            </button>
            <button
              className="account-select"
              onClick={() => {
                keyboard.hide();
                setOptionsOpen((value) => !value);
              }}
              aria-label="اختيار حساب لكشف الحساب"
              aria-expanded={optionsOpen}
            >
              <span>{selected?.name || "لا توجد حسابات"}</span>
              <ChevronDownIcon />
            </button>
          </div>
          {optionsOpen ? (
            <div className="account-options" role="listbox" aria-label="الحسابات">
              {filteredAccounts.length ? (
                filteredAccounts.map((acc) => (
                  <button
                    key={acc.id}
                    type="button"
                    role="option"
                    aria-selected={acc.id === selected?.id}
                    onClick={() => {
                      keyboard.hide();
                      setSelectedId(acc.id);
                      setSearch("");
                      setOptionsOpen(false);
                    }}
                  >
                    <span>{acc.name}</span>
                    <small className="account-option-meta">
                      #{acc.codeNumber}
                      {acc.phone ? ` · ${acc.phone}` : ""}
                    </small>
                  </button>
                ))
              ) : (
                <p className="account-search-empty" role="status">
                  لا توجد حسابات مطابقة لـ «{search.trim()}»
                </p>
              )}
            </div>
          ) : null}
        </div>
        <div className="account-picker-actions">
          <button className="cancel" onClick={close}>
            إلغاء
          </button>
          <button
            className="confirm"
            onClick={() => {
              if (!selected) {
                triggerHaptic("warning");
                ctx.showToast("لا توجد حسابات بعد — اضغط + لإضافة حساب جديد");
                return;
              }
              keyboard.hide();
              setOptionsOpen(false);
              setSearch("");
              onConfirm(selected);
            }}
          >
            موافق
          </button>
        </div>
      </section>
    </div>
  );
}

function TransactionModal({
  open,
  initialAccount,
  editingEntry,
  onClose,
}: {
  open: boolean;
  initialAccount?: AccountRecord;
  editingEntry?: LedgerEntryRecord;
  onClose: () => void;
}) {
  const ctx = useWorkspace();
  const keyboard = useKeyboard();
  const [accountSearch, setAccountSearch] = useState("");
  const [accountId, setAccountId] = useState(
    editingEntry?.accountId ?? initialAccount?.id ?? ctx.accounts[0]?.id ?? "",
  );
  const [cashboxId, setCashboxId] = useState<number | undefined>(
    editingEntry?.cashboxId ?? ctx.cashboxes[0]?.id,
  );
  const [currency, setCurrency] = useState<CurrencyCode>(
    editingEntry?.currency ?? initialAccount?.currency ?? "ريال",
  );
  const [amount, setAmount] = useState(editingEntry ? String(editingEntry.amount) : "");
  const [note, setNote] = useState(editingEntry?.details ?? "");
  const [payment, setPayment] = useState<"cash" | "balance">(
    editingEntry?.payment === "balance" ? "balance" : "cash",
  );
  const [direction, setDirection] = useState<"debit" | "credit">(editingEntry?.direction ?? "debit");
  const [expenseCategory, setExpenseCategory] = useState(editingEntry?.expenseCategory ?? "");
  const [saving, setSaving] = useState(false);
  const [txError, setTxError] = useState<{ field?: "account" | "amount" | "submit"; message: string } | null>(null);
  const amountInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) {
      setTxError(null);
      setAccountSearch("");
      setAccountId(editingEntry?.accountId ?? initialAccount?.id ?? ctx.accounts[0]?.id ?? "");
      setCashboxId(editingEntry?.cashboxId ?? ctx.cashboxes[0]?.id);
      setCurrency(editingEntry?.currency ?? initialAccount?.currency ?? "ريال");
      setAmount(editingEntry ? String(editingEntry.amount) : "");
      setNote(editingEntry?.details ?? "");
      setPayment(editingEntry?.payment === "balance" ? "balance" : "cash");
      setDirection(editingEntry?.direction ?? "debit");
      setExpenseCategory(editingEntry?.expenseCategory ?? "");
    }
  }, [ctx.accounts, ctx.cashboxes, editingEntry, initialAccount, open]);

  if (!open) return null;

  const selectedAccount = ctx.accounts.find((a) => a.id === accountId) ?? initialAccount ?? ctx.accounts[0];
  const summary = selectedAccount ? computeAccountSummary(selectedAccount, ctx.ledger, currency) : null;
  const currentTime = new Intl.DateTimeFormat("ar-SA", {
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date());

  const save = async (andPrint = false) => {
    if (!selectedAccount) {
      triggerHaptic("warning");
      const msg = "اختر حسابًا أولًا قبل الحفظ.";
      setTxError({ field: "account", message: msg });
      ctx.showToast(msg, 4500);
      return;
    }
    const parsedAmount = parseArabicNumber(amount);
    if (parsedAmount <= 0) {
      triggerHaptic("warning");
      const msg = "أدخل مبلغًا أكبر من صفر قبل حفظ السند.";
      setTxError({ field: "amount", message: msg });
      ctx.showToast(msg, 4500);
      amountInputRef.current?.focus();
      return;
    }
    setTxError(null);
    setSaving(true);
    try {
      const nextNum =
        editingEntry?.entryNumber ?? Math.max(1000, ...ctx.ledger.map((e) => e.entryNumber)) + 1;
      const typeLabel = direction === "credit" ? "له (سند)" : "عليه (سند)";
      let targetEntryId = editingEntry?.id ?? "";
      if (editingEntry) {
        await updateLedgerEntry(ctx.uid, editingEntry.id, {
          ...editingEntry,
          accountId: selectedAccount.id,
          accountName: selectedAccount.name,
          ...(cashboxId ? { cashboxId } : {}),
          payment,
          direction,
          typeLabel,
          amount: parsedAmount,
          currency,
          details: note || typeLabel,
          ...(expenseCategory ? { expenseCategory } : {}),
        });
        triggerHaptic("success");
        ctx.showToast(`تم تعديل السند #${editingEntry.entryNumber}`);
      } else {
        targetEntryId = await createLedgerEntry(ctx.uid, {
          accountId: selectedAccount.id,
          accountName: selectedAccount.name,
          ...(cashboxId ? { cashboxId } : {}),
          kind: "voucher",
          typeLabel,
          payment,
          direction,
          amount: parsedAmount,
          currency,
          exchangeRate: 1,
          details: note || typeLabel,
          entryNumber: nextNum,
          deleted: false,
          entryDate: new Date().toISOString().slice(0, 10),
          ...(expenseCategory ? { expenseCategory } : {}),
        });
        triggerHaptic("success");
        ctx.showToast(`تم حفظ السند رقم #${nextNum} بنجاح`);
      }
      onClose();
      if (andPrint && targetEntryId) {
        ctx.flowRef.current?.push(cashInvoicePreviewScreen(targetEntryId));
      }
    } catch (err) {
      triggerHaptic("warning");
      const msg = err instanceof Error && err.message ? err.message : "تعذر حفظ السند";
      setTxError({ field: "submit", message: msg });
      ctx.showToast(msg, err instanceof UncertainWriteError ? 7500 : 5000);
    } finally {
      setSaving(false);
    }
  };

  const moveToTrash = async () => {
    if (!editingEntry) return;
    setSaving(true);
    try {
      await setLedgerDeleted(ctx.uid, editingEntry.id, true);
      ctx.showToast(`تم نقل العملية #${editingEntry.entryNumber} إلى سلة المحذوفات`);
      onClose();
    } finally {
      setSaving(false);
    }
  };

  const filteredAccounts = rankAccountSearchMatches(ctx.accounts, accountSearch);

  return (
    <div className="center-modal-layer" data-testid="transaction-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق السند" />
      <section className="transaction-modal" role="dialog" aria-modal="true" aria-labelledby="transaction-modal-title">
        <h2 id="transaction-modal-title">
          {editingEntry
            ? `تعديل سند #${editingEntry.entryNumber}`
            : selectedAccount?.name
              ? `سند جديد - ${selectedAccount.name}`
              : "سند جديد"}
        </h2>
        <div className="invoice-search" style={{ minHeight: 34 }}>
          <KeyboardInput
            aria-label="البحث عن حساب السند"
            data-testid="transaction-account-search"
            placeholder="بحث سريع عن الحساب..."
            value={accountSearch}
            onChange={(e) => setAccountSearch(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && filteredAccounts.length > 0) {
                e.preventDefault();
                setAccountId(filteredAccounts[0].id);
                setAccountSearch("");
                keyboard.hide();
              }
            }}
          />
          {accountSearch ? (
            <button type="button" aria-label="مسح بحث الحساب" onClick={() => setAccountSearch("")}>
              <Cross2Icon />
            </button>
          ) : null}
        </div>

        <div className={editingEntry ? "transaction-source-row has-delete" : "transaction-source-row"}>
          <time>{currentTime}</time>
          <select
            className="transaction-fund"
            aria-label="حساب السند"
            value={
              accountSearch.trim()
                ? (filteredAccounts.find((a) => a.id === accountId)?.id ?? filteredAccounts[0]?.id ?? "")
                : (selectedAccount?.id ?? "")
            }
            onChange={(e) => {
              setAccountId(e.target.value);
              if (accountSearch.trim()) setAccountSearch("");
            }}
          >
            {filteredAccounts.length === 0 ? (
              <option value="">لا توجد حسابات مطابقة</option>
            ) : (
              filteredAccounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))
            )}
          </select>
          {editingEntry ? (
            <button
              className="transaction-settings"
              aria-label="حذف السند إلى السلة"
              onClick={moveToTrash}
              title="نقل إلى سلة المحذوفات"
            >
              <TrashIcon />
            </button>
          ) : null}
        </div>
        <div className="transaction-cashbox-row">
          {ctx.cashboxes.length > 0 || editingEntry?.cashboxId ? (
            <select
              className="transaction-fund"
              aria-label="صندوق النقد"
              value={cashboxId ?? ""}
              onChange={(e) => setCashboxId(Number(e.target.value))}
            >
              {ctx.cashboxes.map((cb) => (
                <option key={cb.id} value={cb.id}>
                  {cb.name}
                </option>
              ))}
              {editingEntry?.cashboxId && !ctx.cashboxes.some((c) => c.id === editingEntry.cashboxId) ? (
                <option value={editingEntry.cashboxId}>
                  صندوق #{editingEntry.cashboxId} (غير نشط)
                </option>
              ) : null}
            </select>
          ) : null}
          <select
            className="transaction-fund"
            aria-label="عملة السند"
            value={currency}
            onChange={(e) => setCurrency(e.target.value as CurrencyCode)}
          >
            {ctx.currencyCodes.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </div>
        {ctx.cashboxes.length > 0 ? (
          <div className="transaction-cashbox-meta">
            <span>الصناديق النشطة: {ctx.cashboxes.length}</span>
            <span>
              عملة الصندوق:{" "}
              <bdi>{ctx.cashboxes.find((c) => c.id === cashboxId)?.currencyCode ?? currency}</bdi>
            </span>
          </div>
        ) : null}
        <strong
          className={`transaction-balance-strip ${summary?.tone ?? "neutral"}`}
          data-testid="transaction-balance-strip"
        >
          {summary?.tone === "credit"
            ? `الرصيد لكم: ${formatAmount(summary.netBalance)} ${currency}`
            : summary?.tone === "debit"
              ? `الرصيد عليكم: ${formatAmount(summary.netBalance)} ${currency}`
              : `الرصيد الحالي: 0 ${currency}`}
        </strong>
        <OutlinedAmountField
          id="new-transaction-amount"
          label="المبلغ"
          testId="transaction-amount"
          inputRef={amountInputRef}
          ariaInvalid={txError?.field === "amount"}
          currency={currency}
          value={amount}
          onChange={(next) => {
            if (txError?.field === "amount" || txError?.field === "submit") setTxError(null);
            setAmount(next);
          }}
        />
        {txError ? (
          <div className="field-inline-error" role="alert" data-testid="transaction-amount-error">
            {txError.message}
          </div>
        ) : null}
        <div className="transaction-input">
          <CameraIcon />
          <label htmlFor="new-transaction-note">
            <KeyboardInput
              id="new-transaction-note"
              value={note}
              onChange={(event) => setNote(event.target.value)}
              placeholder="اكتب البيان"
            />
          </label>
          <button aria-label="مسح البيان" onClick={() => setNote("")}>
            <Cross2Icon />
          </button>
        </div>
        <div className="transaction-radio-row" aria-label="طريقة السداد">
          <label>
            <input
              type="radio"
              name="transaction-payment"
              checked={payment === "cash"}
              onChange={() => setPayment("cash")}
            />{" "}
            نقدية
          </label>
          <label>
            <input
              type="radio"
              name="transaction-payment"
              checked={payment === "balance"}
              onChange={() => setPayment("balance")}
            />{" "}
            أرصدة
          </label>
        </div>
        <div className="transaction-radio-row direction-row" aria-label="اتجاه السند">
          <label className="credit">
            <input
              type="radio"
              name="transaction-direction"
              checked={direction === "credit"}
              onChange={() => setDirection("credit")}
            />{" "}
            له
          </label>
          <label className="debit">
            <input
              type="radio"
              name="transaction-direction"
              checked={direction === "debit"}
              onChange={() => setDirection("debit")}
            />{" "}
            عليه
          </label>
        </div>
        <ExpenseCategorySelector
          value={expenseCategory}
          onChange={setExpenseCategory}
          description={note}
          vendorName={selectedAccount?.name ?? ""}
          accountCategory={selectedAccount?.category}
          amount={amount}
          currency={currency}
          entryType={direction === "credit" ? "سند له" : "سند عليه / مصروف"}
        />
        <div className="form-modal-actions form-modal-actions-3">
          <button className="cancel" onClick={onClose}>
            إلغاء
          </button>
          <button className="save-print" disabled={saving} onClick={() => void save(true)}>
            حفظ وطباعة
          </button>
          <button className="save" disabled={saving} onClick={() => void save(false)}>
            {saving ? "جاري الحفظ..." : "حفظ"}
          </button>
        </div>
      </section>
    </div>
  );
}

function AccountCreateModal({
  mode,
  open,
  initialAccount,
  defaultCategory = "purchases",
  onClose,
}: {
  mode: AccountCreateMode;
  open: boolean;
  initialAccount?: AccountRecord;
  defaultCategory?: AccountCategory;
  onClose: () => void;
}) {
  const ctx = useWorkspace();
  const [name, setName] = useState(initialAccount?.name ?? "");
  const [category, setCategory] = useState<AccountCategory>(initialAccount?.category ?? defaultCategory);
  const [phone, setPhone] = useState(initialAccount?.phone ?? "");
  const [note, setNote] = useState(initialAccount?.note ?? "");
  const [debtLimit, setDebtLimit] = useState(Boolean(initialAccount?.creditLimit));
  const [openingBalance, setOpeningBalance] = useState(Boolean(initialAccount?.openingBalance));
  const [openingAmount, setOpeningAmount] = useState(
    initialAccount?.openingBalance ? String(initialAccount.openingBalance) : "",
  );
  const [openingDirection, setOpeningDirection] = useState<"debit" | "credit">(
    initialAccount?.openingDirection ?? "debit",
  );
  const [debtAmount, setDebtAmount] = useState(
    initialAccount?.creditLimit ? String(initialAccount.creditLimit) : "",
  );
  const [settlement, setSettlement] = useState(initialAccount?.settlement ?? false);
  const [documentNumber, setDocumentNumber] = useState(initialAccount?.documentNumberRequired ?? false);
  const [accountImage, setAccountImage] = useState<"1" | "2" | "3">(initialAccount?.accountImage ?? "1");
  const [accountCurrency, setAccountCurrency] = useState<CurrencyCode>(initialAccount?.currency ?? "ريال");
  const [sortOrder, setSortOrder] = useState(String(initialAccount?.sortOrder ?? ctx.accounts.length + 1));
  const [messageMethod, setMessageMethod] = useState<"sms" | "whatsapp">(initialAccount?.messageMethod ?? "sms");
  const [sendMode, setSendMode] = useState<"auto" | "confirm" | "never">(initialAccount?.sendMode ?? "never");
  const [saving, setSaving] = useState(false);
  const keyboard = useKeyboard();
  const close = () => {
    keyboard.hide();
    onClose();
  };
  if (!open) return null;
  const testId = mode === "compact" ? "account-form-compact" : "account-form-extended";

  const submitAccount = async () => {
    keyboard.hide();
    if (!name.trim()) {
      triggerHaptic("warning");
      ctx.showToast("أدخل اسم الحساب أولًا");
      return;
    }
    setSaving(true);
    try {
      const nextCode =
        initialAccount?.codeNumber ?? Math.max(0, ...ctx.accounts.map((a) => a.codeNumber)) + 1;
      await createOrUpdateAccount(
        ctx.uid,
        {
          name: name.trim(),
          category,
          phone,
          creditLimit: debtLimit ? parseArabicNumber(debtAmount) : initialAccount?.creditLimit ?? 1000000,
          currency: accountCurrency,
          isCashAccount: initialAccount?.isCashAccount ?? false,
          accountImage,
          sortOrder: parseArabicNumber(sortOrder) || 1,
          settlement,
          documentNumberRequired: documentNumber,
          messageMethod,
          sendMode,
          note,
          openingBalance: openingBalance ? parseArabicNumber(openingAmount) : 0,
          openingDirection,
          codeNumber: nextCode,
        },
        initialAccount?.id,
      );
      triggerHaptic("success");
      ctx.showToast(initialAccount ? "تم تحديث بيانات الحساب" : "تم إنشاء الحساب وحفظه في السحابة");
      onClose();
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="center-modal-layer" data-testid={testId}>
      <button className="center-modal-backdrop" onClick={close} aria-label="إغلاق إضافة الحساب" />
      <section
        className={`account-form-modal ${mode}${mode === "extended" && openingBalance ? " has-opening-balance" : ""}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby={`${testId}-title`}
      >
        <h2 id={`${testId}-title`}>{initialAccount ? "تعديل بيانات حساب" : "إضافة حساب جديد"}</h2>
        {mode === "compact" ? (
          <>
            <label className="underlined-form-field" htmlFor="compact-account-name">
              <KeyboardInput
                id="compact-account-name"
                aria-label="اسم الحساب الجديد"
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="أدخل الاسم"
              />
            </label>
            <span className="form-section-label">التصنيف والصورة</span>
            <label className="account-image-row">
              <span className="account-avatar">
                {accountImage === "1" ? <PersonIcon /> : accountImage === "2" ? <HomeIcon /> : <CubeIcon />}
              </span>
              <select
                aria-label="تصنيف الحساب"
                value={category}
                onChange={(e) => setCategory(e.target.value as AccountCategory)}
              >
                <option value="purchases">المشتريات</option>
                <option value="sales">المبيعات</option>
                <option value="clients">العملاء</option>
                <option value="employees">الموظفين</option>
                <option value="transfers">الحوالات</option>
                <option value="shop">المحل</option>
              </select>
              <ChevronDownIcon />
            </label>
            <div className="account-check-row">
              <label>
                <input
                  type="checkbox"
                  checked={settlement}
                  onChange={(event) => setSettlement(event.target.checked)}
                />{" "}
                قيد تسوية
              </label>
              <label>
                <input
                  type="checkbox"
                  checked={documentNumber}
                  onChange={(event) => setDocumentNumber(event.target.checked)}
                />{" "}
                رقم المستند
              </label>
            </div>
            <span className="form-section-label">حدد العملة الافتراضية للحساب</span>
            <div className="account-currency-row compact-currency-row">
              <div className="compact-currency-selector">
                <button
                  className="currency-plus"
                  aria-label="تبديل الصورة"
                  onClick={() => setAccountImage((v) => (v === "1" ? "2" : v === "2" ? "3" : "1"))}
                >
                  <PlusIcon />
                </button>
                <select
                  aria-label="العملة الافتراضية"
                  value={accountCurrency}
                  onChange={(event) => setAccountCurrency(event.target.value as CurrencyCode)}
                >
                  {ctx.currencyCodes.map((c) => (
                    <option key={c}>{c}</option>
                  ))}
                </select>
              </div>
              <label htmlFor="account-order">
                <span>الترتيب</span>
                <KeyboardInput
                  id="account-order"
                  aria-label="ترتيب الحساب"
                  value={sortOrder}
                  onChange={(e) => setSortOrder(e.target.value)}
                  inputMode="numeric"
                />
              </label>
            </div>
          </>
        ) : (
          <>
            <label className="icon-underlined-field" htmlFor="extended-account-name">
              <PersonIcon />
              <KeyboardInput
                id="extended-account-name"
                aria-label="اسم الحساب"
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="أدخل الاسم"
              />
            </label>
            <label className="icon-underlined-field" htmlFor="extended-account-phone">
              <MobileIcon />
              <KeyboardInput
                id="extended-account-phone"
                aria-label="رقم هاتف الحساب"
                inputMode="tel"
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
                placeholder="أدخل رقم الهاتف"
              />
            </label>
            <label className="wide-toggle">
              <span>تصنيف الحساب:</span>
              <select
                aria-label="تصنيف الحساب الموسع"
                value={category}
                onChange={(e) => setCategory(e.target.value as AccountCategory)}
                style={{ border: "1px solid var(--nasqo-line)", borderRadius: 5, padding: "2px 8px" }}
              >
                <option value="purchases">المشتريات</option>
                <option value="sales">المبيعات</option>
                <option value="clients">العملاء</option>
                <option value="employees">الموظفين</option>
                <option value="transfers">الحوالات</option>
                <option value="shop">المحل</option>
              </select>
            </label>
            <label className="wide-toggle">
              <span>إضافة سقف مديونية للحساب</span>
              <input
                className="account-form-switch"
                role="switch"
                type="checkbox"
                checked={debtLimit}
                onChange={(event) => {
                  keyboard.hide();
                  setDebtLimit(event.target.checked);
                }}
              />
            </label>
            {debtLimit ? (
              <label className="underlined-form-field account-debt-field">
                <KeyboardInput
                  aria-label="سقف المديونية"
                  inputMode="decimal"
                  value={debtAmount}
                  onChange={(event) => setDebtAmount(event.target.value)}
                  placeholder="أدخل سقف المديونية"
                />
              </label>
            ) : null}
            <label className="icon-underlined-field" htmlFor="extended-account-note">
              <ChatBubbleIcon />
              <KeyboardInput
                id="extended-account-note"
                aria-label="ملاحظة الحساب"
                value={note}
                onChange={(event) => setNote(event.target.value)}
                placeholder="اكتب ملاحظة"
              />
            </label>
            <fieldset className="account-radio-box">
              <legend>طريقة إرسال الرسائل</legend>
              <label>
                <input
                  type="radio"
                  name="message-method"
                  checked={messageMethod === "sms"}
                  onChange={() => setMessageMethod("sms")}
                />{" "}
                SMS
              </label>
              <label>
                <input
                  type="radio"
                  name="message-method"
                  checked={messageMethod === "whatsapp"}
                  onChange={() => setMessageMethod("whatsapp")}
                />{" "}
                واتساب
              </label>
            </fieldset>
            <fieldset className="account-radio-box three">
              <legend>إرسال الرسائل</legend>
              <label>
                <input
                  type="radio"
                  name="send-mode"
                  checked={sendMode === "auto"}
                  onChange={() => setSendMode("auto")}
                />{" "}
                تلقائي
              </label>
              <label>
                <input
                  type="radio"
                  name="send-mode"
                  checked={sendMode === "confirm"}
                  onChange={() => setSendMode("confirm")}
                />{" "}
                بعد التأكيد
              </label>
              <label>
                <input
                  type="radio"
                  name="send-mode"
                  checked={sendMode === "never"}
                  onChange={() => setSendMode("never")}
                />{" "}
                لا ترسل
              </label>
            </fieldset>
            <label className="wide-toggle">
              <span>إضافة رصيد افتتاحي أو رصيد سابق</span>
              <input
                className="account-form-switch"
                role="switch"
                type="checkbox"
                data-testid="opening-balance-toggle"
                aria-controls="opening-balance-fields"
                aria-expanded={openingBalance}
                checked={openingBalance}
                onChange={(event) => {
                  keyboard.hide();
                  setOpeningBalance(event.target.checked);
                }}
              />
            </label>
            {openingBalance ? (
              <div className="account-opening-fields" id="opening-balance-fields" data-testid="opening-balance-fields">
                <div className="account-opening-amount-row">
                  <KeyboardInput
                    aria-label="مبلغ الرصيد الافتتاحي"
                    data-testid="opening-balance-amount"
                    inputMode="decimal"
                    value={openingAmount}
                    onChange={(event) => setOpeningAmount(event.target.value)}
                    placeholder="أدخل المبلغ"
                  />
                  <select
                    aria-label="عملة الرصيد الافتتاحي"
                    value={accountCurrency}
                    onChange={(event) => setAccountCurrency(event.target.value as CurrencyCode)}
                  >
                    {ctx.currencyCodes.map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="transaction-radio-row direction-row" role="group" aria-label="اتجاه الرصيد الافتتاحي">
                  <label className="credit">
                    <input
                      type="radio"
                      name="opening-balance-direction"
                      checked={openingDirection === "credit"}
                      onChange={() => setOpeningDirection("credit")}
                    />{" "}
                    له
                  </label>
                  <label className="debit">
                    <input
                      type="radio"
                      name="opening-balance-direction"
                      checked={openingDirection === "debit"}
                      onChange={() => setOpeningDirection("debit")}
                    />{" "}
                    عليه
                  </label>
                </div>
              </div>
            ) : null}
          </>
        )}
        <div className="form-modal-actions">
          <button className="cancel" onClick={close}>
            إلغاء
          </button>
          <button className="save" disabled={saving} onClick={submitAccount}>
            {saving ? "جاري الحفظ..." : "حفظ"}
          </button>
        </div>
      </section>
    </div>
  );
}

function formatSmartReportNumber(value: number, signed = false): string {
  const num = Number.isFinite(value) ? value : 0;
  if (signed) {
    return formatSignedSmartBalance(num);
  }
  const abs = Math.abs(num);
  const rounded = Math.round(abs * 100) / 100;
  return rounded % 1 !== 0
    ? rounded.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    : formatAmount(rounded);
}

function TrialBalanceModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ctx = useWorkspace();
  const defaultCurrency = ctx.workspace?.defaultCurrency ?? "ريال";
  const [currency, setCurrency] = useState<string>(defaultCurrency);
  const [periodMode, setPeriodMode] = useState<"daily" | "all" | "monthly" | "yearly" | "custom">("all");
  const todayIso = useMemo(() => new Date().toISOString().slice(0, 10), []);
  const [fromDate, setFromDate] = useState<string>(todayIso);
  const [toDate, setToDate] = useState<string>(todayIso);

  const handlePeriodSelect = (mode: "daily" | "all" | "monthly" | "yearly") => {
    setPeriodMode(mode);
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    if (mode === "daily") {
      setFromDate(today);
      setToDate(today);
    } else if (mode === "monthly") {
      const ym = today.slice(0, 7);
      const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().slice(0, 10);
      setFromDate(`${ym}-01`);
      setToDate(lastDay);
    } else if (mode === "yearly") {
      const yr = today.slice(0, 4);
      setFromDate(`${yr}-01-01`);
      setToDate(`${yr}-12-31`);
    }
  };

  const report = useMemo(() => {
    const activeFrom = periodMode === "all" ? undefined : fromDate || undefined;
    const activeTo = periodMode === "all" ? undefined : toDate || undefined;
    return computeTrialBalanceReport(ctx.accounts, ctx.ledger, ctx.inventory, ctx.cashboxes, {
      currency,
      fromDate: activeFrom,
      toDate: activeTo,
    });
  }, [ctx.accounts, ctx.ledger, ctx.inventory, ctx.cashboxes, currency, periodMode, fromDate, toDate]);

  if (!open) return null;

  return (
    <div className="center-modal-layer" data-testid="trial-balance-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق ميزان المراجعة" />
      <section className="trial-balance-modal" role="dialog" aria-modal="true" aria-labelledby="trial-balance-title">
        <header className="smart-modal-header">
          <button type="button" className="smart-modal-close" onClick={onClose} aria-label="إغلاق">
            <Cross2Icon />
          </button>
          <h2 id="trial-balance-title">ميزان المراجعة</h2>
          <span className="smart-modal-spacer" aria-hidden="true" />
        </header>

        <div className="trial-balance-controls">
          <div className="trial-balance-currency-box">
            <div className="smart-sub-bar">العملة</div>
            <select
              data-testid="trial-balance-currency"
              aria-label="عملة ميزان المراجعة"
              value={currency}
              onChange={(e) => setCurrency(e.target.value)}
            >
              {ctx.currencyCodes.map((c, idx) => (
                <option key={c} value={c}>
                  {idx === 0 && c === "ريال" ? "ريال (العملة الأساسية)" : c}
                </option>
              ))}
              <option value="الكل">الكل</option>
            </select>
          </div>

          <div className="trial-balance-date-box">
            <div className="trial-balance-period-row" role="radiogroup" aria-label="الفترة">
              {(
                [
                  { id: "daily", label: "يومي" },
                  { id: "all", label: "الكلي" },
                  { id: "monthly", label: "شهري" },
                  { id: "yearly", label: "سنوي" },
                ] as const
              ).map((item) => (
                <label key={item.id} className={`trial-period-pill ${periodMode === item.id ? "active" : ""}`}>
                  <input
                    type="radio"
                    name="trial-balance-period"
                    checked={periodMode === item.id}
                    onChange={() => handlePeriodSelect(item.id)}
                  />
                  <span>{item.label}</span>
                </label>
              ))}
            </div>
            <div className="trial-balance-dates-grid">
              <label className="trial-date-row">
                <span className="trial-date-tag">من تاريخ</span>
                <KeyboardInput
                  type="date"
                  aria-label="من تاريخ"
                  value={fromDate}
                  onChange={(e) => {
                    setPeriodMode("custom");
                    setFromDate(e.target.value);
                  }}
                />
              </label>
              <label className="trial-date-row">
                <span className="trial-date-tag">الى تاريخ</span>
                <KeyboardInput
                  type="date"
                  aria-label="الى تاريخ"
                  value={toDate}
                  onChange={(e) => {
                    setPeriodMode("custom");
                    setToDate(e.target.value);
                  }}
                />
              </label>
            </div>
          </div>
        </div>

        <div className="trial-balance-sections">
          <div className="smart-section-band">
            الحسابات — {currency === "ريال" ? "ريال (العملة الأساسية المسجلة)" : currency === "الكل" ? "جميع العملات" : currency}
          </div>
          <div className="trial-balance-rows">
            <div className="trial-balance-row">
              <span className="trial-row-label">اجمالي المدين (لكم)</span>
              <strong className="trial-row-val pos" data-testid="trial-total-debit">
                <bdi>{formatSmartReportNumber(report.totalDebitAccounts)}</bdi>
              </strong>
            </div>
            <div className="trial-balance-row">
              <span className="trial-row-label">اجمالي الدائن (عليكم)</span>
              <strong className="trial-row-val neg" data-testid="trial-total-credit">
                <bdi>{formatSmartReportNumber(report.totalCreditAccounts)}</bdi>
              </strong>
            </div>
            <div className="trial-balance-row">
              <span className="trial-row-label">اجمالي النقدية</span>
              <strong className={`trial-row-val ${report.cashTotal < 0 ? "neg" : "pos"}`} data-testid="trial-cash-total">
                <bdi>{formatSmartReportNumber(report.cashTotal, true)}</bdi>
              </strong>
            </div>
            <div className="trial-balance-row">
              <span className="trial-row-label">صافي الرصيد</span>
              <strong className={`trial-row-val ${report.netBalance < 0 ? "neg" : "pos"}`} data-testid="trial-net-balance">
                <bdi>{formatSmartReportNumber(report.netBalance, true)}</bdi>
              </strong>
            </div>
            <div className="trial-balance-row">
              <span className="trial-row-label">النتيجة</span>
              <strong className={`trial-row-val ${report.netBalance < 0 ? "neg" : "pos"}`} data-testid="trial-result-label">
                {report.resultLabel}
              </strong>
            </div>
            <div className="trial-balance-row">
              <span className="trial-row-label">نسبة السيولة</span>
              <strong className={`trial-row-val ${report.liquidityRatioPercent < 0 ? "neg" : "pos"}`} data-testid="trial-liquidity">
                <bdi>{report.liquidityRatioPercent.toFixed(1)}%</bdi>
              </strong>
            </div>
          </div>

          <div className="smart-section-band">الفواتير والمخازن</div>
          <div className="trial-balance-rows">
            <div className="trial-balance-row">
              <span className="trial-row-label">المبيعات</span>
              <strong className="trial-row-val pos" data-testid="trial-sales-total">
                <bdi>{formatSmartReportNumber(report.salesTotal)}</bdi>
              </strong>
            </div>
            <div className="trial-balance-row">
              <span className="trial-row-label">المشتريات</span>
              <strong className="trial-row-val neg" data-testid="trial-purchases-total">
                <bdi>{formatSmartReportNumber(report.purchasesTotal)}</bdi>
              </strong>
            </div>
            <div className="trial-balance-row">
              <span className="trial-row-label">قيمة المخزون</span>
              <strong className="trial-row-val pos" data-testid="trial-inventory-value">
                <bdi>{formatSmartReportNumber(report.inventoryValue)}</bdi>
              </strong>
            </div>
            <div className="trial-balance-row">
              <span className="trial-row-label">صافي الربح</span>
              <strong className={`trial-row-val ${report.netProfit < 0 ? "neg" : "pos"}`} data-testid="trial-net-profit">
                <bdi>{formatSmartReportNumber(report.netProfit, true)}</bdi>
              </strong>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}

function AccountGroupsModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ctx = useWorkspace();
  const [editingGroup, setEditingGroup] = useState<AccountGroupRecord | null>(null);
  const [name, setName] = useState("");
  const [category, setCategory] = useState<AccountCategory>("shop");
  const [currencyCode, setCurrencyCode] = useState<CurrencyCode>("ريال");
  const [query, setQuery] = useState("");
  const [saving, setSaving] = useState(false);

  const resetForm = () => {
    setEditingGroup(null);
    setName("");
    setCategory("shop");
    setCurrencyCode((ctx.workspace?.defaultCurrency as CurrencyCode) ?? "ريال");
  };

  const filteredGroups = useMemo(() => {
    const q = normalizeArabicSearch(query);
    if (!q) return ctx.accountGroups;
    return ctx.accountGroups.filter((g) =>
      matchesArabicSearch(`${g.name} ${g.legacyId} ${categoryTitle(g.category)}`, q),
    );
  }, [ctx.accountGroups, query]);

  const countByGroup = useMemo(() => {
    const counts = new Map<number, number>();
    for (const acc of ctx.accounts) {
      if (acc.groupId != null) {
        counts.set(acc.groupId, (counts.get(acc.groupId) ?? 0) + 1);
      }
    }
    return counts;
  }, [ctx.accounts]);

  if (!open) return null;

  const handleSave = async (isUpdate: boolean) => {
    const trimmed = name.trim();
    if (!trimmed) {
      ctx.showToast("أدخل اسم الصندوق أولًا");
      return;
    }
    setSaving(true);
    try {
      await saveAccountGroup(ctx.uid, {
        ...(isUpdate && editingGroup ? { id: editingGroup.id, sortOrder: editingGroup.sortOrder } : {}),
        name: trimmed,
        category,
        currencyCode,
      });
      ctx.showToast(isUpdate && editingGroup ? "تم تعديل الصندوق بنجاح" : "تم حفظ الصندوق الجديد");
      resetForm();
    } catch (err) {
      ctx.showToast(err instanceof Error ? err.message : "تعذر حفظ بيانات الصندوق");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="center-modal-layer" data-testid="account-groups-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق دليل الحسابات" />
      <section className="account-groups-modal" role="dialog" aria-modal="true" aria-labelledby="account-groups-title">
        <header className="smart-modal-header">
          <button type="button" className="smart-modal-close" onClick={onClose} aria-label="إغلاق">
            <Cross2Icon />
          </button>
          <h2 id="account-groups-title">دليل الحسابات</h2>
          <span className="smart-modal-spacer" aria-hidden="true" />
        </header>

        <fieldset className="account-groups-fieldset">
          <legend>بيانات الصندوق</legend>
          <div className="account-groups-form-grid">
            <label className="account-groups-field">
              <span className="account-groups-tag">اسم الحساب</span>
              <KeyboardInput
                data-testid="account-group-name-input"
                placeholder="اسم الصندوق أو المجموعة"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </label>

            <label className="account-groups-field">
              <span className="account-groups-tag">العملة الافتراضية</span>
              <select
                aria-label="العملة الافتراضية"
                value={currencyCode}
                onChange={(e) => setCurrencyCode(e.target.value as CurrencyCode)}
              >
                {ctx.currencyCodes.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>

            <label className="account-groups-field">
              <span className="account-groups-tag">التصنيف</span>
              <select
                aria-label="تصنيف الصندوق"
                value={category}
                onChange={(e) => setCategory(e.target.value as AccountCategory)}
              >
                <option value="sales">المبيعات</option>
                <option value="purchases">المشتريات</option>
                <option value="clients">العملاء</option>
                <option value="employees">الموظفين</option>
                <option value="transfers">الحوالات</option>
                <option value="shop">المحل</option>
              </select>
            </label>

            <label className="account-groups-field">
              <span className="account-groups-tag">بحث</span>
              <KeyboardInput
                data-testid="account-group-search-input"
                placeholder="ابحث في الصناديق..."
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
            </label>
          </div>

          <div className="account-groups-actions">
            <button
              type="button"
              className="ag-btn save"
              disabled={saving}
              onClick={() => void handleSave(false)}
            >
              حفظ جديد
            </button>
            <button
              type="button"
              className="ag-btn edit"
              disabled={saving || !editingGroup}
              onClick={() => void handleSave(true)}
            >
              تعديل
            </button>
            <button type="button" className="ag-btn cancel" onClick={resetForm}>
              إلغاء الأمر
            </button>
          </div>
        </fieldset>

        <div className="account-groups-table-wrap">
          <table className="account-groups-table">
            <thead>
              <tr>
                <th scope="col">الرقم</th>
                <th scope="col">اسم الصندوق</th>
                <th scope="col">التصنيف</th>
                <th scope="col">العملة</th>
                <th scope="col">الحسابات</th>
              </tr>
            </thead>
            <tbody>
              {filteredGroups.map((group) => {
                const isSelected = editingGroup?.id === group.id;
                const count = countByGroup.get(group.id) ?? 0;
                return (
                  <tr
                    key={group.id}
                    data-testid={`account-group-row-${group.legacyId}`}
                    className={isSelected ? "selected" : undefined}
                    onClick={() => {
                      setEditingGroup(group);
                      setName(group.name);
                      setCategory(group.category);
                      setCurrencyCode(group.currencyCode);
                    }}
                  >
                    <td>
                      <bdi>{group.legacyId}</bdi>
                    </td>
                    <td className="ag-name-cell">{group.name}</td>
                    <td>{categoryTitle(group.category)}</td>
                    <td>{group.currencyCode}</td>
                    <td>
                      <bdi>{count}</bdi>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <footer className="account-groups-footer">
          <span>انقر على أي صف لتعديله ({filteredGroups.length} / {ctx.accountGroups.length})</span>
          <button type="button" className="ag-btn close" onClick={onClose}>
            إغلاق
          </button>
        </footer>
      </section>
    </div>
  );
}

function ChartOfAccountsModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ctx = useWorkspace();
  const [query, setQuery] = useState("");
  const [selectedGroupId, setSelectedGroupId] = useState<string>("all");
  const [balanceFilter, setBalanceFilter] = useState<"all" | "with-moves" | "non-zero" | "zero-moves">("all");
  const [sortBy, setSortBy] = useState<"code" | "name" | "balance" | "moves">("code");

  const groupMap = useMemo(
    () => new Map(ctx.accountGroups.map((g) => [g.id, g])),
    [ctx.accountGroups],
  );

  const accountRows = useMemo(() => {
    return ctx.accounts.map((acc) => {
      const summary = computeAccountSummary(acc, ctx.ledger);
      const group = acc.groupId != null ? groupMap.get(acc.groupId) : undefined;
      return {
        acc,
        summary,
        groupName: group?.name ?? categoryTitle(acc.category),
      };
    });
  }, [ctx.accounts, ctx.ledger, groupMap]);

  const filtered = useMemo(() => {
    const q = normalizeArabicSearch(query);
    const rows = accountRows.filter(({ acc, summary, groupName }) => {
      if (selectedGroupId !== "all" && String(acc.groupId ?? "") !== selectedGroupId) {
        return false;
      }
      if (balanceFilter === "with-moves" && summary.entryCount === 0) return false;
      if (balanceFilter === "non-zero" && summary.netBalance < 0.005) return false;
      if (balanceFilter === "zero-moves" && summary.entryCount > 0) return false;
      if (!q) return true;
      return matchesArabicSearch(
        `${acc.codeNumber} ${acc.name} ${acc.phone} ${groupName} ${categoryTitle(acc.category)} ${acc.currency} ${acc.note ?? ""}`,
        q,
      );
    });
    rows.sort((a, b) => {
      if (sortBy === "name") return a.acc.name.localeCompare(b.acc.name, "ar");
      if (sortBy === "balance") return b.summary.netBalance - a.summary.netBalance;
      if (sortBy === "moves") return b.summary.entryCount - a.summary.entryCount;
      return a.acc.codeNumber - b.acc.codeNumber || a.acc.sortOrder - b.acc.sortOrder;
    });
    return rows;
  }, [accountRows, balanceFilter, query, selectedGroupId, sortBy]);

  const totals = useMemo(() => {
    let debit = 0;
    let credit = 0;
    let activeMoves = 0;
    for (const r of filtered) {
      debit += r.summary.debitTotal;
      credit += r.summary.creditTotal;
      if (r.summary.entryCount > 0) activeMoves += 1;
    }
    return { debit, credit, activeMoves };
  }, [filtered]);

  if (!open) return null;

  return (
    <div className="center-modal-layer" data-testid="chart-of-accounts-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق شجرة الحسابات" />
      <section
        className="account-groups-modal chart-of-accounts-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="chart-accounts-title"
        style={{ maxHeight: "88vh", display: "flex", flexDirection: "column" }}
      >
        <header className="smart-modal-header smart-modal-header-wide">
          <button type="button" className="smart-modal-close" onClick={onClose} aria-label="إغلاق">
            <Cross2Icon />
          </button>
          <h2 id="chart-accounts-title">
            جميع الحسابات ({filtered.length} / {ctx.accounts.length})
          </h2>
          <button
            type="button"
            className="ag-btn save"
            style={{ fontSize: 11, padding: "4px 10px", whiteSpace: "nowrap" }}
            onClick={() => {
              onClose();
              ctx.openAccountCreate("extended");
            }}
          >
            + حساب جديد
          </button>
        </header>

        <div className="modal-filter-strip">
          <KeyboardInput
            data-testid="coa-search-input"
            aria-label="بحث في جميع الحسابات"
            placeholder="ابحث بالرقم أو الاسم أو الهاتف..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <select
            aria-label="تصفية حسب المجموعة"
            value={selectedGroupId}
            onChange={(e) => setSelectedGroupId(e.target.value)}
          >
            <option value="all">جميع المجموعات ({ctx.accountGroups.length})</option>
            {ctx.accountGroups.map((g) => (
              <option key={g.id} value={String(g.id)}>
                {g.legacyId ? `#${g.legacyId} ` : ""}
                {g.name}
              </option>
            ))}
          </select>
          <select
            aria-label="تصفية حسب الحركات"
            value={balanceFilter}
            onChange={(e) => setBalanceFilter(e.target.value as typeof balanceFilter)}
          >
            <option value="all">الكل ({ctx.accounts.length})</option>
            <option value="with-moves">حسابات لها حركات</option>
            <option value="non-zero">حسابات برصيد غير صفري</option>
            <option value="zero-moves">حسابات بلا حركات</option>
          </select>
          <select
            aria-label="فرز الحسابات"
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value as typeof sortBy)}
          >
            <option value="code">ترتيب: رقم الحساب</option>
            <option value="name">ترتيب: الاسم</option>
            <option value="balance">ترتيب: الأعلى رصيدًا</option>
            <option value="moves">ترتيب: الأكثر حركات</option>
          </select>
        </div>

        <div className="account-groups-table-wrap" style={{ flex: 1, overflow: "auto" }}>
          <table className="account-groups-table" style={{ fontSize: 11.5 }}>
            <thead>
              <tr>
                <th>الرقم</th>
                <th>اسم الحساب</th>
                <th>المجموعة / النوع</th>
                <th>العملة</th>
                <th>افتتاحي</th>
                <th>مدين (عليه)</th>
                <th>دائن (له)</th>
                <th>الرصيد الحالي</th>
                <th>حركات</th>
                <th>كشف</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(({ acc, summary, groupName }) => (
                <tr key={acc.id}>
                  <td>
                    <bdi>{acc.codeNumber}</bdi>
                  </td>
                  <td className="ag-name-cell">
                    <button
                      type="button"
                      className="modal-link-btn"
                      onClick={() => {
                        onClose();
                        ctx.flowRef.current?.push(supplierScreen(acc.id));
                      }}
                    >
                      {acc.name}
                    </button>
                    {acc.isCashAccount ? (
                      <small className="coa-cash-tag">(نقدي)</small>
                    ) : null}
                  </td>
                  <td>{groupName}</td>
                  <td>{acc.currency}</td>
                  <td>{formatAmount(acc.openingBalance)}</td>
                  <td className="coa-debit-cell">{formatAmount(summary.debitTotal)}</td>
                  <td className="coa-credit-cell">{formatAmount(summary.creditTotal)}</td>
                  <td className={`coa-bal-cell ${summary.tone}`}>
                    {formatAmount(summary.netBalance)}{" "}
                    {summary.tone === "credit" ? "له" : summary.tone === "debit" ? "عليه" : ""}
                  </td>
                  <td>{summary.entryCount}</td>
                  <td className="coa-actions-cell">
                    <button
                      type="button"
                      className="ag-btn edit coa-mini-btn"
                      onClick={() => {
                        onClose();
                        ctx.flowRef.current?.push(supplierScreen(acc.id));
                      }}
                    >
                      كشف
                    </button>
                    <button
                      type="button"
                      className="ag-btn"
                      style={{
                        padding: "2px 7px",
                        fontSize: 10,
                        background: "#f1f5f9",
                        color: "#0f172a",
                        border: "1px solid #cbd5e1",
                      }}
                      aria-label={`تعديل ${acc.name}`}
                      onClick={() => {
                        onClose();
                        ctx.openAccountEdit(acc);
                      }}
                    >
                      تعديل
                    </button>
                  </td>
                </tr>
              ))}
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={10} style={{ textAlign: "center", padding: 16, color: "#64748b" }}>
                    لا توجد حسابات مطابقة للتصفية الحالية.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>

        <footer className="account-groups-footer" style={{ flexWrap: "wrap", gap: 8 }}>
          <span style={{ fontSize: 11 }}>
            نشطة بالحركات: <b>{totals.activeMoves}</b> • إجمالي المدين:{" "}
            <b style={{ color: "#dc2626" }}>{formatAmount(totals.debit)}</b> • إجمالي الدائن:{" "}
            <b style={{ color: "#059669" }}>{formatAmount(totals.credit)}</b>
          </span>
          <button type="button" className="ag-btn close" onClick={onClose}>
            إغلاق
          </button>
        </footer>
      </section>
    </div>
  );
}

function CashboxesReportModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ctx = useWorkspace();
  const [report, setReport] = useState<Awaited<ReturnType<typeof fetchCashboxesReport>> | null>(null);
  const [currencyFilter, setCurrencyFilter] = useState<string>(ctx.workspace?.defaultCurrency || "ريال");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!open) return;
    let active = true;
    setLoading(true);
    void fetchCashboxesReport(ctx.uid, {
      currency: currencyFilter === "الكل" ? undefined : currencyFilter,
    })
      .then((res) => {
        if (active) setReport(res);
      })
      .catch(() => {
        if (active) setReport(null);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [ctx.uid, ctx.ledger.length, currencyFilter, open]);

  if (!open) return null;
  const cashAccounts = ctx.accounts.filter((a) => a.isCashAccount);

  return (
    <div className="center-modal-layer" data-testid="cashboxes-report-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق تقرير الصناديق" />
      <section
        className="account-groups-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="cashboxes-report-title"
        style={{ maxWidth: 580, width: "94vw", maxHeight: "84vh", display: "flex", flexDirection: "column" }}
      >
        <header className="smart-modal-header">
          <button type="button" className="smart-modal-close" onClick={onClose} aria-label="إغلاق">
            <Cross2Icon />
          </button>
          <h2 id="cashboxes-report-title">صناديق النقدية والتدفق النقدي</h2>
          <span className="smart-modal-spacer" aria-hidden="true" />
        </header>

        <div className="cashboxes-toolbar">
          <span>النطاق: كامل السجل</span>
          <label className="cashboxes-currency-label">
            <span>العملة</span>
            <select
              aria-label="عملة تقرير الصناديق"
              value={currencyFilter}
              onChange={(e) => setCurrencyFilter(e.target.value)}
            >
              {ctx.currencyCodes.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
              <option value="الكل">الكل</option>
            </select>
          </label>
        </div>

        <div className="account-groups-table-wrap cashboxes-table-wrap">
          {loading ? (
            <NasqoBrandLoader size="sm" label="جاري حساب حركة الصناديق..." />
          ) : (
            <>
              <table className="account-groups-table" style={{ fontSize: 12, marginBottom: 12 }}>
                <thead>
                  <tr>
                    <th>الصندوق</th>
                    <th>الحالة</th>
                    <th>العملة</th>
                    <th>وارد</th>
                    <th>صادر</th>
                    <th>الصافي</th>
                    <th>الحركات</th>
                  </tr>
                </thead>
                <tbody>
                  {(report?.cashboxes ?? []).map((cb) => (
                    <tr key={cb.id}>
                      <td className="ag-name-cell">{cb.name}</td>
                      <td>
                        <span className={cb.isActive === false ? "coa-debit-cell" : "coa-credit-cell"} style={{ fontWeight: 700 }}>
                          {cb.isActive === false ? "موقوف" : "نشط"}
                        </span>
                      </td>
                      <td>{cb.currencyCode}</td>
                      <td className="coa-credit-cell">{formatAmount(cb.totalIn)}</td>
                      <td className="coa-debit-cell">{formatAmount(cb.totalOut)}</td>
                      <td style={{ fontWeight: 700 }}>{formatAmount(cb.netBalance)}</td>
                      <td>{cb.entryCount}</td>
                    </tr>
                  ))}
                  {(report?.cashboxes ?? []).length === 0 ? (
                    <tr>
                      <td colSpan={7} className="coa-empty-cell">
                        لا توجد صناديق نقدية مسجلة في القاعدة.
                      </td>
                    </tr>
                  ) : null}
                </tbody>
              </table>

              {report?.reconciliation ? (
                <div
                  className="cashbox-reconciliation-box"
                  data-testid="cashboxes-report-reconciliation"
                >
                  <strong>تسوية إجمالي النقدية ({report.reconciliation.currencyFilter}):</strong>
                  <div>
                    مجموع صافي الصناديق المربوطة: <b>{formatAmount(report.reconciliation.linkedCashboxesNet)}</b>
                  </div>
                  <div>
                    حركات نقدية مسددة بدون ربط صندوق ({report.reconciliation.unlinkedCashCount} حركة):{" "}
                    <b>{formatAmount(report.reconciliation.unlinkedCashNet)}</b> (وارد{" "}
                    {formatAmount(report.reconciliation.unlinkedCashIn)} − صادر{" "}
                    {formatAmount(report.reconciliation.unlinkedCashOut)})
                  </div>
                  <div>
                    إجمالي صافي النقدية الموحد (يطابق الميزانية):{" "}
                    <b className="coa-cash-tag">{formatAmount(report.reconciliation.totalCashNet)}</b>
                  </div>
                </div>
              ) : null}

              {cashAccounts.length > 0 ? (
                <div className="cashbox-accounts-section">
                  <strong>
                    حسابات الدليل المُعلّمة كنقدية ({cashAccounts.length}) — ليست صناديق خزينة:
                  </strong>
                  <div className="cashbox-accounts-grid">
                    {cashAccounts.map((acc) => {
                      const s = computeAccountSummary(acc, ctx.ledger, currencyFilter === "الكل" ? undefined : currencyFilter);
                      return (
                        <button
                          key={acc.id}
                          type="button"
                          className="cashbox-account-card"
                          onClick={() => {
                            onClose();
                            ctx.flowRef.current?.push(supplierScreen(acc.id));
                          }}
                        >
                          <span>
                            <b>{acc.name}</b> ({s.entryCount} حركة)
                          </span>
                          <span>
                            مدين: {formatAmount(s.debitTotal)} / دائن: {formatAmount(s.creditTotal)}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              ) : null}
            </>
          )}
        </div>

        <footer className="account-groups-footer">
          <span>
            الصناديق النشطة المتاحة للسندات: {ctx.cashboxes.length}
            {report?.reconciliation && report.reconciliation.inactiveCount > 0
              ? ` (موقوف: ${report.reconciliation.inactiveCount})`
              : ""}
          </span>
          <button type="button" className="ag-btn close" onClick={onClose}>
            إغلاق
          </button>
        </footer>
      </section>
    </div>
  );
}

function CurrenciesModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ctx = useWorkspace();
  const keyboard = useKeyboard();
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [editingCurrency, setEditingCurrency] = useState<CurrencyRecord | null>(null);
  const [name, setName] = useState("");
  const [sellRate, setSellRate] = useState("1");
  const [buyRate, setBuyRate] = useState("1");
  const [subUnit, setSubUnit] = useState("");
  const [symbol, setSymbol] = useState("");
  const [query, setQuery] = useState("");
  const [saving, setSaving] = useState(false);

  const currenciesList = useMemo<CurrencyRecord[]>(
    () =>
      ctx.currencies.length > 0
        ? ctx.currencies
        : [
            {
              id: 1,
              code: "ريال",
              name: "ريال",
              symbol: "_",
              ratePrimary: 1,
              rateSecondary: 1,
              nameSecondary: "",
              legacyId: 1,
            },
          ],
    [ctx.currencies],
  );

  useEffect(() => {
    if (!open) return;
    if (selectedId == null && currenciesList.length > 0) {
      setSelectedId(currenciesList[0].id);
    }
  }, [currenciesList, open, selectedId]);

  const filteredCurrencies = useMemo(() => {
    const q = normalizeArabicSearch(query);
    if (!q) return currenciesList;
    return currenciesList.filter((c) =>
      matchesArabicSearch(`${c.legacyId ?? c.id} ${c.name} ${c.nameSecondary} ${c.symbol}`, q),
    );
  }, [currenciesList, query]);

  const resetForm = useCallback(() => {
    keyboard.hide();
    setEditingCurrency(null);
    setName("");
    setSellRate("1");
    setBuyRate("1");
    setSubUnit("");
    setSymbol("");
  }, [keyboard]);

  const loadRowForEdit = useCallback(
    (c: CurrencyRecord) => {
      setSelectedId(c.id);
      setEditingCurrency(c);
      setName(c.name);
      setSellRate(String(c.ratePrimary ?? 1));
      setBuyRate(String(c.rateSecondary ?? 1));
      setSubUnit(c.nameSecondary ?? "");
      setSymbol(c.symbol ?? "");
    },
    [],
  );

  const handleSave = async (isEditButton: boolean) => {
    keyboard.hide();
    const cleanName = name.trim();
    if (!cleanName) {
      if (isEditButton && selectedId != null) {
        const target = currenciesList.find((c) => c.id === selectedId);
        if (target) {
          loadRowForEdit(target);
          ctx.showToast(`تم تحميل عملة «${target.name}» للتعديل`);
          return;
        }
      }
      triggerHaptic("warning");
      ctx.showToast("يرجى إدخال اسم العملة أولًا");
      return;
    }
    const parsedSell = Math.max(0.0001, parseArabicNumber(sellRate) || 1);
    const parsedBuy = Math.max(0.0001, parseArabicNumber(buyRate) || 1);
    setSaving(true);
    try {
      const targetId = isEditButton ? (editingCurrency?.id ?? selectedId ?? undefined) : editingCurrency?.id;
      const updated = await saveCurrencyRecord(ctx.uid, {
        id: targetId,
        name: cleanName,
        symbol: symbol.trim() || "_",
        nameSecondary: subUnit.trim(),
        ratePrimary: parsedSell,
        rateSecondary: parsedBuy,
      });
      const savedRow = updated.find((c) => c.name === cleanName) ?? updated[updated.length - 1];
      if (savedRow) setSelectedId(savedRow.id);
      triggerHaptic("success");
      ctx.showToast(targetId ? `تم تعديل العملة: ${cleanName}` : `تم حفظ العملة: ${cleanName}`);
      resetForm();
    } catch (err) {
      triggerHaptic("warning");
      ctx.showToast(err instanceof Error ? err.message : "تعذر حفظ العملة");
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteSelected = useCallback(async () => {
    keyboard.hide();
    const targetId = editingCurrency?.id ?? selectedId;
    const target = currenciesList.find((c) => c.id === targetId);
    if (!target) {
      ctx.showToast("حدد عملة من الجدول أولًا");
      return;
    }
    setSaving(true);
    try {
      const updated = await deleteCurrencyRecord(ctx.uid, target.id);
      setSelectedId(updated[0]?.id ?? null);
      resetForm();
      triggerHaptic("success");
      ctx.showToast(`تم حذف العملة: ${target.name}`);
    } catch (err) {
      triggerHaptic("warning");
      ctx.showToast(err instanceof Error ? err.message : "لا يمكن حذف العملة الوحيدة المتبقية");
    } finally {
      setSaving(false);
    }
  }, [ctx, currenciesList, editingCurrency?.id, keyboard, resetForm, selectedId]);

  if (!open) return null;

  return (
    <div
      className="center-modal-layer"
      data-testid="currencies-modal"
      onKeyDown={(e) => {
        if (e.key === "F2") {
          e.preventDefault();
          const target = currenciesList.find((c) => c.id === selectedId);
          if (target) loadRowForEdit(target);
        } else if (e.key === "Delete" && document.activeElement?.tagName !== "INPUT") {
          e.preventDefault();
          void handleDeleteSelected();
        }
      }}
    >
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق نافذة العملات" />
      <section
        className="currencies-window-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="currencies-window-title"
      >
        <div className="currencies-win-chrome">
          <span className="currencies-win-caption">العملات</span>
          <button
            type="button"
            className="currencies-win-close"
            onClick={onClose}
            aria-label="إغلاق العملات"
          >
            <Cross2Icon />
          </button>
        </div>

        <header className="currencies-blue-banner">
          <h2 id="currencies-window-title">العمـــــــلات</h2>
        </header>

        <div className="currencies-form-wrap">
          <div className="currencies-form-section-title">بيانات العملة</div>
          <div className="currencies-form-box">
            <div className="currencies-form-row row-1">
              <label className="currencies-field">
                <span className="currencies-tag">إسم العملة</span>
                <KeyboardInput
                  data-testid="currency-name-input"
                  aria-label="إسم العملة"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                />
              </label>
              <label className="currencies-field rate">
                <span className="currencies-tag">سعر البيع</span>
                <KeyboardInput
                  data-testid="currency-sell-rate-input"
                  aria-label="سعر البيع"
                  inputMode="decimal"
                  value={sellRate}
                  onChange={(e) => setSellRate(e.target.value)}
                />
              </label>
              <label className="currencies-field rate">
                <span className="currencies-tag">سعر الشراء</span>
                <KeyboardInput
                  data-testid="currency-buy-rate-input"
                  aria-label="سعر الشراء"
                  inputMode="decimal"
                  value={buyRate}
                  onChange={(e) => setBuyRate(e.target.value)}
                />
              </label>
            </div>

            <div className="currencies-form-row row-2">
              <label className="currencies-field">
                <span className="currencies-tag">تجزئة العملة</span>
                <KeyboardInput
                  data-testid="currency-subunit-input"
                  aria-label="تجزئة العملة"
                  value={subUnit}
                  onChange={(e) => setSubUnit(e.target.value)}
                />
              </label>
              <label className="currencies-field wide">
                <span className="currencies-tag">إختصار العملة</span>
                <KeyboardInput
                  data-testid="currency-symbol-input"
                  aria-label="إختصار العملة"
                  value={symbol}
                  onChange={(e) => setSymbol(e.target.value)}
                />
              </label>
            </div>

            <div className="currencies-form-row row-3">
              <label className="currencies-field search">
                <span className="currencies-tag">بحث</span>
                <KeyboardInput
                  data-testid="currency-search-input"
                  aria-label="بحث العملات"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
              </label>
              <div className="currencies-actions">
                <button
                  type="button"
                  className="curr-btn save"
                  data-testid="currency-save-btn"
                  disabled={saving}
                  onClick={() => void handleSave(false)}
                >
                  حفظ
                </button>
                <button
                  type="button"
                  className="curr-btn edit"
                  data-testid="currency-edit-btn"
                  disabled={saving}
                  onClick={() => void handleSave(true)}
                >
                  تعديل
                </button>
                <button
                  type="button"
                  className="curr-btn cancel"
                  data-testid="currency-cancel-btn"
                  onClick={resetForm}
                >
                  الغاء الأمر
                </button>
              </div>
            </div>
          </div>
        </div>

        <div className="currencies-table-area">
          <table className="currencies-grid-table" data-testid="currencies-table">
            <thead>
              <tr>
                <th scope="col" className="col-num">الرقم</th>
                <th scope="col" className="col-name">اسم العملة</th>
                <th scope="col" className="col-sub">تجزئة العملة</th>
                <th scope="col" className="col-sym">رمز العملة</th>
                <th scope="col" className="col-rate">سعر البيع</th>
                <th scope="col" className="col-rate">سعر الشراء</th>
              </tr>
            </thead>
            <tbody>
              {filteredCurrencies.map((c, idx) => {
                const isSelected = selectedId === c.id;
                return (
                  <tr
                    key={c.id}
                    data-testid={`currency-row-${c.name}`}
                    className={isSelected ? "selected" : undefined}
                    onClick={() => loadRowForEdit(c)}
                  >
                    <td>{c.legacyId ?? idx + 1}</td>
                    <td className="curr-name-cell">{c.name}</td>
                    <td>{c.nameSecondary}</td>
                    <td>{c.symbol || "_"}</td>
                    <td>{c.ratePrimary}</td>
                    <td>{c.rateSecondary}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <footer className="currencies-footer-bar">
          <button
            type="button"
            className="currencies-footer-hint"
            onClick={() => {
              const target = currenciesList.find((c) => c.id === selectedId);
              if (target) loadRowForEdit(target);
            }}
          >
            تعديل عملة: F2
          </button>
          <button
            type="button"
            className="currencies-footer-hint"
            data-testid="currency-delete-btn"
            onClick={() => void handleDeleteSelected()}
          >
            حذف عملة : DELETE
          </button>
          <span className="currencies-footer-hint">التنقل : TAB</span>
        </footer>
      </section>
    </div>
  );
}

function TrashModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ctx = useWorkspace();
  if (!open) return null;
  const deletedEntries = ctx.ledger.filter((e) => e.deleted);

  return (
    <div className="center-modal-layer" data-testid="trash-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق سلة المحذوفات" />
      <section className="warehouse-modal" role="dialog" aria-modal="true" aria-labelledby="trash-title">
        <h2 id="trash-title">سلة المحذوفات ({deletedEntries.length})</h2>
        {deletedEntries.length === 0 ? (
          <p className="cash-empty">سلة المحذوفات فارغة.</p>
        ) : (
          <div style={{ display: "grid", gap: 8, maxHeight: 280, overflowY: "auto" }}>
            {deletedEntries.map((item) => (
              <div
                key={item.id}
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  padding: "8px 10px",
                  border: "1px solid var(--nasqo-line)",
                  borderRadius: 6,
                  fontSize: 12,
                }}
              >
                <div>
                  <strong>
                    #{item.entryNumber} · {item.accountName}
                  </strong>
                  <div style={{ color: "var(--nasqo-muted)" }}>
                    {formatAmount(item.amount)} {item.currency}
                  </div>
                </div>
                <div style={{ display: "flex", gap: 6 }}>
                  <button
                    onClick={async () => {
                      await setLedgerDeleted(ctx.uid, item.id, false);
                      ctx.showToast("تمت استعادة العملية");
                    }}
                    style={{
                      padding: "4px 8px",
                      borderRadius: 5,
                      background: "var(--nasqo-home-primary-bg, var(--nasqo-blue, #4338ca))",
                      color: "#fff",
                      fontSize: 11,
                    }}
                  >
                    استعادة
                  </button>
                  <button
                    onClick={async () => {
                      await permanentlyDeleteLedger(ctx.uid, item.id);
                      ctx.showToast("تم الحذف النهائي");
                    }}
                    style={{
                      padding: "4px 8px",
                      borderRadius: 5,
                      background: "#c91b08",
                      color: "#fff",
                      fontSize: 11,
                    }}
                  >
                    حذف نهائي
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
        <div className="form-modal-actions" style={{ gridTemplateColumns: "1fr" }}>
          <button className="cancel" onClick={onClose}>
            إغلاق
          </button>
        </div>
      </section>
    </div>
  );
}

function ResetDatabaseConfirmModal({
  open,
  onClose,
  onConfirm,
}: {
  open: boolean;
  onClose: () => void;
  onConfirm: () => Promise<void>;
}) {
  const keyboard = useKeyboard();
  const [confirmWord, setConfirmWord] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!open) {
      setConfirmWord("");
      setBusy(false);
    }
  }, [open]);

  if (!open) return null;

  const canConfirm = confirmWord.trim() === "تفريغ";

  const handleClose = () => {
    if (busy) return;
    keyboard.hide();
    onClose();
  };

  const handleConfirm = async () => {
    if (!canConfirm || busy) return;
    keyboard.hide();
    setBusy(true);
    try {
      await onConfirm();
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="center-modal-layer" data-testid="reset-db-confirm-modal">
      <button className="center-modal-backdrop" onClick={handleClose} aria-label="إغلاق تأكيد التفريغ" />
      <section className="warehouse-modal" role="dialog" aria-modal="true" aria-labelledby="reset-db-title">
        <h2 id="reset-db-title">تفريغ البيانات</h2>
        <p style={{ margin: "0 0 10px", fontSize: 13, lineHeight: 1.6, color: "var(--nasqo-muted)" }}>
          سيؤدي هذا الإجراء إلى حذف جميع الحسابات والحركات والأصناف الحالية. تأكد من حفظ نسخة احتياطية أولًا، ثم اكتب كلمة{" "}
          <strong style={{ color: "var(--nasqo-red)" }}>تفريغ</strong> للتأكيد:
        </p>
        <KeyboardInput
          data-testid="reset-db-confirm-input"
          aria-label="اكتب كلمة تفريغ للتأكيد"
          placeholder="اكتب كلمة تفريغ هنا"
          value={confirmWord}
          onChange={(e) => setConfirmWord(e.target.value)}
        />
        <div className="form-modal-actions" style={{ marginTop: 12 }}>
          <button type="button" className="cancel" disabled={busy} onClick={handleClose}>
            إلغاء
          </button>
          <button
            type="button"
            className="save"
            data-testid="reset-db-confirm-submit"
            disabled={!canConfirm || busy}
            style={{ background: canConfirm ? "#c91b08" : undefined }}
            onClick={() => void handleConfirm()}
          >
            {busy ? "جاري التفريغ..." : "تأكيد التفريغ"}
          </button>
        </div>
      </section>
    </div>
  );
}

function systemSettingsScreen(): FlowScreen {
  return {
    id: "system-settings",
    headerHeight: 50,
    header: (flow) => <SimpleAppHeader title="الإعدادات" onBack={flow.pop} />,
    render: (flow) => <SystemSettingsScreenBody flow={flow} />,
  };
}

function SystemSettingsScreenBody({ flow }: { flow: FlowControls }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  return (
    <SystemSettingsPage
      uid={ctx.uid}
      userEmail={ctx.userEmail}
      workspace={ctx.workspace}
      currencyOptions={ctx.currencyCodes}
      extended={ctx.extendedSettings}
      onChangeExtended={ctx.setExtendedSettings}
      themeMode={ctx.themeMode}
      onChangeThemeMode={ctx.setThemeMode}
      brandColor={ctx.brandColor}
      onChangeBrandColor={ctx.setBrandColor}
      onResetBrandColor={ctx.resetBrandColor}
      hapticsEnabled={ctx.hapticsEnabled}
      onChangeHaptics={ctx.setHapticsEnabled}
      lastBackupIso={ctx.lastBackupIso}
      onOpenBackupModal={ctx.openBackupModal}
      onOpenGoogleDrive={ctx.openGoogleDriveModal}
      onOpenFullSqliteImport={ctx.openFullSqliteImport}
      onRestoreJson={ctx.triggerJsonRestore}
      onOpenTrash={ctx.openTrash}
      onSignOut={ctx.handleSignOut}
      onNotify={ctx.showToast}
      onBack={flow.pop}
    />
  );
}

function WorkspaceSettingsModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const ctx = useWorkspace();
  const [companyName, setCompanyName] = useState(ctx.workspace?.companyName ?? "نسقو برو");
  const [defaultCurrency, setDefaultCurrency] = useState<CurrencyCode>(
    ctx.workspace?.defaultCurrency ?? "ريال",
  );
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open && ctx.workspace) {
      setCompanyName(ctx.workspace.companyName);
      setDefaultCurrency(ctx.workspace.defaultCurrency);
    }
  }, [ctx.workspace, open]);

  if (!open) return null;

  const backupStatus = isBackupOverdue(ctx.lastBackupIso);

  const save = async () => {
    if (!ctx.workspace || !companyName.trim()) return;
    setSaving(true);
    try {
      await saveWorkspaceSettings(ctx.uid, {
        ...ctx.workspace,
        companyName: companyName.trim(),
        defaultCurrency,
      });
      triggerHaptic("success");
      ctx.showToast("تم حفظ إعدادات المنشأة بنجاح");
      onClose();
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="center-modal-layer" data-testid="settings-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق الإعدادات" />
      <section className="warehouse-modal" role="dialog" aria-modal="true" aria-labelledby="settings-title">
        <h2 id="settings-title">إعدادات المنشأة والسحابة</h2>
        <KeyboardInput
          aria-label="اسم المنشأة"
          placeholder="اسم المنشأة أو النشاط التجاري"
          value={companyName}
          onChange={(e) => setCompanyName(e.target.value)}
        />
        <select
          aria-label="العملة الافتراضية"
          value={defaultCurrency}
          onChange={(e) => setDefaultCurrency(e.target.value as CurrencyCode)}
          style={{
            height: 36,
            border: "1px solid var(--nasqo-line)",
            borderRadius: 6,
            padding: "0 10px",
          }}
        >
          {ctx.currencyCodes.map((c) => (
            <option key={c}>{c}</option>
          ))}
        </select>

        <div className="settings-appearance-box">
          <div className="settings-subhead">المظهر ولون العلامة والاهتزاز</div>
          <div className="exec-segmented" role="group" aria-label="وضع الألوان">
            {(
              [
                ["light", "فاتح"],
                ["dark", "داكن"],
                ["system", "النظام"],
              ] as const
            ).map(([m, label]) => (
              <button
                key={m}
                type="button"
                className={ctx.themeMode === m ? "active" : ""}
                onClick={() => {
                  triggerHaptic("light");
                  ctx.setThemeMode(m);
                }}
              >
                {label}
              </button>
            ))}
          </div>
          <div className="exec-color-swatches" style={{ marginTop: 6 }}>
            {BRAND_COLOR_PRESETS.map((preset) => (
              <button
                key={preset.id}
                type="button"
                className={`exec-color-swatch ${ctx.brandColor === preset.hex ? "active" : ""}`}
                style={{ background: preset.hex }}
                aria-label={preset.label}
                onClick={() => {
                  triggerHaptic("light");
                  ctx.setBrandColor(preset.hex);
                }}
              />
            ))}
            <input
              type="color"
              aria-label="لون مخصص"
              value={ctx.brandColor}
              onChange={(e) => ctx.setBrandColor(e.target.value)}
              style={{ width: 28, height: 28, padding: 0, border: 0 }}
            />
            <button
              type="button"
              className="settings-reset-color-btn"
              onClick={() => {
                triggerHaptic("light");
                ctx.resetBrandColor();
                ctx.setThemeMode("light");
              }}
            >
              الافتراضي
            </button>
          </div>
          <label className="exec-haptic-toggle" style={{ marginTop: 4 }}>
            <input
              type="checkbox"
              checked={ctx.hapticsEnabled}
              onChange={(e) => ctx.setHapticsEnabled(e.target.checked)}
            />
            <span>تفعيل ردود الفعل اللمسية (الاهتزاز) عند التفاعل</span>
          </label>
        </div>

        <div
          className={`settings-backup-freshness ${backupStatus.overdue ? "overdue" : "healthy"}`}
          data-testid="settings-backup-banner"
        >
          <strong>
            {backupStatus.overdue
              ? backupStatus.daysSince === null
                ? "تنبيه: لم يتم أخذ نسخة احتياطية بعد"
                : `تنبيه: آخر نسخة احتياطية منذ ${backupStatus.daysSince} يومًا`
              : `النسخة الاحتياطية محدثة (منذ ${backupStatus.daysSince ?? 0} يوم)`}
          </strong>
          {ctx.lastBackupIso ? (
            <div style={{ fontSize: 11, marginTop: 3 }}>
              آخر تصدير: <bdi>{new Date(ctx.lastBackupIso).toLocaleString("en-GB")}</bdi>
            </div>
          ) : null}
        </div>

        <div className="form-modal-actions form-modal-actions-3">
          <button className="cancel" onClick={onClose}>
            إلغاء
          </button>
          <button className="cancel" onClick={ctx.handleSignOut} style={{ borderColor: "#c91b08", color: "#c91b08" }}>
            تسجيل الخروج
          </button>
          <button className="save" disabled={saving} onClick={save}>
            {saving ? "جاري الحفظ..." : "حفظ"}
          </button>
        </div>
      </section>
    </div>
  );
}

function InventoryItemModal({
  open,
  editing,
  onClose,
}: {
  open: boolean;
  editing?: InventoryItemRecord;
  onClose: () => void;
}) {
  const ctx = useWorkspace();
  const [name, setName] = useState("");
  const [unit, setUnit] = useState("حبة");
  const [quantity, setQuantity] = useState("1");
  const [avgCost, setAvgCost] = useState("");
  const [warehouseId, setWarehouseId] = useState("");
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState("");

  useEffect(() => {
    if (!open) return;
    setFormError("");
    if (editing) {
      setName(editing.name);
      setUnit(editing.unit || "حبة");
      setQuantity(String(editing.quantity ?? 0));
      setAvgCost(String(editing.avgCost ?? 0));
      setWarehouseId(editing.warehouseId);
      return;
    }
    if (!warehouseId || !ctx.warehouses.some((w) => w.id === warehouseId)) {
      const fallback = ctx.warehouses.find((w) => w.isDefault)?.id ?? ctx.warehouses[0]?.id ?? "";
      setWarehouseId(fallback);
    }
  }, [ctx.warehouses, editing, open, warehouseId]);

  if (!open) return null;

  const effectiveWarehouseId =
    warehouseId || ctx.warehouses.find((w) => w.isDefault)?.id || ctx.warehouses[0]?.id || "";

  const save = async () => {
    setFormError("");
    const trimmedName = name.trim();
    if (!trimmedName) {
      triggerHaptic("warning");
      const msg = "أدخل اسم الصنف في حقل «اسم الصنف» أولًا.";
      setFormError(msg);
      ctx.showToast(msg);
      return;
    }
    if (!effectiveWarehouseId) {
      triggerHaptic("warning");
      const msg = "لا يوجد مخزن محدد؛ أضف مخزنًا أو اختر المخزن المستهدف أولًا.";
      setFormError(msg);
      ctx.showToast(msg);
      return;
    }
    const parsedQty = quantity.trim() === "" ? 0 : parseArabicNumber(quantity);
    const parsedCost = avgCost.trim() === "" ? 0 : parseArabicNumber(avgCost);
    if (!Number.isFinite(parsedQty) || parsedQty < 0) {
      triggerHaptic("warning");
      const msg = "قيمة «الكمية» يجب أن تكون رقمًا صحيحًا أو صفرًا.";
      setFormError(msg);
      ctx.showToast(msg);
      return;
    }
    if (!Number.isFinite(parsedCost) || parsedCost < 0) {
      triggerHaptic("warning");
      const msg = "قيمة «متوسط التكلفة» يجب أن تكون رقمًا موجبًا أو صفرًا.";
      setFormError(msg);
      ctx.showToast(msg);
      return;
    }
    setSaving(true);
    try {
      await createInventoryItem(ctx.uid, {
        name: trimmedName,
        unit: unit.trim() || "حبة",
        quantity: parsedQty,
        avgCost: parsedCost,
        warehouseId: effectiveWarehouseId,
        quantityUnverified: false,
      });
      triggerHaptic("success");
      ctx.showToast(`تم حفظ الصنف «${trimmedName}» في المخزن`);
      setName("");
      setQuantity("1");
      setAvgCost("");
      setFormError("");
      onClose();
    } catch (err) {
      triggerHaptic("warning");
      const msg = err instanceof Error ? err.message : "تعذر حفظ الصنف في قاعدة البيانات.";
      setFormError(msg);
      ctx.showToast(msg);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="center-modal-layer" data-testid="inventory-item-modal">
      <button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق" />
      <section className="warehouse-modal" role="dialog" aria-modal="true" aria-labelledby="inv-add-title">
        <h2 id="inv-add-title">إضافة صنف مخزني</h2>
        {formError ? (
          <p role="alert" className="auth-error" data-testid="inventory-item-error" style={{ margin: 0 }}>
            {formError}
          </p>
        ) : null}
        <KeyboardInput
          aria-label="اسم الصنف"
          placeholder="اسم الصنف"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
          <KeyboardInput
            aria-label="الوحدة"
            placeholder="الوحدة (حبة / كرتون)"
            value={unit}
            onChange={(e) => setUnit(e.target.value)}
          />
          <KeyboardInput
            aria-label="الكمية"
            inputMode="decimal"
            placeholder="الكمية"
            value={quantity}
            onChange={(e) => setQuantity(e.target.value)}
          />
        </div>
        <KeyboardInput
          aria-label="متوسط التكلفة"
          inputMode="decimal"
          placeholder="متوسط التكلفة"
          value={avgCost}
          onChange={(e) => setAvgCost(e.target.value)}
        />
        <select
          aria-label="المخزن المستهدف"
          value={effectiveWarehouseId}
          onChange={(e) => setWarehouseId(e.target.value)}
          style={{ height: 36, border: "1px solid var(--nasqo-line)", borderRadius: 6, padding: "0 10px" }}
        >
          {ctx.warehouses.length === 0 ? <option value="">لا توجد مخازن مسجلة</option> : null}
          {ctx.warehouses.map((w) => (
            <option key={w.id} value={w.id}>
              {w.name}
            </option>
          ))}
        </select>
        <div className="form-modal-actions" style={{ gridTemplateColumns: "1fr 1fr" }}>
          <button className="cancel" onClick={onClose}>
            إلغاء
          </button>
          <button className="save" data-testid="inventory-item-save-btn" disabled={saving} onClick={save}>
            {saving ? "جاري الحفظ..." : "حفظ"}
          </button>
        </div>
      </section>
    </div>
  );
}

function SheetContent({
  kind,
  setKind,
}: {
  kind: SheetKind;
  setKind: (kind: SheetKind) => void;
}) {
  const ctx = useWorkspace();
  if (kind === "notifications") {
    const overLimit = ctx.accounts.filter((a) => {
      const s = computeAccountSummary(a, ctx.ledger);
      return a.creditLimit > 0 && s.netBalance > a.creditLimit;
    });
    return (
      <div className="filter-sheet">
        {overLimit.length === 0 ? (
          <p className="cash-empty">جميع الحسابات ضمن سقف المديونية المحدد.</p>
        ) : (
          overLimit.map((acc) => {
            const s = computeAccountSummary(acc, ctx.ledger);
            return (
              <div
                key={acc.id}
                style={{
                  padding: "10px 12px",
                  borderRadius: 8,
                  background: "var(--nasqo-warning-bg)",
                  color: "var(--nasqo-red)",
                  fontSize: 12,
                  marginBottom: 6,
                }}
              >
                <strong>تجاوز سقف المديونية: {acc.name}</strong>
                <div>
                  الرصيد: {formatAmount(s.netBalance)} / السقف: {formatAmount(acc.creditLimit)}
                </div>
              </div>
            );
          })
        )}
      </div>
    );
  }
  if (kind === "filters") {
    const activeEntries = ctx.ledger.filter((e) => !e.deleted);
    const scopedEntries = ctx.activeStatementAccountId
      ? activeEntries.filter(
          (e) =>
            e.accountId === ctx.activeStatementAccountId ||
            e.counterpartAccountId === ctx.activeStatementAccountId,
        )
      : activeEntries;
    const f = ctx.statementFilter;
    return (
      <div className="filter-sheet" data-testid="statement-filters-sheet">
        <span className="sheet-label">
          {ctx.activeStatementAccountId
            ? `عمليات الحساب النشطة: ${scopedEntries.length} (إجمالي الدفتر: ${activeEntries.length})`
            : `العمليات النشطة بالدفتر: ${activeEntries.length}`}
        </span>
        <label style={{ display: "grid", gap: 4, fontSize: 12 }}>
          <span>نوع العملية</span>
          <select
            aria-label="تصفية نوع العملية"
            value={f.docKind}
            onChange={(e) =>
              ctx.setStatementFilter((prev) => ({
                ...prev,
                docKind: e.target.value as "all" | "invoice" | "voucher" | "return" | "quote" | "order",
              }))
            }
            style={{ height: 36, border: "1px solid var(--nasqo-line)", borderRadius: 6, padding: "0 8px" }}
          >
            <option value="all">جميع الحركات والفواتير</option>
            <option value="invoice">الفواتير فقط</option>
            <option value="voucher">السندات فقط</option>
            <option value="return">المردودات فقط</option>
            <option value="quote">عروض الأسعار</option>
            <option value="order">الطلبيات</option>
          </select>
        </label>
        <label style={{ display: "grid", gap: 4, fontSize: 12 }}>
          <span>الفترة الزمنية</span>
          <select
            aria-label="تصفية الفترة"
            value={f.period}
            onChange={(e) => {
              const p = e.target.value;
              const bounds = computePeriodDateRange(p);
              ctx.setStatementFilter((prev) => ({
                ...prev,
                period: p,
                fromDate: bounds.fromDate,
                toDate: bounds.toDate,
              }));
            }}
            style={{ height: 36, border: "1px solid var(--nasqo-line)", borderRadius: 6, padding: "0 8px" }}
          >
            <option value="الكل">الكل (جميع الفترات)</option>
            <option value="يومي">اليوم</option>
            <option value="شهري">الشهر الحالي</option>
            <option value="سنوي">السنة الحالية</option>
          </select>
        </label>
        <label style={{ display: "grid", gap: 4, fontSize: 12 }}>
          <span>ترتيب العرض</span>
          <select
            aria-label="ترتيب الحركات"
            value={f.sortOrder}
            onChange={(e) =>
              ctx.setStatementFilter((prev) => ({
                ...prev,
                sortOrder: e.target.value === "asc" ? "asc" : "desc",
              }))
            }
            style={{ height: 36, border: "1px solid var(--nasqo-line)", borderRadius: 6, padding: "0 8px" }}
          >
            <option value="desc">الأحدث أولًا (تنازلي)</option>
            <option value="asc">الأقدم أولًا (تصاعدي)</option>
          </select>
        </label>
        <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 12 }}>
          <input
            type="checkbox"
            checked={f.showPreviousBalance ?? false}
            onChange={(e) =>
              ctx.setStatementFilter((prev) => ({ ...prev, showPreviousBalance: e.target.checked }))
            }
          />
          <span>إظهار الرصيد السابق</span>
        </label>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
          <button
            type="button"
            className="cancel"
            onClick={() => {
              ctx.setStatementFilter({
                docKind: "all",
                sortOrder: "desc",
                period: "الكل",
                fromDate: "",
                toDate: "",
                showPreviousBalance: null,
              });
              ctx.showToast("تمت إعادة ضبط التصفية");
            }}
          >
            إعادة ضبط
          </button>
          <button
            type="button"
            className="primary full"
            onClick={() => {
              setKind(null);
              ctx.showToast("تم تحديث العرض حسب عوامل التصفية");
            }}
          >
            تطبيق التصفية
          </button>
        </div>
      </div>
    );
  }
  if (kind === "export") {
    return (
      <div className="sheet-action-list">
        <button
          onClick={() => {
            setKind(null);
            triggerPrintWithLoader("جاري تجهيز الطباعة...");
          }}
        >
          <span>
            <FileTextIcon />
          </span>
          <div>
            <strong>طباعة / حفظ PDF</strong>
            <small>مستند جاهز للطباعة</small>
          </div>
          <ChevronLeftIcon />
        </button>
      </div>
    );
  }
  return null;
}

function sheetTitle(kind: SheetKind) {
  return (
    ({
      filters: "التصفية والترتيب",
      export: "تصدير كشف الحساب",
      notifications: "تنبيهات الحدود والأرصدة",
    }) as Record<Exclude<SheetKind, null>, string>
  )[kind as Exclude<SheetKind, null>] ?? "";
}

function sheetDescription(kind: SheetKind) {
  if (kind === "export") return "طباعة وتصدير التقارير المالية";
  return undefined;
}

function cashInvoicePreviewScreen(entryId: string): FlowScreen {
  return {
    id: `invoice-preview-${entryId}`,
    headerHeight: 58,
    header: (flow) => <SimpleAppHeader title="معاينة الفاتورة" onBack={flow.pop} />,
    render: (flow) => <CashInvoicePreviewPage entryId={entryId} flow={flow} />,
  };
}

function CashInvoicePreviewPage({ entryId, flow }: { entryId: string; flow: FlowControls }) {
  const ctx = useWorkspace();
  ctx.flowRef.current = flow;
  const entry = ctx.ledger.find((e) => e.id === entryId || String(e.entryNumber) === entryId);
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const [viewportWidth, setViewportWidth] = useState(373);
  const [zoom, setZoom] = useState<number | null>(null);
  const [downloadingPdf, setDownloadingPdf] = useState(false);
  const [uploadingDrive, setUploadingDrive] = useState(false);
  const [generatedAt] = useState(() => new Date());
  const [invoiceLines, setInvoiceLines] = useState<UnifiedInvoiceLine[]>([]);
  const fitScale = Math.min(viewportWidth / 1280, 1);
  const scale = zoom ?? fitScale;

  useEffect(() => {
    if (!entry) {
      setInvoiceLines([]);
      return;
    }
    let active = true;
    void fetchInvoiceDetailWithLines(ctx.uid, entry.id)
      .then((detail) => {
        if (active) setInvoiceLines(detail.lines ?? []);
      })
      .catch(() => {
        if (active) setInvoiceLines([]);
      });
    return () => {
      active = false;
    };
  }, [ctx.uid, entry]);

  useEffect(() => {
    const viewport = viewportRef.current;
    if (!viewport) return;
    const updateWidth = () => setViewportWidth(viewport.clientWidth);
    updateWidth();
    const observer = new ResizeObserver(updateWidth);
    observer.observe(viewport);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const viewport = viewportRef.current;
    if (viewport) viewport.scrollLeft = Math.max(0, viewport.scrollWidth - viewport.clientWidth);
  }, [scale]);

  const moveDocument = (direction: -1 | 1) =>
    viewportRef.current?.scrollBy({ left: direction * 240, behavior: "smooth" });

  const handleDownloadPdf = async () => {
    if (!entry || downloadingPdf) return;
    setDownloadingPdf(true);
    triggerHaptic("light");
    try {
      await ctx.runWithLoader("جاري إنشاء ملف PDF للفاتورة...", async () => {
        const { filename } = await generatePrintableInvoicePdfFromDatabase(ctx.uid, entry.id, {
          companyName: ctx.workspace?.companyName || "نسقو برو",
          footerNote: ctx.extendedSettings.salesInvoiceFooterNote,
          fallbackEntry: entry,
        });
        triggerHaptic("success");
        ctx.showToast(`تم تنزيل ملخص الفاتورة (${filename})`);
      });
    } catch {
      triggerHaptic("warning");
      ctx.showToast("تعذّر إنشاء ملف PDF للفاتورة");
    } finally {
      setDownloadingPdf(false);
    }
  };

  const handleUploadPdfToDrive = async () => {
    if (!entry || uploadingDrive) return;
    setUploadingDrive(true);
    triggerHaptic("light");
    try {
      await ctx.runWithLoader("جاري رفع الفاتورة إلى Google Drive...", async () => {
        const summary = buildInvoicePdfSummaryData(entry, {
          companyName: ctx.workspace?.companyName || "نسقو برو",
          footerNote: ctx.extendedSettings.salesInvoiceFooterNote,
        });
        const { bytes, filename, mimeType } = await buildInvoiceSummaryPdfBytes(summary);
        let token = getGoogleAccessToken();
        if (!token) {
          const authResult = await connectGoogleDrive();
          token = authResult.accessToken;
        }
        try {
          const folder = await findOrCreateDriveFolder(token, "NASQO Pro Invoices");
          await uploadFileToDrive(token, {
            name: filename,
            content: bytes,
            mimeType,
            parentId: folder.id,
            description: `فاتورة ${summary.title} #${summary.entryNumber} - ${summary.accountName}`,
          });
        } catch (err) {
          if (err instanceof DriveAuthExpiredError) {
            const authResult = await connectGoogleDrive();
            const folder = await findOrCreateDriveFolder(authResult.accessToken, "NASQO Pro Invoices");
            await uploadFileToDrive(authResult.accessToken, {
              name: filename,
              content: bytes,
              mimeType,
              parentId: folder.id,
              description: `فاتورة ${summary.title} #${summary.entryNumber} - ${summary.accountName}`,
            });
          } else {
            throw err;
          }
        }
        triggerHaptic("success");
        ctx.showToast(`تم حفظ الفاتورة PDF في Google Drive: ${filename}`);
      });
    } catch (err) {
      triggerHaptic("warning");
      ctx.showToast(
        err instanceof Error
          ? `تعذر رفع الفاتورة إلى Drive: ${err.message}`
          : "تعذر رفع الفاتورة إلى Google Drive",
      );
    } finally {
      setUploadingDrive(false);
    }
  };

  if (!entry) {
    return (
      <MobileScroll className="app-screen">
        <p className="cash-invoice-unavailable">لم يُعثر على المستند المطلوب.</p>
      </MobileScroll>
    );
  }

  return (
    <main className="cash-invoice-preview" data-testid="cash-invoice-screen">
      <div className="cash-invoice-controls" role="group" aria-label="تكبير الفاتورة وتنزيل PDF">
        <button
          data-testid="cash-invoice-zoom-in"
          aria-label="تكبير الفاتورة"
          disabled={scale >= 1.5}
          onClick={() => setZoom(Math.min(1.5, Math.ceil((scale + 0.01) * 4) / 4))}
        >
          +
        </button>
        <output data-testid="cash-invoice-zoom-value" aria-live="polite">
          {Math.round(scale * 100)}%
        </output>
        <button
          data-testid="cash-invoice-zoom-out"
          aria-label="تصغير الفاتورة"
          disabled={scale <= fitScale}
          onClick={() => setZoom(Math.max(fitScale, Math.floor((scale - 0.01) * 4) / 4))}
        >
          −
        </button>
        <button className="cash-invoice-fit" data-testid="cash-invoice-reset" onClick={() => setZoom(null)}>
          ملاءمة العرض
        </button>
        <button className="cash-invoice-actual" data-testid="cash-invoice-actual-size" onClick={() => setZoom(1)}>
          100%
        </button>
        <button
          className="cash-invoice-actual"
          onClick={() => triggerPrintWithLoader("جاري تجهيز طباعة الفاتورة...")}
          aria-label="طباعة الفاتورة"
        >
          طباعة PDF
        </button>
        <button
          type="button"
          className="cash-invoice-download"
          data-testid="cash-invoice-download-pdf"
          aria-label="تنزيل ملخص الفاتورة PDF"
          disabled={downloadingPdf}
          onClick={() => void handleDownloadPdf()}
        >
          <DownloadIcon />
          <span>{downloadingPdf ? "جارٍ الإنشاء..." : "تنزيل PDF"}</span>
        </button>
        <button
          type="button"
          className="cash-invoice-drive"
          data-testid="cash-invoice-upload-drive"
          aria-label="رفع الفاتورة PDF إلى Google Drive"
          disabled={uploadingDrive}
          onClick={() => void handleUploadPdfToDrive()}
        >
          <GlobeIcon />
          <span>{uploadingDrive ? "جاري الرفع..." : "حفظ لـ Drive"}</span>
        </button>
      </div>
      <div className="cash-invoice-reader-hint">
        {scale > fitScale ? (
          <>
            <button aria-label="تحريك الفاتورة إلى اليمين" onClick={() => moveDocument(1)}>
              <ArrowRightIcon />
            </button>
            <span>مرّر لقراءة بقية المستند</span>
            <button aria-label="تحريك الفاتورة إلى اليسار" onClick={() => moveDocument(-1)}>
              <ArrowLeftIcon />
            </button>
          </>
        ) : (
          <span>
            مستند رقم {entry.entryNumber} · اضغط تنزيل PDF لحفظ ملخص الفاتورة أو طباعة PDF
          </span>
        )}
      </div>
      <MobileScroll className="cash-invoice-scroll">
        <div className="cash-invoice-horizontal" ref={viewportRef} data-testid="cash-invoice-pan" tabIndex={0} aria-label="عرض مستند الفاتورة">
          <div
            className="cash-invoice-sheet-space"
            style={{
              width: 1280 * scale,
              height: Math.max(908, 600 + Math.max(invoiceLines.length, entry.lineCount ?? 0, 1) * 52) * scale,
              marginInline: "auto",
              direction: "ltr",
            }}
          >
            <CashInvoiceDocument
              companyName={ctx.workspace?.companyName || "نسقو برو"}
              entry={entry}
              generatedAt={generatedAt}
              scale={scale}
              footerNote={ctx.extendedSettings.salesInvoiceFooterNote}
              invoiceLines={invoiceLines}
            />
          </div>
        </div>
      </MobileScroll>
    </main>
  );
}

function CashInvoiceDocument({
  companyName,
  entry,
  generatedAt,
  scale,
  footerNote,
  invoiceLines = [],
}: {
  companyName: string;
  entry: LedgerEntryRecord;
  generatedAt: Date;
  scale: number;
  footerNote?: string;
  invoiceLines?: readonly UnifiedInvoiceLine[];
}) {
  const stamp = `${generatedAt.getFullYear()}-${String(generatedAt.getMonth() + 1).padStart(2, "0")}-${String(
    generatedAt.getDate(),
  ).padStart(2, "0")} ${String(generatedAt.getHours()).padStart(2, "0")}:${String(
    generatedAt.getMinutes(),
  ).padStart(2, "0")}`;

  const lines = entry.details
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);

  const totalQuantity =
    invoiceLines.length > 0
      ? invoiceLines.reduce((sum, l) => sum + (Number(l.quantity) || 0), 0)
      : Math.max(1, lines.length);

  const tafqeetText = amountToArabicWords(entry.amount, entry.currency);

  return (
    <article
      className="cash-invoice-document cash-invoice-document-flow"
      data-testid="cash-invoice-document"
      dir="rtl"
      aria-label={`مستند رقم ${entry.entryNumber}`}
      style={{
        transform: `scale(${scale})`,
        minHeight: Math.max(908, 600 + Math.max(invoiceLines.length, lines.length, 1) * 52),
      }}
    >
      <div className="cash-invoice-header-band">
        <div className="cash-invoice-merchant arabic">
          <span>{companyName}</span>
          <span>إدارة الحسابات والفواتير</span>
        </div>
        <div className="cash-invoice-center-badge">
          <h1>{entry.typeLabel}</h1>
        </div>
        <div className="cash-invoice-merchant english" lang="en" dir="ltr">
          <span>NASQO PRO</span>
          <span>Business Accounting</span>
        </div>
      </div>
      <div className="cash-invoice-divider-flow" />
      <div className="cash-invoice-meta-pair">
        <p className="cash-invoice-date-flow">
          التاريخ : <bdi>{entry.entryDate}</bdi>
        </p>
        <p className="cash-invoice-number-flow">
          الرقم : <bdi>{entry.entryNumber}</bdi>
        </p>
      </div>
      <div className="cash-invoice-meta-pair">
        <p className="cash-invoice-recipient-flow">الأخ / {entry.accountName}</p>
        <p className="cash-invoice-salutation-flow">المحترم</p>
      </div>
      <p className="cash-invoice-description-flow">
        البيان /{entry.warehouseName ? ` (${entry.warehouseName})` : ""}
        {entry.details && entry.details !== entry.typeLabel
          ? ` ${entry.details.replace(/\s*—\s*\[.*\]$/, "")}`
          : ""}
      </p>
      <table className="cash-invoice-table cash-invoice-table-flow" aria-label="بنود المستند">
        <colgroup>
          <col style={{ width: 538 }} />
          <col style={{ width: 146 }} />
          <col style={{ width: 172 }} />
          <col style={{ width: 134 }} />
          <col style={{ width: 194 }} />
        </colgroup>
        <thead>
          <tr>
            <th scope="col">الصنف</th>
            <th scope="col">الوحدة</th>
            <th scope="col">سعر الوحدة</th>
            <th scope="col">الكمية</th>
            <th scope="col">المجموع</th>
          </tr>
        </thead>
        <tbody>
          {invoiceLines.length > 0 ? (
            invoiceLines.map((line) => (
              <tr key={line.id}>
                <td>{line.itemName || line.details || entry.typeLabel}</td>
                <td>{line.unit || "حبة"}</td>
                <td className="red">{formatAmount(line.price)}</td>
                <td>{formatAmount(line.quantity)}</td>
                <td className="blue">{formatAmount(line.total)}</td>
              </tr>
            ))
          ) : lines.length > 1 ? (
            lines.map((line, idx) => (
              <tr key={idx}>
                <td>{line}</td>
                <td>بند</td>
                <td className="red">{idx === 0 ? formatAmount(entry.amount) : "—"}</td>
                <td>1</td>
                <td className="blue">{idx === 0 ? formatAmount(entry.amount) : "—"}</td>
              </tr>
            ))
          ) : (
            <tr>
              <td>{lines[0] || entry.typeLabel}</td>
              <td>عملية</td>
              <td className="red">{formatAmount(entry.amount)}</td>
              <td>1</td>
              <td className="blue">{formatAmount(entry.amount)}</td>
            </tr>
          )}
        </tbody>
      </table>
      <div className="cash-invoice-summary-flow">
        <div>
          <strong>الكمية</strong>
          <bdi data-testid="cash-invoice-quantity-total">{formatAmount(totalQuantity)}</bdi>
        </div>
        <div>
          <strong>الإجمالي</strong>
          <bdi className="blue" data-testid="cash-invoice-grand-total">
            {formatAmount(entry.amount)}
          </bdi>
        </div>
      </div>
      <p className="cash-invoice-total-words cash-invoice-total-words-flow" data-testid="cash-invoice-tafqeet">
        {tafqeetText}
        {footerNote ? ` — ${footerNote}` : ""}
      </p>
      <footer className="cash-invoice-document-footer cash-invoice-document-footer-flow">
        <time dateTime={generatedAt.toISOString()}>{stamp}</time>
        <span dir="rtl">صفحة 1 | {companyName}</span>
      </footer>
    </article>
  );
}
