export type HybridScreenBatch = 1 | 2 | 3 | 4 | 5;

export type HybridRouteId =
  // Batch 1: Home / Dashboard
  | "dashboard"
  // Batch 2: Accounts & Suppliers
  | "purchases"
  | "sales"
  | "clients"
  | "employees"
  | "transfers"
  | "shop"
  | "supplier"
  | "currency"
  | "account-groups"
  | "chart-of-accounts"
  | "currencies-manager"
  // Batch 3: Invoices, Vouchers & Inventory Operations
  | "invoice"
  | "voucher"
  | "simple-entry"
  | "transfer"
  | "warehouses"
  | "items"
  // Batch 4: Reports & Documents
  | "reports-hub"
  | "trial-balance"
  | "cashboxes-report"
  | "inventory-report"
  | "daily-journal"
  | "analytics-dashboard"
  | "cash-invoice-preview"
  // Batch 5: Settings & Integrations
  | "settings"
  | "whatsapp"
  | "google-drive"
  | "backup"
  | "notifications"
  | "trash";

export interface HybridRouteDescriptor {
  id: HybridRouteId;
  batch: HybridScreenBatch;
  titleAr: string;
  presentation: "screen" | "modal";
  offlineSupported: boolean;
  requiresFlutterAuth?: boolean;
}

export const HYBRID_ROUTES: readonly HybridRouteDescriptor[] = [
  // Batch 1 — الشاشة الرئيسية
  { id: "dashboard", batch: 1, titleAr: "الشاشة الرئيسية", presentation: "screen", offlineSupported: true },
  // Batch 2 — الحسابات والموردون
  { id: "purchases", batch: 2, titleAr: "المشتريات والموردون", presentation: "screen", offlineSupported: true },
  { id: "sales", batch: 2, titleAr: "المبيعات", presentation: "screen", offlineSupported: true },
  { id: "clients", batch: 2, titleAr: "العملاء", presentation: "screen", offlineSupported: true },
  { id: "employees", batch: 2, titleAr: "الموظفون", presentation: "screen", offlineSupported: true },
  { id: "transfers", batch: 2, titleAr: "الحوالات", presentation: "screen", offlineSupported: true },
  { id: "shop", batch: 2, titleAr: "المحل", presentation: "screen", offlineSupported: true },
  { id: "supplier", batch: 2, titleAr: "كشف الحساب", presentation: "screen", offlineSupported: true },
  { id: "currency", batch: 2, titleAr: "مصارفة العملات", presentation: "screen", offlineSupported: true },
  { id: "account-groups", batch: 2, titleAr: "مجموعات الحسابات", presentation: "modal", offlineSupported: true },
  { id: "chart-of-accounts", batch: 2, titleAr: "دليل الحسابات", presentation: "modal", offlineSupported: true },
  { id: "currencies-manager", batch: 2, titleAr: "العملات", presentation: "modal", offlineSupported: true },
  // Batch 3 — الفواتير والسندات والمخازن
  { id: "invoice", batch: 3, titleAr: "فاتورة / مرتجع / عرض سعر", presentation: "modal", offlineSupported: true },
  { id: "voucher", batch: 3, titleAr: "سند قبض / صرف", presentation: "modal", offlineSupported: true },
  { id: "simple-entry", batch: 3, titleAr: "قيد بسيط", presentation: "screen", offlineSupported: true },
  { id: "transfer", batch: 3, titleAr: "حوالة مالية", presentation: "modal", offlineSupported: true },
  { id: "warehouses", batch: 3, titleAr: "المخازن", presentation: "screen", offlineSupported: true },
  { id: "items", batch: 3, titleAr: "دليل الأصناف", presentation: "screen", offlineSupported: true },
  // Batch 4 — التقارير والمستندات
  { id: "reports-hub", batch: 4, titleAr: "التقارير المالية والمخزنية", presentation: "modal", offlineSupported: true },
  { id: "trial-balance", batch: 4, titleAr: "ميزان المراجعة", presentation: "modal", offlineSupported: true },
  { id: "cashboxes-report", batch: 4, titleAr: "تقرير الصناديق", presentation: "modal", offlineSupported: true },
  { id: "inventory-report", batch: 4, titleAr: "حركة المخازن", presentation: "screen", offlineSupported: true },
  { id: "daily-journal", batch: 4, titleAr: "الحركة اليومية", presentation: "screen", offlineSupported: true },
  { id: "analytics-dashboard", batch: 4, titleAr: "لوحة المبيعات والمخزون", presentation: "screen", offlineSupported: true },
  { id: "cash-invoice-preview", batch: 4, titleAr: "معاينة الفاتورة", presentation: "screen", offlineSupported: true },
  // Batch 5 — الإعدادات والتكاملات
  { id: "settings", batch: 5, titleAr: "الإعدادات", presentation: "screen", offlineSupported: true },
  { id: "whatsapp", batch: 5, titleAr: "إعدادات الواتساب", presentation: "screen", offlineSupported: true },
  { id: "google-drive", batch: 5, titleAr: "Google Drive السحابي", presentation: "modal", offlineSupported: false, requiresFlutterAuth: true },
  { id: "backup", batch: 5, titleAr: "النسخ الاحتياطي والاستعادة", presentation: "modal", offlineSupported: true },
  { id: "notifications", batch: 5, titleAr: "مركز التنبيهات", presentation: "modal", offlineSupported: true },
  { id: "trash", batch: 5, titleAr: "سلة المهملات", presentation: "modal", offlineSupported: true },
];

const ROUTE_MAP = new Map<string, HybridRouteDescriptor>(HYBRID_ROUTES.map((r) => [r.id, r]));

export function isValidHybridRoute(route: string): route is HybridRouteId {
  return ROUTE_MAP.has(route);
}

export function getHybridRouteDescriptor(route: string): HybridRouteDescriptor | null {
  return ROUTE_MAP.get(route) ?? null;
}

export function normalizeFlowScreenIdToHybridRoute(screenId: string): HybridRouteId {
  if (screenId.startsWith("supplier:")) return "supplier";
  if (screenId.startsWith("cash-invoice-preview:")) return "cash-invoice-preview";
  if (screenId.startsWith("accounts-purchases") || screenId === "category-purchases" || screenId === "purchases") return "purchases";
  if (screenId.startsWith("accounts-sales") || screenId === "category-sales" || screenId === "sales") return "sales";
  if (screenId.startsWith("accounts-clients") || screenId === "category-clients" || screenId === "clients") return "clients";
  if (screenId.startsWith("accounts-employees") || screenId === "category-employees" || screenId === "employees") return "employees";
  if (screenId.startsWith("accounts-transfers") || screenId === "category-transfers" || screenId === "transfers") return "transfers";
  if (screenId.startsWith("accounts-shop") || screenId === "category-shop" || screenId === "shop") return "shop";
  if (isValidHybridRoute(screenId)) return screenId;
  return "dashboard";
}
