export type DashboardWidgetId =
  | "kpis"
  | "sales-trend"
  | "supplier-performance"
  | "expense-trends"
  | "recent-invoices"
  | "low-stock";

export const DEFAULT_WIDGET_ORDER: readonly DashboardWidgetId[] = [
  "kpis",
  "sales-trend",
  "supplier-performance",
  "expense-trends",
  "recent-invoices",
  "low-stock",
];

export const WIDGET_LABELS: Record<DashboardWidgetId, string> = {
  kpis: "المؤشرات الرئيسية",
  "sales-trend": "اتجاه المبيعات (7 أيام)",
  "supplier-performance": "أداء الموردين",
  "expense-trends": "اتجاهات المصروفات",
  "recent-invoices": "أحدث الفواتير",
  "low-stock": "تنبيهات المخزون",
};

export type PinnedFavoriteTarget =
  | { kind: "route"; route: "inventory-report" | "daily-journal" | "purchases" | "sales" | "currency" | "shop" }
  | { kind: "action"; action: "new-invoice" | "new-purchase" | "new-contact" | "qr-scan" | "export-pdf" }
  | { kind: "account"; accountId: string };

export interface PinnedFavoriteItem {
  id: string;
  label: string;
  subtitle?: string;
  target: PinnedFavoriteTarget;
}

export const DEFAULT_FAVORITES: readonly PinnedFavoriteItem[] = [
  {
    id: "fav_inventory",
    label: "تقرير المخزون",
    subtitle: "جرد والأرصدة",
    target: { kind: "route", route: "inventory-report" },
  },
  {
    id: "fav_journal",
    label: "الحركة اليومية",
    subtitle: "كشف القيود",
    target: { kind: "route", route: "daily-journal" },
  },
  {
    id: "fav_purchases",
    label: "حسابات الموردين",
    subtitle: "المشتريات",
    target: { kind: "route", route: "purchases" },
  },
];

const WIDGET_ORDER_KEY = "nasqo-dashboard-widget-order";
const FAVORITES_KEY = "nasqo-pinned-favorites";
const LAST_BACKUP_KEY = "nasqo-last-backup-at";

export function readWidgetOrder(): DashboardWidgetId[] {
  if (typeof window === "undefined") return [...DEFAULT_WIDGET_ORDER];
  try {
    const raw = window.localStorage.getItem(WIDGET_ORDER_KEY);
    if (!raw) return [...DEFAULT_WIDGET_ORDER];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [...DEFAULT_WIDGET_ORDER];
    const valid = parsed.filter((id): id is DashboardWidgetId =>
      (DEFAULT_WIDGET_ORDER as readonly string[]).includes(String(id)),
    );
    const missing = DEFAULT_WIDGET_ORDER.filter((id) => !valid.includes(id));
    return [...valid, ...missing];
  } catch {
    return [...DEFAULT_WIDGET_ORDER];
  }
}

export function writeWidgetOrder(order: readonly DashboardWidgetId[]): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(WIDGET_ORDER_KEY, JSON.stringify(order));
  } catch {
    // Ignore storage access errors
  }
}

export function readPinnedFavorites(): PinnedFavoriteItem[] {
  if (typeof window === "undefined") return [...DEFAULT_FAVORITES];
  try {
    const raw = window.localStorage.getItem(FAVORITES_KEY);
    if (!raw) return [...DEFAULT_FAVORITES];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [...DEFAULT_FAVORITES];
    return parsed.filter(
      (item): item is PinnedFavoriteItem =>
        Boolean(item && typeof item === "object" && "id" in item && "label" in item && "target" in item),
    );
  } catch {
    return [...DEFAULT_FAVORITES];
  }
}

export function writePinnedFavorites(items: readonly PinnedFavoriteItem[]): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(FAVORITES_KEY, JSON.stringify(items));
  } catch {
    // Ignore storage access errors
  }
}

export function readLastBackupIso(): string | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(LAST_BACKUP_KEY);
    return raw && raw.trim() ? raw.trim() : null;
  } catch {
    return null;
  }
}

export function recordLastBackupNow(iso: string = new Date().toISOString()): string {
  if (typeof window !== "undefined") {
    try {
      window.localStorage.setItem(LAST_BACKUP_KEY, iso);
    } catch {
      // Ignore storage access errors
    }
  }
  return iso;
}

export type HomeMetricId =
  | "sales"
  | "purchases"
  | "clients"
  | "employees"
  | "transfers"
  | "shop"
  | "inventory"
  | "new-account";

export const DEFAULT_HOME_METRIC_ORDER: readonly HomeMetricId[] = [
  "sales",
  "purchases",
  "clients",
  "employees",
  "transfers",
  "shop",
  "inventory",
  "new-account",
];

const HOME_METRICS_ORDER_KEY = "nasqo-home-metrics-order";

export function readHomeMetricOrder(): HomeMetricId[] {
  if (typeof window === "undefined") return [...DEFAULT_HOME_METRIC_ORDER];
  try {
    const raw = window.localStorage.getItem(HOME_METRICS_ORDER_KEY);
    if (!raw) return [...DEFAULT_HOME_METRIC_ORDER];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [...DEFAULT_HOME_METRIC_ORDER];
    const valid = parsed.filter((id): id is HomeMetricId =>
      (DEFAULT_HOME_METRIC_ORDER as readonly string[]).includes(String(id)),
    );
    const missing = DEFAULT_HOME_METRIC_ORDER.filter((id) => !valid.includes(id));
    return [...valid, ...missing];
  } catch {
    return [...DEFAULT_HOME_METRIC_ORDER];
  }
}

export function writeHomeMetricOrder(order: readonly HomeMetricId[]): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(HOME_METRICS_ORDER_KEY, JSON.stringify(order));
  } catch {
    // Ignore storage access errors
  }
}

export type HomeTileTone = "blue" | "amber";

export type HomeTileId =
  | "new-voucher"
  | "new-transfer"
  | "new-invoice"
  | "new-return"
  | "simple-entry"
  | "quote"
  | "currency-exchange"
  | "new-order"
  | "daily-journal"
  | "cashboxes"
  | "statement"
  | "currencies"
  | "account-groups"
  | "accounts"
  | "warehouses"
  | "sales-dashboard"
  | "trial-balance"
  | "items"
  | "stock-movement";

export const DEFAULT_HOME_TILE_ORDER: readonly HomeTileId[] = [
  "new-voucher",
  "new-transfer",
  "new-invoice",
  "new-return",
  "simple-entry",
  "quote",
  "currency-exchange",
  "new-order",
  "daily-journal",
  "cashboxes",
  "statement",
  "currencies",
  "account-groups",
  "accounts",
  "warehouses",
  "sales-dashboard",
  "trial-balance",
  "items",
  "stock-movement",
];

export interface HomeTileLayout {
  order: HomeTileId[];
  pinned: HomeTileId[];
  hidden: HomeTileId[];
  toneOverrides: Partial<Record<HomeTileId, HomeTileTone>>;
}

export const DEFAULT_HOME_TILE_LAYOUT: HomeTileLayout = {
  order: [...DEFAULT_HOME_TILE_ORDER],
  pinned: [],
  hidden: [],
  toneOverrides: {},
};

const HOME_TILE_LAYOUT_KEY = "nasqo-home-tile-layout-v1";

function isValidHomeTileId(value: unknown): value is HomeTileId {
  return (DEFAULT_HOME_TILE_ORDER as readonly string[]).includes(String(value));
}

export function normalizeHomeTileLayout(raw?: Partial<HomeTileLayout> | null): HomeTileLayout {
  const safe = raw && typeof raw === "object" ? raw : {};
  const seenOrder = new Set<HomeTileId>();
  const validOrder: HomeTileId[] = [];
  if (Array.isArray(safe.order)) {
    for (const id of safe.order) {
      if (isValidHomeTileId(id) && !seenOrder.has(id)) {
        seenOrder.add(id);
        validOrder.push(id);
      }
    }
  }
  for (const id of DEFAULT_HOME_TILE_ORDER) {
    if (!seenOrder.has(id)) {
      seenOrder.add(id);
      validOrder.push(id);
    }
  }

  const seenPinned = new Set<HomeTileId>();
  const validPinned: HomeTileId[] = [];
  if (Array.isArray(safe.pinned)) {
    for (const id of safe.pinned) {
      if (isValidHomeTileId(id) && !seenPinned.has(id)) {
        seenPinned.add(id);
        validPinned.push(id);
      }
    }
  }

  const seenHidden = new Set<HomeTileId>();
  const validHidden: HomeTileId[] = [];
  if (Array.isArray(safe.hidden)) {
    for (const id of safe.hidden) {
      if (isValidHomeTileId(id) && !seenHidden.has(id)) {
        seenHidden.add(id);
        validHidden.push(id);
      }
    }
  }

  // Ensure hidden tiles are not simultaneously pinned
  const hiddenSet = new Set(validHidden);
  const filteredPinned = validPinned.filter((id) => !hiddenSet.has(id));

  const toneOverrides: Partial<Record<HomeTileId, HomeTileTone>> = {};
  if (safe.toneOverrides && typeof safe.toneOverrides === "object") {
    for (const [k, v] of Object.entries(safe.toneOverrides)) {
      if (isValidHomeTileId(k) && (v === "blue" || v === "amber")) {
        toneOverrides[k] = v;
      }
    }
  }

  return {
    order: validOrder,
    pinned: filteredPinned,
    hidden: validHidden,
    toneOverrides,
  };
}

export function readHomeTileLayout(): HomeTileLayout {
  if (typeof window === "undefined") return normalizeHomeTileLayout(DEFAULT_HOME_TILE_LAYOUT);
  try {
    const raw = window.localStorage.getItem(HOME_TILE_LAYOUT_KEY);
    if (!raw) return normalizeHomeTileLayout(DEFAULT_HOME_TILE_LAYOUT);
    const parsed = JSON.parse(raw) as Partial<HomeTileLayout>;
    return normalizeHomeTileLayout(parsed);
  } catch {
    return normalizeHomeTileLayout(DEFAULT_HOME_TILE_LAYOUT);
  }
}

export function writeHomeTileLayout(layout: HomeTileLayout): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(
      HOME_TILE_LAYOUT_KEY,
      JSON.stringify(normalizeHomeTileLayout(layout)),
    );
  } catch {
    // Ignore storage access errors
  }
}

export function isDefaultHomeTileLayout(layout: HomeTileLayout): boolean {
  if (layout.pinned.length > 0 || layout.hidden.length > 0) return false;
  if (Object.keys(layout.toneOverrides).length > 0) return false;
  if (layout.order.length !== DEFAULT_HOME_TILE_ORDER.length) return false;
  return layout.order.every((id, idx) => id === DEFAULT_HOME_TILE_ORDER[idx]);
}

export function getVisibleOrderedHomeTiles(layout: HomeTileLayout): {
  pinnedIds: HomeTileId[];
  unpinnedIds: HomeTileId[];
  allVisibleIds: HomeTileId[];
} {
  const hiddenSet = new Set(layout.hidden);
  const pinnedSet = new Set(layout.pinned);
  const pinnedIds: HomeTileId[] = [];
  const unpinnedIds: HomeTileId[] = [];
  for (const id of layout.order) {
    if (hiddenSet.has(id)) continue;
    if (pinnedSet.has(id)) pinnedIds.push(id);
    else unpinnedIds.push(id);
  }
  return {
    pinnedIds,
    unpinnedIds,
    allVisibleIds: [...pinnedIds, ...unpinnedIds],
  };
}

export function moveHomeTile(
  layout: HomeTileLayout,
  sourceId: HomeTileId,
  targetId: HomeTileId,
): HomeTileLayout {
  if (sourceId === targetId) return layout;
  const nextOrder = [...layout.order];
  const fromIdx = nextOrder.indexOf(sourceId);
  const toIdx = nextOrder.indexOf(targetId);
  if (fromIdx < 0 || toIdx < 0) return layout;

  nextOrder.splice(fromIdx, 1);
  nextOrder.splice(toIdx, 0, sourceId);

  const pinnedSet = new Set(layout.pinned);
  const targetPinned = pinnedSet.has(targetId);
  const sourcePinned = pinnedSet.has(sourceId);
  let nextPinned = layout.pinned;
  if (targetPinned && !sourcePinned) {
    nextPinned = [...layout.pinned, sourceId];
  } else if (!targetPinned && sourcePinned) {
    nextPinned = layout.pinned.filter((id) => id !== sourceId);
  }

  return normalizeHomeTileLayout({
    ...layout,
    order: nextOrder,
    pinned: nextPinned,
  });
}

export function stepHomeTile(
  layout: HomeTileLayout,
  tileId: HomeTileId,
  delta: -1 | 1,
): HomeTileLayout {
  const { allVisibleIds } = getVisibleOrderedHomeTiles(layout);
  const idx = allVisibleIds.indexOf(tileId);
  if (idx < 0) return layout;
  const targetIdx = idx + delta;
  if (targetIdx < 0 || targetIdx >= allVisibleIds.length) return layout;
  return moveHomeTile(layout, tileId, allVisibleIds[targetIdx]);
}

export function togglePinHomeTile(layout: HomeTileLayout, tileId: HomeTileId): HomeTileLayout {
  const isPinned = layout.pinned.includes(tileId);
  if (isPinned) {
    return normalizeHomeTileLayout({
      ...layout,
      pinned: layout.pinned.filter((id) => id !== tileId),
    });
  }
  const nextOrder = layout.order.filter((id) => id !== tileId);
  const pinnedCount = layout.pinned.length;
  nextOrder.splice(pinnedCount, 0, tileId);
  return normalizeHomeTileLayout({
    ...layout,
    order: nextOrder,
    pinned: [...layout.pinned, tileId],
    hidden: layout.hidden.filter((id) => id !== tileId),
  });
}

export function toggleHideHomeTile(layout: HomeTileLayout, tileId: HomeTileId): HomeTileLayout {
  const isHidden = layout.hidden.includes(tileId);
  if (isHidden) {
    return normalizeHomeTileLayout({
      ...layout,
      hidden: layout.hidden.filter((id) => id !== tileId),
    });
  }
  const { allVisibleIds } = getVisibleOrderedHomeTiles(layout);
  if (allVisibleIds.length <= 2) return layout;
  return normalizeHomeTileLayout({
    ...layout,
    hidden: [...layout.hidden, tileId],
    pinned: layout.pinned.filter((id) => id !== tileId),
  });
}

export function toggleToneHomeTile(
  layout: HomeTileLayout,
  tileId: HomeTileId,
  defaultTone: HomeTileTone,
): HomeTileLayout {
  const current = layout.toneOverrides[tileId] ?? defaultTone;
  const nextTone: HomeTileTone = current === "blue" ? "amber" : "blue";
  const nextOverrides = { ...layout.toneOverrides };
  if (nextTone === defaultTone) {
    delete nextOverrides[tileId];
  } else {
    nextOverrides[tileId] = nextTone;
  }
  return normalizeHomeTileLayout({
    ...layout,
    toneOverrides: nextOverrides,
  });
}


