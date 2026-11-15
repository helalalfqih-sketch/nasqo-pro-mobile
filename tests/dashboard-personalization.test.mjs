import { test } from "node:test";
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { normalizePrefs, DEFAULT_PREFS, backupAgeDays, contrastOn } from "../src/dashboardPreferences.ts";
import { upcomingWindow, dueAlerts, recentStockAlerts } from "../src/dashboardAlertMath.ts";
import { validScanCode } from "../src/dashboardScanMath.ts";
import { reorderWithin } from "../src/dashboardReorderMath.ts";

test("Odoo upcoming invoices window is seven days ahead from local date", () => {
  assert.deepEqual(upcomingWindow(new Date(2026, 10, 15, 18, 20)), {
    start: "2026-11-15", end: "2026-11-22",
  });
});

test("unpaid due alerts are sorted and contain only accessible row data", () => {
  const alerts = dueAlerts([
    { id: 3, name: "INV3", partner_id: [1, "عميل 1"], invoice_date_due: "2026-11-20",
      amount_residual: 300, move_type: "out_invoice", currency_id: [1, "YER"] },
    { id: 1, name: "BILL1", partner_id: [2, "مورد 2"], invoice_date_due: "2026-11-15",
      amount_residual: 100, move_type: "in_invoice", currency_id: [2, "USD"] },
    { id: 2, name: "PAID", partner_id: false, invoice_date_due: "2026-11-16",
      amount_residual: 0, move_type: "out_invoice", currency_id: false },
    { id: 4, name: "OLD", partner_id: false, invoice_date_due: "2026-11-10",
      amount_residual: 400, move_type: "out_invoice", currency_id: false },
  ], "2026-11-15");
  assert.deepEqual(alerts.map(x => x.id), ["due:1", "due:3"]);
  assert.equal(alerts[0].important, true);
  assert.match(alerts[0].description, /USD/);
});

test("recent low-stock rules warn only when actual orderpoint was recently modified", () => {
  const items = [
    { id: 4, name: "بطارية", location: "المخزن", unit: "قطعة", available: 2, minimum: 8,
      updatedAt: "2026-11-14 13:00:00" },
    { id: 5, name: "صنف قديم", location: "المخزن", unit: "قطعة", available: 1, minimum: 3,
      updatedAt: "2026-10-01 13:00:00" },
  ];
  const result = recentStockAlerts(items, new Date(2026, 10, 15));
  assert.deepEqual(result.map(x => x.id), ["stock:4"]);
  assert.match(result[0].title, /حُدّثت/);
});

test("dashboard preferences reject malformed color and restrict stored favorites", () => {
  const p = normalizePrefs({
    theme: "other", primary: "javascript:alert(1)", haptics: "yes",
    favorites: ["report:vendorBills", "report:vendorBills", "report:unknown", "contact:12", "contact:-1"],
    summaryOrder: ["lowStock", "garbage", "sales"],
    widgetOrder: ["settings", "trend", "alien"],
  });
  assert.equal(p.theme, "system");
  assert.equal(p.primary, DEFAULT_PREFS.primary);
  assert.deepEqual(p.favorites, ["report:vendorBills", "contact:12"]);
  assert.deepEqual(p.summaryOrder, ["lowStock", "sales", "invoices"]);
  assert.ok(p.widgetOrder.includes("notifications"));
  assert.equal(p.haptics, true);
  assert.equal(normalizePrefs({ primary: "#ABCDEF" }).primary, "#abcdef");
});

test("manual full-export date notification threshold strictly exceeds seven days", () => {
  const now = new Date(2026, 10, 15, 18);
  assert.equal(backupAgeDays("2026-11-07", now), 8);
  assert.equal(backupAgeDays("2026-11-08", now), 7);
  assert.equal(backupAgeDays("2026-11-16", now), null);
  assert.equal(backupAgeDays("2026-99-99", now), null);
  assert.equal(backupAgeDays(null, now), null);
});

test("brand-color contrast chooses readable foreground", () => {
  assert.equal(contrastOn("#000000"), "#ffffff");
  assert.equal(contrastOn("#ffffff"), "#132238");
});

test("card and widget reordering never adds, loses or duplicates ids", () => {
  const before = ["notifications", "favorites", "trend", "invoices"];
  assert.deepEqual(reorderWithin(before, "invoices", "notifications"),
    ["invoices", "notifications", "favorites", "trend"]);
  assert.equal(before[0], "notifications", "input should remain immutable");
  assert.deepEqual(reorderWithin(before, "nonexistent", "trend"), before);
});

test("QR scanner rejects URLs, code injection and invalid identifiers", () => {
  assert.equal(validScanCode("  ABC-1234  "), "ABC-1234");
  assert.equal(validScanCode("https://evil.example/"), null);
  assert.equal(validScanCode("<script>"), null);
  assert.equal(validScanCode(""), null);
  assert.equal(validScanCode("x".repeat(80)), null);
});

test("production dashboard includes QR, DnD, user-scoped preferences and notifications", () => {
  const source = readFileSync("src/NasqoDashboard.tsx", "utf8");
  const scanner = readFileSync("src/DashboardScanner.tsx", "utf8");
  const settings = readFileSync("src/DashboardExtras.tsx", "utf8");
  assert.match(source, /<DashboardReorder/);
  assert.match(source, /<DashboardScanner/);
  assert.match(source, /useDashboardTheme/);
  assert.match(scanner, /import\("@zxing\/browser"\)/);
  assert.match(scanner, /search_read/);
  assert.doesNotMatch(scanner, /"create"|"write"|fetch\("https?:/);
  assert.match(settings, /theme-color/);
  assert.match(settings, /data-nasqo-color-mode/);
  assert.match(settings, /Notification.requestPermission/);
});

test("mobile drag handles do not compete with MobileScroll gesture capture", () => {
  const source = readFileSync("src/DashboardReorder.tsx", "utf8");
  assert.match(source, /data-scroll-drag="ignore"/);
  assert.match(source, /useSensor\(TouchSensor/);
  assert.match(source, /useSensor\(KeyboardSensor/);
});
