import { test } from "node:test";
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { lastSevenDays, sumSales, lowStockRows } from "../src/dashboardMath.ts";

const days = lastSevenDays(new Date(2026, 10, 15, 12));
test("seven-day sales window includes today and previous six days", () => {
  assert.deepEqual(days, ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12",
    "2026-11-13", "2026-11-14", "2026-11-15"]);
});
test("sales aggregates are net of refunds and never combine currencies", () => {
  const values = sumSales([
    { id: 1, invoice_date: days[0], move_type: "out_invoice", amount_total: 500, currency_id: [1, "YER"] },
    { id: 2, invoice_date: days[0], move_type: "out_refund", amount_total: 100, currency_id: [1, "YER"] },
    { id: 3, invoice_date: days[2], move_type: "out_invoice", amount_total: 30, currency_id: [2, "USD"] },
    { id: 4, invoice_date: "2026-11-08", move_type: "out_invoice", amount_total: 7000, currency_id: [1, "YER"] },
    { id: 5, invoice_date: days[1], move_type: "in_invoice", amount_total: 200, currency_id: [1, "YER"] },
  ], days);
  assert.equal(values.length, 2);
  assert.equal(values.find(x => x.currency === "YER")?.total, 400);
  assert.equal(values.find(x => x.currency === "USD")?.total, 30);
  assert.equal(values.find(x => x.currency === "YER")?.daily.length, 7);
  assert.equal(values.find(x => x.currency === "YER")?.daily[1].amount, 0);
});
test("low stock only lists orderpoints below configured minimum and preserves locations", () => {
  const result = lowStockRows([
    { id: 1, product_id: [5, "بطاريات"], location_id: [12, "مخزن 1"], product_uom: [1, "حبة"], qty_on_hand: 2, product_min_qty: 10 },
    { id: 2, product_id: [6, "مياه"], location_id: [12, "مخزن 1"], product_uom: [1, "حبة"], qty_on_hand: 10, product_min_qty: 10 },
    { id: 3, product_id: [7, "أدوات"], location_id: [13, "مخزن 2"], product_uom: [1, "حبة"], qty_on_hand: 20, product_min_qty: 1 },
    { id: 4, product_id: [8, "أصناف مجهولة"], location_id: false, product_uom: false, qty_on_hand: false, product_min_qty: 10 },
  ]);
  assert.deepEqual(result.map(item => item.name), ["بطاريات"]);
  assert.equal(result[0].location, "مخزن 1");
  assert.equal(result[0].minimum, 10);
  assert.equal(result[0].available, 2);
});
test("PDF never sends data to an external render endpoint", () => {
  const source = readFileSync("src/dashboardPdf.ts", "utf8");
  assert.match(source, /import\("html2canvas"\)/);
  assert.match(source, /import\("jspdf"\)/);
  assert.match(source, /document\.createElement\("a"\)/);
  assert.match(source, /textContent = value/);
  assert.doesNotMatch(source, /fetch\(|XMLHttpRequest|sendBeacon|outerHTML\s*=/);
});
test("dashboard reads only Odoo models, and has limits to avoid false totals", () => {
  const source = readFileSync("src/dashboardData.ts", "utf8");
  assert.match(source, /"account.move"/);
  assert.match(source, /"stock.warehouse.orderpoint"/);
  assert.match(source, /TOO_MANY_ROWS/);
  assert.match(source, /"search_count"/);
});
test("D3 line chart and quick actions exist in the new dashboard", () => {
  const source = readFileSync("src/NasqoDashboard.tsx", "utf8");
  assert.match(source, /from "d3"/);
  assert.match(source, /<Sparkline/);
  for (const label of ["فاتورة جديدة", "عملية شراء جديدة", "جهة اتصال جديدة", "تصدير PDF"]) {
    assert.ok(source.includes(label), label);
  }
});
