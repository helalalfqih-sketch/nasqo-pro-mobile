/**
 * Whitelisted Odoo 19 native window actions, resolved from the installed
 * ir.actions.act_window metadata on nasqo-odoo19 on 2026-11-15.
 * Odoo still enforces model ACLs, company record rules, and form validations.
 * The mobile UI does not post financial documents directly.
 */
export const NATIVE_ODOO_ACTIONS = {
  contacts: 552,
  partnerLedger: 256,
  employees: 617,
  activities: 130,
  pos: 708,
  productVariants: 176,
  currencies: 66,
  customers: 55,
  suppliers: 57,
  customerInvoices: 261,
  customerRefunds: 263,
  vendorBills: 264,
  vendorRefunds: 266,
  journalEntries: 259,
  payments: 236,
  cashRegisters: 281,
  internalPayments: 239,
  chartOfAccounts: 275,
  cashJournals: 301,
  warehouses: 469,
  stockLocations: 465,
  stockTransfers: 473,
  stockReceipts: 474,
  stockDeliveries: 475,
  internalStockTransfers: 476,
  stockMoves: 472,
  products: 175,
  salesOrders: 355,
  quotations: 357,
  purchaseOrders: 539,
  purchaseRFQs: 538,
} as const;

export type NativeOdooAction = keyof typeof NATIVE_ODOO_ACTIONS;
export const ODOO_MAIN = "/odoo";
export const ODOO_WAHA_STATUS = "/nasqo/whatsapp/live";

/** Use an Odoo-managed form rather than emulating accounting writes. */
export function nativeOdooPath(action: NativeOdooAction): string {
  return `/odoo/action-${NATIVE_ODOO_ACTIONS[action]}`;
}

export function openNativeOdoo(action: NativeOdooAction): void {
  window.location.assign(nativeOdooPath(action));
}

export function openOdooWhatsAppStatus(): void {
  window.location.assign(ODOO_WAHA_STATUS);
}
