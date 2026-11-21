// Adapt just the data and device-action seams of the existing React pages.
export function directoryComponents(sourceOf, replace) {
  const part = (s, start, end, replacement) => {
    const i=s.indexOf(start), j=s.indexOf(end,i+start.length);
    if (i<0 || j<0) throw Error('Directory source changed: '+start);
    return s.slice(0,i)+replacement+s.slice(j);
  };
  let wh=sourceOf('WarehousesPage');
  wh=part(wh,'  const [editing,','  const keyboard','');
  wh=part(wh,'  const open = (warehouse:', '  return (',
    '  const open = warehouse => ctx.warehouse(warehouse === "new" ? "create" : "edit", warehouse.id);\n');
  wh=part(wh,'      {editing !== null ?', '    </>', '');
  wh=replace(wh,'aria-label={`فتح ${warehouse.name}`}\n                  onClick={() => flow.push(inventoryReportScreen(warehouse.id))}',
    'aria-label={`فتح ${warehouse.name}`} onClick={() => ctx.warehouse("items",warehouse.id)}');

  let coa=sourceOf('ChartOfAccountsModal');
  coa=replace(coa,'computeAccountSummary(acc, ctx.ledger)','summaryOf(acc, acc.currency)');
  coa=part(coa,'  const totals = useMemo(', '  if (!open)',
    '  const totals = currencyFooter(filtered.map(({acc})=>acc));\n');
  coa=part(coa,'            نشطة بالحركات:', '          </span>','            {totals}\n');
  // A native route is pushed above the WebView. Retain the directory filters.
  coa=coa.replace(/onClose\(\);\s*(?=ctx\.)/g,'');

  let vendors=sourceOf('PurchasesPage');
  vendors=replace(vendors,'useState("الكل")','[ctx.dir.period, value => ctx.filter(value, ctx.dir.currency)]');
  vendors=replace(vendors,'const [byCurrency, setByCurrency] = useState(false);','const [byCurrency, setByCurrency] = [ctx.onlyCurrency, ctx.setOnlyCurrency];');
  vendors=replace(vendors,'screenRef.current?.querySelector(".nasqo-app")','screenRef.current');
  vendors=part(vendors,'  const periodLedger =','  const orderedVendors =',
    `  const activeCurrencyParam = currencyFilter === "الكل" ? undefined : currencyFilter;
  const categoryAccounts = ctx.accounts.filter(a => !byCurrency || !activeCurrencyParam ||
    a.currency === activeCurrencyParam || a.amounts[activeCurrencyParam]?.entryCount > 0);
`);
  vendors=part(vendors,'                const summary = computeAccountSummary(', '                return (',
    '                const summary = summaryOf(vendor, currencyFilter);\n');
  vendors=part(vendors,'                          window.location.href', '                        } else', '                          ctx.accountAction("contact",vendor.id);\n');
  vendors=part(vendors,'                          void shareOrCopyText(', '                        }', '                          ctx.accountAction("message",vendor.id)\n');
  vendors=part(vendors,'                          void openWhatsAppChat(', '                        }','                          ctx.accountAction("whatsapp",vendor.id)\n');
  vendors=part(vendors,'                          {formatAmount(summary.netBalance)}', '                        </strong>',
    '                          {balanceLabel(vendor,currencyFilter)}\n');
  let trial=sourceOf('TrialBalanceModal');
  trial=part(trial,'  const report = useMemo(', '  if (!open)',`  const from=periodMode==='all'?'':fromDate, through=periodMode==='all'?'':toDate;
  const invalid=from && through && from>through;
  const ready=ctx.dir.currency===currency && ctx.dir.from===from && ctx.dir.through===through;
  useEffect(()=>{
    if(!invalid && !ready) ctx.requestTrial(currency,from,through);
  },[currency,from,through,invalid,ready]);
`);
  trial=replace(trial,'        <div className="trial-balance-sections">',
    '        {invalid ? <p role="alert">يجب أن يسبق تاريخ البداية تاريخ النهاية.</p> : !ready ? <p role="status">جارٍ تحميل الميزان…</p> : ctx.dir.reports.map(report=><div key={report.currency} className="trial-balance-sections" data-currency={report.currency}>');
  trial=replace(trial,'{currency === "ريال" ? "ريال (العملة الأساسية المسجلة)" : currency === "الكل" ? "جميع العملات" : currency}',
    '{report.currency === defaultCurrency ? report.currency+" (العملة الأساسية المسجلة)" : report.currency}');
  for(const field of ['inventoryValue','netProfit']){
    const format=field==='netProfit'?'formatSmartReportNumber(report.netProfit, true)':'formatSmartReportNumber(report.inventoryValue)';
    trial=replace(trial,'{'+format+'}','{report.'+field+'===null?"—":'+format+'}');
  }
  trial=replace(trial,'        </div>\n      </section>',
    '          {report.inventoryValue===null && <p>تُقيّم تكلفة المخزون بعملة المنشأة '+ '{defaultCurrency}.</p>}\n        </div>)}\n      </section>');
  return [
    sourceOf('formatSmartReportNumber'), 'export '+trial,
    'const KeyboardInput="input";',
    'const inventoryReportScreen = id => ({operation:"movement",id});',
    'const supplierScreen = id => ({operation:"statement",id});',
    'const currencyScreen = id => id ? ({operation:"exchange",id}) : "currency-exchange";',
    sourceOf('categoryTitle'), sourceOf('computePeriodDateRange'), wh,
    ...['warehousesScreen','AppHeader','AccountPickerModal','PurchasesHeader','FinancialFooter','ExportSideMenu'].filter(n=>n!=='AppHeader').map(n=>'export '+sourceOf(n)),
    'export '+coa, 'export '+vendors,
  ].join('\n');
}
