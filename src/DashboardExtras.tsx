import { useEffect, useMemo, useState } from "react";
import type { LivePartner } from "./liveOdoo";
import type { Alert } from "./dashboardAlertMath";
import type { AlertStatus } from "./dashboardAlerts";
import type { DashboardPrefs, FavoriteId, ThemeMode } from "./dashboardPreferences";
import { backupAgeDays, contrastOn, vibrateFeedback } from "./dashboardPreferences";
import { openNativeOdoo, type NativeOdooAction } from "./odooNavigation";

const reportNames: { id: NativeOdooAction; label: string }[] = [
  { id: "partnerLedger", label: "تقرير كشف الحساب" },
  { id: "customerInvoices", label: "فواتير العملاء" },
  { id: "vendorBills", label: "فواتير الموردين" },
  { id: "stockMoves", label: "حركة المخزون" },
  { id: "products", label: "الأصناف" },
  { id: "contacts", label: "جهات الاتصال" },
  { id: "salesOrders", label: "طلبات البيع" },
  { id: "purchaseOrders", label: "طلبات الشراء" },
];
export function useDashboardTheme(prefs: DashboardPrefs) {
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const mode = prefs.theme === "system" ? mq.matches ? "dark" : "light" : prefs.theme;
      document.body.setAttribute("data-nasqo-color-mode", mode);
      document.body.style.setProperty("--nasqo-blue", prefs.primary);
      document.body.style.setProperty("--nasqo-on-primary", contrastOn(prefs.primary));
      const app = document.querySelector<HTMLElement>(".nasqo-app");
      if (app) {
        app.setAttribute("data-color-mode", mode);
        app.style.setProperty("--nasqo-blue", prefs.primary);
        app.style.setProperty("--nasqo-on-primary", contrastOn(prefs.primary));
      }
      let meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
      if (!meta) {
        meta = document.createElement("meta");
        meta.name = "theme-color";
        document.head.append(meta);
      }
      meta.content = prefs.primary;
    };
    apply();
    mq.addEventListener?.("change", apply);
    return () => {
      mq.removeEventListener?.("change", apply);
      document.body.removeAttribute("data-nasqo-color-mode");
      document.body.style.removeProperty("--nasqo-blue");
      document.body.style.removeProperty("--nasqo-on-primary");
    };
  }, [prefs.theme, prefs.primary]);
  useEffect(() => {
    const callback = (event: MouseEvent) => {
      if (!(event.target instanceof Element) ||
          !(event.target.closest(".nasqo-app button") || event.target.closest(".nasqo-scan-overlay button"))) return;
      const kind = event.target.closest("[data-haptic]")?.getAttribute("data-haptic");
      vibrateFeedback(prefs.haptics, kind === "success" || kind === "pin" ? kind : "tap");
    };
    document.addEventListener("click", callback, true);
    return () => document.removeEventListener("click", callback, true);
  }, [prefs.haptics]);
}

export function DashboardFavorites({ prefs, update, partners, openContact }: {
  prefs: DashboardPrefs; update: (p: Partial<DashboardPrefs>) => void;
  partners: LivePartner[]; openContact: (id: number) => void;
}) {
  const [selected, setSelected] = useState<FavoriteId>("report:partnerLedger");
  const visible = useMemo(() => prefs.favorites.map(id => {
    if (id.startsWith("report:")) {
      const report = reportNames.find(report => "report:" + report.id === id);
      return report ? { id, label: report.label } : null;
    }
    if (id.startsWith("contact:")) {
      const partner = partners.find(p => String(p.id) === id.slice(8));
      return partner ? { id, label: partner.name } : null;
    }
    return null;
  }).filter((x): x is { id: string; label: string } => !!x), [prefs.favorites, partners]);
  const pin = () => {
    if (!selected || prefs.favorites.includes(selected) || prefs.favorites.length >= 8) return;
    update({ favorites: [...prefs.favorites, selected] });
    vibrateFeedback(prefs.haptics, "pin");
  };
  return <section className="insights-panel nasqo-favorites-panel" aria-label="المفضلة">
    <h3>⭐ المفضلة</h3>
    <p>ثبّت التقارير أو حسابات العملاء المتكررة للعودة إليها بسرعة.</p>
    <div className="nasqo-favorites-row">{visible.length ? visible.map(item =>
      <span className="nasqo-favorite" key={item.id}>
        <button type="button" onClick={() => {
          if (item.id.startsWith("report:")) openNativeOdoo(item.id.slice(7) as NativeOdooAction);
          else openContact(Number(item.id.slice(8)));
        }}>{item.label}</button>
        <button aria-label={"إزالة " + item.label + " من المفضلة"} onClick={() =>
          update({ favorites: prefs.favorites.filter(id => id !== item.id) })}>×</button>
      </span>) : <p>لا توجد عناصر مثبتة حتى الآن.</p>}</div>
    <div className="nasqo-pref-controls">
      <select aria-label="اختيار مهمة للمفضلة" value={selected} onChange={event => setSelected(event.target.value)}>
        {reportNames.map(item => <option key={item.id} value={"report:" + item.id}>{item.label}</option>)}
        {partners.map(partner =>
          <option key={partner.id} value={"contact:" + partner.id}>حساب: {partner.name}</option>)}
      </select>
      <button data-haptic="pin" disabled={prefs.favorites.length >= 8 || prefs.favorites.includes(selected)}
        onClick={pin}>تثبيت</button>
    </div>
    <small>المفضلة محلية لهذا الحساب على هذا الجهاز فقط، وتخفي الحسابات التي لم تعد ضمن صلاحياتك.</small>
  </section>;
}

function sourceStatus(status: AlertStatus, title: string) {
  if (status === "loading") return "تحميل " + title + "…";
  if (status === "denied") return "لا تتوفر صلاحية قراءة " + title + ".";
  if (status === "error") return "تعذّر تحميل " + title + ".";
  return "";
}

export function DashboardNotifications({ alerts, dueStatus, systemStatus, backupDate, refresh }: {
  alerts: Alert[]; dueStatus: AlertStatus; systemStatus: AlertStatus;
  backupDate: string | null; refresh: () => void;
}) {
  const age = backupAgeDays(backupDate);
  const stale = age !== null && age > 7;
  const allAlerts = stale ? [
    { id: "backup:stale", title: "تنبيه النسخ الاحتياطي", type: "backup" as const,
      description: "تجاوز تاريخ التصدير الكامل المسجّل يدويًا سبعة أيام. تحقق من النسخ الفعلية.",
      important: true },
    ...alerts,
  ] : alerts;
  return <section id="nasqo-notification-center" className="insights-panel nasqo-notifications" aria-label="مركز الإشعارات">
    <div className="insights-panel-heading">
      <h3>🔔 مركز الإشعارات {allAlerts.length ? "(" + allAlerts.length + ")" : ""}</h3>
      <button className="insight-text-action" onClick={refresh}>تحديث</button>
    </div>
    {dueStatus !== "ready" ? <p className="insight-unavailable">{sourceStatus(dueStatus, "مواعيد الاستحقاق")}</p> : null}
    {systemStatus !== "ready" ? <p className="insight-unavailable">{sourceStatus(systemStatus, "رسائل النظام")}</p> : null}
    {allAlerts.length ? <ul className="nasqo-notification-list">{allAlerts.map(item =>
      <li key={item.id} className={item.important ? "important" : ""}>
        <strong>{item.title}</strong><p>{item.description}</p>
        {item.date ? <time>{item.date.slice(0, 16)}</time> : null}
      </li>)}</ul> :
      <p className="insight-unavailable">لا توجد تنبيهات جديدة ضمن البيانات المتاحة حاليًا.</p>}
    <small>الإشعارات تظهر عند فتح اللوحة أو تحديثها؛ لا تُرسل رسائل تلقائية خارج التطبيق.</small>
  </section>;
}

export function DashboardSettings({ prefs, update }: {
  prefs: DashboardPrefs; update: (p: Partial<DashboardPrefs>) => void;
}) {
  const [dateDraft, setDateDraft] = useState(prefs.lastBackupDate ?? "");
  const [message, setMessage] = useState("");
  const age = backupAgeDays(prefs.lastBackupDate);
  const stale = age !== null && age > 7;
  useEffect(() => { setDateDraft(prefs.lastBackupDate ?? ""); }, [prefs.lastBackupDate]);
  const enableDeviceAlert = async () => {
    if (!("Notification" in window)) {
      setMessage("إشعارات الجهاز غير مدعومة هنا؛ التنبيه داخل لوحة التحكم متاح.");
      return;
    }
    try {
      const result = await Notification.requestPermission();
      update({ deviceNotifications: result === "granted" });
      setMessage(result === "granted" ? "تم تفعيل إشعار الجهاز عند تأخر النسخ المسجّل." :
        "لم يُسمح بإشعارات الجهاز. سيبقى التنبيه داخل اللوحة.");
    } catch {
      setMessage("تعذر تفعيل إشعارات الجهاز؛ سيبقى التنبيه داخل اللوحة.");
    }
  };
  const record = () => {
    const value = dateDraft.trim();
    const parsed = new Date(value + "T00:00:00");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(parsed.getTime()) ||
        parsed > new Date() || parsed.toISOString().slice(0, 10) !== value) {
      setMessage("اختر تاريخ تصدير صحيحًا غير مستقبلي.");
      return;
    }
    update({ lastBackupDate: value, lastBackupNoticeDate: null });
    setMessage("تم تسجيل التاريخ يدويًا على هذا الجهاز؛ لم يتحقق التطبيق من خادم النسخ.");
  };
  return <section className="insights-panel nasqo-dashboard-settings" aria-label="إعدادات لوحة التحكم">
    <h3>⚙️ إعدادات لوحة التحكم</h3>
    <div className="nasqo-setting-line">
      <label htmlFor="nasqo-theme-mode">المظهر</label>
      <select id="nasqo-theme-mode" value={prefs.theme} onChange={event =>
        update({ theme: event.target.value as ThemeMode })}>
        <option value="light">فاتح</option><option value="dark">داكن</option>
        <option value="system">حسب النظام</option>
      </select>
    </div>
    <div className="nasqo-setting-line">
      <label htmlFor="nasqo-brand-color">لون العلامة الأساسي</label>
      <input id="nasqo-brand-color" type="color" value={prefs.primary}
        onChange={event => update({ primary: event.target.value })} />
      <button type="button" onClick={() => update({ primary: "#0b5ca8" })}>الافتراضي</button>
    </div>
    <label className="nasqo-setting-line">
      <span>اهتزاز اللمس عند التفاعل (إذا دعمه الجهاز)</span>
      <input type="checkbox" checked={prefs.haptics} onChange={event => update({ haptics: event.target.checked })} />
    </label>
    <div className={"nasqo-backup-status " + (stale ? "stale" : "")}>
      <strong>آخر تصدير كامل لقاعدة البيانات</strong>
      <p>{prefs.lastBackupDate ?
        "آخر تاريخ مدخل يدويًا: " + prefs.lastBackupDate +
        (stale ? " · تجاوز 7 أيام — راجع النسخ الاحتياطية" : " · خلال آخر 7 أيام") :
        "لم يُربط مصدر موثوق لحالة النسخ، ولا يمكن التحقق تلقائيًا من آخر تصدير."}</p>
      <small>التاريخ أدناه توثيق يدوي فقط، وليس إثباتًا على اكتمال أو سلامة نسخة الخادم.</small>
      <div className="nasqo-pref-controls">
        <input type="date" aria-label="تاريخ التصدير الكامل الذي تحققت منه يدويًا"
          value={dateDraft} onChange={event => setDateDraft(event.target.value)}
          max={new Date().toISOString().slice(0, 10)} />
        <button onClick={record}>تسجيل التاريخ</button>
      </div>
      <button type="button" className="insight-text-action" onClick={() => void enableDeviceAlert()}>
        {prefs.deviceNotifications ? "إشعارات الجهاز مفعّلة" : "تفعيل تنبيه الجهاز عند التأخر"}
      </button>
    </div>
    {message ? <p className="insight-export-notice" role="status">{message}</p> : null}
  </section>;
}
