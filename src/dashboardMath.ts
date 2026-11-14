export type DailySales = { date: string; amount: number };
export type SalesCurrency = { id: number; currency: string; total: number; count: number; daily: DailySales[] };
export type LowStockItem = { id: number; name: string; location: string; unit: string; available: number; minimum: number };
export type InvoiceRow = {
  id: number; invoice_date: string | false; move_type: string;
  amount_total: number; currency_id: [number, string] | false;
};
export type OrderPoint = {
  id: number; product_id: [number, string] | false;
  product_min_qty: number; qty_on_hand: number | false;
  location_id: [number, string] | false; product_uom: [number, string] | false;
};
function isoDay(day: Date): string {
  return [day.getFullYear(), String(day.getMonth() + 1).padStart(2, "0"), String(day.getDate()).padStart(2, "0")].join("-");
}
export function lastSevenDays(reference = new Date()): string[] {
  const today = new Date(reference.getFullYear(), reference.getMonth(), reference.getDate());
  return Array.from({ length: 7 }, (_, i) => {
    const day = new Date(today);
    day.setDate(today.getDate() - 6 + i);
    return isoDay(day);
  });
}
export function sumSales(rows: InvoiceRow[], days: string[]): SalesCurrency[] {
  const allowed = new Set(days);
  const groups = new Map<number, { label: string; count: number; day: Map<string, number> }>();
  for (const row of rows) {
    if (!row.invoice_date || !allowed.has(row.invoice_date) ||
        !Array.isArray(row.currency_id) || !Number.isFinite(row.amount_total)) continue;
    if (row.move_type !== "out_invoice" && row.move_type !== "out_refund") continue;
    const [id, label] = row.currency_id;
    const group = groups.get(id) ?? { label, count: 0, day: new Map(days.map(d => [d, 0])) };
    const amount = Math.abs(row.amount_total) * (row.move_type === "out_refund" ? -1 : 1);
    group.day.set(row.invoice_date, (group.day.get(row.invoice_date) ?? 0) + amount);
    group.count += 1;
    groups.set(id, group);
  }
  return [...groups].map(([id, group]) => ({
    id, currency: group.label, count: group.count,
    total: Number([...group.day.values()].reduce((a, v) => a + v, 0).toFixed(2)),
    daily: days.map(date => ({ date, amount: Number((group.day.get(date) ?? 0).toFixed(2)) })),
  })).sort((a, b) => b.count - a.count);
}
export function lowStockRows(rows: OrderPoint[]): LowStockItem[] {
  return rows.filter(row =>
    Number.isFinite(row.product_min_qty) && row.product_min_qty > 0 &&
    typeof row.qty_on_hand === "number" && Number.isFinite(row.qty_on_hand) &&
    row.qty_on_hand < row.product_min_qty
  ).map(row => ({
    id: row.id, name: Array.isArray(row.product_id) ? row.product_id[1] : "صنف #" + row.id,
    location: Array.isArray(row.location_id) ? row.location_id[1] : "الموقع غير محدد",
    unit: Array.isArray(row.product_uom) ? row.product_uom[1] : "",
    available: row.qty_on_hand as number, minimum: row.product_min_qty,
  })).sort((a, b) => b.minimum - b.available - (a.minimum - a.available));
}
