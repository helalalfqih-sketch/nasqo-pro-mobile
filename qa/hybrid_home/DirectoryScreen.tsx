import React, {useLayoutEffect, useMemo, useState} from 'react';
import {
  AccountPickerModal, ChartOfAccountsModal, ExportSideMenu, FinancialFooter,
  PurchasesHeader, PurchasesPage, warehousesScreen,
} from 'dashboard:presentation';
import {formatAmount} from '../../src/accounting';
import {Workspace, send} from './workspace';
import {directoryTotals} from './directory_amounts';

export function DirectoryScreen({data, base, rows, close, backRef, tile, navigate}) {
  const [layer,setLayer] = useState('');
  const [onlyCurrency,setOnlyCurrency] = useState(false);
  const wh = useMemo(warehousesScreen, []);
  const accountAction = (op,id) => send('account',{op,id});
  const warehouse = (op,id?) => send('warehouse',id ? {op,id} : {op});
  const filter = (period,currency) => send('filter',{period,currency});
  const accounts = data.accounts ?? [];
  const category = data.category ?? rows.find(row=>row.id===data.group)?.category ?? 'purchases';
  const route = dest => {
    if (typeof dest === 'string') {tile(dest);return;}
    if (dest.operation==='movement') warehouse('movement',dest.id);
    else accountAction(dest.operation,dest.id);
  };
  const flow = {push:route,pop:close};
  const ctx = {...base, accounts, accountGroups:rows, warehouses:data.warehouses ?? [],
    ledger:[], dir:data, accountAction, warehouse, onlyCurrency, setOnlyCurrency,
    filter, flowRef:{current:flow}, categoryCurrencies:{[category]:data.currency},
    setCategoryCurrency:(_,c)=>filter(data.period,c), openSheet:()=>document.querySelector('select[aria-label="ترتيب المشتريات"]')?.focus(),
    openExportMenu:()=>setLayer('export'), openPrintOptions:()=>setLayer('export'),
    openAccountPicker:()=>setLayer('picker'), openAccountEdit:a=>accountAction('edit',a.id),
    openAccountCreate:()=>navigate('account-new'), openInvoice:()=>tile('new-invoice'),
    openTransaction:a=>a ? accountAction('voucher',a.id) : tile('new-voucher'),
    openTransferModal:id=>id ? accountAction('transfer',id) : tile('new-transfer'),
    openVendorInvoice:(a,kind='invoice')=>a ? accountAction(kind,a.id) :
      tile({invoice:'new-invoice',return:'new-return',order:'new-order',quote:'quote'}[kind]),
  };
  useLayoutEffect(()=>{
    backRef.current=()=>{
      if (document.querySelector('.vendor-menu-layer')) {document.querySelector<HTMLElement>('.vendor-menu-layer .context-menu-backdrop')?.click();return;}
      if (document.querySelector('.purchase-create-layer')) {document.querySelector<HTMLElement>('.purchase-create-layer .context-menu-backdrop')?.click();return;}
      if (document.querySelector('[role="listbox"]')) {document.querySelector<HTMLElement>('.account-select')?.click();return;}
      if (layer) setLayer(''); else close();
    };
    return ()=>{backRef.current=null;};
  },[layer,close]);
  const selectedAccounts = onlyCurrency && data.currency!=='الكل'
    ? accounts.filter(a=>a.currency===data.currency || a.amounts[data.currency]?.entryCount>0) : accounts;
  const totals=directoryTotals(selectedAccounts,data.currency);
  const amount = (fn) => totals.length ? totals.map(([c,t])=>formatAmount(fn(t))+(data.currency==='الكل'?' '+c:'')).join(' · ') : '0';
  const picker = <AccountPickerModal open onClose={data.screen==='picker' ? close : ()=>setLayer('')}
    onAddAccount={()=>navigate('account-new')} onConfirm={a=>accountAction('statement',a.id)}/>;
  return <Workspace.Provider value={ctx}>
    {data.screen==='warehouses' || data.screen==='suppliers' ? <div className="flow-stack hybrid-directory">
      <div className="flow-fixed-header">{data.screen==='warehouses' ? wh.header(flow) :
        <PurchasesHeader flow={flow} category={category} groupTitle={rows.find(row=>row.id===data.group)?.name}/>}</div>
      <div className="flow-scenes"><div className="flow-screen">{data.screen==='warehouses' ? wh.render(flow) :
        <PurchasesPage flow={flow} category={category} groupId={data.group ?? undefined}/>}</div></div>
      <div className="flow-fixed-footer">{data.screen==='warehouses' ? wh.footer() :
        <FinancialFooter debit={amount(t=>t.debit)} credit={amount(t=>t.credit)} balance={amount(t=>Math.abs(t.credit-t.debit))}
          hidePrimaryAction onMenu={()=>setLayer('export')}/>}</div>
    </div> : null}
    {data.screen==='chart' && <ChartOfAccountsModal open onClose={close}/>}
    {(data.screen==='picker' || layer==='picker') && picker}
    {layer==='export' && <ExportSideMenu open kind="purchases" onClose={()=>setLayer('')} onSelectAction={format=>{
      setLayer('');
      if (format==='import') navigate('account-import');
      else send('directoryExport',{format,onlyCurrency});
    }}/>}
  </Workspace.Provider>;
}
