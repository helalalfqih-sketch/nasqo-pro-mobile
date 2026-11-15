import { useMemo, useState } from "react";
import type { NativeOdooAction } from "./odooNavigation";

export type ThemeMode = "light" | "dark" | "system";
export type WidgetId = "notifications" | "favorites" | "trend" | "invoices" |
  "lowStock" | "quick" | "export" | "settings";
export const defaultWidgets: WidgetId[] = [
  "notifications", "favorites", "trend", "invoices", "lowStock", "quick", "export", "settings",
];
export const defaultSummary = ["sales", "invoices", "lowStock"] as const;
export type FavoriteId = string;
export type DashboardPrefs = {
  theme: ThemeMode; primary: string; haptics: boolean;
  summaryOrder: string[]; widgetOrder: WidgetId[];
  favorites: FavoriteId[]; lastBackupDate: string | null;
  deviceNotifications: boolean; lastBackupNoticeDate: string | null;
};
export const DEFAULT_PREFS: DashboardPrefs = {
  theme: "system", primary: "#0b5ca8", haptics: true,
  summaryOrder: [...defaultSummary], widgetOrder: [...defaultWidgets],
  favorites: [], lastBackupDate: null, deviceNotifications: false,
  lastBackupNoticeDate: null,
};
const allowedReportActions = new Set<NativeOdooAction>([
  "partnerLedger", "customerInvoices", "vendorBills", "stockMoves",
  "products", "contacts", "salesOrders", "purchaseOrders",
]);
const validColor = (value: unknown): value is string =>
  typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value);
const validDate = (value: unknown): value is string =>
  typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  !Number.isNaN(new Date(value + "T00:00:00").getTime()) &&
  new Date(value + "T00:00:00").toISOString().slice(0, 10) === value;

export function normalizePrefs(input: unknown): DashboardPrefs {
  if (!input || typeof input !== "object" || Array.isArray(input)) return { ...DEFAULT_PREFS };
  const p = input as Partial<DashboardPrefs>;
  const unique = (xs: unknown, allowed: readonly string[]): string[] => {
    if (!Array.isArray(xs)) return [...allowed];
    const set = new Set(xs.filter((x): x is string => typeof x === "string" && allowed.includes(x)));
    return [...set, ...allowed.filter(x => !set.has(x))];
  };
  const faves = Array.isArray(p.favorites) ? [...new Set(p.favorites)].filter(value =>
    typeof value === "string" && (
      value.startsWith("report:") && allowedReportActions.has(value.slice(7) as NativeOdooAction) ||
      /^contact:[1-9]\d{0,11}$/.test(value)
    )).slice(0, 8) as FavoriteId[] : [];
  return {
    theme: p.theme === "light" || p.theme === "dark" ? p.theme : "system",
    primary: validColor(p.primary) ? p.primary.toLowerCase() : DEFAULT_PREFS.primary,
    haptics: typeof p.haptics === "boolean" ? p.haptics : DEFAULT_PREFS.haptics,
    summaryOrder: unique(p.summaryOrder, defaultSummary),
    widgetOrder: unique(p.widgetOrder, defaultWidgets) as WidgetId[],
    favorites: faves,
    lastBackupDate: validDate(p.lastBackupDate) ? p.lastBackupDate : null,
    deviceNotifications: p.deviceNotifications === true,
    lastBackupNoticeDate: validDate(p.lastBackupNoticeDate) ? p.lastBackupNoticeDate : null,
  };
}
const keyOf = (uid: number) => "nasqo-dashboard-prefs-v2-" + uid;
function load(uid: number): DashboardPrefs {
  try {
    const raw = window.localStorage.getItem(keyOf(uid));
    return normalizePrefs(raw ? JSON.parse(raw) : null);
  } catch {
    return normalizePrefs(null);
  }
}
export function useDashboardPreferences(uid: number) {
  const [version, setVersion] = useState(0);
  const value = useMemo(() => load(uid), [uid, version]);
  const update = (change: Partial<DashboardPrefs>) => {
    const next = normalizePrefs({ ...value, ...change });
    try { window.localStorage.setItem(keyOf(uid), JSON.stringify(next)); } catch { /* private mode */ }
    setVersion(n => n + 1);
  };
  return { value, update };
}
export function backupAgeDays(date: string | null, now = new Date()): number | null {
  if (!date || !validDate(date)) return null;
  const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  const d = new Date(date + "T00:00:00");
  const then = Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
  const value = Math.floor((today - then) / 86400000);
  return value < 0 ? null : value;
}
export function vibrateFeedback(enabled: boolean, kind: "tap" | "success" | "pin" = "tap") {
  if (!enabled || typeof navigator === "undefined" || typeof navigator.vibrate !== "function") return;
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return;
  navigator.vibrate(kind === "success" ? [28, 35, 24] : kind === "pin" ? [20, 25, 20] : 14);
}
export function contrastOn(hex: string): "#ffffff" | "#132238" {
  const c = hex.slice(1).match(/.{2}/g)?.map(x => parseInt(x, 16) / 255) ?? [0, 0, 0];
  const rgb = c.map(v => v <= .04045 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4));
  const brightness = .2126 * rgb[0] + .7152 * rgb[1] + .0722 * rgb[2];
  return brightness > .36 ? "#132238" : "#ffffff";
}
