import React, {useCallback, useEffect, useLayoutEffect, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {AppDrawer, DashboardAddMenu, DashboardBottomNav, DashboardHeader, DashboardPage} from 'dashboard:presentation';
import {normalizeHomeTileLayout} from '../../src/utils/dashboardPrefs';
import {applyCardAppearanceSettings, DEFAULT_EXTENDED_SETTINGS} from '../../src/utils/appSettings';
import {applyBrandColor} from '../../src/utils/brandColor';
import {computeCategoryTotals} from '../../src/accounting';
import {HomeMetrics} from './metrics';
import {ReportsMenu, ReportsPanel, type ReportDestination} from '../../src/components/ReportsMenu';
import {Workspace, send, triggerHaptic} from './workspace';

const root = createRoot(document.getElementById('home')!);
const drawerRoutes = {
  'analytics-dashboard': ['tile','sales-dashboard'], 'daily-journal': ['tile','daily-journal'],
  whatsapp: ['navigate','message-settings'], 'inventory-report': ['tile','stock-movement'],
  quotes: ['navigate','quotes'], orders: ['navigate','orders'], trash: ['tile','trash'],
  settings: ['tile','settings'], warehouses: ['tile','warehouses'], items: ['tile','items'],
  accounts: ['tile','account-groups'], currency: ['tile','currency-exchange'],
  'erp-hub': ['tile','erp-hub'], 'erp-finance': ['navigate','finance'], 'erp-hr': ['navigate','hr'],
  'erp-crm': ['navigate','crm'], 'erp-procurement': ['navigate','procurement'],
  'erp-manufacturing': ['navigate','manufacturing'],
};
const options = [
  ['local-backups','نسخ احتياطي واستعادة'], ['theme','تبديل المظهر'],
  ['app-update','التحقق من تحديثات التطبيق'], ['home-mode','الرئيسية الأصلية'],
];

const scroller = () => document.querySelector<HTMLElement>('.dashboard-scroll .mobile-scroll');
window.nasqoTop = () => scroller()?.scrollTo({top: 0, behavior: 'smooth'});

function Shell({snapshot}) {
  const [overlay, setOverlay] = useState('');
  const [quick, setQuick] = useState(false);
  const [toast, setToast] = useState('');
  const close = useCallback(() => setOverlay(''), []);
  const tile = (id: string) => {
    if (id === 'reports') setOverlay('reports');
    else send('tile', {id});
  };
  const navigate = (id: string) => send('navigate', {id});
  const flow = {push: tile};
  const openReport = (id: ReportDestination) => {
    if (id === 'cashboxes' || id === 'trial-balance') {tile(id); return;}
    navigate({
      closing: 'report-closing', 'by-category': 'report-category', movement: 'report-movement',
      'stock-expiry': 'report-expiry', 'stock-remaining': 'report-stock',
      'invoice-profit': 'report-profit', services: 'report-services', tax: 'recorded-sales-tax',
    }[id]);
  };

  useLayoutEffect(() => {
    const a = snapshot.appearance ?? {};
    document.documentElement.classList.toggle('dark', snapshot.dark);
    applyBrandColor(a.primary ?? DEFAULT_EXTENDED_SETTINGS.homePrimaryBtnColor);
    applyCardAppearanceSettings({...DEFAULT_EXTENDED_SETTINGS,
      homePrimaryBtnColor: a.primary ?? DEFAULT_EXTENDED_SETTINGS.homePrimaryBtnColor,
      homeSecondaryBtnColor: a.secondary ?? DEFAULT_EXTENDED_SETTINGS.homeSecondaryBtnColor,
      homeButtonRadius: a.radius ?? DEFAULT_EXTENDED_SETTINGS.homeButtonRadius,
    });
  }, [snapshot]);

  useEffect(() => {
    const node = scroller();
    if (!node) return;
    let active = true, timer = 0;
    const save = () => send('scroll', {y: Math.round(node.scrollTop)});
    const scroll = () => {clearTimeout(timer); timer = window.setTimeout(save, 140);};
    const hide = () => {if (document.hidden) {clearTimeout(timer); save();}};
    document.fonts.ready.then(() => requestAnimationFrame(() => {
      if (!active) return;
      node.scrollTop = snapshot.scroll ?? 0;
      node.addEventListener('scroll', scroll, {passive: true});
      document.addEventListener('visibilitychange', hide);
      requestAnimationFrame(() => {if (active) send('paint');});
    }));
    return () => {active = false; clearTimeout(timer); node.removeEventListener('scroll', scroll); document.removeEventListener('visibilitychange', hide);};
  }, []);

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(''), 1800);
    return () => clearTimeout(timer);
  }, [toast]);

  useLayoutEffect(() => {
    send('overlay', {active: !!overlay || quick});
    window.nasqoBack = () => {
      if (overlay) {close(); return true;}
      if (quick) {document.querySelector<HTMLElement>('[data-testid="home-nav-center-fab"]')?.click(); return true;}
      if (!document.querySelector('[data-testid="home-tiles-edit-bar"]')) return false;
      window.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape'}));
      return true;
    };
  }, [overlay, quick, close]);

  const context = {
    workspace: {companyName: snapshot.company, defaultCurrency: snapshot.defaultCurrency},
    accounts: __REFERENCE__ ? snapshot.fixture.accounts : [],
    accountGroups: __REFERENCE__ ? snapshot.fixture.accountGroups : [],
    ledger: __REFERENCE__ ? snapshot.fixture.ledger : [],
    extendedSettings: {}, currencyCodes: snapshot.currencies, userEmail: 'account@nasqo.local',
    unreadNotificationsCount: snapshot.unread, quickState: setQuick,
    flowRef: {current: flow}, showToast: setToast,
    openDrawer: () => setOverlay('drawer'), openDashboardMenu: () => setOverlay('add'),
    openOptionsMenu: () => setOverlay('options'), openTrash: () => tile('trash'),
    openWhatsAppPicker: () => navigate('message-settings'), openNotifications: () => navigate('notifications'),
    openQuickSearch: () => tile('quick-search'), openQrScanner: () => tile('qr-scanner'),
    openTransferModal: () => tile('new-transfer'), openInvoice: () => tile('new-invoice'),
    openTransaction: () => tile('new-voucher'), openSettings: () => tile('settings'),
    openReportsHub: () => tile('reports'), openInventoryAdd: () => navigate('item-new'),
    openAccountCreate: () => navigate('account-new'), openAccountEdit: () => tile('accounts'),
    openVendorInvoice: (_,kind) => tile({return: 'new-return', quote: 'quote', order: 'new-order'}[kind]),
    openChartOfAccounts: () => navigate('chart-accounts'), openCurrenciesManager: () => tile('currencies'),
    triggerCsvImport: () => navigate('account-import'),
    handleSignOut: () => {close(); setToast('تعمل مساحة الجهاز محليًا دون تسجيل دخول');},
  };
  const balances = __REFERENCE__
    ? Object.fromEntries(Object.entries(computeCategoryTotals(context.accounts,context.ledger,snapshot.defaultCurrency)).map(([k,v])=>[k,v.netSigned]))
    : snapshot.metrics;
  const host = {context, rows: snapshot.rows, layout: normalizeHomeTileLayout(snapshot.layout),
    metrics: <HomeMetrics balances={balances} count={snapshot.measurementCount} currency={snapshot.defaultCurrency} onOpen={navigate}/>,
    selectCurrency: update => {const [[id,currency]] = Object.entries(update({})); send('currency',{id:Number(id),currency});},
    openGroup: (id: number) => send('group',{id}), openTile: tile,
    editing: active => send('editing',{active}), saveLayout: value => send('layout',{value}), haptic: triggerHaptic,
  };
  return <Workspace.Provider value={context}>
    <div className="flow-stack hybrid-shell">
      <div className="flow-fixed-header"><DashboardHeader/></div>
      <div className="flow-scenes"><div className="flow-screen"><DashboardPage host={host}/></div></div>
      <div className="flow-fixed-footer"><DashboardBottomNav flow={flow}/></div>
    </div>
    <AppDrawer open={overlay === 'drawer'} onClose={close} onNavigate={target => {
      close();
      if (target === 'dashboard') {window.nasqoTop(); return;}
      const [action,id] = drawerRoutes[target]; send(action,{id});
    }}/>
    <DashboardAddMenu open={overlay === 'add'} onClose={close}/>
    {overlay === 'reports' && <ReportsPanel title="التقارير" footer="اختر تقريرًا" onClose={close}>
      <ReportsMenu onSelect={openReport}/>
    </ReportsPanel>}
    {overlay === 'options' && <div className="options-menu-layer" data-testid="options-menu">
      <button className="context-menu-backdrop" aria-label="إغلاق الخيارات" onClick={close}/>
      <aside className="header-options-menu" role="menu" aria-label="خيارات التطبيق">
        {options.map(([id,label]) => <button type="button" role="menuitem" className="opt-tile" key={id}
          onClick={() => {close(); navigate(id);}}>{label}</button>)}
      </aside>
    </div>}
    {toast && <div className="app-toast" role="status">{toast}</div>}
  </Workspace.Provider>;
}

window.nasqoPresent = snapshot => root.render(<Shell snapshot={snapshot}/>);
window.addEventListener('message', event => {
  if (typeof event.data === 'string') window.nasqoPresent(JSON.parse(event.data));
});
send('ready');
