/**
 * Minimal Odoo 19 contact mutation. Never touches general ledger or payments.
 * Uses the logged-in browser session and lets Odoo enforce ACLs / record rules.
 * Values are validated and explicitly confirmed by the user before this is called.
 */
export interface ContactDraft {
  id?: number;
  name: string;
  phone?: string;
  note?: string;
}
export class ContactSaveError extends Error {
  readonly reason: "login" | "permission" | "validation" | "network";
  constructor(reason: "login" | "permission" | "validation" | "network") {
    super(reason);
    this.name = "ContactSaveError";
    this.reason = reason;
  }
}
function requireERPOrigin(): void {
  if (window.location.protocol !== "https:" ||
      window.location.hostname !== "erp.indexesstore.com" ||
      !window.location.pathname.startsWith("/nasqo-mobile/")) {
    throw new ContactSaveError("permission");
  }
}
async function odooRpc<T>(path: string, params: Record<string, unknown>): Promise<T> {
  let response: Response;
  try {
    response = await fetch(path, {
      method: "POST", credentials: "same-origin", cache: "no-store",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", method: "call", params, id: 1 }),
    });
  } catch {
    throw new ContactSaveError("network");
  }
  if (!response.ok) throw new ContactSaveError("network");
  let data: { result?: T; error?: { code?: number; data?: { name?: string } } };
  try {
    data = await response.json();
  } catch {
    throw new ContactSaveError("network");
  }
  if (data.error) {
    if (data.error.code === 100) throw new ContactSaveError("login");
    if (String(data.error.data?.name).includes("Access")) throw new ContactSaveError("permission");
    throw new ContactSaveError("validation");
  }
  if (!Object.hasOwn(data, "result")) throw new ContactSaveError("network");
  return data.result as T;
}
export async function saveOdooContact(draft: ContactDraft): Promise<number> {
  requireERPOrigin();
  const name = draft.name.trim();
  if (!name || name.length > 180 || (draft.phone && draft.phone.length > 60) ||
      (draft.note && draft.note.length > 2500)) {
    throw new ContactSaveError("validation");
  }
  if (draft.id !== undefined && (!Number.isSafeInteger(draft.id) || draft.id <= 0)) {
    throw new ContactSaveError("validation");
  }
  const session = await odooRpc<{ uid?: number | false }>("/web/session/get_session_info", {});
  if (!session.uid) throw new ContactSaveError("login");
  // Do not erase existing phone or notes when an edit form omits them.
  const values: Record<string, string> = { name };
  if (draft.phone?.trim()) values.phone = draft.phone.trim();
  if (draft.note?.trim()) values.comment = draft.note.trim();
  const isEdit = draft.id !== undefined;
  const id = isEdit ? draft.id! : 0;
  const result = await odooRpc<number | number[] | boolean>(
    "/web/dataset/call_kw/res.partner/" + (isEdit ? "write" : "create"),
    { model: "res.partner", method: isEdit ? "write" : "create",
      args: isEdit ? [[id], values] : [[values]], kwargs: {} },
  );
  if (isEdit) {
    if (result !== true) throw new ContactSaveError("validation");
    return id;
  }
  const newId = Array.isArray(result) ? result[0] : result;
  if (typeof newId !== "number" || !Number.isSafeInteger(newId) || newId <= 0) {
    throw new ContactSaveError("validation");
  }
  return newId;
}
