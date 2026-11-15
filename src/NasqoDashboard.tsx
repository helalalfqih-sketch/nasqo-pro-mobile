import { useEffect, useMemo, useState, type ReactNode } from "react";
import { curveMonotoneX, line, max, min, scaleLinear, scalePoint } from "d3";
import { useLiveOdoo } from "./liveOdoo";
import { DashboardReorder } from "./DashboardReorder";
import { DashboardScanner } from "./DashboardScanner";
import { DashboardNotifications, DashboardFavorites, DashboardSettings, useDashboardTheme } from "./DashboardExtras";
import { useDashboardAlerts } from "./dashboardAlerts";
import { recentStockAlerts } from "./dashboardAlertMath";
import { backupAgeDays, useDashboardPreferences, vibrateFeedback, type WidgetId } from "./dashboardPreferences";

import { useNasqoDashboardData, type DataStatus, type DailySales } from "./dashboardData";
import { createDashboardPdf, numberAr, type ExportMode } from "./dashboardPdf";
import { FileTextIcon, PersonIcon, PlusIcon, ReloadIcon, BackpackIcon, Share1Icon, DownloadIcon } from "@radix-ui/react-icons";

type Actions = {
  newInvoice: () => void;
  newPurchase: () => void;
  newContact: () => void;
  openInvoices: () => void;
  openStock: () => void;
  openContact: (id: number) => void;
};

function unavailable(status: DataStatus, subject: string): string {
  if (status === "denied") return "ليس لديك صلاحية قراءة " + subject + " في Odoo.";
  if (status === "too-many") return "عدد السجلات كبير؛ لم نحسب إجماليًا غير مكتمل.";
  if (status === "loading") return "جارٍ تحميل البيانات الفعلية…";
  if (status === "error") return "تعذّر قراءة " + subject + " من Odoo. حاول التحديث.";
  return "";
}

function Sparkline({ points, currency }: { points: DailySales[]; currency: string }) {
  const width = 360, height = 122;
  const x = useMemo(() => scalePoint<string>().domain(points.map(point => point.date)).range([18, width - 18]), [points]);
  const bottom = min(points, item => item.amount) ?? 0;
  const top = max(points, item => item.amount) ?? 0;
  const y = scaleLinear().domain([Math.min(0, bottom), Math.max(1, top)]).nice().range([height - 30, 10]);
  const path = line<DailySales>().x(point => x(point.date) ?? 18).y(point => y(point.amount)).curve(curveMonotoneX)(points);
  return <div className="insight-chart-scroll">
    <svg className="insight-sparkline" viewBox={"0 0 " + width + " " + height}
      role="img" aria-label={"اتجاه المبيعات لآخر سبعة أيام بعملة " + currency}>
      <line x1="18" x2={width - 18} y1={y(0)} y2={y(0)}
        stroke="#b7cddd" strokeDasharray="4 4" strokeWidth="1" />
      {path ? <path d={path} fill="none" stroke="var(--nasqo-blue)"
        strokeWidth="2.7" strokeLinecap="round" strokeLinejoin="round" /> : null}
      {points.map(point => <g key={point.date}>
        <circle cx={x(point.date) ?? 18} cy={y(point.amount)} r="3.4"
          fill="var(--nasqo-orange)" stroke="#ffffff" strokeWidth="1.2">
          <title>{point.date + ": " + numberAr(point.amount) + " " + currency}</title>
        </circle>
        <text x={x(point.date) ?? 18} y={height - 8} textAnchor="middle"
          fill="#526e86" fontSize="10">{point.date.slice(5).replace("-", "/")}</text>
      </g>)}
    </svg>
  </div>;
}

export function NasqoDashboard({ newInvoice, newPurchase, newContact, openInvoices, openStock, openContact }: Actions) {
  const live = useLiveOdoo();
  const data = useNasqoDashboardData();
  const preferences = useDashboardPreferences(live.userId ?? 0);
  const prefs = preferences.value;
  const alerts = useDashboardAlerts();
  useDashboardTheme(prefs);
  const [scannerOpen, setScannerOpen] = useState(false);
  const recentAlerts = [
    ...alerts.due.items, ...recentStockAlerts(data.lowStock), ...alerts.system.items,
  ];
  useEffect(() => {
    const date = prefs.lastBackupDate;
    const age = backupAgeDays(date);
    if (age === null || age <= 7 || !prefs.deviceNotifications || !date ||
        prefs.lastBackupNoticeDate === date || !("Notification" in window) ||
        Notification.permission !== "granted") return;
    try {
      new Notification("تنبيه نسقو — متابعة النسخ الاحتياطي", {
        body: "مر أكثر من سبعة أيام على تاريخ التصدير المسجل يدويًا. تحقق من آخر تصدير كامل.",
        tag: "nasqo-backup-age",
      });
      preferences.update({ lastBackupNoticeDate: date });
    } catch { /* Some mobile browsers restrict local notifications. */ }
  }, [prefs.lastBackupDate, prefs.lastBackupNoticeDate, prefs.deviceNotifications]);

  const [preferredCurrency, setPreferredCurrency] = useState<number | null>(null);
  const [showAllLowStock, setShowAllLowStock] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [notice, setNotice] = useState("");
  const chosen = data.sales.find(item => item.id === preferredCurrency) ?? data.sales[0];
  const invoices = useMemo(() =>
    [...live.invoices].sort((a, b) => String(b.invoice_date || "").localeCompare(String(a.invoice_date || "")) ||
      b.id - a.id).slice(0, 5),
  [live.invoices]);
  const visibleLow = showAllLowStock ? data.lowStock.slice(0, 150) : data.lowStock.slice(0, 5);
  const pending = data.salesStatus === "loading" || data.stockStatus === "loading";
  const canExport = !pending && (data.salesStatus === "ready" || data.stockStatus === "ready");

  const exportReport = async (mode: ExportMode) => {
    if (!canExport || exporting) return;
    setExporting(true);
    setNotice("");
    try {
      const result = await createDashboardPdf(data, live.problems.includes("الفواتير") ? [] : invoices, mode);
      setNotice(result === "shared" ? "فُتحت مشاركة التقرير" :
        "تم تجهيز ملف PDF للتنزيل؛ يمكنك مشاركته بعد حفظه.");
    } catch (error) {
      const cancelled = error instanceof Error && error.name === "AbortError";
      setNotice(cancelled ? "أُلغيت المشاركة دون إرسال التقرير." :
        "تعذّر إنشاء PDF على هذا المتصفح؛ لا توجد أي مشاركة أو إرسال.");
    } finally {
      setExporting(false);
    }
  };

  const summaryCards: Record<string, ReactNode> = {
    sales: (
      <article className="insight-summary-card">
        <span>إجمالي المبيعات الصافي · ٧ أيام</span>
        {data.salesStatus === "ready" ? chosen ?
          <strong dir="auto">{numberAr(chosen.total)} <small>{chosen.currency}</small></strong> :
          <strong>لا توجد مبيعات مرحّلة</strong> :
          <p className="insight-unavailable">{unavailable(data.salesStatus, "المبيعات")}</p>}
        {data.salesStatus === "ready" && data.sales.length > 1 ?
          <select aria-label="عملة ملخص المبيعات" value={chosen?.id ?? ""}
            onChange={event => setPreferredCurrency(Number(event.target.value))}>
            {data.sales.map(item => <option key={item.id} value={item.id}>{item.currency}</option>)}
          </select> : null}
        <small>الفواتير المرحّلة − المردودات؛ دون دمج عملات مختلفة</small>
      </article>
    ),
    invoices: (
      <article className="insight-summary-card">
        <span>الفواتير الأخيرة</span>
        <strong>{live.problems.includes("الفواتير") ? "غير متاحة" : numberAr(live.invoices.length)}</strong>
        <small>{live.problems.includes("الفواتير") ? "لا تتوفر صلاحية قراءة هذه الفواتير" :
          "أحدث السجلات المتاحة من حد 100 فاتورة"}</small>
        <button className="insight-text-action" onClick={openInvoices}>عرض الفواتير</button>
      </article>
    ),
    lowStock: (
      <article className="insight-summary-card insight-low-summary">
        <span><BackpackIcon /> تنبيهات انخفاض المخزون</span>
        <strong>{data.stockStatus === "ready" ? numberAr(data.lowStock.length) : "—"}</strong>
        <small>{data.stockStatus === "ready" ? "أقل من حد إعادة الطلب المعرّف" :
          unavailable(data.stockStatus, "قواعد إعادة الطلب")}</small>
      </article>
    ),
  };
  const widgets: Record<WidgetId, ReactNode> = {
    notifications: <DashboardNotifications alerts={recentAlerts}
      dueStatus={alerts.due.status} systemStatus={alerts.system.status}
      backupDate={prefs.lastBackupDate} refresh={() => { alerts.refresh(); data.refresh(); }} />,
    favorites: <DashboardFavorites prefs={prefs} update={preferences.update}
      partners={live.partners} openContact={openContact} />,
    trend: (
    <section className="insights-panel" aria-label="اتجاهات المبيعات">
      <div className="insights-panel-heading"><h3>اتجاه المبيعات · آخر ٧ أيام</h3>
        {chosen ? <span>{chosen.currency}</span> : null}</div>
      {data.salesStatus !== "ready" ?
        <p className="insight-unavailable">{unavailable(data.salesStatus, "اتجاه المبيعات")}</p> :
        chosen ? <Sparkline points={chosen.daily} currency={chosen.currency}/> :
          <p className="insight-unavailable">لا توجد فواتير مبيعات مرحّلة خلال الأيام السبعة الماضية.</p>}
    </section>
    ),
    invoices: (
    <section className="insights-panel" aria-label="أحدث الفواتير">
      <div className="insights-panel-heading"><h3>أحدث الفواتير</h3>
        <button className="insight-text-action" onClick={openInvoices}>الكل</button></div>
      {live.problems.includes("الفواتير") ?
        <p className="insight-unavailable">الفواتير غير متاحة لصلاحيات الحساب الحالي.</p> :
        invoices.length ? <div className="insight-invoices-list">{invoices.map(invoice =>
          <button key={invoice.id} className="insight-invoice-row" onClick={openInvoices}
            aria-label={"عرض فواتير Odoo — " + String(invoice.name || invoice.id)}>
            <span><strong>{invoice.name || "فاتورة " + invoice.id}</strong>
              <small>{invoice.invoice_date || "بدون تاريخ"} · {Array.isArray(invoice.partner_id) ? invoice.partner_id[1] : "—"}</small></span>
            <b dir="ltr">{numberAr(invoice.amount_total)} {Array.isArray(invoice.currency_id) ? invoice.currency_id[1] : ""}</b>
          </button>)}</div> :
          <p className="insight-unavailable">لا توجد فواتير في السجلات المتاحة.</p>}
    </section>
    ),
    lowStock: (
    <section className="insights-panel insight-low-panel" aria-label="الأصناف منخفضة المخزون">
      <div className="insights-panel-heading"><h3>الأصناف دون الحد الأدنى</h3>
        <button className="insight-text-action" onClick={openStock}>المخزون في Odoo</button></div>
      {data.stockStatus !== "ready" ?
        <p className="insight-unavailable">{unavailable(data.stockStatus, "قواعد إعادة الطلب")}</p> :
        data.lowStock.length ? <>
          <ul className="insight-low-list">{visibleLow.map(item =>
            <li key={item.id}>
              <strong>{item.name}</strong>
              <small>{item.location}</small>
              <div>المتوفر: <b>{numberAr(item.available)} {item.unit}</b> · الحد الأدنى:
                <b>{numberAr(item.minimum)} {item.unit}</b></div>
            </li>)}</ul>
          {data.lowStock.length > 5 ? <button className="insight-show-more"
            onClick={() => setShowAllLowStock(value => !value)}>
            {showAllLowStock ? "عرض أقل" : "عرض المزيد (" + numberAr(data.lowStock.length) + ")"}
          </button> : null}
          {data.lowStock.length > 150 && showAllLowStock ?
            <p className="insight-unavailable">تُعرض أول 150 قاعدة؛ راجع البقية من Odoo.</p> : null}
        </> : <p className="insight-success">لا توجد أصناف أقل من الحد الأدنى ضمن قواعد إعادة الطلب المسموح بها.</p>}
    </section>
    ),
    quick: (
    <section className="insights-panel" aria-label="الإجراءات السريعة">
      <h3>الإجراءات السريعة</h3>
      <div className="insight-quick-actions">
        <button onClick={newInvoice}><FileTextIcon /> فاتورة جديدة</button>
        <button onClick={newPurchase}><PlusIcon /> عملية شراء جديدة</button>
        <button onClick={newContact}><PersonIcon /> جهة اتصال جديدة</button>
        <button onClick={() => setScannerOpen(true)}>▦ مسح QR / باركود</button>
      </div>
    </section>
    ),
    export: (
    <section className="insights-panel insight-export" aria-label="تصدير الملخص المالي">
      <div><h3>التقرير المالي والمخزون</h3>
        <p>ملف PDF يتضمن ملخص المبيعات والفواتير وقائمة المخزون المتاحة حسب صلاحيات Odoo.</p></div>
      <div className="insight-export-actions">
        <button disabled={!canExport || exporting} onClick={() => void exportReport("download")}>
          <DownloadIcon /> تصدير PDF</button>
        <button disabled={!canExport || exporting} onClick={() => void exportReport("share")}>
          <Share1Icon /> مشاركة PDF</button>
      </div>
      {notice ? <p className="insight-export-notice" role="status">{notice}</p> : null}
    </section>
    ),
    settings: <DashboardSettings prefs={prefs} update={preferences.update} />,
  };
  return <>
    <section className="nasqo-insights" data-testid="nasqo-dashboard-insights" aria-label="لوحة التحكم المالية">
    <div className="insights-heading">
      <div>
        <h2>لوحة التحكم</h2>
        <p>ملخص أعمالك من Odoo · {data.start || "—"} إلى {data.end || "—"}</p>
      </div>
      <button className="insights-refresh" onClick={() => { data.refresh(); live.refresh(); }}
        aria-label="تحديث لوحة التحكم" title="تحديث البيانات"><ReloadIcon /></button>
    </div>

      <p className="nasqo-arrange-help">يمكنك إعادة ترتيب البطاقات والأدوات بسحب علامة ⠿.</p>
      <DashboardReorder
        summaryOrder={prefs.summaryOrder}
        widgetOrder={prefs.widgetOrder}
        summaryCards={summaryCards}
        widgets={widgets}
        onSummary={summaryOrder => preferences.update({ summaryOrder })}
        onWidgets={widgetOrder => preferences.update({ widgetOrder })}
        haptic={() => vibrateFeedback(prefs.haptics, "pin")}
      />
    </section>
    {scannerOpen ? <DashboardScanner onClose={() => setScannerOpen(false)} haptics={prefs.haptics} /> : null}
  </>;
}
