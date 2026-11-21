import React, {useCallback, useEffect, useLayoutEffect, useRef, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {AppDrawer, DashboardAddMenu, DashboardBottomNav, DashboardHeader, DashboardPage, HeaderOptionsMenu} from 'dashboard:presentation';
import {normalizeHomeTileLayout} from '../../src/utils/dashboardPrefs';
import {applyCardAppearanceSettings, DEFAULT_EXTENDED_SETTINGS} from '../../src/utils/appSettings';
import {applyBrandColor} from '../../src/utils/brandColor';
import {computeCategoryTotals} from '../../src/accounting';
import {HomeMetrics} from './metrics';
import {DirectoryScreen} from './DirectoryScreen';
import {DrivePresentation} from 'drive:presentation';
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
const scroller = () => document.querySelector<HTMLElement>('.dashboard-scroll .mobile-scroll');
window.nasqoTop = () => scroller()?.scrollTo({top: 0, behavior: 'smooth'});

function Shell({snapshot}) {
  const [overlay, setOverlay] = useState('');
  const [quick, setQuick] = useState(false);
  const [toast, setToast] = useState('');
  const directoryBack = useRef(null);
  const metricBack=useRef(null);
  const editors=useRef({tiles:false,metrics:false});
  const editing=(part:'tiles'|'metrics',active:boolean)=>{
    editors.current[part]=active;
    send('editing',{active:editors.current.tiles || editors.current.metrics});
  };
  const directoryOpen = useRef(false);
  const directoryParent=useRef('');
  const openDirectory = (screen, action='browse', fields={screen}) => {
    directoryParent.current=overlay==='reports' ? 'reports' : '';
    directoryOpen.current = true;
    setOverlay(screen);
    send(action,fields);
  };
  const close = useCallback(() => {
    const parent=directoryOpen.current ? directoryParent.current : '';
    if (directoryOpen.current) {directoryOpen.current=false;directoryParent.current='';send('browse',{screen:'home'});}
    setOverlay(parent);
  }, []);
  const tile = (id: string) => {
    if (id === 'reports') setOverlay('reports');
    else if (id==='trial-balance') openDirectory('trial');
    else if (id==='warehouses' || id==='accounts' || id==='statement') {
      openDirectory({warehouses:'warehouses',accounts:'chart',statement:'picker'}[id]);
    } else send('tile', {id});
  };
  const navigate = (id: string) => {
    if (id.startsWith('group-')) openDirectory('suppliers','members',{category:id.slice(6)});
    else if (id==='chart-accounts') openDirectory('chart');
    else send('navigate', {id});
  };
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
      if (directoryBack.current) {directoryBack.current(); return true;}
      if (overlay) {close(); return true;}
      if (metricBack.current) return metricBack.current();
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
    openAccountCreate: () => navigate('account-new'), openAccountEdit: () => openDirectory('chart'),
    openVendorInvoice: (_,kind) => tile({return: 'new-return', quote: 'quote', order: 'new-order'}[kind]),
    openChartOfAccounts: () => navigate('chart-accounts'), openCurrenciesManager: () => tile('currencies'),
    triggerCsvImport: () => navigate('account-import'),
    openLocalBackups: () => navigate('local-backups'), triggerJsonRestore: () => navigate('local-backups'),
    openAndroidOption: navigate,
    handleSignOut: () => {close(); setToast('تعمل مساحة الجهاز محليًا دون تسجيل دخول');},
  };
  const balances = __REFERENCE__
    ? Object.fromEntries(Object.entries(computeCategoryTotals(context.accounts,context.ledger,snapshot.defaultCurrency)).map(([k,v])=>[k,v.netSigned]))
    : snapshot.metrics;
  const host = {context, rows: snapshot.rows, layout: normalizeHomeTileLayout(snapshot.layout),
    metrics: tileEditing => <HomeMetrics balances={balances} count={snapshot.measurementCount}
      currency={snapshot.defaultCurrency} onOpen={navigate} initialLayout={snapshot.metricLayout}
      onEditing={active=>editing('metrics',active)} backRef={metricBack} tileEditing={tileEditing}/>,
    selectCurrency: update => {const [[id,currency]] = Object.entries(update({})); send('currency',{id:Number(id),currency});},
    openGroup: (id: number) => openDirectory('suppliers','group',{id}), openTile: tile,
    editing: active => editing('tiles',active), saveLayout: value => send('layout',{value}), haptic: triggerHaptic,
  };
  return <Workspace.Provider value={context}>
    <div className="flow-stack hybrid-shell" inert={!!overlay}
      style={['warehouses','suppliers'].includes(overlay) && snapshot.directory?.screen===overlay ? {visibility:'hidden'} : undefined}>
      <div className="flow-fixed-header"><DashboardHeader/></div>
      <div className="flow-scenes"><div className="flow-screen"><DashboardPage host={host}/></div></div>
      <div className="flow-fixed-footer"><DashboardBottomNav flow={flow}/></div>
    </div>
    <AppDrawer open={overlay === 'drawer'} onClose={close} onNavigate={target => {
      close();
      if (target === 'dashboard') {window.nasqoTop(); return;}
      const [action,id] = drawerRoutes[target]; (action==='tile'?tile:navigate)(id);
    }}/>
    <DashboardAddMenu open={overlay === 'add'} onClose={close}/>
    {snapshot.directory && overlay===snapshot.directory.screen && <DirectoryScreen key={overlay}
      data={snapshot.directory} base={context} rows={snapshot.rows} close={close}
      backRef={directoryBack} tile={tile} navigate={navigate}/>}
    {overlay === 'reports' && <ReportsPanel title="التقارير" footer="اختر تقريرًا" onClose={close}>
      <ReportsMenu onSelect={openReport}/>
    </ReportsPanel>}
    <HeaderOptionsMenu open={overlay==='options'} onClose={close}/>
    {toast && <div className="app-toast" role="status">{toast}</div>}
  </Workspace.Provider>;
}

window.nasqoPresent = snapshot => root.render(snapshot.standalone === 'drive'
  ? <DrivePresentation model={snapshot}/> : <Shell snapshot={snapshot}/>);
window.addEventListener('message', event => {
  if (typeof event.data === 'string') window.nasqoPresent(JSON.parse(event.data));
});
send('ready');
