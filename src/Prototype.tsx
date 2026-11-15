import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react";
import { createPortal } from "react-dom";
import {
  ActivityLogIcon, ArchiveIcon, ArrowLeftIcon, ArrowRightIcon, BackpackIcon, BellIcon,
  CameraIcon, CardStackIcon, ChatBubbleIcon, CheckCircledIcon, ChevronDownIcon, ChevronLeftIcon,
  Cross2Icon, CubeIcon, DownloadIcon, ExclamationTriangleIcon, FilePlusIcon,
  FileTextIcon, GearIcon, GlobeIcon, Half2Icon, HamburgerMenuIcon, HomeIcon, ImageIcon, InfoCircledIcon,
  LockClosedIcon, MagnifyingGlassIcon, MixIcon, MixerHorizontalIcon, MobileIcon, PaperPlaneIcon,
  Pencil1Icon, PersonIcon, PlusIcon, ReaderIcon, ReloadIcon, Share1Icon, SpeakerLoudIcon,
  RulerHorizontalIcon, RulerSquareIcon, StarIcon, SwitchIcon, TableIcon, TrashIcon, TriangleUpIcon, VideoIcon,
} from "@radix-ui/react-icons";
import { BottomSheet, FlowStack, KeyboardInput, MobileScroll, useKeyboard, useScreenPortal, type FlowControls, type FlowScreen } from "./mobile";
import { LiveOdooProvider, LiveOdooGate, useLiveOdoo } from "./liveOdoo";
import { LiveInvoicesPage } from "./LiveInvoices";
import { NasqoDashboard } from "./NasqoDashboard";
import { openNativeOdoo, openOdooWhatsAppStatus, type NativeOdooAction } from "./odooNavigation";
import { ContactSaveError, saveOdooContact } from "./odooContacts";

type IconComponent = typeof HomeIcon;
type SheetKind = "add-operation" | "filters" | "export" | null;
type OverlayKind = "activation" | "account-picker" | "transaction" | "account-create-compact" | "account-create-extended" | "invoice" | null;
type AccountCreateMode = "compact" | "extended";
type ExportKind = "statement" | "inventory" | "purchases";
type InvoiceIntent = "invoice" | "return" | "quote" | "order";
type DrawerTarget = "dashboard" | "purchases" | "settings" | "whatsapp" | "activation" | "shop" | "warehouses" | "inventory-report" | "quotes" | "orders" | "accounts" | "currency";

type AppContext = {
  flowRef: MutableRefObject<FlowControls | null>;
  openDrawer: () => void;
  openSheet: (kind: Exclude<SheetKind, null>) => void;
  openAccountPicker: () => void;
  openAccountEdit: () => void;
  openTransaction: (vendor?: Vendor) => void;
  openAccountCreate: (mode?: AccountCreateMode) => void;
  openInvoice: () => void;
  openVendorInvoice: (vendor: Vendor, intent?: InvoiceIntent) => void;
  openDashboardMenu: () => void;
  openExportMenu: (kind?: ExportKind) => void;
  showToast: (message: string) => void;
  nativeAction: (action: NativeOdooAction) => void;
};

const vendors = [
  { name: "البراري للتوريد", phone: "055 832 1042", limit: "1,000,000", balance: "280,450", tone: "credit", code: "ب" },
  { name: "نقـد هلال", phone: "050 441 7731", limit: "500,000", balance: "0", tone: "neutral", code: "ن" },
  { name: "الواحة التجارية", phone: "053 190 6208", limit: "750,000", balance: "227,601", tone: "credit", code: "و" },
  { name: "خطابي وشركاه", phone: "056 710 8824", limit: "250,000", balance: "64,000", tone: "debit", code: "خ" },
  { name: "بشار العزي", phone: "", limit: "1,000,000", balance: "227,601", tone: "credit", code: "ع" },
  { name: "الشرعبي عبد ربه", phone: "", limit: "1,000,000", balance: "64,000", tone: "credit", code: "ش" },
  { name: "محمد العزي", phone: "", limit: "1,000,000", balance: "112,250", tone: "credit", code: "م" },
  { name: "متجر بن نايف", phone: "", limit: "1,001,000", balance: "71,900", tone: "credit", code: "ن" },
  { name: "علي بابا صنعا", phone: "", limit: "1,000,000", balance: "105,400", tone: "credit", code: "ع" },
  { name: "يوسف عالم الولاعات", phone: "", limit: "1,000,000", balance: "0", tone: "neutral", code: "ي" },
  { name: "لاين فون", phone: "", limit: "100,000", balance: "0", tone: "neutral", code: "ل" },
  { name: "حسين بيلة", phone: "", limit: "1,000,000", balance: "0", tone: "neutral", code: "ح" },
  { name: "مشتريات حسين", phone: "", limit: "1,000,000", balance: "0", tone: "neutral", code: "ح" },
] as const;

type Vendor = { id?: number; name: string; phone: string; limit: string; balance: string; tone: "credit" | "debit" | "neutral"; code: string };

const vendorListMetadata = new Map<Vendor, { count: number; id: number }>(vendors.map((vendor, index) => [vendor, {
  count: [47, 44, 6, 3, 65, 46, 17, 3, 1, 2, 4, 7, 5][index],
  id: [34, 9, 49, 53, 6, 5, 31, 50, 51, 52, 54, 55, 56][index],
}]));

const transactions = [
  { id: "#1178", type: "فاتورة آجلة", amount: "33,000", detail: "عازل سطوح 10 كيلو · 1 كيلو", date: "28 ديسمبر، 12:00 م", balance: "112,250", tone: "credit" },
  { id: "#1136", type: "فاتورة آجلة", amount: "4,000", detail: "زينة منازل شكل شجرة · 1 حبة", date: "26 ديسمبر، 12:00 م", balance: "79,250", tone: "credit" },
  { id: "#1108", type: "عليه", amount: "20,000", detail: "تسوية حساب مورد", date: "25 ديسمبر، 12:00 م", balance: "75,250", tone: "debit" },
  { id: "#998", type: "فاتورة آجلة", amount: "2,500", detail: "ليزر شعر فتلة · 1 حبة", date: "20 ديسمبر، 12:00 م", balance: "95,250", tone: "credit" },
  { id: "#905", type: "فاتورة آجلة", amount: "3,000", detail: "فرامة لحم · 1 حبة", date: "16 ديسمبر، 12:00 م", balance: "92,750", tone: "credit" },
  { id: "#785", type: "عليه", amount: "20,100", detail: "تسوية نقدية للمورد", date: "12 ديسمبر، 12:00 م", balance: "89,750", tone: "debit" },
  { id: "#752", type: "فاتورة آجلة", amount: "3,000", detail: "فرامة لحم · 1 حبة", date: "9 ديسمبر، 12:00 م", balance: "109,850", tone: "credit" },
  { id: "#719", type: "فاتورة آجلة", amount: "3,000", detail: "توريد أدوات مخزنية", date: "7 ديسمبر، 12:00 م", balance: "106,850", tone: "credit" },
] as const;

export default function Prototype() {
  // On the real ERP domain, show NASQO as a responsive browser application.
  // Keep the simulator intact for isolated preview and protected runtime tests.
  useEffect(() => {
    const isERP = window.location.protocol === "https:"
      && window.location.hostname === "erp.indexesstore.com"
      && window.location.pathname.startsWith("/nasqo-mobile");
    if (!isERP) return;
    document.body.classList.add("nasqo-browser-mode");
    return () => document.body.classList.remove("nasqo-browser-mode");
  }, []);

  const [drawerOpen, setDrawerOpen] = useState(false);
  const [sheet, setSheet] = useState<SheetKind>(null);
  const [overlay, setOverlay] = useState<OverlayKind>(null);
  const [pickerMode, setPickerMode] = useState<"statement" | "edit">("statement");
  const [editingAccount, setEditingAccount] = useState<Vendor | undefined>();
  const [transactionVendor, setTransactionVendor] = useState<Vendor>(vendors[0]);
  const [exportMenuOpen, setExportMenuOpen] = useState(false);
  const [exportKind, setExportKind] = useState<ExportKind>("statement");
  const [dashboardMenuOpen, setDashboardMenuOpen] = useState(false);
  const [invoiceSeed, setInvoiceSeed] = useState<{ vendor: Vendor; intent: InvoiceIntent; revision: number }>({ vendor: vendors[0], intent: "invoice", revision: 0 });
  const returnOverlay = useRef<OverlayKind>(null);
  const [toast, setToast] = useState<string | null>(null);
  const flowRef = useRef<FlowControls | null>(null);
  const keyboard = useKeyboard();

  const openSheet = useCallback((kind: Exclude<SheetKind, null>) => setSheet(kind), []);
  const showToast = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(null), 2200);
  }, []);
  const dismissKeyboard = useCallback(() => {
    keyboard.hide();
    const activeElement = document.activeElement;
    if (activeElement instanceof HTMLElement) activeElement.blur();
  }, [keyboard]);
  const openDrawer = useCallback(() => {
    dismissKeyboard();
    setDrawerOpen(true);
  }, [dismissKeyboard]);
  const openAccountPicker = useCallback(() => {
    dismissKeyboard();
    setExportMenuOpen(false);
    setPickerMode("statement");
    setOverlay("account-picker");
  }, [dismissKeyboard]);
  const openAccountEdit = useCallback(() => {
    dismissKeyboard();
    setPickerMode("edit");
    setOverlay("account-picker");
  }, [dismissKeyboard]);
  const openTransaction = useCallback((vendor: Vendor = vendors[0]) => {
    dismissKeyboard();
    setTransactionVendor(vendor);
    setOverlay("transaction");
  }, [dismissKeyboard]);
  const openAccountCreate = useCallback((mode: AccountCreateMode = "compact") => {
    dismissKeyboard();
    setEditingAccount(undefined);
    setOverlay(mode === "extended" ? "account-create-extended" : "account-create-compact");
  }, [dismissKeyboard]);
  const openInvoice = useCallback(() => {
    dismissKeyboard();
    setInvoiceSeed(value => ({ vendor: vendors[0], intent: "invoice", revision: value.revision + 1 }));
    setOverlay("invoice");
  }, [dismissKeyboard]);
  const openVendorInvoice = useCallback((vendor: Vendor, intent: InvoiceIntent = "invoice") => {
    dismissKeyboard();
    setInvoiceSeed(value => ({ vendor, intent, revision: value.revision + 1 }));
    setOverlay("invoice");
  }, [dismissKeyboard]);
  const openDashboardMenu = useCallback(() => {
    dismissKeyboard();
    setDashboardMenuOpen(value => !value);
  }, [dismissKeyboard]);
  const closeOverlay = () => {
    dismissKeyboard();
    setOverlay(returnOverlay.current);
    returnOverlay.current = null;
  };
  const openExportMenu = useCallback((kind: ExportKind = "statement") => {
    dismissKeyboard();
    setExportKind(kind);
    setExportMenuOpen((open) => !open);
  }, [dismissKeyboard]);

  const ctx = useMemo<AppContext>(
    () => ({ flowRef, openDrawer, openSheet, openAccountPicker, openAccountEdit, openTransaction, openAccountCreate, openInvoice, openVendorInvoice, openDashboardMenu, openExportMenu, showToast, nativeAction: openNativeOdoo }),
    [openAccountCreate, openAccountPicker, openAccountEdit, openDrawer, openExportMenu, openInvoice, openVendorInvoice, openDashboardMenu, openSheet, openTransaction, showToast],
  );
  const initial = useMemo(() => dashboardScreen(ctx), [ctx]);

  const navigateFromDrawer = (target: DrawerTarget) => {
    setDrawerOpen(false);
    if (window.location.protocol === "https:" && window.location.hostname === "erp.indexesstore.com" && window.location.pathname.startsWith("/nasqo-mobile")) {
      if (target === "dashboard") flowRef.current?.replace(dashboardScreen(ctx));
      else if (target === "purchases" || target === "shop") flowRef.current?.push(purchasesScreen(ctx));
      else if (target === "warehouses") flowRef.current?.push(warehousesScreen(ctx));
      else if (target === "accounts") openNativeOdoo("chartOfAccounts");
      else if (target === "currency") openNativeOdoo("currencies");
      else if (target === "quotes") openNativeOdoo("quotations");
      else if (target === "orders") openNativeOdoo("salesOrders");
      else if (target === "inventory-report") openNativeOdoo("stockMoves");
      else if (target === "whatsapp") openOdooWhatsAppStatus();
      else if (target === "settings") window.location.assign("/odoo");
      else showToast("هذه الوظيفة غير متصلة بنظام Odoo؛ لم تُنفّذ أي عملية");
      return;
    }
    if (target === "accounts") {
      openAccountPicker();
      return;
    }
    if (target === "currency") {
      flowRef.current?.push(currencyScreen(ctx));
      return;
    }
    if (target === "quotes" || target === "orders") {
      openVendorInvoice(vendors[0], target === "quotes" ? "quote" : "order");
      return;
    }
    if (target === "warehouses" || target === "inventory-report" || target === "shop") {
      flowRef.current?.push(target === "shop" ? shopScreen(ctx) : target === "warehouses" ? warehousesScreen(ctx) : inventoryReportScreen(ctx));
      return;
    }
    if (target === "activation") {
      dismissKeyboard();
      setOverlay("activation");
      return;
    }
    if (target === "purchases") {
      flowRef.current?.push(purchasesScreen(ctx));
      return;
    }
    if (target === "whatsapp") {
      flowRef.current?.push(whatsappSettingsScreen(ctx));
      return;
    }
    showToast(target === "settings" ? "الإعدادات متاحة للمعاينة فقط" : "أنت في لوحة نسقو الرئيسية");
  };

  return (
    <LiveOdooProvider><LiveOdooGate>
    <div className={window.location.protocol === "https:" && window.location.hostname === "erp.indexesstore.com" && window.location.pathname.startsWith("/nasqo-mobile") ? "nasqo-app live-connected" : "nasqo-app"} dir="rtl">
      <FlowStack initial={initial} />
      <AppDrawer open={drawerOpen} onClose={() => setDrawerOpen(false)} onNavigate={navigateFromDrawer} onNotify={showToast} />
      <DashboardAddMenu open={dashboardMenuOpen} onClose={() => setDashboardMenuOpen(false)} ctx={ctx} />
      <ExportSideMenu open={exportMenuOpen} kind={exportKind} onClose={() => setExportMenuOpen(false)} onAction={(message) => { setExportMenuOpen(false); showToast(message); }} />
      <InvoiceModal key={invoiceSeed.revision} vendor={invoiceSeed.vendor} intent={invoiceSeed.intent} open={overlay === "invoice"} onClose={closeOverlay} onNotify={showToast} onAddAccount={() => { returnOverlay.current = "invoice"; openAccountCreate("extended"); }} onDone={(message) => { closeOverlay(); showToast(message); }} />
      <ActivationModal open={overlay === "activation"} onClose={() => setOverlay(null)} onDone={(message) => { setOverlay(null); showToast(message); }} />
      <AccountPickerModal open={overlay === "account-picker"} title={pickerMode === "edit" ? "تعديل بيانات حساب" : "كشف حساب"} onClose={() => setOverlay(null)} onAddAccount={() => openAccountCreate("compact")} onConfirm={(vendor) => { if (pickerMode === "edit") { setEditingAccount(vendor); setOverlay("account-create-compact"); } else { setOverlay(null); flowRef.current?.push(window.location.protocol === "https:" && window.location.hostname === "erp.indexesstore.com" && window.location.pathname.startsWith("/nasqo-mobile/") ? livePartnerScreen(ctx, vendor) : supplierScreen(ctx, vendor)); } }} />
      <TransactionModal open={overlay === "transaction"} vendor={transactionVendor} onClose={() => setOverlay(null)} onNotify={showToast} onDone={(message) => { setOverlay(null); showToast(message); }} />
      <AccountCreateModal key={editingAccount?.name ?? "new-compact"} initialVendor={editingAccount} mode="compact" open={overlay === "account-create-compact"} onClose={() => setOverlay(null)} onNotify={showToast} onDone={(message) => { setOverlay(null); showToast(message); }} />
      <AccountCreateModal mode="extended" open={overlay === "account-create-extended"} onClose={closeOverlay} onNotify={showToast} onDone={(message) => { closeOverlay(); showToast(message); }} />
      <BottomSheet
        open={sheet !== null}
        onOpenChange={(open) => !open && setSheet(null)}
        title={sheetTitle(sheet)}
        description={sheetDescription(sheet)}
        snap={0.6}
      >
        <SheetContent
          kind={sheet}
          ctx={ctx}
          setKind={setSheet}
          onDone={(message) => {
            setSheet(null);
            showToast(message);
          }}
        />
      </BottomSheet>
      {toast ? <div className="app-toast" role="status" aria-live="polite"><CheckCircledIcon /><span>{toast}</span></div> : null}
    </div>
    </LiveOdooGate></LiveOdooProvider>
  );
}

function dashboardScreen(ctx: AppContext): FlowScreen {
  const liveMode = window.location.protocol === "https:" && window.location.hostname === "erp.indexesstore.com" && window.location.pathname.startsWith("/nasqo-mobile");
  return {
    id: "dashboard",
    headerHeight: 50,
    header: () => <AppHeader className="dashboard-header" title="نسقو برو" subtitle="" onMenu={ctx.openDrawer} actions={[
      { label: "بحث", icon: MagnifyingGlassIcon, onClick: () => liveMode ? ctx.nativeAction("contacts") : ctx.showToast("البحث السريع جاهز") },
      { label: "التنبيهات", icon: BellIcon, onClick: () => liveMode ?
        document.getElementById("nasqo-notification-center")?.scrollIntoView({ behavior: "smooth", block: "start" }) :
        ctx.showToast("لديك 3 تنبيهات جديدة") },
      { label: "مزامنة", icon: ReloadIcon, onClick: () => liveMode ? window.location.reload() : ctx.showToast("تم تحديث بيانات النموذج") },
      { label: "إضافة", icon: PlusIcon, onClick: ctx.openDashboardMenu },
    ]} />,
    footerHeight: 28,
    footer: () => <BottomNav ctx={ctx} />,
    render: (flow) => {
      ctx.flowRef.current = flow;
      return <DashboardPage flow={flow} ctx={ctx} />;
    },
  };
}

function purchasesScreen(ctx: AppContext): FlowScreen {
  const liveMode = window.location.protocol === "https:" && window.location.hostname === "erp.indexesstore.com" && window.location.pathname.startsWith("/nasqo-mobile");
  return {
    id: "purchases",
    headerHeight: 58,
    header: (flow) => <AppHeader title={liveMode ? "جهات الاتصال" : "المشتريات"} subtitle="" onBack={flow.pop} actions={[
      { label: "تصفية", icon: MixerHorizontalIcon, onClick: () => liveMode ? ctx.nativeAction("suppliers") : ctx.openSheet("filters") },
      { label: "تصدير المشتريات", icon: DownloadIcon, onClick: () => ctx.openExportMenu("purchases") },
      { label: "بحث", icon: MagnifyingGlassIcon, onClick: () => liveMode ? ctx.nativeAction("contacts") : ctx.showToast("اكتب اسم المورد للبحث") },
    ]} />,
    footerHeight: 54,
    footer: () => liveMode ? <div className="live-readonly-footer">جهات الاتصال من Odoo · لا توجد أرصدة افتراضية</div> : <FinancialFooter debit="8,542,650" credit="11,084,211" balance="2,541,561" />,
    render: (flow) => {
      ctx.flowRef.current = flow;
      return <PurchasesPage flow={flow} ctx={ctx} />;
    },
  };
}

function supplierScreen(ctx: AppContext, vendor: Vendor = vendors[0]): FlowScreen {
  const isCashAccount = vendor === vendors[1];
  const cashMenuControl: MutableRefObject<(() => void) | null> = { current: null };
  const cashSearchControl: MutableRefObject<(() => void) | null> = { current: null };
  return {
    id: "supplier-details",
    headerHeight: 58,
    header: (flow) => <AppHeader title={isCashAccount ? "مشتريات نقد هلال" : vendor.name} subtitle={isCashAccount ? "" : "كشف حساب المورد"} className={isCashAccount ? "cash-statement-header" : ""} onBack={flow.pop} actions={[
      { label: "تصفية", icon: MixerHorizontalIcon, onClick: () => ctx.openSheet("filters") },
      { label: "تصدير", icon: DownloadIcon, onClick: () => ctx.openExportMenu() },
      { label: "بحث", icon: MagnifyingGlassIcon, onClick: () => isCashAccount ? cashSearchControl.current?.() : ctx.showToast("البحث في حركات المورد") },
    ]} />,
    footerHeight: isCashAccount ? 43 : 54,
    footer: () => isCashAccount ? <CashStatementFooter ctx={ctx} vendor={vendor} onMenu={() => cashMenuControl.current?.()} /> : <FinancialFooter debit="70,100" credit="182,350" balance="112,250" compact />,
    render: (flow) => {
      ctx.flowRef.current = flow;
      return isCashAccount ? <CashSupplierPage ctx={ctx} vendor={vendor} menuControl={cashMenuControl} searchControl={cashSearchControl} /> : <SupplierPage ctx={ctx} vendor={vendor} />;
    },
  };
}

function shopScreen(ctx: AppContext): FlowScreen {
  return {
    id: "shop", headerHeight: 58,
    header: (flow) => <AppHeader title="المحل" subtitle="" onBack={flow.pop} actions={[
      { label: "تصفية", icon: MixerHorizontalIcon, onClick: () => ctx.openSheet("filters") },
      { label: "تصدير", icon: DownloadIcon, onClick: () => ctx.openExportMenu() },
      { label: "بحث", icon: MagnifyingGlassIcon, onClick: () => ctx.showToast("اختر الحساب لعرض حركاته") },
    ]} />,
    footerHeight: 54,
    footer: () => <div className="shop-totals"><button aria-label="إضافة حساب من شريط الرصيد" onClick={() => ctx.openAccountCreate("extended")}><PlusIcon /></button><span>عليه: 261,100 · له: 0 · الرصيد عليه: 261,100</span><HamburgerMenuIcon /></div>,
    render: (flow) => { ctx.flowRef.current = flow; return <ShopPage ctx={ctx} />; },
  };
}

function ShopPage({ ctx }: { ctx: AppContext }) {
  const [period, setPeriod] = useState("الكل");
  const [sort, setSort] = useState("تنازلي");
  return <><MobileScroll className="app-screen"><main className="shop-page page-with-footer" data-testid="shop-screen">
    <section className="shop-filters">
      <div className="reference-radio-row">{["يومي", "شهري", "الكل", "سنوي"].map(item => <label key={item}><input type="radio" name="shop-period" checked={period === item} onChange={() => setPeriod(item)} />{item}</label>)}</div>
      <div className="shop-sort"><select aria-label="ترتيب الحسابات"><option>ترتيب حسب التاريخ</option><option>ترتيب حسب الاسم</option></select><div>{["تصاعدي", "تنازلي"].map(item => <label key={item}><input type="radio" name="shop-sort" checked={sort === item} onChange={() => setSort(item)} />{item}</label>)}</div></div>
      <div className="shop-currency"><span>العملة</span><select aria-label="عملة حسابات المحل"><option>ريال</option><option>دولار</option></select><label><input type="checkbox" />حسب العملة</label></div>
      <div className="reference-date-strip"><ArrowRightIcon /><span>من <b>1/1/2026</b></span><span>إلى <b>10/11/2026</b></span><ArrowLeftIcon /></div>
    </section>
    <article className="shop-account-card"><button className="warehouse-icon" aria-label="عرض حساب المحل" onClick={() => ctx.flowRef.current?.push(supplierScreen(ctx))}><MobileIcon /></button><strong>حساب المحل</strong><span>261,100</span><button aria-label="إضافة حساب للمحل" onClick={() => ctx.openAccountCreate("extended")}><PlusIcon /></button></article>
  </main></MobileScroll><button className="fab fixed-fab" aria-label="إنشاء حساب بالمحل" onClick={() => ctx.openAccountCreate("extended")}><PlusIcon /></button></>;
}

const initialWarehouses = [{ id: 4, name: "بينون", details: "", isDefault: false }, { id: 1, name: "المخزن الرئيسي", details: "", isDefault: true }, { id: 3, name: "مخازن بينون", details: "", isDefault: false }];
type Warehouse = (typeof initialWarehouses)[number];

function warehousesScreen(ctx: AppContext): FlowScreen {
  const searchControl: MutableRefObject<(() => void) | null> = { current: null };
  return {
    id: "warehouses", headerHeight: 58,
    header: (flow) => <AppHeader title="المخازن" subtitle="" onBack={flow.pop} actions={[{ label: "بحث في المخازن", icon: MagnifyingGlassIcon, onClick: () => searchControl.current?.() }]} />,
    footerHeight: 26, footer: () => <div className="warehouse-bottom-strip" />,
    render: (flow) => { ctx.flowRef.current = flow; return <WarehousesPage ctx={ctx} searchControl={searchControl} />; },
  };
}

function WarehousesPage({ ctx, searchControl }: { ctx: AppContext; searchControl: MutableRefObject<(() => void) | null> }) {
  const live = useLiveOdoo();
  const [warehouses, setWarehouses] = useState<Warehouse[]>(initialWarehouses);
  const [editing, setEditing] = useState<Warehouse | "new" | null>(null);
  const keyboard = useKeyboard();
  const [searchOpen, setSearchOpen] = useState(false);
  const [search, setSearch] = useState("");
  searchControl.current = () => { keyboard.hide(); setSearchOpen(value => !value); setSearch(""); };
  const open = (warehouse: Warehouse | "new") => { keyboard.hide(); setEditing(warehouse); };
  const close = () => { keyboard.hide(); setEditing(null); };
  const availableWarehouses: Warehouse[] = live.enabled ? live.warehouses.map(w => ({
    id: w.id, name: w.name, details: "", isDefault: false,
  })) : warehouses;
  return <><MobileScroll className="warehouse-scroll"><main className="warehouse-page page-with-footer" data-testid="warehouses-screen">
    {live.enabled ? <p className="live-data-notice">{live.deniedSections.includes("المخازن") ? "المخازن: لا يملك هذا الحساب صلاحية القراءة في Odoo. اطلب من مسؤول النظام مراجعة صلاحيات المخزون." : live.problems.includes("المخازن") ? "تعذر تحميل المخازن من Odoo. حاول تحديث الصفحة." : "مخازن نسقو ERP الفعلية · قراءة فقط"}</p> : null}
    {searchOpen ? <KeyboardInput className="warehouse-search" aria-label="اسم المخزن للبحث" placeholder="ابحث عن المخزن" value={search} onChange={event => setSearch(event.target.value)} /> : null}
    {availableWarehouses.filter(warehouse => warehouse.name.includes(search)).map(warehouse => <article className="warehouse-card" key={warehouse.id}>
      <button className="warehouse-icon" aria-label={`فتح ${warehouse.name}`} onClick={() => live.enabled ? ctx.nativeAction("stockMoves") : ctx.flowRef.current?.push(inventoryReportScreen(ctx, warehouse.name))}><CubeIcon /></button>
      <strong>{warehouse.name}</strong><b>{warehouse.id}</b>
      <div className="warehouse-card-actions"><button aria-label={`تعديل ${warehouse.name}`} onClick={() => live.enabled ? ctx.nativeAction("warehouses") : open(warehouse)}><Pencil1Icon /></button><button aria-label={`تقرير حركة ${warehouse.name}`} onClick={() => live.enabled ? ctx.nativeAction("stockMoves") : ctx.flowRef.current?.push(inventoryReportScreen(ctx, warehouse.name))}><ReaderIcon /></button></div>
    </article>)}
  </main></MobileScroll><button className="fab warehouse-fab" aria-label="إضافة مخزن" onClick={() => live.enabled ? ctx.nativeAction("warehouses") : open("new")}><PlusIcon /></button>
    {editing !== null ? <WarehouseModal key={editing === "new" ? "new" : editing.id} warehouse={editing === "new" ? undefined : editing} onClose={close} onNotify={ctx.showToast} onSave={(value) => {
      setWarehouses(current => {
        const saved = { ...value, id: editing === "new" ? Math.max(...current.map(w => w.id)) + 1 : editing.id };
        const others = current.filter(w => w.id !== saved.id).map(w => value.isDefault ? { ...w, isDefault: false } : w);
        return [...others, saved];
      }); close(); ctx.showToast("تم حفظ المخزن في المعاينة");
    }} /> : null}
  </>;
}

function WarehouseModal({ warehouse, onClose, onSave, onNotify }: { warehouse?: Warehouse; onClose: () => void; onSave: (value: Omit<Warehouse, "id">) => void; onNotify: (message: string) => void }) {
  const { screenRef } = useScreenPortal();
  const [name, setName] = useState(warehouse?.name ?? "");
  const [details, setDetails] = useState(warehouse?.details ?? "");
  const [isDefault, setIsDefault] = useState(warehouse?.isDefault ?? false);
  const [error, setError] = useState(false);
  const target = screenRef.current?.querySelector(".nasqo-app");
  if (!target) return null;
  return createPortal(<div className="center-modal-layer" data-testid="warehouse-modal"><button className="center-modal-backdrop" aria-label="إغلاق المخزن" onClick={onClose} /><section className="warehouse-modal" role="dialog" aria-modal="true" aria-labelledby="warehouse-title">
    <h2 id="warehouse-title">{warehouse ? "تعديل المخزن" : "مخزن جديد"}</h2>
    <KeyboardInput aria-label="اسم المخزن" placeholder="أدخل الاسم" value={name} onChange={event => { setName(event.target.value); setError(false); }} aria-invalid={error} />
    <KeyboardInput aria-label="تفاصيل المخزن" placeholder="تفاصيل" value={details} onChange={event => setDetails(event.target.value)} />
    <label className="warehouse-default"><span>اعتماد هذا المخزن كافتراضي</span><input className="nasqo-switch" type="checkbox" role="switch" checked={isDefault} onChange={event => setIsDefault(event.target.checked)} /></label>
    {error ? <p className="form-error" role="alert">أدخل اسم المخزن أولًا</p> : null}
    <div className="form-modal-actions"><button className="cancel" onClick={onClose}>إلغاء</button><button className="form-help" onClick={() => onNotify("أدخل اسم المخزن وتفاصيله ثم اختر حفظ")}><VideoIcon />شرح</button><button className="save" onClick={() => name.trim() ? onSave({ name: name.trim(), details, isDefault }) : setError(true)}>حفظ</button></div>
  </section></div>, target);
}

const inventoryItems = ["ابجورة شكل قمر", "استشوار جوي", "استشوار ونستب", "إضاءة قنديل البحر", "إضاءة معلق مغناطيس", "إضاءة نيو 5 متر", "إضاءة نيو حبل", "إضاءة شلال", "أم بي ثري أندرويد", "أم بي ثري حرف ج", "أم بي ثري ديسكو أسود", "أم بي ثري طويل", "بخاخ تلميع كفرات", "بخاخ سيارة", "بخاخ مزيل الدهون"];

function inventoryReportScreen(ctx: AppContext, warehouse = "مخازن بينون"): FlowScreen {
  return {
    id: "inventory-report", headerHeight: 58,
    header: (flow) => <AppHeader title="تقرير حركة المخزون" subtitle="" onBack={flow.pop} actions={[{ label: "تصدير", icon: DownloadIcon, onClick: () => ctx.openExportMenu("inventory") }]} />,
    footerHeight: 70, footer: () => <div className="inventory-totals"><div>بيع: <b>0</b>　 شراء: <b>0</b>　 ربح: <b>0</b></div><div>عدد المتبقي: <b>522.5</b>　 القيمة: <b>2,151,260</b></div></div>,
    render: (flow) => { ctx.flowRef.current = flow; return <InventoryReportPage warehouse={warehouse} />; },
  };
}

function InventoryReportPage({ warehouse }: { warehouse: string }) {
  const [period, setPeriod] = useState("الكل");
  const [selectedWarehouse, setWarehouse] = useState(warehouse);
  return <MobileScroll className="inventory-report-scroll"><main className="inventory-report-page" data-testid="inventory-report-screen">
    <section className="inventory-filters">
      <label className="inventory-select"><span>المخزن</span><select aria-label="المخزن" value={selectedWarehouse} onChange={event => setWarehouse(event.target.value)}>{Array.from(new Set([...initialWarehouses.map(w => w.name), warehouse])).map(name => <option key={name}>{name}</option>)}</select></label>
      <div className="reference-radio-row">{["يومي", "شهري", "الكل"].map(item => <label key={item}><input type="radio" name="inventory-period" checked={period === item} onChange={() => setPeriod(item)} />{item}</label>)}</div>
      <select className="profit-select" aria-label="حساب الأرباح حسب"><option>حساب الأرباح حسب: متوسط سعر الشراء</option><option>حساب الأرباح حسب: آخر سعر شراء</option></select>
      <div className="reference-date-strip"><ArrowRightIcon /><span>من <b>1/1/2026</b></span><span>إلى <b>10/11/2026</b></span><ArrowLeftIcon /></div>
    </section>
    <table className="inventory-table"><thead><tr><th scope="col">الصنف</th><th scope="col">الوحدة</th><th scope="col">كمية الشراء</th></tr></thead><tbody>{inventoryItems.map(item => <tr key={item}><td>{item}</td><td>حبة</td><td>0</td></tr>)}</tbody></table>
  </main></MobileScroll>;
}

function InvoiceModal({ open, vendor, intent, onClose, onAddAccount, onDone, onNotify }: { open: boolean; vendor: Vendor; intent: InvoiceIntent; onClose: () => void; onAddAccount: () => void; onDone: (message: string) => void; onNotify: (message: string) => void }) {
  const live = useLiveOdoo();
  const [content, setContent] = useState("items");
  const [payment, setPayment] = useState(vendor === vendors[1] ? "cash" : "credit");
  const [kind, setKind] = useState(vendor === vendors[1] ? "purchase" : "sale");
  const [isReturn, setReturn] = useState(intent === "return");
  const [search, setSearch] = useState("");
  const [note, setNote] = useState("");
  const [account, setAccount] = useState(vendor.name as string);
  const now = useMemo(() => new Intl.DateTimeFormat("ar", { weekday: "short", hour: "2-digit", minute: "2-digit" }).format(new Date()), []);
  if (!open) return null;
  return <div className="center-modal-layer" data-testid="invoice-modal"><button className="center-modal-backdrop" aria-label="إغلاق الفاتورة" onClick={onClose} /><section className="invoice-modal" role="dialog" aria-modal="true" aria-labelledby="invoice-title">
    <h2 id="invoice-title">{intent === "quote" ? "عرض سعر" : intent === "order" ? "طلبية جديدة" : isReturn ? "مردود جديد" : "فاتورة جديدة"}</h2>
    <div className="invoice-top-row"><time>{now}<br />{new Date().toLocaleDateString("en-GB")}</time><button aria-label="إعدادات الفاتورة" onClick={() => onNotify("حدد نوع الفاتورة وطريقة الدفع من الخيارات أدناه")}><GearIcon /></button></div>
    <div className="invoice-radio-bar"><div>{[["items", "أصناف"], ["free", "حرة"]].map(([value, label]) => <label key={value}><input type="radio" name="invoice-content" checked={content === value} onChange={() => setContent(value)} />{label}</label>)}</div><div>{[["cash", "نقدي"], ["credit", "آجل"]].map(([value, label]) => <label className={value === "cash" ? "green" : "red"} key={value}><input type="radio" name="invoice-payment" checked={payment === value} onChange={() => setPayment(value)} />{label}</label>)}</div></div>
    <div className="invoice-radio-bar invoice-kind-bar"><label className="green"><input type="radio" name="invoice-kind" checked={kind === "purchase"} onChange={() => setKind("purchase")} />فاتورة شراء</label><label className="red"><input type="radio" name="invoice-kind" checked={kind === "sale"} onChange={() => setKind("sale")} />فاتورة بيع</label><button aria-pressed={isReturn} onClick={() => setReturn(value => !value)}>{isReturn ? "فاتورة جديدة" : "مردود جديد"}</button></div>
    <div className="invoice-search"><KeyboardInput aria-label="البحث عن حساب الفاتورة" placeholder="ابحث عن الاسم هنا" value={search} onChange={event => setSearch(event.target.value)} /><button aria-label="مسح بحث الفاتورة" onClick={() => setSearch("")}><Cross2Icon /></button></div>
    <span className="invoice-helper">أو حدد الحساب من هنا</span>
    <div className="invoice-account"><button aria-label="إضافة حساب للفاتورة" onClick={onAddAccount}><PlusIcon /></button><select aria-label="حساب الفاتورة" value={live.enabled && !live.partners.some(p => p.name === account) ? live.partners[0]?.name ?? "" : account} onChange={event => setAccount(event.target.value)}>{live.enabled ? live.partners.filter(p => !search || p.name.includes(search) || p.name === account).map(p => <option key={p.id} value={p.name}>{p.name}</option>) : vendors.filter(v => !search || v.name.includes(search) || v.name === account).map(v => <option key={v.name}>{v.name}</option>)}</select></div>
    <div className="invoice-currency"><label><span>العملة</span><select aria-label="عملة الفاتورة"><option>ريال</option><option>دولار</option></select></label><label><span>سعر الصرف</span><KeyboardInput aria-label="سعر صرف الفاتورة" inputMode="decimal" defaultValue="1" /></label></div>
    <label className="invoice-warehouse"><span>المخزن</span><select aria-label="مخزن الفاتورة">{(live.enabled ? live.warehouses : initialWarehouses).map(w => <option key={w.id}>{w.name}</option>)}</select></label>
    <div className="invoice-note"><button aria-label="صورة بيان الفاتورة" onClick={() => onNotify("إرفاق الصور متاح في النسخة المتصلة")}><CameraIcon /></button><KeyboardInput aria-label="بيان الفاتورة" placeholder="اكتب البيان" value={note} onChange={event => setNote(event.target.value)} /><button aria-label="بيان الفاتورة صوتيًا" onClick={() => onNotify("الإدخال الصوتي للمعاينة فقط")}><SpeakerLoudIcon /></button></div>
    <div className="form-modal-actions"><button className="cancel" onClick={onClose}>إلغاء</button><button className="form-help" onClick={() => onNotify("اختر الحساب والمخزن ثم اضغط عمل فاتورة")}><VideoIcon />شرح</button><button className="save" onClick={() => {
    if (live.enabled) {
      const target: NativeOdooAction = intent === "quote" ? "quotations" :
        intent === "order" ? (kind === "purchase" ? "purchaseOrders" : "salesOrders") :
        isReturn ? (kind === "purchase" ? "vendorRefunds" : "customerRefunds") :
        (kind === "purchase" ? "vendorBills" : "customerInvoices");
      if (window.confirm("سيُفتح النموذج الأصلي في Odoo لإكمال الأصناف والضرائب والصلاحيات. لم تُنشأ أي فاتورة بعد.")) openNativeOdoo(target);
      return;
    }
    onDone("تم تجهيز فاتورة تجريبية");
  }}>عمل فاتورة</button></div>
  </section></div>;
}

function currencyScreen(ctx: AppContext, vendor: Vendor = vendors[0]): FlowScreen {
  return {
    id: "currency-exchange",
    headerHeight: 58,
    header: (flow) => <SimpleAppHeader title="صرف عملات" onBack={flow.pop} />,
    render: (flow) => {
      ctx.flowRef.current = flow;
      return <CurrencyPage ctx={ctx} flow={flow} vendor={vendor} />;
    },
  };
}

function simpleEntryScreen(ctx: AppContext, toVendor: Vendor = vendors[1]): FlowScreen {
  return {
    id: "simple-entry",
    headerHeight: 58,
    header: (flow) => <div className="simple-entry-header"><SimpleAppHeader title="قيد بسيط" onBack={flow.pop} /></div>,
    render: (flow) => {
      ctx.flowRef.current = flow;
      return <SimpleEntryPage ctx={ctx} flow={flow} toVendor={toVendor} />;
    },
  };
}

function whatsappSettingsScreen(ctx: AppContext): FlowScreen {
  return {
    id: "whatsapp-settings",
    headerHeight: 0,
    render: (flow) => {
      ctx.flowRef.current = flow;
      return <WhatsAppSettingsPage ctx={ctx} flow={flow} />;
    },
  };
}

function AppHeader({ title, subtitle, onBack, onMenu, actions, className = "" }: {
  title: string;
  subtitle: string;
  onBack?: () => void;
  onMenu?: () => void;
  className?: string;
  actions: { label: string; icon: IconComponent; badge?: string; onClick: () => void }[];
}) {
  return <div className={`app-header ${className}`}>
    <button className="header-icon header-leading" onClick={onBack ?? onMenu} aria-label={onBack ? "رجوع" : "فتح القائمة"}>{onBack ? <ArrowRightIcon /> : <HamburgerMenuIcon />}</button>
    <div className="header-brand"><span className="brand-mark" aria-hidden="true"><CubeIcon /></span><span className="header-copy"><strong>{title}</strong>{subtitle ? <small>{subtitle}</small> : null}</span></div>
    <div className="header-actions">{actions.map((action) => <button key={action.label} className="header-icon" onClick={action.onClick} aria-label={action.label}><action.icon />{action.badge ? <span className="notification-badge">{action.badge}</span> : null}</button>)}</div>
  </div>;
}

function SimpleAppHeader({ title, onBack }: { title: string; onBack: () => void }) {
  return <div className="app-header simple-app-header"><button className="header-icon" onClick={onBack} aria-label="رجوع"><ArrowRightIcon /></button><strong>{title}</strong></div>;
}

function TransferArrowsIcon() {
  return <span className="transfer-arrows-icon" aria-hidden="true"><ArrowRightIcon /><ArrowLeftIcon /></span>;
}

function DashboardPage({ flow, ctx }: { flow: FlowControls; ctx: AppContext }) {
  const live = useLiveOdoo();
  const quickActions: { label: string; icon: IconComponent; action: () => void; accent?: boolean }[] = [
    { label: "سند جديد", icon: FilePlusIcon, action: () => ctx.openTransaction() },
    { label: "حوالة جديدة", icon: PaperPlaneIcon, action: () => ctx.openSheet("add-operation") },
    { label: "كشف حساب", icon: ReaderIcon, action: ctx.openAccountPicker },
    { label: "قيد بسيط", icon: MixIcon, action: () => flow.push(simpleEntryScreen(ctx)), accent: true },
    { label: "الحركة اليومية", icon: ActivityLogIcon, action: () => ctx.showToast("تم تحديث الحركة اليومية"), accent: true },
    { label: "صناديق النقدية", icon: BackpackIcon, action: () => ctx.showToast("عرض أرصدة الصناديق في المعاينة"), accent: true },
    { label: "فاتورة جديدة", icon: FileTextIcon, action: ctx.openInvoice },
    { label: "صرف عملات", icon: ReloadIcon, action: () => flow.push(currencyScreen(ctx)) },
    { label: "البحث السريع", icon: MagnifyingGlassIcon, action: () => flow.push(purchasesScreen(ctx)) },
  ];
  const metrics: { label: string; value?: string; icon: IconComponent; tone?: "credit" | "debit"; action?: () => void }[] = [
    { label: "المبيعات", value: "−172,650", icon: PersonIcon, tone: "debit" },
    { label: "المشتريات", value: "−2,541,561", icon: PersonIcon, tone: "credit", action: () => flow.push(purchasesScreen(ctx)) },
    { label: "العملاء", value: "0", icon: PersonIcon, tone: "debit", action: () => flow.push(shopScreen(ctx)) },
    { label: "الموظفين", value: "−10,500", icon: PersonIcon, tone: "credit" },
    { label: "الحوالات", value: "0", icon: PersonIcon, tone: "debit", action: () => ctx.openSheet("add-operation") },
    { label: "المحل", value: "−261,100", icon: PersonIcon, tone: "debit", action: () => flow.push(shopScreen(ctx)) },
    { label: "تمييز ومقاسات", icon: RulerHorizontalIcon },
    { label: "مقاس جديد", icon: RulerSquareIcon },
  ];

  // The nine quick actions and eight metric cards keep their original labels,
  // order, and styling. Live finance actions open Odoo's own ACL-protected forms.
  const liveQuickTargets: NativeOdooAction[] = [
    "payments", "internalPayments", "partnerLedger", "journalEntries", "journalEntries",
    "cashRegisters", "customerInvoices", "currencies", "contacts",
  ];
  const displayActions = live.enabled ? quickActions.map((item, index) => ({
    ...item, action: () => index === 6 ? ctx.openInvoice() :
      index === 8 ? flow.push(purchasesScreen(ctx)) : ctx.nativeAction(liveQuickTargets[index]),
  })) : quickActions;
  const liveMetricTargets: NativeOdooAction[] = [
    "customerInvoices", "vendorBills", "customers", "employees",
    "internalPayments", "pos", "productVariants", "productVariants",
  ];
  const displayMetrics = live.enabled ? metrics.map((metric, index) => ({
    ...metric, value: metric.value === undefined ? undefined : "—",
    action: () => ctx.nativeAction(liveMetricTargets[index]),
  })) : metrics;
  return <><MobileScroll className="app-screen dashboard-scroll">
    <main className="dashboard-page page-with-footer" data-testid="dashboard-screen">
      {live.enabled ? <p className="live-data-notice">متصل بنسقو ERP · بيانات حقيقية وصلاحيات Odoo {live.problems.length ? "· " + live.problems.map(section => live.deniedSections.includes(section) ? section + ": لا تملك صلاحية القراءة في Odoo" : "تعذر تحميل: " + section).join("، ") : ""}</p> : null}
      {live.enabled ? <NasqoDashboard
        newInvoice={ctx.openInvoice}
        newPurchase={() => ctx.nativeAction("purchaseOrders")}
        newContact={() => ctx.openAccountCreate("compact")}
        openInvoices={() => flow.push(liveInvoicesScreen(ctx))}
        openStock={() => ctx.nativeAction("stockMoves")}
        openContact={id => {
          const partner = live.partners.find(item => item.id === id);
          if (partner) flow.push(liveInvoicesScreen(ctx, { id: partner.id, name: partner.name }));
          else ctx.showToast("هذه الجهة غير متاحة ضمن صلاحياتك الحالية.");
        }}
      /> : null}
      <section className="section-block quick-section"><div className="quick-grid">{displayActions.map((item) => <button key={item.label} className={item.accent ? "quick-action accent" : "quick-action"} onClick={item.action}><item.icon /><span>{item.label}</span></button>)}</div></section>
      {!live.enabled ? <section className="section-block metrics-section"><div className="metrics-grid">{displayMetrics.map((metric) => <button key={metric.label} className={`metric-card ${metric.tone ?? "measurement"}`} onClick={metric.action ?? (() => ctx.showToast(`${metric.label} متاح للمعاينة فقط`))}><span className="metric-icon"><metric.icon /></span><span className="metric-copy"><small>{metric.label}</small>{metric.value ? <strong>{metric.value}</strong> : null}</span></button>)}</div></section> : null}
    </main>
  </MobileScroll><button className="fab dashboard-fab" onClick={() => ctx.openSheet("add-operation")} aria-label="إضافة عملية"><PlusIcon /></button></>;
}

function liveInvoicesScreen(ctx: AppContext, partner?: Pick<Vendor, "id" | "name">): FlowScreen {
  return {
    id: partner ? "real-partner-" + partner.id : "real-invoices",
    headerHeight: 50,
    header: (flow) => <AppHeader
      title={partner ? "فواتير " + partner.name : "الفواتير الحقيقية"} subtitle=""
      onBack={flow.pop} actions={[]}
    />,
    render: (flow) => {
      ctx.flowRef.current = flow;
      return <LiveInvoicesPage partnerId={partner?.id} />;
    },
  };
}

function livePartnerScreen(ctx: AppContext, partner: Vendor): FlowScreen {
  return liveInvoicesScreen(ctx, partner);
}

function PurchasesPage({ flow, ctx }: { flow: FlowControls; ctx: AppContext }) {
  const live = useLiveOdoo();
  const [period, setPeriod] = useState("الكل");
  const [sortDirection, setSortDirection] = useState("تنازلي");
  const [sortBy, setSortBy] = useState("date");
  const [byCurrency, setByCurrency] = useState(false);
  const [createMenuOpen, setCreateMenuOpen] = useState(false);
  const [operationVendor, setOperationVendor] = useState<Vendor | null>(null);
  const keyboard = useKeyboard();
  const { screenRef } = useScreenPortal();
  const periods = ["يومي", "شهري", "الكل", "سنوي"];
  const createActions: { label: string; action: () => void }[] = [
    { label: "سند جديد", action: () => ctx.openTransaction() },
    { label: "فاتورة جديدة", action: ctx.openInvoice },
    { label: "مردود جديد", action: () => ctx.showToast("تم تجهيز مردود تجريبي") },
    { label: "حوالة جديدة", action: () => ctx.openSheet("add-operation") },
    { label: "صرف عملات", action: () => flow.push(currencyScreen(ctx)) },
    { label: "عرض سعر", action: () => ctx.showToast("تم تجهيز عرض سعر تجريبي") },
    { label: "طلبية جديدة", action: () => ctx.showToast("تم تجهيز طلبية تجريبية") },
    { label: "إضافة تنبيه سداد", action: () => ctx.showToast("تمت إضافة تنبيه تجريبي") },
  ];
  const createTargets: NativeOdooAction[] = [
    "payments", "customerInvoices", "customerRefunds", "internalPayments",
    "currencies", "quotations", "salesOrders", "payments",
  ];
  const runCreateAction = (action: () => void, index: number) => {
    keyboard.hide();
    setCreateMenuOpen(false);
    if (live.enabled) ctx.nativeAction(createTargets[index]);
    else action();
  };
  const openVendorMenu = (vendor: Vendor) => {
    keyboard.hide();
    setCreateMenuOpen(false);
    setOperationVendor(vendor);
  };
  const contextActions = operationVendor ? [
    { label: "فاتورة جديدة", action: () => ctx.openVendorInvoice(operationVendor) },
    { label: "مردود جديد", action: () => ctx.openVendorInvoice(operationVendor, "return") },
    { label: "حوالة جديدة", action: () => { ctx.openTransaction(operationVendor); ctx.showToast(`حوالة تجريبية لحساب ${operationVendor.name}`); } },
    { label: "صرف عملات", action: () => flow.push(currencyScreen(ctx, operationVendor)) },
    { label: "عرض سعر", action: () => ctx.openVendorInvoice(operationVendor, "quote") },
    { label: "طلبية جديدة", action: () => ctx.openVendorInvoice(operationVendor, "order") },
  ] : [];
  const portal = screenRef.current?.querySelector(".nasqo-app");
  const vendorOperationTargets: NativeOdooAction[] = [
    "vendorBills", "vendorRefunds", "payments", "currencies", "purchaseRFQs", "purchaseOrders",
  ];
  const availableVendors: Vendor[] = live.enabled ? live.partners.map(partner => ({
    id: partner.id, name: partner.name, phone: partner.phone || "", limit: "—",
    balance: "—", tone: "neutral", code: partner.name[0] || "؟",
  })) : [...vendors];
  const orderedVendors = sortBy === "name"
    ? [...availableVendors].sort((a, b) => a.name.localeCompare(b.name, "ar"))
    : [...availableVendors];
  const visibleVendors = sortDirection === "تنازلي" ? orderedVendors : orderedVendors.reverse();

  return <div className="purchases-layout">
    <section className="purchases-filter-panel" data-testid="purchases-filter-panel">
      {live.enabled ? <p className="live-data-notice">جهات الاتصال من نسقو ERP · قراءة فقط · الأرصدة ليست معروضة</p> : null}
      <div className="purchases-periods" role="group" aria-label="الفترة">{periods.map(item => <button key={item} aria-pressed={period === item} onClick={() => setPeriod(item)}><span className="period-radio-mark" />{item}</button>)}</div>
      <div className="purchases-sort-row"><select aria-label="ترتيب المشتريات" value={sortBy} onChange={event => setSortBy(event.target.value)}><option value="date">ترتيب حسب التاريخ</option><option value="name">ترتيب حسب الاسم</option></select><div>{["تصاعدي", "تنازلي"].map(item => <button key={item} aria-pressed={sortDirection === item} onClick={() => setSortDirection(item)}><span className="period-radio-mark" />{item}</button>)}</div></div>
      <div className="purchases-currency-row"><span>العملة</span><select aria-label="عملة المشتريات"><option>ريال</option><option>دولار</option></select><label><input type="checkbox" checked={byCurrency} onChange={event => setByCurrency(event.target.checked)} />حسب العملة</label></div>
      <div className="reference-date-strip"><button aria-label="تاريخ بداية المشتريات" onClick={() => ctx.openSheet("filters")}><ArrowRightIcon /></button><span>من <b>1/1/2026</b></span><span>إلى <b>10/11/2026</b></span><button aria-label="تاريخ نهاية المشتريات" onClick={() => ctx.openSheet("filters")}><ArrowLeftIcon /></button></div>
    </section>
    <MobileScroll className="app-screen purchases-list-scroll">
      <main className="purchases-page page-with-footer" data-testid="purchases-screen">
        <section className="vendor-list">{visibleVendors.map(vendor => <article key={vendor.name} className="vendor-card" data-vendor-id={vendor.id ?? vendorListMetadata.get(vendor)?.id}>
          <button className="vendor-call" aria-label={`اتصال بـ ${vendor.name}`} onClick={() => {
      if (live.enabled && vendor.phone && /^\+?[0-9 ()-]{5,25}$/.test(vendor.phone)) window.location.href = "tel:" + vendor.phone.replace(/[^\d+]/g, "");
      else ctx.showToast(live.enabled ? "رقم الهاتف غير متاح لهذا الحساب" : "معاينة اتصال فقط — لم يتم إجراء مكالمة");
    }}><MobileIcon /></button>
          <button className="vendor-open" onClick={() => flow.push(live.enabled ? livePartnerScreen(ctx, vendor) : supplierScreen(ctx, vendor))} aria-label={`فتح كشف ${vendor.name}`}>
            <span className="vendor-main"><strong>{vendor.name}</strong><small>{live.enabled ? "جهة اتصال فعلية" : "سقف المديونية: " + vendor.limit}</small>{vendor.phone ? <em className={vendor === vendors[1] ? "cash-vendor-phone" : undefined}>{vendor.phone}</em> : null}</span>
            <span className={`vendor-balance ${vendor.tone}`}><strong>{vendor.balance}{!live.enabled && vendor.tone === "credit" ? "-" : ""}</strong></span>
          </button>
          <span className="vendor-actions" role="group" aria-label={`إجراءات ${vendor.name}`}>
            <button aria-label={`تعديل ${vendor.name}`} onClick={() => live.enabled ? ctx.nativeAction("contacts") : ctx.openAccountCreate("compact")}><Pencil1Icon /></button>
            <button aria-label={`رسالة إلى ${vendor.name}`} onClick={() => live.enabled ? ctx.showToast("الإرسال المباشر يتطلب خدمة مراسلة موثقة؛ لم تُرسل رسالة") : ctx.showToast("معاينة فقط — لم يتم إرسال أي رسالة")}><ChatBubbleIcon /></button>
            <button className="vendor-operation-add" aria-label={`عمليات ${vendor.name}`} onClick={() => openVendorMenu(vendor)}><PlusIcon /></button>
            <button className="vendor-count" aria-label={`عرض حركات ${vendor.name}`} onClick={() => flow.push(live.enabled ? livePartnerScreen(ctx, vendor) : supplierScreen(ctx, vendor))}>{live.enabled ? live.problems.includes("الفواتير") ? "—" : live.invoices.filter(i => Array.isArray(i.partner_id) && i.partner_id[0] === vendor.id).length : vendorListMetadata.get(vendor)?.count}</button>
            <span className="vendor-code">{vendor.id ?? vendorListMetadata.get(vendor)?.id}</span>
          </span>
        </article>)}</section>
      </main>
    </MobileScroll>
    {createMenuOpen ? <div className="purchase-create-menu" data-testid="purchase-create-menu" role="menu" aria-label="قائمة إنشاء عملية">{createActions.map((item) => <button key={item.label} role="menuitem" onClick={() => runCreateAction(item.action, createActions.indexOf(item))}>{item.label}</button>)}</div> : null}
    <button className="fab fixed-fab" onClick={() => { keyboard.hide(); setCreateMenuOpen((open) => !open); }} aria-label="إضافة مورد أو عملية" aria-expanded={createMenuOpen}><PlusIcon /></button>
    {operationVendor && portal ? createPortal(<div className="vendor-menu-layer" data-testid="vendor-operations-menu"><button className="context-menu-backdrop" aria-label="إغلاق عمليات المورد" onClick={() => setOperationVendor(null)} /><aside className="vendor-operations-menu" role="menu" aria-label={`عمليات ${operationVendor.name}`}>{contextActions.map((item, index) => <button role="menuitem" key={item.label} onClick={() => {
      setOperationVendor(null);
      if (live.enabled) ctx.nativeAction(vendorOperationTargets[index]);
      else item.action();
    }}>{item.label}</button>)}</aside></div>, portal) : null}
  </div>;
}

function SupplierPage({ ctx, vendor }: { ctx: AppContext; vendor: Vendor }) {
  const [period, setPeriod] = useState("الكل");
  const [showPreviousBalance, setShowPreviousBalance] = useState(false);
  const periods = ["شهري", "الكل", "سنوي"];

  return <MobileScroll className="app-screen">
    <main className="supplier-page page-with-footer" data-testid="supplier-screen">
      <section className="statement-controls"><button className="select-box currency-select" onClick={() => ctx.openSheet("filters")}><span>العملة</span><strong>ريال سعودي</strong><ChevronDownIcon /></button><div className="statement-options"><div className="period-tabs compact" role="group" aria-label="فترة كشف الحساب">{periods.map((item) => <button key={item} className={period === item ? "selected" : ""} aria-pressed={period === item} onClick={() => setPeriod(item)}>{item}</button>)}</div><label className="previous-balance"><input type="checkbox" checked={showPreviousBalance} onChange={(event) => setShowPreviousBalance(event.target.checked)} /> رصيد سابق</label></div><div className="statement-date"><button aria-label="الفترة التالية" onClick={() => ctx.openSheet("filters")}><ArrowRightIcon /></button><span>من <strong>7 نوفمبر</strong></span><span>إلى <strong>28 ديسمبر</strong></span><button aria-label="الفترة السابقة" onClick={() => ctx.openSheet("filters")}><ChevronLeftIcon /></button></div></section>
      <div className="table-heading"><span>العملية</span><span>المبلغ</span><span>التفاصيل</span><span>الرصيد</span></div>
      <section className="transactions-list">{transactions.map((item) => <article key={item.id} className="transaction-card"><div className="transaction-grid"><span className={`transaction-type ${item.tone}`}>{item.type}</span><strong className={`transaction-amount ${item.tone}`}>{item.amount}</strong><span className="transaction-detail"><b>{item.detail}</b><time>{item.date}</time><em>{item.id}</em></span><span className="transaction-balance">{item.balance}-</span></div><div className="transaction-actions"><button aria-label={`تعديل ${item.id}`} onClick={() => ctx.openTransaction(vendor)}><Pencil1Icon /></button><button aria-label={`ملف PDF للعملية ${item.id}`} onClick={() => ctx.showToast(`تم تجهيز ${item.id} بصيغة PDF`)}><FileTextIcon /></button><button aria-label={`مشاركة ${item.id}`} onClick={() => ctx.showToast("المشاركة التجريبية جاهزة — لم يتم إرسال شيء")}><Share1Icon /></button></div></article>)}</section>
    </main>
    <button className="fab" onClick={() => ctx.openTransaction(vendor)} aria-label="إضافة سند"><PlusIcon /></button>
  </MobileScroll>;
}

const cashStatementRows = [
  { id: "1218", amount: "20,000", detail: ["محلات بن عوضة", "مكينة خياطة كبير | 2 حبة"], date: "29/12/2025" },
  { id: "1140", amount: "3,000", detail: ["توصيلة تايب سي 2 متر | 1 حبة", "بطارية جهاز كشف الذهب | 1 حبة"], date: "26/12/2025", tall: true },
  { id: "1090", amount: "17,000", detail: ["فواحة عطرية خازن | 5 حبة"], date: "24/12/2025" },
  { id: "1058", amount: "4,900", detail: ["حامل جوال مغناطيس | 1 حبة", "نظارة مع سماعة | 1 حبة"], date: "23/12/2025", tall: true },
  { id: "1057", amount: "1,500", detail: ["تسوية", "محلول مجاري 500 جرام | 1 حبة"], date: "23/12/2025" },
  { id: "1056", amount: "1,000", detail: ["تسوية ناقص", "محلول انسداد مجاري | 1 حبة"], date: "23/12/2025" },
  { id: "607", amount: "—", detail: ["تفاصيل حركة سابقة"], date: "3/12/2025" },
  { id: "588", amount: "8,000", detail: ["كيب ستور", "سخان فوري | 1 حبة"], date: "3/12/2025" },
  { id: "508", amount: "19,000", detail: ["مكينة خياطة كبير | 2 حبة"], date: "29/11/2025" },
  { id: "471", amount: "3,000", detail: ["دفاية سمكة | 1 حبة"], date: "27/11/2025" },
  { id: "431", amount: "40,000", detail: ["طربال سيارة مقاس مترين | 2 حبة"], date: "25/11/2025" },
  { id: "390", amount: "12,500", detail: ["حزام ركبة الأصفر | 5 حبة", "مساج الأقدام أسود | 5 حبة", "مساج رقبة | 1 حبة"], date: "23/11/2025", long: true },
  { id: "375", amount: "4,500", detail: ["حقيبة خصر ملون | 5 حبة"], date: "23/11/2025" },
  { id: "362", amount: "40,000", detail: ["مساج رقبة | 5 حبة"], date: "22/11/2025" },
  { id: "341", amount: "43,000", detail: ["منشار جلخ طاولة | 2 حبة"], date: "22/11/2025" },
  { id: "—", amount: "3,500", detail: ["أم بي ثري ديسكو أسود | 1 حبة"], date: "" },
  { id: "16", amount: "—", detail: ["ساعة أكسسوار", "ساعة رولكس", "منظف أسنان", "رأس عصا", "فسفوري | 1 حبة", "ليد كور سيارة", "مغناطيس", "غمازات", "متر ليزر | 1 حبة", "قلم إزالة خدوش", "قفاقي سيليكون", "شريط شنط", "ورق طابعة حراري | 0.5 حبة", "تحويلة جلخ | 1 حبة", "شدات أكياس حراري | 2 حبة", "صفارة شكمان سيارة | 2 حبة", "فواحة مع أمبيثري | 1 حبة", "تبخيرة أكسجين الأصلي | 1 حبة", "ثلاجة إنسولين | 1 حبة", "طائرة ألعاب ملون | 2 حبة", "ستارة سيارة سحب | 5 حبة", "كشاف يامو 3000 متر | 4 حبة", "عصارة فواكه | 1 حبة", "مفتاح تربو الأصلي | 1 حبة", "لاصق باب سيارة تايوتا | 2 حبة", "كرت لاصق تايوتا | 10 حبة", "جهاز مساج فراشة | 1 حبة", "بخاخ تنظيف كراسي | 2 حبة"], date: "7/11/2025", expanded: true },
] as const;

const cashCurrencyOptions = ["ريال", "عملة 2", "دولار", "جميع العملات بدون مصارفة", "مصارفة الكل بعملة ريال"] as const;
const cashSearchOptions = ["الكل", "الرقم", "البيان", "رقم المستند", "اسم المرسل", "اسم المستلم", "اسم الشركة", "المبلغ عليه", "المبلغ له"] as const;
type CashSearchMode = (typeof cashSearchOptions)[number];

function cashRowMatches(row: (typeof cashStatementRows)[number], query: string, mode: CashSearchMode) {
  const normalize = (text: string) => text.replace(/[أإآ]/g, "ا").replace(/[ـ,٬]/g, "").replace(/[٠-٩]/g, digit => String("٠١٢٣٤٥٦٧٨٩".indexOf(digit))).toLocaleLowerCase().trim();
  const fields: Record<Exclude<CashSearchMode, "الكل">, string> = {
    "الرقم": row.id, "البيان": row.detail.join(" "), "رقم المستند": "", "اسم المرسل": "",
    "اسم المستلم": "مشتريات نقد هلال", "اسم الشركة": "نسقو برو", "المبلغ عليه": row.amount, "المبلغ له": row.amount,
  };
  const needle = normalize(query);
  if (!needle) return true;
  if (mode === "المبلغ عليه" || mode === "المبلغ له") return fields[mode].replace(/[,٬]/g, "").includes(needle.replace(/[,٬]/g, ""));
  return normalize(mode === "الكل" ? [...Object.values(fields), row.date].join(" ") : fields[mode]).includes(needle);
}

function CashStatementFooter({ ctx, vendor, onMenu }: { ctx: AppContext; vendor: Vendor; onMenu: () => void }) {
  return <div className="cash-statement-footer" data-testid="cash-statement-footer">
    <button aria-label="تحويل الرصيد" onClick={() => ctx.flowRef.current?.push(simpleEntryScreen(ctx, vendor))}><TransferArrowsIcon /></button>
    <div><span>عليه: <bdi>1,168,310</bdi></span><span>له: <bdi>1,168,310</bdi></span><span>الرصيد عليه: <bdi className="cash-statement-total-balance">0</bdi></span></div>
    <button aria-label="خيارات الرصيد" onClick={onMenu}><HamburgerMenuIcon /></button>
  </div>;
}

function CashSupplierPage({ ctx, vendor, menuControl, searchControl }: { ctx: AppContext; vendor: Vendor; menuControl: MutableRefObject<(() => void) | null>; searchControl: MutableRefObject<(() => void) | null> }) {
  const [period, setPeriod] = useState("الكل");
  const [currency, setCurrency] = useState("ريال");
  const [showPreviousBalance, setShowPreviousBalance] = useState(false);
  const [operationsOpen, setOperationsOpen] = useState(false);
  const [currencyOpen, setCurrencyOpen] = useState(false);
  const [searchMenuOpen, setSearchMenuOpen] = useState(false);
  const [searchMode, setSearchMode] = useState<CashSearchMode>("الكل");
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState("");
  const listRef = useRef<HTMLElement>(null);
  const keyboard = useKeyboard();
  const { screenRef } = useScreenPortal();
  menuControl.current = () => { keyboard.hide(); setCurrencyOpen(false); setSearchMenuOpen(false); setOperationsOpen(open => !open); };
  searchControl.current = () => { keyboard.hide(); setCurrencyOpen(false); setOperationsOpen(false); setSearchMenuOpen(open => !open); };
  useEffect(() => { listRef.current?.closest(".mobile-scroll")?.scrollTo({ top: 0 }); }, [query, currency, searchMode]);
  const rows = cashStatementRows.filter(item => !["عملة 2", "دولار"].includes(currency) && cashRowMatches(item, query, searchMode));
  const searchPortal = screenRef.current?.querySelector(".nasqo-app");
  const startDate = period === "شهري" ? "1/12/2025" : period === "سنوي" ? "1/1/2025" : "7/11/2025";
  return <div className={`cash-statement-layout${searchOpen ? " cash-search-active" : ""}`} data-testid="cash-statement-screen">
    <section className="cash-statement-filters" data-testid="cash-statement-filters">
      <div className="cash-statement-currency"><span>العملة</span><button aria-label="عملة كشف المشتريات النقدية" data-testid="cash-currency-trigger" aria-haspopup="listbox" aria-expanded={currencyOpen} className={currency.length > 10 ? "long-label" : ""} onClick={() => { keyboard.hide(); setSearchMenuOpen(false); setOperationsOpen(false); setCurrencyOpen(open => !open); }}><span>{currency}</span><ChevronDownIcon /></button></div>
      <div className="cash-statement-options" role="group" aria-label="فترة كشف المشتريات النقدية">{["شهري", "الكل"].map(item => <button key={item} aria-pressed={period === item} onClick={() => setPeriod(item)}><span className="period-radio-mark" />{item}</button>)}<label><input type="checkbox" checked={showPreviousBalance} onChange={event => setShowPreviousBalance(event.target.checked)} />رصيد سابق</label><button aria-pressed={period === "سنوي"} onClick={() => setPeriod("سنوي")}><span className="period-radio-mark" />سنوي</button><button className="cash-statement-filter-button" aria-label="تصفية كشف المشتريات النقدية" onClick={() => ctx.openSheet("filters")}><MixerHorizontalIcon /></button></div>
      <div className="cash-statement-date-strip"><button aria-label="بداية فترة المشتريات النقدية" onClick={() => ctx.openSheet("filters")}><ArrowRightIcon /></button><span>من <bdi>{startDate}</bdi></span><span>إلى <bdi>29/12/2025</bdi></span><button aria-label="نهاية فترة المشتريات النقدية" onClick={() => ctx.openSheet("filters")}><ArrowLeftIcon /></button></div>
    </section>
    {searchOpen ? <div className="cash-search-form"><label><span>البحث بواسطة {searchMode}</span><KeyboardInput data-testid="cash-search-input" aria-label={`البحث بواسطة ${searchMode}`} placeholder="اكتب للبحث في الحركات" value={query} onChange={event => setQuery(event.target.value)} onBlur={() => keyboard.hide()} onKeyDown={event => { if (event.key === "Enter") { keyboard.hide(); event.currentTarget.blur(); } }} /></label><button data-testid="cash-search-clear" aria-label="مسح بحث الحركات" onClick={() => { keyboard.hide(); setQuery(""); }}><Cross2Icon /></button><button data-testid="cash-search-close" onClick={() => { keyboard.hide(); setSearchOpen(false); setQuery(""); setSearchMode("الكل"); }}>إغلاق</button></div> : null}
    <div className="cash-statement-table-heading"><span>النوع</span><span>المبلغ</span><span>التفاصيل</span><span>الرصيد</span></div>
    <MobileScroll className="cash-statement-scroll"><main ref={listRef} data-testid="supplier-screen" className="cash-statement-list">
      {currency === "مصارفة الكل بعملة ريال" ? <p className="cash-preview-note" role="status">كل الحركات التجريبية بالريال؛ لم يطبّق سعر صرف.</p> : null}
      {rows.length === 0 ? <p className="cash-empty" role="status">{["عملة 2", "دولار"].includes(currency) ? "لا توجد حركات تجريبية بهذه العملة." : "لا توجد حركات تطابق البحث."}</p> : null}
      {showPreviousBalance ? <div className="cash-statement-previous" role="status"><span>رصيد سابق</span><bdi>0</bdi></div> : null}
      {rows.map(item => <article className={`cash-statement-row${"tall" in item && item.tall ? " tall" : ""}${"long" in item && item.long ? " long" : ""}${"expanded" in item && item.expanded ? " expanded" : ""}`} key={item.id} data-transaction-id={item.id}>
        <div className="cash-statement-row-main"><span className="cash-statement-type">ف.ش.نقدي</span><strong className="cash-statement-amount">{item.amount}</strong><div className="cash-statement-detail">{item.detail.map(line => <span key={line}>{line}</span>)}</div><bdi className="cash-statement-balance">0</bdi></div>
        <div className="cash-statement-row-bottom"><time dateTime={item.date ? `${item.date.split("/").reverse().map(part => part.padStart(2, "0")).join("-")}T00:00:00` : undefined}>{item.date ? `${item.date} 12:00 AM` : "—"}</time><span className="cash-statement-id">{item.id}</span><div className="cash-statement-actions"><button aria-label={`تعديل #${item.id}`} onClick={() => ctx.openTransaction(vendor)}><Pencil1Icon /></button><button className="cash-statement-pdf" aria-label={`ملف PDF للعملية #${item.id}`} onClick={event => { if (item.id === "1140") { event.currentTarget.blur(); ctx.flowRef.current?.push(cashInvoicePreviewScreen(ctx, item.id)); } else ctx.showToast("معاينة PDF — لم يتم إنشاء ملف"); }}><FileTextIcon /></button><button aria-label={`مشاركة #${item.id}`} onClick={() => ctx.showToast("معاينة المشاركة — لم يتم إرسال شيء")}><Share1Icon /></button></div></div>
      </article>)}
    </main></MobileScroll>
    <button className="fab cash-statement-fab" aria-label="إضافة سند" onClick={() => ctx.openTransaction(vendor)}><PlusIcon /></button>
    {currencyOpen ? <div className="cash-currency-layer"><button className="context-menu-backdrop" aria-label="إغلاق قائمة العملات" onClick={() => setCurrencyOpen(false)} /><div className="cash-currency-menu" data-testid="cash-currency-menu" role="listbox" aria-label="عملات الكشف">{cashCurrencyOptions.map(option => <button role="option" aria-selected={currency === option} key={option} onClick={() => { setCurrency(option); setCurrencyOpen(false); }}>{option}</button>)}</div></div> : null}
    {searchMenuOpen && searchPortal ? createPortal(<div className="cash-search-menu-layer"><button className="context-menu-backdrop" aria-label="إغلاق خيارات البحث" onClick={() => setSearchMenuOpen(false)} /><aside className="cash-search-menu" data-testid="cash-search-menu" role="menu" aria-label="خيارات البحث في الحركات">{cashSearchOptions.map(mode => <button role="menuitem" key={mode} onClick={() => { setSearchMode(mode); setQuery(""); setSearchOpen(true); setSearchMenuOpen(false); }}>البحث بواسطة {mode}</button>)}</aside></div>, searchPortal) : null}
    {operationsOpen ? <CashOperationsMenu ctx={ctx} vendor={vendor} onClose={() => setOperationsOpen(false)} /> : null}
  </div>;
}

function CashOperationsMenu({ ctx, vendor, onClose }: { ctx: AppContext; vendor: Vendor; onClose: () => void }) {
  const { screenRef } = useScreenPortal();
  const target = screenRef.current?.querySelector(".nasqo-app");
  if (!target) return null;
  const actions = [
    { label: "فاتورة جديدة", action: () => ctx.openVendorInvoice(vendor) },
    { label: "مردود جديد", action: () => ctx.openVendorInvoice(vendor, "return") },
    { label: "حوالة جديدة", action: () => { ctx.openTransaction(vendor); ctx.showToast(`حوالة تجريبية لحساب ${vendor.name}`); } },
    { label: "صرف عملات", action: () => ctx.flowRef.current?.push(currencyScreen(ctx, vendor)) },
    { label: "عرض سعر", action: () => ctx.openVendorInvoice(vendor, "quote") },
    { label: "طلبية جديدة", action: () => ctx.openVendorInvoice(vendor, "order") },
  ];
  return createPortal(<div className="vendor-menu-layer"><button className="context-menu-backdrop" aria-label="إغلاق عمليات المشتريات النقدية" onClick={onClose} /><aside className="vendor-operations-menu cash-operations-menu" data-testid="cash-operations-menu" role="menu" aria-label="عمليات مشتريات نقد هلال">{actions.map(item => <button role="menuitem" key={item.label} onClick={() => { onClose(); item.action(); }}>{item.label}</button>)}</aside></div>, target);
}

function SimpleEntryPage({ ctx, flow, toVendor }: { ctx: AppContext; flow: FlowControls; toVendor: Vendor }) {
  const keyboard = useKeyboard();
  const [fromAccount, setFromAccount] = useState<string>(vendors[0].name);
  const [toAccount, setToAccount] = useState<string>(toVendor.name);
  const [fromSearch, setFromSearch] = useState("");
  const [toSearch, setToSearch] = useState("");
  const [amount, setAmount] = useState("");
  const [currency, setCurrency] = useState("ريال");
  const [note, setNote] = useState("");
  const [documentNumber, setDocumentNumber] = useState("");
  const [error, setError] = useState("");
  const [previewReady, setPreviewReady] = useState(false);
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const accountLabel = (name: string) => name === vendors[1].name ? "مشتريات نقد هلال" : name;
  const normalizeSearch = (value: string) => value.replace(/ـ/g, "").trim();
  const matchesSearch = (vendor: Vendor, query: string) => normalizeSearch(`${accountLabel(vendor.name)} ${vendor.name}`).includes(normalizeSearch(query));
  const fromOptions = vendors.filter(vendor => matchesSearch(vendor, fromSearch));
  const toOptions = vendors.filter(vendor => matchesSearch(vendor, toSearch));
  const resetFeedback = () => { setError(""); setPreviewReady(false); };
  const changeSearch = (side: "from" | "to", value: string) => {
    resetFeedback();
    const current = vendors.find(vendor => vendor.name === (side === "from" ? fromAccount : toAccount));
    if (side === "from") {
      setFromSearch(value);
      if (current && !matchesSearch(current, value)) setFromAccount("");
    } else {
      setToSearch(value);
      if (current && !matchesSearch(current, value)) setToAccount("");
    }
  };
  const clearAccount = (side: "from" | "to") => {
    resetFeedback();
    if (side === "from") { setFromSearch(""); setFromAccount(""); }
    else { setToSearch(""); setToAccount(""); }
  };
  const swapAccounts = () => {
    keyboard.hide();
    resetFeedback();
    setFromAccount(toAccount); setToAccount(fromAccount);
    setFromSearch(toSearch); setToSearch(fromSearch);
  };
  const previewEntry = () => {
    keyboard.hide();
    setPreviewReady(false);
    const numericAmount = Number(amount.replace(/[٠-٩]/g, digit => String("٠١٢٣٤٥٦٧٨٩".indexOf(digit))).replace(/[۰-۹]/g, digit => String("۰۱۲۳۴۵۶۷۸۹".indexOf(digit))).replace(/[,٬\s]/g, "").replace(/٫/g, "."));
    if (!vendors.some(vendor => vendor.name === fromAccount) || !vendors.some(vendor => vendor.name === toAccount)) {
      setError("اختر حساب المصدر وحساب الوجهة أولًا.");
    } else if (fromAccount === toAccount) {
      setError("اختر حسابين مختلفين للقيد.");
    } else if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      setError("أدخل مبلغًا أكبر من صفر.");
    } else {
      setError("");
      setPreviewReady(true);
    }
  };

  return <MobileScroll className="app-screen simple-entry-scroll">
    <main className="simple-entry-page" data-testid="simple-entry-screen" onBlur={event => {
      const nextTarget = event.relatedTarget;
      const nextIsTextField = nextTarget instanceof HTMLTextAreaElement || (nextTarget instanceof HTMLInputElement && ["text", "search", "tel", "url", "email", "password", "number"].includes(nextTarget.type));
      if (event.target instanceof HTMLInputElement && !(nextIsTextField && event.currentTarget.contains(nextTarget))) keyboard.hide();
    }}>
      <time className="simple-entry-time" dateTime={now.toISOString()}><span>{now.toLocaleDateString("ar-SA", { weekday: "long" })}</span> <bdi>{now.toLocaleDateString("en-GB")} {now.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", hour12: true })}</bdi></time>
      <section className="simple-entry-account-group">
        <div className="simple-entry-search from-search"><KeyboardInput data-testid="simple-entry-from-search" aria-label="البحث عن حساب المصدر" placeholder="من حساب (ابحث عن الاسم هنا)" value={fromSearch} onChange={event => changeSearch("from", event.target.value)} /><button className="simple-entry-clear" data-testid="simple-entry-from-clear" aria-label="مسح حساب المصدر" onClick={() => clearAccount("from")}><Cross2Icon /></button></div>
        <label className="simple-entry-account-label" htmlFor="simple-entry-from-account">أو حدد الحساب من هنا</label>
        <select id="simple-entry-from-account" data-testid="simple-entry-from-account" className="simple-entry-account-select" aria-label="حساب المصدر" value={fromAccount} onChange={event => { setFromAccount(event.target.value); setFromSearch(""); resetFeedback(); }}>
          <option value="">{fromOptions.length ? "اختر الحساب" : "لا توجد حسابات مطابقة"}</option>
          {fromOptions.map(vendor => <option key={vendor.name} value={vendor.name}>{accountLabel(vendor.name)}</option>)}
        </select>
        <div className="simple-entry-balance">الرصيد له: <bdi>0</bdi></div>
      </section>
      <section className="simple-entry-account-group">
        <div className="simple-entry-search to-search"><button className="simple-entry-swap" data-testid="simple-entry-swap" aria-label="تبديل حساب المصدر والوجهة" onClick={swapAccounts}><TransferArrowsIcon /></button><label><span>إلى حساب (ابحث عن الاسم هنا)</span><KeyboardInput data-testid="simple-entry-to-search" aria-label="البحث عن حساب الوجهة" placeholder={accountLabel(toAccount) || "ابحث عن الاسم هنا"} value={toSearch} onChange={event => changeSearch("to", event.target.value)} /></label><button className="simple-entry-clear" data-testid="simple-entry-to-clear" aria-label="مسح حساب الوجهة" onClick={() => clearAccount("to")}><Cross2Icon /></button></div>
        <label className="simple-entry-account-label" htmlFor="simple-entry-to-account">أو حدد الحساب من هنا</label>
        <select id="simple-entry-to-account" data-testid="simple-entry-to-account" className="simple-entry-account-select" aria-label="حساب الوجهة" value={toAccount} onChange={event => { setToAccount(event.target.value); setToSearch(""); resetFeedback(); }}>
          <option value="">{toOptions.length ? "اختر الحساب" : "لا توجد حسابات مطابقة"}</option>
          {toOptions.map(vendor => <option key={vendor.name} value={vendor.name}>{accountLabel(vendor.name)}</option>)}
        </select>
        <div className="simple-entry-balance">الرصيد له: <bdi>0</bdi></div>
      </section>
      <div className="simple-entry-amount-row">
        <button className="simple-entry-demo-icon" aria-label="آلة حاسبة للمبلغ" onClick={() => { keyboard.hide(); ctx.showToast("الآلة الحاسبة للمعاينة فقط — أدخل المبلغ في الحقل"); }}><TableIcon /></button>
        <label className="simple-entry-amount-field"><span>أدخل المبلغ</span><KeyboardInput data-testid="simple-entry-amount" aria-label="مبلغ القيد" inputMode="decimal" value={amount} onChange={event => { setAmount(event.target.value); resetFeedback(); }} /></label>
        <button className="simple-entry-demo-icon voice" aria-label="إدخال مبلغ القيد صوتيًا" onClick={() => { keyboard.hide(); ctx.showToast("الإدخال الصوتي للمعاينة فقط"); }}><SpeakerLoudIcon /></button>
        <select className="simple-entry-currency" aria-label="عملة القيد" value={currency} onChange={event => { setCurrency(event.target.value); resetFeedback(); }}><option value="ريال">ر.س</option><option value="دولار">$</option></select>
      </div>
      <div className="simple-entry-amount-caption">{amount ? `${amount} ${currency}` : `صفر ${currency}`}</div>
      <div className="simple-entry-note-row"><button className="simple-entry-demo-icon" aria-label="صورة بيان القيد" onClick={() => { keyboard.hide(); ctx.showToast("إرفاق الصور للمعاينة فقط — لم يُفتح أي ملف"); }}><CameraIcon /></button><KeyboardInput data-testid="simple-entry-note" aria-label="بيان القيد" placeholder="اكتب البيان" value={note} onChange={event => { setNote(event.target.value); resetFeedback(); }} /><button className="simple-entry-demo-icon voice" aria-label="إدخال بيان القيد صوتيًا" onClick={() => { keyboard.hide(); ctx.showToast("الإدخال الصوتي للمعاينة فقط"); }}><SpeakerLoudIcon /></button></div>
      <KeyboardInput className="simple-entry-document" data-testid="simple-entry-document" aria-label="رقم مستند القيد" placeholder="رقم المستند" value={documentNumber} onChange={event => { setDocumentNumber(event.target.value); resetFeedback(); }} />
      {error ? <p className="simple-entry-feedback error" role="alert">{error}</p> : null}
      {previewReady ? <p className="simple-entry-feedback success" role="status">معاينة فقط — لم يُحفظ القيد ولم تتغير أي أرصدة.</p> : null}
      <div className="simple-entry-actions"><button className="save" data-testid="simple-entry-save" onClick={previewEntry}>حفظ</button><button className="cancel" data-testid="simple-entry-cancel" onClick={flow.pop}>إلغاء</button></div>
    </main>
  </MobileScroll>;
}

function CurrencyPage({ ctx, flow, vendor }: { ctx: AppContext; flow: FlowControls; vendor: Vendor }) {
  const [search, setSearch] = useState("");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [mode, setMode] = useState<"buy" | "sell">("buy");
  const [settlement, setSettlement] = useState<"account" | "cash">("account");
  const currentTime = useMemo(() => new Intl.DateTimeFormat("ar-SA", { hour: "2-digit", minute: "2-digit" }).format(new Date()), []);

  return <MobileScroll className="app-screen currency-page-scroll">
    <main className="currency-page" data-testid="currency-screen">
      <time className="currency-time">اليوم · {currentTime}</time>
      <section className="currency-workspace">
        <div className="currency-search-field"><button aria-label="مسح البحث" onClick={() => setSearch("")}><Cross2Icon /></button><label htmlFor="currency-search"><span>ابحث عن الاسم هنا</span><KeyboardInput id="currency-search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="ابحث عن الاسم هنا" /></label></div>
        <p className="currency-helper">أو حدد الحساب من هنا</p>
        <div className="currency-account-row"><button className="currency-account-add" data-testid="currency-account-add" aria-label="إضافة حساب للصرف" onClick={() => ctx.openAccountCreate("extended")}><PlusIcon /></button><button className="currency-account-select" onClick={() => ctx.showToast("قائمة الحسابات التجريبية جاهزة")}><span>{vendor.name}</span><ChevronDownIcon /></button></div>
        <div className="exchange-rate-card"><span><small>من</small><strong>—</strong></span><ChevronDownIcon /><span className="rate-value"><small>سعر الصرف</small><strong>1</strong></span></div>
        <div className="currency-entry"><TableIcon /><label htmlFor="currency-amount"><span>أدخل المبلغ</span><KeyboardInput id="currency-amount" data-testid="currency-amount" inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0" /></label><button aria-label="إدخال صوتي للمبلغ" onClick={() => ctx.showToast("الإدخال الصوتي للمعاينة فقط")}><SpeakerLoudIcon /></button><em>صفر ريال</em></div>
        <div className="exchange-rate-card"><span><small>إلى</small><strong>—</strong></span><ChevronDownIcon /><span className="rate-value"><small>سعر الصرف</small><strong>1</strong></span></div>
        <div className="currency-result"><small>المبلغ المقابل</small><strong>{amount || "0"}</strong><em>صفر ريال</em></div>
        <div className="currency-entry note-entry"><CameraIcon /><label htmlFor="currency-note"><KeyboardInput id="currency-note" value={note} onChange={(event) => setNote(event.target.value)} placeholder="اكتب البيان" /></label><button aria-label="إدخال صوتي للبيان" onClick={() => ctx.showToast("الإدخال الصوتي للمعاينة فقط")}><SpeakerLoudIcon /></button></div>
        <div className="inline-radio-group" aria-label="نوع صرف العملات"><label className={mode === "buy" ? "selected green" : "green"}><input type="radio" name="currency-mode" checked={mode === "buy"} onChange={() => setMode("buy")} /> شراء</label><label className={mode === "sell" ? "selected red" : "red"}><input type="radio" name="currency-mode" checked={mode === "sell"} onChange={() => setMode("sell")} /> بيع</label></div>
        <div className="inline-radio-group settlement-group" aria-label="طريقة المصادقة"><label className={settlement === "account" ? "selected" : ""}><input type="radio" name="settlement" checked={settlement === "account"} onChange={() => setSettlement("account")} /> مصادقة في حساب عميل</label><label className={settlement === "cash" ? "selected" : ""}><input type="radio" name="settlement" checked={settlement === "cash"} onChange={() => setSettlement("cash")} /> مصادقة نقدية في الصندوق</label></div>
        <div className="form-modal-actions currency-actions"><button className="cancel" onClick={flow.pop}>إلغاء</button><button className="form-help" onClick={() => ctx.showToast("شرح صرف العملات متاح للمعاينة")}><VideoIcon /> شرح</button><button className="save" data-testid="currency-save" onClick={() => { flow.pop(); ctx.showToast("تم حفظ عملية صرف تجريبية"); }}>حفظ</button></div>
      </section>
    </main>
  </MobileScroll>;
}

function WhatsAppSettingsPage({ ctx, flow }: { ctx: AppContext; flow: FlowControls }) {
  const [provider, setProvider] = useState<"nasqo" | "external">("nasqo");
  const [instantEnabled, setInstantEnabled] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");

  return <MobileScroll className="whatsapp-settings-scroll">
    <main className="whatsapp-settings-page" data-testid="whatsapp-settings-screen">
      <button className="whatsapp-back" aria-label="رجوع" onClick={flow.pop}><ArrowLeftIcon /></button>
      <section className="whatsapp-brand"><span><MobileIcon /></span><strong>نسقو برو</strong><small>إدارة إشعارات واتساب</small></section>
      <section className="whatsapp-settings-card">
        <h2><ChatBubbleIcon /> إعدادات إشعارات الواتساب</h2>
        <div className="provider-choice" role="group" aria-label="مزود خدمة واتساب"><button aria-pressed={provider === "external"} onClick={() => setProvider("external")}><span className="radio-dot" /> خدمة خارجية</button><button aria-pressed={provider === "nasqo"} onClick={() => setProvider("nasqo")}><span className="radio-dot" /> نسقو برو</button></div>
        <label className="settings-toggle"><span>تفعيل نظام الرسائل الفورية عبر الواتساب</span><input type="checkbox" checked={instantEnabled} onChange={(event) => setInstantEnabled(event.target.checked)} /></label>
        <label className="settings-input" htmlFor="whatsapp-phone"><PersonIcon /><KeyboardInput id="whatsapp-phone" data-testid="whatsapp-phone" inputMode="tel" value={phone} onChange={(event) => setPhone(event.target.value)} placeholder="أدخل رقم الهاتف" />{!phone ? <ExclamationTriangleIcon className="warning-icon" /> : null}</label>
        <label className="settings-input" htmlFor="whatsapp-password"><LockClosedIcon /><KeyboardInput id="whatsapp-password" data-testid="whatsapp-password" type={showPassword ? "text" : "password"} value={password} onChange={(event) => setPassword(event.target.value)} placeholder="أدخل كلمة المرور" /></label>
        <label className="show-password"><input type="checkbox" checked={showPassword} onChange={(event) => setShowPassword(event.target.checked)} /> عرض كلمة المرور</label>
        <button className="whatsapp-save" data-testid="whatsapp-save" onClick={() => ctx.showToast("تم حفظ المعاينة فقط — لم تُرسل بيانات اتصال")}>حفظ الاتصال بهذا الحساب</button>
        <p className="whatsapp-contact">إذا لم يكن لديك حساب من قبل <button onClick={() => ctx.showToast("قناة التواصل للمعاينة فقط")}>تواصل معنا</button></p>
        <div className="account-info"><h3><InfoCircledIcon /> معلومات الحساب</h3><p><span>وجود حساب:</span><strong>نسخة تجريبية</strong></p><p><span>ارتباط الحساب بالواتساب:</span><strong>غير مرتبط</strong></p><p><span>إرسال الرسائل:</span><strong>متوقف</strong></p></div>
      </section>
    </main>
  </MobileScroll>;
}

function BottomNav({ ctx }: { ctx: AppContext }) {
  const live = useLiveOdoo();
  return <nav className="dashboard-footer" aria-label="روابط نسقو"><div><button aria-label="موقع نسقو" onClick={() => live.enabled ? window.location.assign("/nasqo") : ctx.showToast("رابط نسقو في المعاينة")}><GlobeIcon /></button><button aria-label="واتساب" onClick={() => live.enabled ? openOdooWhatsAppStatus() : ctx.flowRef.current?.push(whatsappSettingsScreen(ctx))}><ChatBubbleIcon /></button></div><span>رقم الإصدار: <bdi>0.1.0</bdi></span><div><button aria-label="شرح الاستخدام" onClick={() => live.enabled ? window.location.assign("/odoo") : ctx.showToast("شرح الاستخدام متاح للمعاينة فقط")}><VideoIcon /></button><button aria-label="قناة نسقو" onClick={() => live.enabled ? window.location.assign("/nasqo") : ctx.showToast("قناة نسقو في المعاينة")}><PaperPlaneIcon /></button></div></nav>;
}

function FinancialFooter({ debit, credit, balance, compact = false }: { debit: string; credit: string; balance: string; compact?: boolean }) {
  return <div className={compact ? "financial-footer compact with-balance" : "financial-footer with-balance"}><button className="footer-primary-action" aria-label={compact ? "تحويل الرصيد" : "إضافة عملية"} onClick={() => {
  if (window.location.pathname.startsWith("/nasqo-mobile/")) openNativeOdoo(compact ? "internalPayments" : "payments");
  else window.alert("هذه الوظيفة للمعاينة فقط");
}}>{compact ? <SwitchIcon /> : <PlusIcon />}</button><div><span>عليه</span><strong>{debit}</strong></div><div><span>له</span><strong>{credit}</strong></div><div><span>الرصيد له</span><strong>{balance}</strong></div><button className="footer-menu" aria-label="خيارات الرصيد" onClick={() => {
  if (window.location.pathname.startsWith("/nasqo-mobile/")) openNativeOdoo("partnerLedger");
  else window.alert("خيارات الرصيد للمعاينة فقط");
}}><HamburgerMenuIcon /></button></div>;
}

function AppDrawer({ open, onClose, onNavigate, onNotify }: { open: boolean; onClose: () => void; onNavigate: (target: DrawerTarget) => void; onNotify: (message: string) => void }) {
  const live = useLiveOdoo();
  const liveMenuTargets: Record<string, NativeOdooAction> = {
    "التحويلات المخزنية": "internalStockTransfers",
    "الأصناف": "products",
    "استيراد الأصناف من إكسل": "products",
    "دليل الحسابات": "chartOfAccounts",
    "العملات": "currencies",
    "استيراد الحسابات من ملف إكسل": "chartOfAccounts",
  };
  const filesPreviewNotice = "معاينة فقط — لم تُنسخ أو تُرفع أو تُستعد أي ملفات";
  const sections: { title?: string; notice?: string; items: { label: string; ariaLabel?: string; icon: IconComponent; target?: DrawerTarget }[] }[] = [
    { items: [
      { label: "اللغة ومظهر التطبيق", icon: Half2Icon }, { label: "الإشعارات", icon: BellIcon },
      { label: "الرسائل الفورية SMS", icon: ChatBubbleIcon }, { label: "الرسائل الفورية واتساب", icon: MobileIcon, target: "whatsapp" },
      { label: "التقارير", icon: ReaderIcon, target: "inventory-report" }, { label: "عروض الأسعار", icon: FileTextIcon, target: "quotes" },
      { label: "الطلبيات", icon: FilePlusIcon, target: "orders" }, { label: "سلة المحذوفات", icon: TrashIcon }, { label: "الإعدادات", icon: GearIcon, target: "settings" },
    ] },
    { title: "المخازن", items: [
      { label: "المخازن", icon: CubeIcon, target: "warehouses" }, { label: "التحويلات المخزنية", icon: ReloadIcon },
      { label: "الأصناف", icon: BackpackIcon, target: "inventory-report" }, { label: "استيراد الأصناف من إكسل", icon: TableIcon },
    ] },
    { title: "الحسابات", items: [
      { label: "دليل الحسابات", icon: ReaderIcon, target: "accounts" }, { label: "العملات", icon: CardStackIcon, target: "currency" },
      { label: "استيراد الحسابات من ملف إكسل", icon: TableIcon },
    ] },
    { title: "النسخ الاحتياطي", notice: filesPreviewNotice, items: [
      { label: "حفظ نسخة احتياطية على الهاتف", icon: ArchiveIcon }, { label: "حفظ نسخة احتياطية على التليجرام", icon: PaperPlaneIcon },
      { label: "مشاركة نسخة احتياطية", icon: Share1Icon }, { label: "استعادة نسخة احتياطية", icon: ArchiveIcon },
    ] },
    { title: "جوجل درايف", notice: filesPreviewNotice, items: [
      { label: "جوجل درايف", icon: TriangleUpIcon }, { label: "إعدادات جوجل درايف", icon: GearIcon },
      { label: "استعادة نسخة احتياطية من جوجل درايف", icon: ArchiveIcon },
    ] },
    { title: "ملفات الصور المرفقة", notice: filesPreviewNotice, items: [
      { label: "نسخ مجلد الصور إلى جوجل درايف", icon: TriangleUpIcon }, { label: "مشاركة مجلد الصور", icon: Share1Icon },
      { label: "استعادة نسخة احتياطية للصور", icon: ImageIcon }, { label: "استعادة الصور من جوجل درايف", icon: ArchiveIcon },
    ] },
    { title: "أخرى", items: [
      { label: "معالجة الأخطاء", icon: ExclamationTriangleIcon }, { label: "تفعيل التطبيق", ariaLabel: "التفعيل", icon: LockClosedIcon, target: "activation" },
      { label: "مقترحات", icon: ChatBubbleIcon },
    ] },
    { title: "عن التطبيق", items: [
      { label: "شرح عن التطبيق على اليوتيوب", icon: VideoIcon }, { label: "شروط الخدمة", icon: LockClosedIcon },
      { label: "سياسة الخصوصية", icon: LockClosedIcon }, { label: "تواصل معنا", icon: MobileIcon },
      { label: "تحديث التطبيق", icon: DownloadIcon }, { label: "مشاركة التطبيق", icon: Share1Icon },
      { label: "عن التطبيق", icon: InfoCircledIcon }, { label: "قيم التطبيق", icon: StarIcon },
    ] },
  ];
  return <div className={open ? "drawer-layer open" : "drawer-layer"} aria-hidden={!open}><button className="drawer-backdrop" onClick={onClose} aria-label="إغلاق القائمة" /><button className="drawer-toolbar-close" onClick={onClose} aria-label="إغلاق"><ArrowRightIcon /></button><aside className="app-drawer" aria-label="قائمة نسقو">{open ? <MobileScroll className="drawer-scroll"><div className="drawer-brand-hero"><span className="drawer-hero-mark"><CubeIcon /></span><strong>نسقو برو</strong><small>نظام إدارة الأعمال الذكي</small></div><div className="drawer-sections">{sections.map((section, index) => <section key={section.title ?? index}>{section.title ? <h3>{section.title}</h3> : null}{section.items.map((item) => <button key={item.label} aria-label={item.ariaLabel} onClick={() => { if (item.target) onNavigate(item.target); else {
    onClose();
    if (live.enabled && liveMenuTargets[item.label]) openNativeOdoo(liveMenuTargets[item.label]);
    else if (live.enabled) onNotify("هذه الوظيفة غير متصلة بعد بـ Odoo؛ لم يتم حفظ أو إرسال أي شيء");
    else onNotify(section.notice ?? `${item.label} متاح للمعاينة فقط`);
  } }}><item.icon /><span>{item.label}</span></button>)}</section>)}</div></MobileScroll> : null}</aside></div>;
}

function DashboardAddMenu({ open, onClose, ctx }: { open: boolean; onClose: () => void; ctx: AppContext }) {
  const live = useLiveOdoo();
  if (!open) return null;
  const actions = [
    { label: "إضافة حساب جديد", action: () => ctx.openAccountCreate("compact") },
    { label: "تعديل بيانات حساب", action: ctx.openAccountEdit },
    { label: "إضافة مردود جديد", action: () => ctx.openVendorInvoice(vendors[0], "return") },
    { label: "إضافة عرض سعر", action: () => ctx.openVendorInvoice(vendors[0], "quote") },
    { label: "إضافة طلبية", action: () => ctx.openVendorInvoice(vendors[0], "order") },
    { label: "تحويل بين الصناديق/بنوك", action: () => ctx.showToast("التحويل بين الصناديق والبنوك متاح للمعاينة فقط") },
    { label: "تحويل مخزني", action: () => ctx.showToast("التحويل المخزني متاح للمعاينة فقط") },
    { label: "توريد مخزني", action: () => ctx.showToast("التوريد المخزني متاح للمعاينة فقط") },
    { label: "صرف مخزني", action: () => ctx.showToast("الصرف المخزني متاح للمعاينة فقط") },
  ];
  const targets: NativeOdooAction[] = [
    "contacts", "contacts", "customerRefunds", "quotations", "salesOrders",
    "internalPayments", "internalStockTransfers", "stockReceipts", "stockDeliveries",
  ];
  return <div className="dashboard-add-layer" data-testid="dashboard-add-menu"><button className="context-menu-backdrop" aria-label="إغلاق قائمة الإضافة" onClick={onClose} /><aside className="dashboard-add-menu" role="menu" aria-label="إضافة وإدارة الحسابات">{actions.map((item, index) => <button role="menuitem" key={item.label} onClick={() => {
    onClose();
    if (live.enabled) ctx.nativeAction(targets[index]);
    else item.action();
  }}>{item.label}</button>)}</aside></div>;
}

function ExportSideMenu({ open, kind = "statement", onClose, onAction }: { open: boolean; kind?: ExportKind; onClose: () => void; onAction: (message: string) => void }) {
  const live = useLiveOdoo();
  const items: { label: string; icon: IconComponent; tone: string }[] = [
    { label: "طباعة كملف PDF", icon: FileTextIcon, tone: "pdf" },
    { label: "مشاركة كملف PDF", icon: Share1Icon, tone: "share" },
    { label: "تصدير إلى ملف إكسل", icon: TableIcon, tone: "excel" },
    { label: "مشاركة كملف إكسل", icon: Share1Icon, tone: "share" },
    { label: "طباعة مصادقة الرصيد", icon: CardStackIcon, tone: "balance" },
    { label: "مشاركة مصادقة الرصيد", icon: Share1Icon, tone: "share" },
  ];
  if (!open) return null;
  const visibleItems = kind === "purchases" ? [...items.slice(0, 4), { label: "استيراد الحسابات من ملف إكسل", icon: TableIcon, tone: "excel" }] : kind === "inventory" ? items.slice(0, 4) : items;
  return <div className="export-menu-layer" data-testid="export-menu"><button className="export-menu-backdrop" onClick={onClose} aria-label="إغلاق قائمة التصدير" /><aside className={`export-side-menu ${kind === "inventory" ? "inventory-export-menu" : kind === "purchases" ? "purchases-export-menu" : ""}`} aria-label="خيارات التصدير">{visibleItems.map((item) => <button key={item.label} onClick={() => {
      if (live.enabled) {
        onClose();
        openNativeOdoo(kind === "inventory" ? "stockMoves" : kind === "purchases" ? "vendorBills" : "partnerLedger");
      } else {
        onAction(item.label.startsWith("استيراد") ? "معاينة الاستيراد — لم يُقرأ أي ملف أو تُغيّر الحسابات" : `معاينة ${item.label} — لم يُنشأ أو يُرسل ملف`);
      }
    }}><item.icon className={item.tone} /><span>{item.label}</span></button>)}</aside></div>;
}

function ActivationModal({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: (message: string) => void }) {
  if (!open) return null;
  return <div className="center-modal-layer" data-testid="activation-modal"><button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق نافذة التفعيل" /><section className="activation-modal" role="dialog" aria-modal="true" aria-labelledby="activation-title"><div className="activation-hero"><span className="activation-lock"><LockClosedIcon /></span><h2 id="activation-title">مرحبًا بكم في نسقو برو</h2><strong>يتوفر لديكم 250 عملية كفترة تجريبية</strong></div><div className="activation-body"><p>للاستمرار وتفعيل التطبيق<br />يمكنك طلب التفعيل ثم التحقق من حالة نسختك.</p><h3>مميزات التفعيل</h3><ul><li><CheckCircledIcon /> عدد العمليات مفتوح طوال السنة</li><li><CheckCircledIcon /> يمكنك تغيير الجوال في أي وقت</li><li><CheckCircledIcon /> إدارة أعمالك من جهاز واحد</li></ul><div className="activation-note"><strong>ملاحظة…</strong><span>هذه معاينة تصميمية فقط؛ لن يُرسل طلب تفعيل أو تُجرى أي عملية مالية.</span></div><div className="activation-actions"><button className="verify" onClick={() => onDone("تم التحقق من الحالة التجريبية")}>تحقق الآن</button><button className="request" onClick={() => onDone("تم تسجيل طلب تجريبي — لم يُرسل طلب فعلي")}>طلب تفعيل</button></div></div></section></div>;
}

function AccountPickerModal({ open, title = "كشف حساب", onClose, onAddAccount, onConfirm }: { open: boolean; title?: string; onClose: () => void; onAddAccount: () => void; onConfirm: (vendor: Vendor) => void }) {
  const live = useLiveOdoo();
  const [selected, setSelected] = useState<Vendor>(vendors[0]);
  const [optionsOpen, setOptionsOpen] = useState(false);
  const [search, setSearch] = useState("");
  const keyboard = useKeyboard();
  const close = () => { keyboard.hide(); setOptionsOpen(false); setSearch(""); onClose(); };
  const options: Vendor[] = live.enabled ? live.partners.map(partner => ({
    id: partner.id, name: partner.name, phone: partner.phone || "", limit: "—",
    balance: "—", tone: "neutral", code: partner.name[0] || "؟",
  })) : [...vendors];
  const selectedAccount = options.find(v => v.id === selected.id && v.name === selected.name) ?? options[0];
  const filteredAccounts = options.filter(vendor => vendor.name.includes(search.trim()));
  if (!open) return null;
  return <div className="center-modal-layer" data-testid="account-picker-modal"><button className="center-modal-backdrop" onClick={close} aria-label="إغلاق اختيار الحساب" /><section className="account-picker-modal" role="dialog" aria-modal="true" aria-labelledby="account-picker-title">
    <h2 id="account-picker-title">{title}</h2>
    <label className="account-picker-search reference-search" htmlFor="account-picker-search"><span>ابحث عن الاسم هنا</span><KeyboardInput id="account-picker-search" aria-label="البحث عن الحساب" data-testid="account-picker-search-input" value={search} onChange={event => { setSearch(event.target.value); setOptionsOpen(true); }} /></label>
    <p>أو حدد الحساب من هنا</p>
    <div className="account-select-row"><button className="account-add" onClick={() => { keyboard.hide(); setOptionsOpen(false); onAddAccount(); }} aria-label="إضافة حساب"><PlusIcon /></button><button className="account-select" onClick={() => { keyboard.hide(); setOptionsOpen(value => !value); }} aria-label="اختيار حساب لكشف الحساب" aria-expanded={optionsOpen}><span>{selectedAccount?.name ?? "لا توجد حسابات متاحة"}</span><ChevronDownIcon /></button></div>
    {optionsOpen ? <div className="account-options" role="listbox" aria-label="الحسابات">{filteredAccounts.length ? filteredAccounts.map(vendor => <button key={vendor.name} role="option" aria-selected={vendor.name === selected.name} onClick={() => { keyboard.hide(); setSelected(vendor); setSearch(""); setOptionsOpen(false); }}>{vendor.name}</button>) : <p className="account-search-empty" role="status">لا توجد حسابات بهذا الاسم</p>}</div> : null}
    <div className="account-picker-actions"><button className="cancel" onClick={close}>إلغاء</button><button className="confirm" onClick={() => { keyboard.hide(); setOptionsOpen(false); setSearch(""); if (selectedAccount) onConfirm(selectedAccount); }}>موافق</button></div>
  </section></div>;
}

function TransactionModal({ open, vendor, onClose, onNotify, onDone }: { open: boolean; vendor: Vendor; onClose: () => void; onNotify: (message: string) => void; onDone: (message: string) => void }) {
  const live = useLiveOdoo();
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [payment, setPayment] = useState<"cash" | "balance">("cash");
  const [direction, setDirection] = useState<"debit" | "credit">("debit");
  const currentTime = useMemo(() => new Intl.DateTimeFormat("ar-SA", { weekday: "short", hour: "2-digit", minute: "2-digit" }).format(new Date()), []);
  if (!open) return null;

  return <div className="center-modal-layer" data-testid="transaction-modal"><button className="center-modal-backdrop" onClick={onClose} aria-label="إغلاق السند" /><section className="transaction-modal" role="dialog" aria-modal="true" aria-labelledby="transaction-modal-title">
    <h2 id="transaction-modal-title">سند جديد - {vendor.name}</h2>
    <div className="transaction-source-row"><time>{currentTime}</time><button className="transaction-fund" onClick={() => onNotify("تم فتح قائمة الصناديق التجريبية")}><span>الصندوق الرئيسي</span><ChevronDownIcon /></button><button className="transaction-settings" aria-label="إعدادات السند" onClick={() => onNotify("إعدادات السند للمعاينة فقط")}><GearIcon /></button></div>
    <strong className="transaction-balance-strip">الرصيد له: 112,250-</strong>
    <div className="transaction-input amount-input"><TableIcon /><label htmlFor="new-transaction-amount"><span>أدخل المبلغ</span><KeyboardInput id="new-transaction-amount" data-testid="transaction-amount" inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0" /></label><button aria-label="إدخال المبلغ صوتيًا" onClick={() => onNotify("الإدخال الصوتي للمعاينة فقط")}><SpeakerLoudIcon /></button><em>صفر ريال</em></div>
    <div className="transaction-input"><CameraIcon /><label htmlFor="new-transaction-note"><KeyboardInput id="new-transaction-note" value={note} onChange={(event) => setNote(event.target.value)} placeholder="اكتب البيان" /></label><button aria-label="إدخال البيان صوتيًا" onClick={() => onNotify("الإدخال الصوتي للمعاينة فقط")}><SpeakerLoudIcon /></button></div>
    <div className="transaction-radio-row" aria-label="طريقة السداد"><label><input type="radio" name="transaction-payment" checked={payment === "cash"} onChange={() => setPayment("cash")} /> نقدية</label><label><input type="radio" name="transaction-payment" checked={payment === "balance"} onChange={() => setPayment("balance")} /> أرصدة</label></div>
    <div className="transaction-radio-row direction-row" aria-label="اتجاه السند"><label className="credit"><input type="radio" name="transaction-direction" checked={direction === "credit"} onChange={() => setDirection("credit")} /> له</label><label className="debit"><input type="radio" name="transaction-direction" checked={direction === "debit"} onChange={() => setDirection("debit")} /> عليه</label></div>
    <div className="form-modal-actions"><button className="cancel" onClick={onClose}>إلغاء</button><button className="form-help" onClick={() => onNotify("شرح السند للمعاينة فقط")}><VideoIcon /> شرح</button><button className="save" onClick={() => {
    if (live.enabled) {
      if (window.confirm("سيُفتح سند الدفع الأصلي في Odoo. أدخل البيانات وأكمل الحفظ هناك؛ لم يُنشأ أي سند بعد.")) openNativeOdoo("payments");
      return;
    }
    onDone("تم حفظ السند التجريبي");
  }}>حفظ</button></div>
  </section></div>;
}

function AccountCreateModal({ mode, open, initialVendor, onClose, onNotify, onDone }: { mode: AccountCreateMode; open: boolean; initialVendor?: Vendor; onClose: () => void; onNotify: (message: string) => void; onDone: (message: string) => void }) {
  const live = useLiveOdoo();
  const [name, setName] = useState(initialVendor?.name ?? "");
  const [phone, setPhone] = useState(initialVendor?.phone ?? "");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [debtLimit, setDebtLimit] = useState(false);
  const [openingBalance, setOpeningBalance] = useState(false);
  const [openingAmount, setOpeningAmount] = useState("");
  const [openingNote, setOpeningNote] = useState("رصيد افتتاحي");
  const [openingCurrency, setOpeningCurrency] = useState("");
  const [openingDirection, setOpeningDirection] = useState<"debit" | "credit">("debit");
  const [debtAmount, setDebtAmount] = useState("");
  const [settlement, setSettlement] = useState(false);
  const [documentNumber, setDocumentNumber] = useState(false);
  const [accountImage, setAccountImage] = useState("1");
  const [accountCurrency, setAccountCurrency] = useState("ريال");
  const [extraCurrency, setExtraCurrency] = useState(false);
  const [messageMethod, setMessageMethod] = useState<"sms" | "whatsapp">("sms");
  const [sendMode, setSendMode] = useState<"auto" | "confirm" | "never">("never");
  const keyboard = useKeyboard();
  const close = () => { keyboard.hide(); if (!saving) onClose(); };
  const saveContact = async () => {
    if (saving) return;
    keyboard.hide();
    if (!name.trim()) { onNotify("أدخل اسم الحساب أولًا."); return; }
    if (openingBalance || debtLimit || settlement || documentNumber) {
      onNotify("الرصيد الافتتاحي والقيود وحدود الائتمان تحتاج نموذج Odoo المحاسبي؛ لم يُحفَظ أي حساب");
      return;
    }
    if (!window.confirm("هل تؤكد حفظ جهة الاتصال في Odoo الحقيقي؟ لن تُرسل رسائل أو تُنشأ قيود مالية.")) return;
    setSaving(true);
    try {
      await saveOdooContact({
        id: initialVendor?.id, name: name.trim(),
        phone: mode === "extended" ? phone : initialVendor?.phone,
        note: note.trim() || undefined,
      });
      live.refresh();
      onDone("تم حفظ جهة الاتصال في Odoo بنجاح");
    } catch (error) {
      const reason = error instanceof ContactSaveError ? error.reason : "network";
      onNotify(reason === "login" ? "انتهت الجلسة؛ سجّل الدخول إلى Odoo" :
        reason === "permission" ? "ليس لديك صلاحية حفظ جهات الاتصال في Odoo" :
        reason === "validation" ? "تعذّر الحفظ: تحقق من حقول جهة الاتصال في Odoo" :
        "تعذّر الاتصال بـ Odoo. لم يتأكد حفظ البيانات؛ تحقق قبل إعادة المحاولة");
    } finally {
      setSaving(false);
    }
  };
  if (!open) return null;
  const testId = mode === "compact" ? "account-form-compact" : "account-form-extended";

  return <div className="center-modal-layer" data-testid={testId}><button className="center-modal-backdrop" onClick={close} aria-label="إغلاق إضافة الحساب" /><section className={`account-form-modal ${mode}${mode === "extended" && openingBalance ? " has-opening-balance" : ""}`} role="dialog" aria-modal="true" aria-labelledby={`${testId}-title`}>
    <h2 id={`${testId}-title`}>{initialVendor ? "تعديل بيانات حساب" : "إضافة حساب جديد"}</h2>
    {mode === "compact" ? <>
      <label className="underlined-form-field" htmlFor="compact-account-name"><KeyboardInput id="compact-account-name" aria-label="اسم الحساب الجديد" value={name} onChange={(event) => setName(event.target.value)} placeholder="أدخل الاسم" /></label>
      <span className="form-section-label">حدد الصورة</span>
      <label className="account-image-row"><span className="account-avatar">{accountImage === "1" ? <PersonIcon /> : accountImage === "2" ? <HomeIcon /> : <CubeIcon />}</span><select aria-label="صورة الحساب" value={accountImage} onChange={event => setAccountImage(event.target.value)}><option value="1">صورة 1</option><option value="2">صورة 2</option><option value="3">صورة 3</option></select><ChevronDownIcon /></label>
      <div className="account-check-row"><label><input type="checkbox" checked={settlement} onChange={(event) => setSettlement(event.target.checked)} /> قيد تسوية</label><label><input type="checkbox" checked={documentNumber} onChange={(event) => setDocumentNumber(event.target.checked)} /> رقم المستند</label></div>
      <span className="form-section-label">حدد العملة الافتراضية للحساب الرئيسي</span>
      <div className="account-currency-row compact-currency-row"><div className="compact-currency-selector"><button className="currency-plus" aria-label="إضافة عملة" onClick={() => { keyboard.hide(); setExtraCurrency(true); setAccountCurrency("يورو"); onNotify("أضيف اليورو إلى خيارات المعاينة"); }}><PlusIcon /></button><select aria-label="العملة الافتراضية" value={accountCurrency} onChange={event => setAccountCurrency(event.target.value)}><option>ريال</option><option>دولار</option>{extraCurrency ? <option>يورو</option> : null}</select></div><label htmlFor="account-order"><span>الترتيب</span><KeyboardInput id="account-order" aria-label="ترتيب الحساب" defaultValue="1" inputMode="numeric" /></label></div>
    </> : <>
      <label className="icon-underlined-field" htmlFor="extended-account-name"><PersonIcon /><KeyboardInput id="extended-account-name" aria-label="اسم الحساب" value={name} onChange={(event) => setName(event.target.value)} placeholder="أدخل الاسم" /></label>
      <label className="icon-underlined-field" htmlFor="extended-account-phone"><MobileIcon /><KeyboardInput id="extended-account-phone" aria-label="رقم هاتف الحساب" inputMode="tel" value={phone} onChange={(event) => setPhone(event.target.value)} placeholder="أدخل رقم الهاتف" /></label>
      <label className="wide-toggle"><span>إضافة سقف مديونية للحساب</span><input className="account-form-switch" role="switch" type="checkbox" checked={debtLimit} onChange={(event) => { keyboard.hide(); setDebtLimit(event.target.checked); }} /></label>
      {debtLimit ? <label className="underlined-form-field account-debt-field"><KeyboardInput aria-label="سقف المديونية" inputMode="decimal" value={debtAmount} onChange={(event) => setDebtAmount(event.target.value)} placeholder="أدخل سقف المديونية" /></label> : null}
      <label className="icon-underlined-field" htmlFor="extended-account-note"><ChatBubbleIcon /><KeyboardInput id="extended-account-note" aria-label="ملاحظة الحساب" value={note} onChange={(event) => setNote(event.target.value)} placeholder="اكتب ملاحظة" /></label>
      <fieldset className="account-radio-box"><legend>طريقة إرسال الرسائل</legend><label><input type="radio" name="message-method" checked={messageMethod === "sms"} onChange={() => setMessageMethod("sms")} /> SMS</label><label><input type="radio" name="message-method" checked={messageMethod === "whatsapp"} onChange={() => setMessageMethod("whatsapp")} /> واتساب</label></fieldset>
      <fieldset className="account-radio-box three"><legend>إرسال الرسائل</legend><label><input type="radio" name="send-mode" checked={sendMode === "auto"} onChange={() => setSendMode("auto")} /> تلقائي</label><label><input type="radio" name="send-mode" checked={sendMode === "confirm"} onChange={() => setSendMode("confirm")} /> بعد التأكيد</label><label><input type="radio" name="send-mode" checked={sendMode === "never"} onChange={() => setSendMode("never")} /> لا ترسل</label></fieldset>
      <label className="wide-toggle"><span>إضافة رصيد افتتاحي أو رصيد سابق</span><input className="account-form-switch" role="switch" type="checkbox" data-testid="opening-balance-toggle" aria-controls="opening-balance-fields" aria-expanded={openingBalance} checked={openingBalance} onChange={(event) => { keyboard.hide(); setOpeningBalance(event.target.checked); }} /></label>
      {openingBalance ? <div className="account-opening-fields" id="opening-balance-fields" data-testid="opening-balance-fields">
        <div className="account-opening-amount-row"><KeyboardInput aria-label="مبلغ الرصيد الافتتاحي" data-testid="opening-balance-amount" inputMode="decimal" value={openingAmount} onChange={(event) => setOpeningAmount(event.target.value)} placeholder="أدخل المبلغ" /><select aria-label="عملة الرصيد الافتتاحي" value={openingCurrency} onChange={(event) => setOpeningCurrency(event.target.value)}><option value="">—</option><option value="SAR">ريال</option><option value="USD">دولار</option></select></div>
        <label className="account-opening-note"><span>اكتب البيان</span><KeyboardInput aria-label="بيان الرصيد الافتتاحي" data-testid="opening-balance-note" value={openingNote} onChange={(event) => setOpeningNote(event.target.value)} /></label>
        <div className="transaction-radio-row direction-row" role="group" aria-label="اتجاه الرصيد الافتتاحي"><label className="credit"><input type="radio" name="opening-balance-direction" checked={openingDirection === "credit"} onChange={() => setOpeningDirection("credit")} /> له</label><label className="debit"><input type="radio" name="opening-balance-direction" checked={openingDirection === "debit"} onChange={() => setOpeningDirection("debit")} /> عليه</label></div>
      </div> : null}
    </>}
    <div className="form-modal-actions"><button className="cancel" onClick={close}>إلغاء</button><button className="form-help" onClick={() => onNotify("شرح إضافة الحساب للمعاينة فقط")}><VideoIcon /> شرح</button><button className="save" onClick={() => {
    keyboard.hide();
    if (live.enabled) { void saveContact(); return; }
    onDone("تم حفظ حساب تجريبي — لم تُرسل أي رسائل");
  }}>حفظ</button></div>
  </section></div>;
}

function SheetContent({ kind, setKind, ctx, onDone }: { kind: SheetKind; setKind: (kind: SheetKind) => void; ctx: AppContext; onDone: (message: string) => void }) {
  const live = useLiveOdoo();
  const [filterPeriod, setFilterPeriod] = useState("الكل");
  const [filterSort, setFilterSort] = useState("الأحدث");
  if (kind === "add-operation") {
    const actions: { label: string; caption: string; icon: IconComponent; action: () => void }[] = [
      { label: "فاتورة جديدة", caption: "مبيعات أو مشتريات", icon: FilePlusIcon, action: ctx.openInvoice },
      { label: "حساب جديد", caption: "عميل أو مورد", icon: PersonIcon, action: () => ctx.openAccountCreate("compact") },
      { label: "سند جديد", caption: "قبض أو صرف", icon: ReaderIcon, action: () => ctx.openTransaction() },
      { label: "صرف عملات", caption: "شراء أو بيع", icon: ReloadIcon, action: () => ctx.flowRef.current?.push(currencyScreen(ctx)) },
    ];
    return <div className="sheet-action-list">{actions.map((action, index) => <button key={action.label} onClick={() => {
      setKind(null);
      if (live.enabled) ctx.nativeAction((["customerInvoices", "contacts", "payments", "currencies"] as NativeOdooAction[])[index]);
      else action.action();
    }}><span><action.icon /></span><div><strong>{action.label}</strong><small>{action.caption}</small></div><ChevronLeftIcon /></button>)}</div>;
  }
  if (kind === "filters") return <div className="filter-sheet"><span className="sheet-label">الفترة</span><div className="choice-row">{["يومي", "شهري", "الكل", "سنوي"].map(period => <button key={period} className={filterPeriod === period ? "selected" : ""} onClick={() => setFilterPeriod(period)}>{period}</button>)}</div><span className="sheet-label">الترتيب</span><div className="choice-row">{["الأحدث", "الأقدم"].map(sort => <button key={sort} className={filterSort === sort ? "selected" : ""} onClick={() => setFilterSort(sort)}>{sort}</button>)}</div><button className="primary full" onClick={() => live.enabled ? ctx.nativeAction("contacts") : onDone("تم تطبيق عوامل التصفية")}>تطبيق التصفية</button></div>;
  if (kind === "export") {
    const exports = [{ label: "تنزيل PDF", icon: FileTextIcon }, { label: "مشاركة PDF", icon: Share1Icon }, { label: "تنزيل Excel", icon: TableIcon }, { label: "إرسال للمدير", icon: PaperPlaneIcon }];
    return <div className="sheet-action-list">{exports.map((item) => <button key={item.label} onClick={() => live.enabled ? ctx.nativeAction("partnerLedger") : onDone(`تم تجهيز ${item.label}`)}><span><item.icon /></span><div><strong>{item.label}</strong><small>كشف الحساب الحالي</small></div><ChevronLeftIcon /></button>)}</div>;
  }
  return null;
}

function sheetTitle(kind: SheetKind) {
  return ({ "add-operation": "إضافة عملية", filters: "التصفية والترتيب", export: "تصدير كشف الحساب" } as Record<Exclude<SheetKind, null>, string>)[kind as Exclude<SheetKind, null>] ?? "";
}

function sheetDescription(kind: SheetKind) {
  if (kind === "add-operation") return "اختر نوع العملية التي تريد إنشاؤها";
  if (kind === "export") return "تصدير آمن دون تغيير بيانات الحساب";
  return undefined;
}

function cashInvoicePreviewScreen(ctx: AppContext, id = "1140"): FlowScreen {
  return {
    id: `cash-invoice-preview-${id}`,
    headerHeight: 58,
    header: flow => <SimpleAppHeader title="معاينة الفاتورة" onBack={flow.pop} />,
    render: flow => {
      ctx.flowRef.current = flow;
      return <CashInvoicePreviewPage id={id} />;
    },
  };
}

function CashInvoicePreviewPage({ id }: { id: string }) {
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const [viewportWidth, setViewportWidth] = useState(373);
  const [zoom, setZoom] = useState<number | null>(null);
  const [generatedAt] = useState(() => new Date());
  const fitScale = Math.min(viewportWidth / 1280, 1);
  const scale = zoom ?? fitScale;
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
  const moveDocument = (direction: -1 | 1) => viewportRef.current?.scrollBy({ left: direction * 240, behavior: "smooth" });
  if (id !== "1140") return <MobileScroll className="app-screen"><p className="cash-invoice-unavailable">معاينة هذه الفاتورة غير متاحة بعد.</p></MobileScroll>;
  return <main className="cash-invoice-preview" data-testid="cash-invoice-screen">
    <div className="cash-invoice-controls" role="group" aria-label="تكبير الفاتورة">
      <button data-testid="cash-invoice-zoom-in" aria-label="تكبير الفاتورة" disabled={scale >= 1.5} onClick={() => setZoom(Math.min(1.5, Math.ceil((scale + 0.01) * 4) / 4))}>+</button>
      <output data-testid="cash-invoice-zoom-value" aria-live="polite">{Math.round(scale * 100)}%</output>
      <button data-testid="cash-invoice-zoom-out" aria-label="تصغير الفاتورة" disabled={scale <= fitScale} onClick={() => setZoom(Math.max(fitScale, Math.floor((scale - 0.01) * 4) / 4))}>−</button>
      <button className="cash-invoice-fit" data-testid="cash-invoice-reset" onClick={() => setZoom(null)}>ملاءمة العرض</button>
      <button className="cash-invoice-actual" data-testid="cash-invoice-actual-size" onClick={() => setZoom(1)}>100%</button>
    </div>
    <div className="cash-invoice-reader-hint">
      {scale > fitScale ? <><button aria-label="تحريك الفاتورة إلى اليمين" onClick={() => moveDocument(1)}><ArrowRightIcon /></button><span>مرّر لقراءة بقية المستند</span><button aria-label="تحريك الفاتورة إلى اليسار" onClick={() => moveDocument(-1)}><ArrowLeftIcon /></button></> : <span>فاتورة رقم 1140 · كبّر لقراءة التفاصيل</span>}
    </div>
    <MobileScroll className="cash-invoice-scroll">
      <div className="cash-invoice-horizontal" ref={viewportRef} data-testid="cash-invoice-pan" tabIndex={0} aria-label="عرض مستند الفاتورة">
        <div className="cash-invoice-sheet-space" style={{ width: 1280 * scale, height: 908 * scale }}>
          <CashInvoiceDocument generatedAt={generatedAt} scale={scale} />
        </div>
      </div>
      <p className="cash-invoice-preview-note">معاينة فقط — لم يُنشأ ملف PDF ولم تُحفظ أي عملية.</p>
    </MobileScroll>
  </main>;
}

function CashInvoiceDocument({ generatedAt, scale }: { generatedAt: Date; scale: number }) {
  const stamp = `${generatedAt.getFullYear()}-${String(generatedAt.getMonth() + 1).padStart(2, "0")}-${String(generatedAt.getDate()).padStart(2, "0")}-${String(generatedAt.getHours()).padStart(2, "0")}-${String(generatedAt.getMinutes()).padStart(2, "0")}-${String(generatedAt.getSeconds()).padStart(2, "0")}`;
  return <article className="cash-invoice-document" data-testid="cash-invoice-document" dir="rtl" aria-label="فاتورة شراء نقدي رقم 1140 — معاينة" style={{ transform: `scale(${scale})` }}>
    <div className="cash-invoice-merchant arabic"><span>اندكس للتجارة العامة</span><span>الجمهورية اليمنية - صنعاء</span><bdi>771370740 +967</bdi></div>
    <div className="cash-invoice-merchant english" lang="en" dir="ltr"><span>indexes Store</span><span>YEMEN SANA'A</span><span>771370740 +967</span></div>
    <h1>فاتورة شراء نقدي</h1>
    <div className="cash-invoice-demo-banner">هذا المستند معاينة تجريبية صادرة من نسقو برو</div>
    <div className="cash-invoice-divider" />
    <p className="cash-invoice-date">التاريخ : الجمعة <bdi>2025/12/26</bdi></p>
    <p className="cash-invoice-number">رقم <bdi>1140</bdi></p>
    <p className="cash-invoice-recipient">الأخ / مشتريات نقد هلال</p>
    <p className="cash-invoice-salutation">المحترم</p>
    <p className="cash-invoice-description">البيان /</p>
    <table className="cash-invoice-table" aria-label="أصناف الفاتورة">
      <colgroup><col style={{ width: 538 }} /><col style={{ width: 151 }} /><col style={{ width: 129 }} /><col style={{ width: 172 }} /><col style={{ width: 194 }} /></colgroup>
      <thead><tr><th scope="col">الصنف</th><th scope="col">الوحدة</th><th scope="col">الكمية</th><th scope="col">السعر</th><th scope="col">الإجمالي</th></tr></thead>
      <tbody>
        <tr><td>توصيلة تايب سي 2 متر</td><td>حبة</td><td className="red">1</td><td>1,500</td><td className="blue">1,500</td></tr>
        <tr><td>بطارية جهاز كشف الذهب</td><td>حبة</td><td className="red">1</td><td>1,500</td><td className="blue">1,500</td></tr>
      </tbody>
    </table>
    <div className="cash-invoice-summary"><div><strong>الكمية</strong><bdi data-testid="cash-invoice-quantity-total">2</bdi></div><div><strong>الإجمالي</strong><bdi className="blue" data-testid="cash-invoice-grand-total">3,000</bdi></div></div>
    <p className="cash-invoice-total-words">ثلاثة ألف ريال</p>
    <footer className="cash-invoice-document-footer"><time dateTime={generatedAt.toISOString()}>{stamp}</time><span lang="en" dir="ltr">page 1</span></footer>
  </article>;
}
