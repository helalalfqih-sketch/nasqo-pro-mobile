import { useLiveOdoo, type LiveInvoice } from "./liveOdoo";
import { MobileScroll } from "./mobile";

const formatAmount = (n: number) => new Intl.NumberFormat("ar-YE", {
  maximumFractionDigits: 2,
}).format(n);

export function LiveInvoicesPage({ partnerId }: { partnerId?: number }) {
  const live = useLiveOdoo();
  const records: LiveInvoice[] = partnerId
    ? live.invoices.filter(invoice => Array.isArray(invoice.partner_id) && invoice.partner_id[0] === partnerId)
    : live.invoices;
  const failed = live.problems.includes("الفواتير");
  return <MobileScroll className="app-screen">
    <main className="live-invoice-page">
      <p className="live-data-notice">فواتير من نسقو ERP · آخر 100 سجل متاح · قراءة فقط</p>
      {failed ? <p className="live-data-error">هذا الحساب لا يملك صلاحية قراءة الفواتير أو الوحدة غير متاحة.</p>
        : records.length === 0 ? <p className="live-data-empty">لا توجد فواتير متاحة لهذه القائمة.</p> : null}
      {records.map(invoice => <article key={invoice.id} className="live-invoice-card">
        <div className="live-invoice-top">
          <strong>{invoice.name || "فاتورة " + invoice.id}</strong>
          <span>{invoice.move_type === "in_invoice" ? "مشتريات" : "مبيعات"}</span>
        </div>
        <div>{Array.isArray(invoice.partner_id) ? invoice.partner_id[1] : "بدون جهة اتصال"}</div>
        <div className="live-invoice-top">
          <time>{invoice.invoice_date || "بدون تاريخ"}</time>
          <b>{formatAmount(invoice.amount_total)}</b>
        </div>
        <small>{invoice.state === "posted" ? "مرحل" : invoice.state === "draft" ? "مسودة" : invoice.state}</small>
      </article>)}
    </main>
  </MobileScroll>;
}
