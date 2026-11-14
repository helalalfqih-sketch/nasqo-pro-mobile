import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { classifyOdooFailure } from "./odooErrors";

export type LivePartner = { id: number; name: string; phone: string | false };
export type LiveWarehouse = { id: number; name: string; company_id?: [number, string] | false };
export type LiveInvoice = {
  id: number; name: string | false; partner_id: [number, string] | false;
  move_type: string; invoice_date: string | false; amount_total: number; state: string;
};

type LiveState = {
  enabled: boolean; status: "demo" | "loading" | "login" | "ready" | "error";
  userId: number | null; partners: LivePartner[]; warehouses: LiveWarehouse[];
  invoices: LiveInvoice[]; problems: string[]; deniedSections: string[]; refresh: () => void;
};

const empty = { partners: [] as LivePartner[], warehouses: [] as LiveWarehouse[], invoices: [] as LiveInvoice[] };
const Context = createContext<LiveState>({
  enabled: false, status: "demo", userId: null, ...empty, problems: [], deniedSections: [], refresh: () => {},
});
export const useLiveOdoo = () => useContext(Context);

async function rpc<T>(path: string, params: Record<string, unknown>, signal: AbortSignal): Promise<T> {
  const response = await fetch(path, {
    method: "POST", credentials: "same-origin", cache: "no-store",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", method: "call", params, id: 1 }), signal,
  });
  if (!response.ok) throw new Error("HTTP " + response.status);
  const payload = await response.json() as {
    result?: T; error?: { code?: number; data?: { name?: string } };
  };
  if (payload.error) {
    const kind = classifyOdooFailure(payload.error);
    if (kind === "login") throw new Error("LOGIN_REQUIRED");
    if (kind === "permission") throw new Error("ODOO_ACCESS_DENIED");
    throw new Error("ODOO_RPC_FAILED");
  }
  if (!Object.prototype.hasOwnProperty.call(payload, "result")) throw new Error("INVALID_RESPONSE");
  return payload.result as T;
}

async function readModel<T>(
  model: string, fields: string[], signal: AbortSignal, domain: unknown[] = [],
): Promise<T[]> {
  const data = await rpc<unknown>("/web/dataset/call_kw/" + model + "/search_read", {
    model, method: "search_read", args: [domain],
    kwargs: { fields, limit: 100, order: "id desc" },
  }, signal);
  if (!Array.isArray(data)) throw new Error("INVALID_RECORDS");
  return data as T[];
}

export function LiveOdooProvider({ children }: { children: ReactNode }) {
  const enabled = window.location.protocol === "https:" && window.location.hostname === "erp.indexesstore.com" && window.location.pathname.startsWith("/nasqo-mobile");
  const [revision, setRevision] = useState(0);
  const [state, setState] = useState<Omit<LiveState, "enabled" | "refresh">>({
    status: enabled ? "loading" : "demo", userId: null, ...empty, problems: [], deniedSections: [],
  });

  useEffect(() => {
    if (!enabled) return;
    const controller = new AbortController();
    setState({ status: "loading", userId: null, ...empty, problems: [], deniedSections: [] });
    const run = async () => {
      try {
        const session = await rpc<{ uid?: number | false }>(
          "/web/session/get_session_info", {}, controller.signal,
        );
        if (!session.uid) throw new Error("LOGIN_REQUIRED");
        const tasks = await Promise.allSettled([
          readModel<LivePartner>("res.partner", ["id", "name", "phone"], controller.signal),
          readModel<LiveWarehouse>("stock.warehouse", ["id", "name", "company_id"], controller.signal),
          readModel<LiveInvoice>(
            "account.move",
            ["id", "name", "partner_id", "move_type", "invoice_date", "amount_total", "state"],
            controller.signal, [["move_type", "in", ["in_invoice", "out_invoice"]]],
          ),
        ] as const);
        if (controller.signal.aborted) return;
        const sections = ["جهات الاتصال", "المخازن", "الفواتير"];
        const failed = tasks.map((t, i) => t.status === "rejected" ? sections[i] : null)
          .filter((v): v is string => !!v);
        const deniedSections = tasks.map((t, i) =>
          t.status === "rejected" &&
          t.reason instanceof Error && t.reason.message === "ODOO_ACCESS_DENIED" ? sections[i] : null,
        ).filter((v): v is string => !!v);
        if (failed.length === tasks.length) throw new Error("ALL_MODELS_UNAVAILABLE");
        setState({
          status: "ready", userId: session.uid,
          partners: tasks[0].status === "fulfilled" ? tasks[0].value : [],
          warehouses: tasks[1].status === "fulfilled" ? tasks[1].value : [],
          invoices: tasks[2].status === "fulfilled" ? tasks[2].value : [],
          problems: failed, deniedSections,
        });
      } catch (error) {
        if (controller.signal.aborted) return;
        setState({
          status: error instanceof Error && error.message === "LOGIN_REQUIRED" ? "login" : "error",
          userId: null, ...empty, problems: [], deniedSections: [],
        });
      }
    };
    void run();
    return () => controller.abort();
  }, [enabled, revision]);

  const value = useMemo<LiveState>(() => ({
    ...state, enabled, refresh: () => setRevision(n => n + 1),
  }), [state, enabled]);
  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function LiveOdooGate({ children }: { children: ReactNode }) {
  const live = useLiveOdoo();
  if (!live.enabled || live.status === "ready") return <>{children}</>;
  const loginUrl = "/web/login?redirect=" + encodeURIComponent(window.location.pathname);
  return <main dir="rtl" className="live-odoo-gate">
    <h2>نسقو برو</h2>
    <p>{live.status === "loading" ? "جارٍ التحقق من اتصال نسقو ERP..." :
      live.status === "login" ? "سجّل الدخول إلى نسقو ERP لعرض بياناتك الفعلية بصلاحيات حسابك." :
        "تعذّر تحميل بيانات نسقو ERP. لم يتم عرض أي بيانات تجريبية بدلًا عنها."}</p>
    {live.status === "login" ? <a href={loginUrl}>تسجيل الدخول إلى نسقو</a> : null}
    {live.status === "error" ? <button type="button" onClick={live.refresh}>إعادة المحاولة</button> : null}
    <small>تُعرض البيانات بحسب صلاحيات Odoo؛ إنشاء الفواتير والقيود المالية يتم عبر نماذج Odoo الأصلية.</small>
  </main>;
}
