// Each route starts on the dashboard; these selectors also identify the live web reference.
const id = (name) => '[data-testid="' + name + '"]';
const button = (label) => ({selector:'button',label});
const menu = (label) => ({selector:'[role=menuitem]',label});
const add = button('إضافة');
export const states = [
  {name:'home', path:[id('home-nav-home')], screen:id('dashboard-screen')},
  {name:'drawer', path:[button('فتح القائمة')], screen:'.drawer-layer.open aside.app-drawer'},
  {name:'add-menu', path:[add], screen:id('dashboard-add-menu')},
  {name:'quick-actions', path:[id('home-nav-center-fab')], screen:id('home-quick-sheet')},
  {name:'management', path:[id('home-nav-services')], screen:id('erp-hub-screen')},
  {name:'reports', path:[id('home-nav-reports')], screen:id('reports-hub-modal')},
  {name:'settings', path:[id('home-nav-profile')], screen:id('system-settings-screen')},
  {name:'account', path:[add,menu('إضافة حساب جديد')], screen:id('account-form-extended')},
  {name:'invoice', path:[add,menu('فاتورة جديدة')], screen:id('invoice-modal')},
  {name:'voucher', path:[add,menu('سند جديد')], screen:id('transaction-modal')},
  {name:'stock', path:[add,menu('إضافة صنف للمخزن')], screen:id('inventory-item-modal')},
  {name:'simple-entry',path:[add,menu('قيد بسيط')],screen:id('simple-entry-screen')},
  {name:'item-catalog',path:[button('الأصناف')],screen:id('items-catalog-screen')},
  {name:'inventory-movement',path:[button('حركة المخزون')],screen:id('inventory-report-screen')},
  {name:'export-menu',path:[button('حركة المخزون'),id('movement-export-excel-btn')],screen:id('export-menu'),back:2},
  {name:'warehouses',path:[button('المخازن')],screen:id('warehouses-screen')},
  {name:'daily-journal',path:[button('الحركة اليومية')],screen:id('daily-journal-screen')},
];

export function findControl({selector,label}) {
  return [...document.querySelectorAll(selector)].find(n =>
    !n.closest('[inert],[aria-hidden=true]') && n.getClientRects().length && !n.disabled &&
    (!label || (n.getAttribute('aria-label') || n.innerText || '').trim() === label));
}

export function measure(selector) {
  const visible = s => [...document.querySelectorAll(s)].filter(n => n.getClientRects().length && !n.closest('[inert],[aria-hidden=true]'));
  const box = n => {
    const rect=n.getBoundingClientRect();
    return {x:Math.round(rect.x),y:Math.round(rect.y),width:Math.round(rect.width),height:Math.round(rect.height)};
  };
  const screen = visible(selector)[0];
  return screen && {width:innerWidth,height:innerHeight,screen:box(screen),
    headers:visible('.flow-fixed-header').map(box),footers:visible('.flow-fixed-footer').map(box),
    navBars:visible('[data-testid=home-bottom-nav]').map(box),labels:visible(selector+' button')
      .map(n=>(n.getAttribute('aria-label')||n.innerText||'').trim()).filter(Boolean)};
}
