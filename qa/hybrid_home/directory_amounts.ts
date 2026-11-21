import {formatAmount} from '../../src/accounting';
const zero = {debitTotal:0, creditTotal:0, netBalance:0, tone:'neutral', entryCount:0};
export function summaryOf(account, currency) {
  if (currency !== 'الكل') return account.amounts?.[currency] ?? zero;
  const rows = Object.values(account.amounts ?? {}) as (typeof zero)[];
  return {...zero,entryCount:rows.reduce((sum,row)=>sum+row.entryCount,0)};
}
export function balanceLabel(account, currency) {
  const label = (s: typeof zero) => formatAmount(s.netBalance)+(s.tone==='credit' ? '-' : '');
  if (currency !== 'الكل') return label(summaryOf(account,currency));
  return Object.keys(account.amounts).map(c=>label(account.amounts[c])+' '+c).join(' · ');
}
export function directoryTotals(accounts, currency?: string) {
  const totals = new Map<string,{debit:number,credit:number}>();
  for (const a of accounts) {
    const keys = currency && currency !== 'الكل' ? [currency] : Object.keys(a.amounts);
    for (const c of keys) {
      const t=totals.get(c) ?? {debit:0,credit:0};
      const s=summaryOf(a,c);
      t.debit+=s.debitTotal; t.credit+=s.creditTotal;
      totals.set(c,t);
    }
  }
  return [...totals];
}
export const currencyFooter = accounts => directoryTotals(accounts).map(([c,t]) =>
  `${c} · إجمالي المدين ${formatAmount(t.debit)} · إجمالي الدائن ${formatAmount(t.credit)}`).join(' | ');
