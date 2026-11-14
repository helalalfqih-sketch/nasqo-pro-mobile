/** Safe classification of Odoo JSON-RPC failures. No server tracebacks reach UI. */
export type OdooFailure = "login" | "permission" | "other";

export function classifyOdooFailure(error: {
  code?: number;
  data?: { name?: string };
}): OdooFailure {
  if (error.code === 100) return "login";
  const name = error.data?.name ?? "";
  if (
    name === "odoo.exceptions.AccessError" ||
    name === "odoo.exceptions.AccessDenied" ||
    name.endsWith(".AccessError") ||
    name.endsWith(".AccessDenied")
  ) return "permission";
  return "other";
}
