import { useCallback, useEffect, useState } from "react";
import { rpc, useLiveOdoo } from "./liveOdoo";
import type { Alert, DueRow } from "./dashboardAlertMath";
import { upcomingWindow, dueAlerts } from "./dashboardAlertMath";

export type AlertStatus = "loading" | "ready" | "denied" | "error";
type SystemRow = {
  id: number; subject: string | false; date: string | false;
};
type Source = { status: AlertStatus; items: Alert[] };
type AlertState = { due: Source; system: Source };
const sourceEmpty = (): Source => ({ status: "loading", items: [] });
export function useDashboardAlerts() {
  const live = useLiveOdoo();
  const [revision, setRevision] = useState(0);
  const [state, setState] = useState<AlertState>({
    due: sourceEmpty(), system: sourceEmpty(),
  });
  useEffect(() => {
    if (live.status !== "ready" || !live.enabled) return;
    const ctrl = new AbortController();
    setState({ due: sourceEmpty(), system: sourceEmpty() });
    const days = upcomingWindow();
    const status = (err: unknown): AlertStatus =>
      err instanceof Error && err.message === "ODOO_ACCESS_DENIED" ? "denied" : "error";
    const due = rpc<unknown>("/web/dataset/call_kw/account.move/search_read", {
      model: "account.move", method: "search_read",
      args: [[
        ["state", "=", "posted"],
        ["move_type", "in", ["out_invoice", "in_invoice"]],
        ["amount_residual", ">", 0],
        ["invoice_date_due", ">=", days.start],
        ["invoice_date_due", "<=", days.end],
      ]],
      kwargs: { fields: ["id", "name", "partner_id", "invoice_date_due",
        "amount_residual", "move_type", "currency_id"], order: "invoice_date_due asc, id desc", limit: 60 },
    }, ctrl.signal).then(rows => {
      if (!ctrl.signal.aborted) setState(prev => ({
        ...prev, due: {
          status: Array.isArray(rows) ? "ready" : "error",
          items: Array.isArray(rows) ? dueAlerts(rows as DueRow[], days.start) : [],
        },
      }));
    }).catch(error => {
      if (!ctrl.signal.aborted) setState(prev => ({ ...prev, due: { status: status(error), items: [] } }));
    });
    const messagesSince = new Date(Date.now() - 14 * 86400000).toISOString().slice(0, 19).replace("T", " ");
    const system = rpc<unknown>("/web/dataset/call_kw/mail.message/search_read", {
      model: "mail.message", method: "search_read",
      args: [[["message_type", "=", "notification"], ["date", ">=", messagesSince]]],
      kwargs: { fields: ["id", "subject", "date"], order: "date desc, id desc", limit: 8 },
    }, ctrl.signal).then(rows => {
      const items: Alert[] = Array.isArray(rows) ? (rows as SystemRow[])
        .filter(row => typeof row.subject === "string" && !!row.subject.trim())
        .map(row => ({
          id: "system:" + row.id, type: "system", title: "رسالة نظام",
          description: (row.subject as string).slice(0, 200), date: row.date || undefined,
        })) : [];
      if (!ctrl.signal.aborted) setState(prev => ({
        ...prev, system: { status: Array.isArray(rows) ? "ready" : "error", items },
      }));
    }).catch(error => {
      if (!ctrl.signal.aborted) setState(prev => ({ ...prev, system: { status: status(error), items: [] } }));
    });
    void Promise.allSettled([due, system]);
    return () => ctrl.abort();
  }, [live.enabled, live.status, live.userId, revision]);
  const refresh = useCallback(() => setRevision(n => n + 1), []);
  return { ...state, refresh };
}
