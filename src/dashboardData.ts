import { useCallback, useEffect, useState } from "react";
import { rpc, useLiveOdoo } from "./liveOdoo";
import { lastSevenDays, sumSales, lowStockRows } from "./dashboardMath";
import type { SalesCurrency, LowStockItem, InvoiceRow, OrderPoint } from "./dashboardMath";
export type { DailySales, SalesCurrency, LowStockItem } from "./dashboardMath";


export type DataStatus = "loading" | "ready" | "denied" | "error" | "too-many";
export type DashboardSnapshot = {
  start: string; end: string;
  salesStatus: DataStatus; stockStatus: DataStatus;
  sales: SalesCurrency[]; lowStock: LowStockItem[];
  salesCount: number; reorderCount: number;
};
const empty: DashboardSnapshot = {
  start: "", end: "", salesStatus: "loading", stockStatus: "loading",
  sales: [], lowStock: [], salesCount: 0, reorderCount: 0,
};
async function readAll<T>(
  model: string, domain: unknown[], fields: string[], maxRows: number, signal: AbortSignal,
): Promise<{ count: number; rows: T[] }> {
  const count = await rpc<number>("/web/dataset/call_kw/" + model + "/search_count", {
    model, method: "search_count", args: [domain], kwargs: {},
  }, signal);
  if (!Number.isSafeInteger(count) || count < 0) throw Error("INVALID_COUNT");
  if (count > maxRows) throw Error("TOO_MANY_ROWS");
  const rows: T[] = [];
  while (rows.length < count) {
    const batch = await rpc<unknown>("/web/dataset/call_kw/" + model + "/search_read", {
      model, method: "search_read", args: [domain],
      kwargs: { fields, limit: Math.min(200, count - rows.length), offset: rows.length, order: "id desc" },
    }, signal);
    if (!Array.isArray(batch) || batch.length < 1) throw Error("INCOMPLETE_ROWS");
    rows.push(...batch as T[]);
  }
  return { count, rows };
}
function statusOf(error: unknown): DataStatus {
  if (error instanceof Error && error.message === "ODOO_ACCESS_DENIED") return "denied";
  if (error instanceof Error && error.message === "TOO_MANY_ROWS") return "too-many";
  return "error";
}
export function useNasqoDashboardData(): DashboardSnapshot & { refresh: () => void } {
  const live = useLiveOdoo();
  const [revision, setRevision] = useState(0);
  const [state, setState] = useState<DashboardSnapshot>(empty);
  useEffect(() => {
    if (!live.enabled || live.status !== "ready") return;
    const abort = new AbortController();
    const days = lastSevenDays();
    const start = days[0], end = days[6];
    setState({ ...empty, start, end });
    const invoices = readAll<InvoiceRow>(
      "account.move",
      [["state", "=", "posted"], ["move_type", "in", ["out_invoice", "out_refund"]],
       ["invoice_date", ">=", start], ["invoice_date", "<=", end]],
      ["id", "invoice_date", "move_type", "amount_total", "currency_id"], 3000, abort.signal,
    ).then(result => {
      if (abort.signal.aborted) return;
      const valid = result.rows.every(row => !!row.invoice_date && Array.isArray(row.currency_id) &&
        Number.isFinite(row.amount_total) && ["out_invoice", "out_refund"].includes(row.move_type));
      setState(prev => ({ ...prev, salesStatus: valid ? "ready" : "error",
        sales: valid ? sumSales(result.rows, days) : [], salesCount: valid ? result.count : 0 }));
    }).catch(error => {
      if (!abort.signal.aborted) setState(prev => ({
        ...prev, salesStatus: statusOf(error), sales: [], salesCount: 0,
      }));
    });
    const orderpoints = readAll<OrderPoint>(
      "stock.warehouse.orderpoint", [["product_min_qty", ">", 0]],
      ["id", "product_id", "product_min_qty", "qty_on_hand", "location_id", "product_uom"],
      3000, abort.signal,
    ).then(result => {
      if (abort.signal.aborted) return;
      const valid = result.rows.every(row => typeof row.qty_on_hand === "number" &&
        Number.isFinite(row.qty_on_hand) && Number.isFinite(row.product_min_qty));
      setState(prev => ({ ...prev, stockStatus: valid ? "ready" : "error",
        lowStock: valid ? lowStockRows(result.rows) : [], reorderCount: valid ? result.count : 0 }));
    }).catch(error => {
      if (!abort.signal.aborted) setState(prev => ({
        ...prev, stockStatus: statusOf(error), lowStock: [], reorderCount: 0,
      }));
    });
    void Promise.allSettled([invoices, orderpoints]);
    return () => abort.abort();
  }, [live.enabled, live.status, revision]);
  const refresh = useCallback(() => setRevision(n => n + 1), []);
  return { ...state, refresh };
}
