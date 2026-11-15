import type { LowStockItem } from "./dashboardMath";
export type Alert = {
  id: string; type: "due" | "stock" | "system" | "backup";
  title: string; description: string; date?: string; important?: boolean;
};
export type DueRow = {
  id: number; name: string | false; partner_id: [number, string] | false;
  invoice_date_due: string | false; amount_residual: number;
  move_type: string; currency_id: [number, string] | false;
};
const dayKey = (date: Date) =>
  [date.getFullYear(), String(date.getMonth() + 1).padStart(2, "0"), String(date.getDate()).padStart(2, "0")].join("-");
export function upcomingWindow(now = new Date()) {
  const end = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  end.setDate(end.getDate() + 7);
  return { start: dayKey(now), end: dayKey(end) };
}
export function dueAlerts(rows: DueRow[], today: string): Alert[] {
  return rows.filter(row => !!row.invoice_date_due && row.invoice_date_due >= today &&
    typeof row.amount_residual === "number" && row.amount_residual > 0)
    .map(row => ({
      id: "due:" + row.id, type: "due" as const, important: row.invoice_date_due === today,
      title: row.move_type === "in_invoice" ? "استحقاق فاتورة مورد" : "استحقاق فاتورة عميل",
      description: (row.name || "فاتورة " + row.id) + " · " +
        (Array.isArray(row.partner_id) ? row.partner_id[1] : "بدون اسم") +
        " · المتبقي " + new Intl.NumberFormat("ar-YE").format(row.amount_residual) +
        (Array.isArray(row.currency_id) ? " " + row.currency_id[1] : ""),
      date: row.invoice_date_due || undefined,
    })).sort((a, b) => (a.date ?? "").localeCompare(b.date ?? ""));
}
export function recentStockAlerts(items: LowStockItem[], now = new Date()): Alert[] {
  const cutoff = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  cutoff.setDate(cutoff.getDate() - 7);
  const minDate = dayKey(cutoff);
  return items.filter(item => !!item.updatedAt && item.updatedAt.slice(0, 10) >= minDate)
    .slice(0, 10).map(item => ({
      id: "stock:" + item.id, type: "stock", important: false,
      title: "قاعدة مخزون منخفض حُدّثت مؤخرًا",
      description: item.name + " · " + item.location + " · المتوفر " +
        item.available + " من الحد " + item.minimum + " " + item.unit,
      date: item.updatedAt?.slice(0, 10),
    }));
}
