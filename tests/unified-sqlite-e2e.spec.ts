import { createRequire } from "node:module";
import { expect, test } from "@playwright/test";
import initSqlJs from "sql.js";

const require = createRequire(import.meta.url);

async function sampleSqlite() {
  const SQL = await initSqlJs({ locateFile: () => require.resolve("sql.js/dist/sql-wasm.wasm") });
  const db = new SQL.Database();
  db.exec(`
    CREATE TABLE boxes (id INTEGER PRIMARY KEY, name TEXT);
    CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, type INTEGER, phone TEXT, lim REAL);
    CREATE TABLE stores (id INTEGER PRIMARY KEY, name TEXT, details TEXT, state INTEGER);
    CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, barcode TEXT, unit TEXT, price REAL, price2 REAL);
    CREATE TABLE currencies (id INTEGER PRIMARY KEY, name TEXT);
    CREATE TABLE input_move (id INTEGER PRIMARY KEY, bill TEXT, per_id INTEGER, bill_type INTEGER, bstate INTEGER, year INTEGER, month INTEGER, day INTEGER, dain REAL, madin REAL, cur INTEGER, details TEXT);
    CREATE TABLE bill_details (id INTEGER PRIMARY KEY, bill_id INTEGER, prod_id INTEGER, store_id INTEGER, unit TEXT, amount REAL, price REAL, discount REAL, total REAL);
    CREATE TABLE bill_details2 (id INTEGER PRIMARY KEY, bill_id INTEGER, details TEXT, total REAL);
    INSERT INTO boxes VALUES (1, 'العملاء');
    INSERT INTO customers VALUES (10, 'عميل اختبار نسق', 1, '777123456', 0);
    INSERT INTO stores VALUES (3, 'مخزن اختبار نسق', '', 1);
    INSERT INTO products VALUES (20, 'فلتر محرك مميز', 'BAR-9988', 'حبة', 150, 100);
    INSERT INTO currencies VALUES (1, 'ريال');
    INSERT INTO input_move VALUES (30, 'INV-9000', 10, 2, 1, 2026, 11, 15, 300, 0, 1, 'اختبار فاتورة تاريخية');
    INSERT INTO bill_details VALUES (40, 30, 20, 3, 'حبة', 2, 150, 0, 300);
  `);
  const bytes = Buffer.from(db.export());
  db.close();
  return bytes;
}

test("unified single SQLite backend persists data, imports SQLite, opens invoice lines, exports .sqlite, and uses zero IndexedDB/Firestore", async ({
  page,
}) => {
  test.setTimeout(120_000);
  const firestoreRequests: string[] = [];
  page.on("request", (req) => {
    if (req.url().includes("firestore.googleapis.com")) {
      firestoreRequests.push(req.url());
    }
  });

  // The shared browser test database must start empty even if another spec
  // just created test records. This is test-only, never production data.
  const reset = await page.request.post("/api/db/workspace/local-erp-workspace/reset", {
    headers: { "X-NASQO-CSRF": "1" },
    data: { confirmation: "RESET:local-erp-workspace" },
  });
  expect(reset.status()).toBe(200);
  await page.addInitScript(() => localStorage.setItem("nasqo-local-session-active", "1"));
  await page.goto("/?autostart=1");
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 20_000 });
  // Empty initial workspace: no hardcoded accounts/groups until user restores backup
  await expect(page.getByTestId("empty-workspace-banner")).toHaveCount(0);
  await expect(page.getByTestId("account-groups-table")).toHaveCount(0);

  // Open Options ("خيارات") dropdown menu and verify alternating backup / restore actions
  await page.getByTestId("header-options-btn").click();
  await expect(page.getByTestId("options-menu")).toBeVisible();
  await expect(page.getByTestId("options-backup-btn")).toHaveText("نسخ إحتياطي");
  await expect(page.getByTestId("options-restore-backup-btn")).toHaveText("إستعادة نسخة");
  await page.getByLabel("إغلاق الخيارات").click();

  const dbs = await page.evaluate(async () => {
    if (!("databases" in indexedDB)) return [];
    const list = await indexedDB.databases();
    return list.map((d) => d.name);
  });
  expect(dbs).not.toContain("nasqo_pro_erp_db");
  expect(dbs).not.toContain("nasqo_legacy_center");
  expect(dbs).not.toContain("nasqo_legacy_archive");

  // Upload SQLite backup via Options -> Restore Backup directly and confirm dashboard hydrates dynamically
  const [fileChooser] = await Promise.all([
    page.waitForEvent("filechooser"),
    (async () => {
      await page.getByTestId("header-options-btn").click();
      await page.getByTestId("options-restore-backup-btn").click();
    })(),
  ]);
  await fileChooser.setFiles({
    name: "erp-backup-test.back",
    mimeType: "application/octet-stream",
    buffer: await sampleSqlite(),
  });
  await expect(page.getByTestId("account-groups-table")).toBeVisible({ timeout: 20_000 });
  await expect(page.getByTestId("account-groups-table").getByText("العملاء")).toBeVisible({ timeout: 10_000 });

  // Also check Settings -> SQLite table browser works over the restored DB
  await page.getByTestId("home-nav-profile").click();
  await expect(page.getByTestId("settings-full-sqlite-import-btn")).toBeVisible({ timeout: 10_000 });
  await page.getByTestId("settings-full-sqlite-import-btn").click();
  const dialog = page.getByRole("dialog");
  await dialog.getByRole("button", { name: /عرض السجلات والجداول/ }).click();
  await expect(dialog.locator("table tbody tr").first()).toBeVisible({ timeout: 10_000 });
  await dialog.getByRole("button", { name: "✕" }).click();
  await page.getByLabel("رجوع", { exact: true }).click();
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 10_000 });

  // Verify native customer statement has NO redundant secondary archive table and opens real invoice lines directly
  await page.getByRole("button", { name: "كشف حساب", exact: true }).click();
  await page.getByLabel("البحث عن الحساب").fill("عميل اختبار نسق");
  await page.getByRole("option", { name: "عميل اختبار نسق" }).first().click();
  await page.getByRole("button", { name: "موافق", exact: true }).click();
  await expect(page.getByTestId("supplier-screen")).toBeVisible({ timeout: 10_000 });
  await expect(page.getByTestId("customer-legacy-archive-section")).toHaveCount(0);
  await page.getByRole("button", { name: /ملف PDF للعملية/ }).first().click();
  await expect(page.getByTestId("cash-invoice-document")).toBeVisible({ timeout: 10_000 });
  await expect(page.getByTestId("cash-invoice-document").getByText("فلتر محرك مميز")).toBeVisible();
  await expect(page.getByTestId("cash-invoice-tafqeet")).toContainText("ريال فقط لا غير");
  await page.getByLabel("رجوع", { exact: true }).click();
  await page.getByLabel("رجوع", { exact: true }).click();
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 10_000 });

  // Create a native multi-line invoice via InvoiceModal and verify Tafqeet preview + SQLite persistence
  await page.getByRole("button", { name: "فاتورة جديدة", exact: true }).click();
  const invModal = page.getByTestId("invoice-modal");
  await expect(invModal).toBeVisible();
  await invModal.getByTestId("invoice-item-search").fill("BAR-9988");
  await invModal.getByRole("listbox", { name: "نتائج الأصناف" }).getByRole("option").first().click();
  await invModal.getByTestId("invoice-save-btn").click();
  await expect(invModal).toHaveCount(0);

  // Open Chart of Accounts ("الحسابات"), locate test customer, jump to statement, edit newly created invoice lines, verify NO duplicate row
  await page.getByRole("button", { name: "الحسابات", exact: true }).click();
  const coaModal = page.getByTestId("chart-of-accounts-modal");
  await expect(coaModal).toBeVisible();
  await coaModal.getByTestId("coa-search-input").fill("عميل اختبار نسق");
  await coaModal.getByRole("button", { name: "كشف", exact: true }).first().click();
  await expect(page.getByTestId("supplier-screen")).toBeVisible({ timeout: 10_000 });
  const preEditCount = await page.locator(".transaction-card").count();
  expect(preEditCount).toBeGreaterThanOrEqual(2);
  await page.locator(".transaction-actions button[aria-label^='تعديل #']").first().click();
  const editInvModal = page.getByTestId("invoice-modal");
  await expect(editInvModal).toBeVisible();
  await expect(editInvModal.locator("#invoice-title")).toContainText("تعديل");
  await expect(editInvModal.getByLabel("اسم الصنف").first()).toHaveValue("فلتر محرك مميز");
  await editInvModal.getByLabel("كمية الصنف").first().fill("3");
  await editInvModal.getByTestId("invoice-save-btn").click();
  await expect(editInvModal).toHaveCount(0);
  await expect(page.locator(".transaction-card")).toHaveCount(preEditCount);

  // Verify statement "التصفية والترتيب" sheet exposes real criteria and filters/resets the statement live
  await page.getByRole("button", { name: "تصفية", exact: true }).click();
  const filterSheet = page.getByTestId("statement-filters-sheet");
  await expect(filterSheet).toBeVisible();
  await expect(filterSheet.getByLabel("تصفية نوع العملية")).toBeVisible();
  await expect(filterSheet.getByLabel("تصفية الفترة")).toBeVisible();
  await expect(filterSheet.getByLabel("ترتيب الحركات")).toBeVisible();
  await expect(filterSheet.getByText("إظهار الرصيد السابق")).toBeVisible();
  await filterSheet.getByLabel("تصفية نوع العملية").selectOption("voucher");
  await filterSheet.getByRole("button", { name: "تطبيق التصفية", exact: true }).click();
  await expect(filterSheet).toHaveCount(0);
  await expect(page.locator(".transaction-card")).toHaveCount(0);
  await page.getByRole("button", { name: "تصفية", exact: true }).click();
  await expect(filterSheet).toBeVisible();
  await filterSheet.getByRole("button", { name: "إعادة ضبط", exact: true }).click();
  await filterSheet.getByRole("button", { name: "تطبيق التصفية", exact: true }).click();
  await expect(page.locator(".transaction-card")).toHaveCount(preEditCount);

  // Move latest invoice to Trash via visible Trash action on statement, verify removal + restore
  await page.locator(".transaction-actions button[aria-label^='نقل #']").first().click();
  await expect(page.locator(".transaction-card")).toHaveCount(preEditCount - 1);
  await page.getByLabel("رجوع", { exact: true }).click();
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 10_000 });
  await page.getByRole("button", { name: "سلة المحذوفات", exact: true }).first().click();
  const trashModal = page.getByTestId("trash-modal");
  await expect(trashModal).toBeVisible({ timeout: 5_000 });
  await expect(trashModal.getByRole("button", { name: "استعادة" })).toHaveCount(1);
  await trashModal.getByRole("button", { name: "استعادة" }).first().click();
  await expect(trashModal.getByRole("button", { name: "استعادة" })).toHaveCount(0);
  await trashModal.getByRole("button", { name: "إغلاق", exact: true }).click();
  await expect(trashModal).toHaveCount(0);

  // Verify Order modal labels read "طلبية جديدة" and "حفظ الطلبية" (never "طلبية جديدة جديدة" or "عمل فاتورة")
  await page.getByLabel("إضافة", { exact: true }).click();
  await page.getByTestId("dashboard-add-menu").getByRole("menuitem", { name: "إضافة طلبية" }).click();
  const orderModal = page.getByTestId("invoice-modal");
  await expect(orderModal).toBeVisible();
  await expect(orderModal.locator("#invoice-title")).toHaveText("طلبية جديدة");
  await expect(orderModal.getByTestId("invoice-save-btn")).toHaveText("حفظ الطلبية");
  await orderModal.getByRole("button", { name: "إلغاء", exact: true }).click();
  await expect(orderModal).toHaveCount(0);

  // Check inventory item is persisted across reload and verify stocktake saves cleanly to SQLite
  await page.reload();
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 20_000 });

  await page.getByTestId("open-erp-hub-btn").click();
  await expect(page.getByTestId("erp-hub-screen")).toBeVisible({ timeout: 15_000 });
  await expect(page.getByTestId("local-db-section")).toContainText("سجلات النظام الموحدة");

  const [sqliteDownload] = await Promise.all([
    page.waitForEvent("download"),
    page.getByTestId("local-db-sqlite-download-btn").click(),
  ]);
  expect(sqliteDownload.suggestedFilename()).toMatch(/^nasqo-unified-.*\.sqlite$/);

  await page.getByLabel("رجوع", { exact: true }).click();
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 10_000 });

  // 1) Open dedicated Items Catalog screen («الأصناف») separately from Stock Movement
  await page.getByTestId("open-items-btn").click();
  const itemsScreen = page.getByTestId("items-catalog-screen");
  await expect(itemsScreen).toBeVisible({ timeout: 10_000 });
  await expect(itemsScreen.getByTestId("items-catalog-table")).toContainText("فلتر محرك مميز");

  // Create a multi-unit item from the Items Catalog screen
  await itemsScreen.getByTestId("catalog-item-name").fill("صنف صفر اختبار");
  await itemsScreen.getByTestId("catalog-item-sku").fill("BAR-ZERO-1");
  await itemsScreen.getByTestId("catalog-item-cost").fill("0");
  await itemsScreen.getByTestId("catalog-item-price1").fill("2500");
  await itemsScreen.getByTestId("catalog-item-unit2").fill("درزن");
  await itemsScreen.getByTestId("catalog-item-count2").fill("6");
  await itemsScreen.getByTestId("catalog-item-price2").fill("9000");
  await itemsScreen.getByTestId("catalog-item-unit3").fill("كرتون");
  await itemsScreen.getByTestId("catalog-item-count3").fill("2");
  await itemsScreen.getByTestId("catalog-item-price3").fill("18000");
  await itemsScreen.getByTestId("catalog-save-btn").click();
  await expect(itemsScreen.getByTestId("items-catalog-table")).toContainText("صنف صفر اختبار", { timeout: 10_000 });
  await expect(itemsScreen.getByTestId("items-catalog-table")).toContainText("درزن");
  await expect(itemsScreen.getByTestId("items-catalog-table")).toContainText("كرتون");

  await page.getByLabel("رجوع", { exact: true }).click();
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 10_000 });

  // 2) Open dedicated Stock Movement screen («حركة المخزون» / «حركة المخازن») separately
  await page.getByTestId("open-stock-movement-btn").click();
  await expect(page.getByTestId("inventory-report-screen")).toBeVisible({ timeout: 10_000 });
  await page.getByLabel("البحث في الأصناف").fill("BAR-9988");
  await expect(page.getByText("فلتر محرك مميز")).toBeVisible();
  await expect(page.getByText("بحاجة إلى تسوية").first()).toBeVisible();
  await page.getByRole("button", { name: "حركة صنف فلتر محرك مميز" }).click();
  const moveModal = page.getByTestId("item-movements-modal");
  await expect(moveModal).toBeVisible();
  await expect(moveModal.getByText("عميل اختبار نسق").first()).toBeVisible();
  await moveModal.locator("section[role='dialog']").getByRole("button", { name: "إغلاق", exact: true }).last().click();
  await page.getByLabel("تحديد فلتر محرك مميز").check();
  await page.getByLabel("نوع تعديل الكمية").selectOption("set");
  await page.getByLabel("قيمة تعديل الكمية").fill("7");
  await page.getByLabel("سعر البيع المعتمد").fill("200");
  await page.getByLabel("تأكيد جرد المخزون الفعلي").check();
  await page.getByLabel("تأكيد اعتماد سعر البيع").check();
  await page.getByTestId("bulk-apply-btn").click();
  await expect(page.getByText("بحاجة إلى تسوية")).toHaveCount(0);

  await page.getByLabel("البحث في الأصناف").fill("صنف صفر اختبار");
  await expect(
    page.getByTestId("inventory-movements-table").getByRole("cell", { name: "صنف صفر اختبار (BAR-ZERO-1)", exact: true }),
  ).toBeVisible({ timeout: 10_000 });

  await page.getByLabel("رجوع", { exact: true }).click();
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 10_000 });

  // Verify TrialBalanceModal keeps its sticky header pinned when scrolled
  await page.getByTestId("open-trial-balance-btn").click();
  const tbModal = page.getByTestId("trial-balance-modal");
  await expect(tbModal).toBeVisible();
  await expect(tbModal.locator("#trial-balance-title")).toHaveText("ميزان المراجعة");
  const tbSticky = await tbModal.evaluate((root) => {
    const scroller = root.querySelector(".trial-balance-modal") as HTMLElement | null;
    const header = root.querySelector(".smart-modal-header") as HTMLElement | null;
    if (!scroller || !header) return null;
    const position = getComputedStyle(header).position;
    scroller.scrollTop = Math.min(240, Math.max(0, scroller.scrollHeight - scroller.clientHeight));
    const sRect = scroller.getBoundingClientRect();
    const hRect = header.getBoundingClientRect();
    return {
      position,
      scrollable: scroller.scrollHeight > scroller.clientHeight,
      headerTopDelta: Math.abs(hRect.top - sRect.top),
    };
  });
  expect(tbSticky).not.toBeNull();
  expect(tbSticky!.position).toBe("sticky");
  expect(tbSticky!.headerTopDelta).toBeLessThanOrEqual(4);
  await tbModal.getByRole("button", { name: "إغلاق", exact: true }).click();
  await expect(tbModal).toHaveCount(0);

  // Verify unbroken long text in CashInvoiceDocument wraps inside its cell at 100% zoom
  const unbrokenText = "X".repeat(60);
  await page.getByRole("button", { name: "فاتورة جديدة", exact: true }).click();
  const longTextInvModal = page.getByTestId("invoice-modal");
  await expect(longTextInvModal).toBeVisible();
  await longTextInvModal.getByLabel("حساب الفاتورة", { exact: true }).selectOption({ label: "عميل اختبار نسق" });
  await longTextInvModal.getByLabel("حرة", { exact: true }).check();
  await longTextInvModal.getByLabel("إجمالي مبلغ الفاتورة").fill("50");
  await longTextInvModal.getByRole("textbox", { name: "بيان الفاتورة", exact: true }).fill(unbrokenText);
  await longTextInvModal.getByTestId("invoice-save-btn").click();
  await expect(longTextInvModal).toHaveCount(0);

  await page.getByRole("button", { name: "كشف حساب", exact: true }).click();
  await page.getByLabel("البحث عن الحساب").fill("عميل اختبار نسق");
  await page.getByRole("option", { name: "عميل اختبار نسق" }).first().click();
  await page.getByRole("button", { name: "موافق", exact: true }).click();
  await expect(page.getByTestId("supplier-screen")).toBeVisible({ timeout: 10_000 });
  await page.locator(".transaction-card", { hasText: unbrokenText }).getByRole("button", { name: /ملف PDF للعملية/ }).click();
  const previewDoc = page.getByTestId("cash-invoice-document");
  await expect(previewDoc).toBeVisible({ timeout: 10_000 });
  await expect(previewDoc.getByRole("cell", { name: unbrokenText, exact: true })).toBeVisible();
  await page.getByTestId("cash-invoice-actual-size").click();
  const wrapMetrics = await previewDoc.evaluate(() => {
    const firstTd = document.querySelector(".cash-invoice-table tbody td:first-child") as HTMLElement | null;
    if (!firstTd) return null;
    const style = getComputedStyle(firstTd);
    return {
      width: firstTd.getBoundingClientRect().width,
      height: firstTd.getBoundingClientRect().height,
      scrollWidth: firstTd.scrollWidth,
      clientWidth: firstTd.clientWidth,
      overflowWrap: style.overflowWrap,
    };
  });
  expect(wrapMetrics).not.toBeNull();
  expect(wrapMetrics!.overflowWrap).toBe("anywhere");
  expect(wrapMetrics!.width).toBeLessThanOrEqual(544);
  expect(wrapMetrics!.scrollWidth).toBeLessThanOrEqual(wrapMetrics!.clientWidth + 2);
  await page.getByLabel("رجوع", { exact: true }).click();
  await page.getByLabel("رجوع", { exact: true }).click();
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 10_000 });

  // Verify Cashboxes Report shows status + reconciliation and matches TransactionModal cashboxes
  await page.getByRole("button", { name: "صناديق النقدية", exact: true }).click();
  const cbModal = page.getByTestId("cashboxes-report-modal");
  await expect(cbModal).toBeVisible();
  await expect(cbModal.getByTestId("cashboxes-report-reconciliation")).toBeVisible({ timeout: 10_000 });
  await expect(cbModal.getByText("الصناديق النشطة المتاحة للسندات:")).toBeVisible();
  await cbModal.locator("button.ag-btn.close").click();
  await expect(cbModal).toHaveCount(0);

  // Verify ERP Finance scope controls, Balance Sheet cash/inventory reconciliation, and explicit VAT regime/persistence
  await page.getByTestId("open-erp-hub-btn").click();
  await expect(page.getByTestId("erp-hub-screen")).toBeVisible({ timeout: 15_000 });
  await page.getByTestId("erp-mod-btn-erp-finance").click();
  const financeScreen = page.getByTestId("erp-finance-screen");
  await expect(financeScreen).toBeVisible({ timeout: 10_000 });
  await expect(financeScreen.getByTestId("erp-finance-scope-bar")).toBeVisible();
  await expect(financeScreen.getByTestId("erp-finance-period-select")).toBeVisible();
  await expect(financeScreen.getByTestId("erp-finance-currency-select")).toBeVisible();
  await expect(financeScreen.getByTestId("erp-finance-scope-summary")).toContainText("سجلات النظام");

  await financeScreen.getByRole("tab", { name: "الميزانية" }).click();
  await expect(financeScreen.getByTestId("erp-balance-reconciliation")).toBeVisible({ timeout: 10_000 });
  await expect(financeScreen.getByTestId("erp-balance-reconciliation")).toContainText("تسوية النقدية");
  await expect(financeScreen.getByTestId("erp-balance-reconciliation")).toContainText("تسوية المخزون");

  await financeScreen.getByRole("tab", { name: "الضرائب" }).click();
  await expect(financeScreen.getByTestId("erp-vat-jurisdiction-select")).toHaveValue("none");
  await expect(financeScreen.getByTestId("erp-vat-warning")).toBeVisible();
  await financeScreen.getByTestId("erp-vat-jurisdiction-select").selectOption("sa_15");
  await financeScreen.getByTestId("erp-vat-save-btn").click();

  await page.reload();
  await expect(page.getByTestId("dashboard-screen")).toBeVisible({ timeout: 20_000 });
  await page.getByTestId("open-erp-hub-btn").click();
  await expect(page.getByTestId("erp-hub-screen")).toBeVisible({ timeout: 15_000 });
  await expect(page.getByTestId("erp-hub-screen")).toContainText("15% تقديري");
  await page.getByTestId("erp-mod-btn-erp-finance").click();
  await page.getByTestId("erp-finance-screen").getByRole("tab", { name: "الضرائب", exact: true }).click();
  await expect(page.getByTestId("erp-vat-jurisdiction-select")).toHaveValue("sa_15");

  // Verify again zero IndexedDB stores & zero Firestore requests throughout entire session
  const postDbs = await page.evaluate(async () => {
    if (!("databases" in indexedDB)) return [];
    const list = await indexedDB.databases();
    return list.map((d) => d.name);
  });
  expect(postDbs).not.toContain("nasqo_pro_erp_db");
  expect(postDbs).not.toContain("nasqo_legacy_center");
  expect(postDbs).not.toContain("nasqo_legacy_archive");
  expect(firestoreRequests).toEqual([]);
});

test("UI handles invalid {} JSON safely, inline invoice validation focuses field, hung requests time out cleanly with uncertain-write warning, and two sessions sync automatically", async ({
  browser,
}) => {
  test.setTimeout(120_000);
  const uid = "local-erp-workspace";
  const headers = { "X-NASQO-CSRF": "1" };

  const context1 = await browser.newContext({ viewport: { width: 412, height: 915 } });
  const context2 = await browser.newContext({ viewport: { width: 412, height: 915 } });
  const page1 = await context1.newPage();
  const page2 = await context2.newPage();

  try {
    // 1) Initial load error recovery: simulate 500 on first workspace GET, confirm error banner (not empty banner), then retry
    await page1.request.post(`/api/db/workspace/${uid}/reset`, {
      headers,
      data: { confirmation: `RESET:${uid}` },
    });
    let failInitialOnce = true;
    await page1.route(`**/api/db/workspace/${uid}*`, async (route) => {
      const urlObj = new URL(route.request().url());
      if (failInitialOnce && route.request().method() === "GET" && urlObj.pathname === `/api/db/workspace/${uid}`) {
        failInitialOnce = false;
        await route.fulfill({
          status: 500,
          contentType: "application/json",
          body: JSON.stringify({ error: "فشل مؤقت في تحميل قاعدة البيانات" }),
        });
        return;
      }
      await route.continue();
    });

    await page1.addInitScript(() => localStorage.setItem("nasqo-local-session-active", "1"));
    await page1.goto("/?autostart=1");
    await expect(page1.getByTestId("startup-storage-error")).toBeVisible({ timeout: 15_000 });
    await page1.getByTestId("startup-retry-button").click({ timeout: 10_000 });
    await expect(page1.getByTestId("startup-storage-error")).toHaveCount(0, { timeout: 15_000 });

    const grpClientsRes = await page1.request.post(`/api/db/workspace/${uid}/groups`, {
      headers,
      data: { group: { name: "العملاء", category: "clients", currencyCode: "ريال", sortOrder: 1 } },
    });
    const { group: grpClients } = await grpClientsRes.json();
    const whRes = await page1.request.post(`/api/db/workspace/${uid}/warehouses`, {
      headers,
      data: { warehouse: { name: "مخزن التزامن", isDefault: true, codeNumber: 1 } },
    });
    const { warehouse } = await whRes.json();
    const accRes = await page1.request.post(`/api/db/workspace/${uid}/accounts`, {
      headers,
      data: { account: { name: "حساب التحقق التفاعلي", category: "clients", groupId: grpClients.id, currency: "ريال", codeNumber: 201 } },
    });
    const { account } = await accRes.json();
    await page1.request.post(`/api/db/workspace/${uid}/ledger`, {
      headers,
      data: {
        entry: {
          accountId: account.id,
          accountName: account.name,
          kind: "invoice",
          typeLabel: "فاتورة بيع آجل",
          payment: "credit",
          direction: "debit",
          amount: 750,
          currency: "ريال",
          warehouseId: warehouse.id,
          warehouseName: warehouse.name,
          invoiceContent: "free",
          entryNumber: 9178,
          entryDate: "2026-11-18",
          details: "فاتورة حرة قابلة للتحقق",
        },
      },
    });
    await page1.reload();
    await expect(page1.getByTestId("dashboard-screen")).toBeVisible({ timeout: 20_000 });

    await page2.addInitScript(() => localStorage.setItem("nasqo-local-session-active", "1"));
    await page2.goto("/?autostart=1");
    await expect(page2.getByTestId("dashboard-screen")).toBeVisible({ timeout: 20_000 });
    await expect(page2.getByTestId("account-groups-table")).toContainText("العملاء", { timeout: 10_000 });

    // 2) Reject {} upload in UI without wiping existing records
    const [invalidChooser] = await Promise.all([
      page1.waitForEvent("filechooser", { timeout: 10_000 }),
      (async () => {
        await page1.getByTestId("header-options-btn").click({ timeout: 10_000 });
        await page1.getByTestId("options-restore-backup-btn").click({ timeout: 10_000 });
      })(),
    ]);
    await invalidChooser.setFiles({
      name: "empty-invalid.json",
      mimeType: "application/json",
      buffer: Buffer.from("{}"),
    });
    await expect(page1.locator(".app-toast")).toContainText(/تم رفض|فارغ/i, { timeout: 10_000 });
    await expect(page1.getByTestId("account-groups-table")).toContainText("العملاء");

    // 3) Inline validation & field focus in InvoiceModal when amount is cleared on existing invoice #9178
    await page1.getByRole("button", { name: "كشف حساب", exact: true }).click({ timeout: 10_000 });
    await page1.getByLabel("البحث عن الحساب").fill("حساب التحقق التفاعلي");
    await page1.getByRole("option", { name: "حساب التحقق التفاعلي" }).first().click({ timeout: 10_000 });
    await page1.getByRole("button", { name: "موافق", exact: true }).click({ timeout: 10_000 });
    await expect(page1.getByTestId("supplier-screen")).toBeVisible({ timeout: 10_000 });
    await page1.locator(".transaction-card", { hasText: "فاتورة حرة قابلة للتحقق" }).getByRole("button", { name: "تعديل #9178" }).click({ timeout: 10_000 });
    const invModal = page1.getByTestId("invoice-modal");
    await expect(invModal).toBeVisible({ timeout: 10_000 });
    const amountInput = invModal.getByTestId("invoice-free-amount");
    await amountInput.fill("");
    await invModal.getByTestId("invoice-save-btn").click({ timeout: 10_000 });
    await expect(invModal).toBeVisible();
    await expect(invModal.getByTestId("invoice-amount-error")).toBeVisible({ timeout: 10_000 });
    const isAmountFocused = await amountInput.evaluate((el) => document.activeElement === el);
    expect(isAmountFocused).toBe(true);
    await invModal.getByRole("button", { name: "إلغاء", exact: true }).click({ timeout: 10_000 });
    await expect(invModal).toHaveCount(0);

    await expect(page1.locator(".transaction-card", { hasText: "750" }).first()).toBeVisible({ timeout: 10_000 });

    // 4) Dropped mutating request displays "النتيجة غير مؤكدة" and verifies server state cleanly
    await page1.route(`**/api/db/workspace/${uid}/ledger`, async (route) => {
      if (route.request().method() === "POST") {
        await route.abort("connectionreset");
        return;
      }
      await route.continue();
    });
    await page1.getByRole("button", { name: "رجوع", exact: true }).click({ timeout: 10_000 });
    await expect(page1.getByTestId("dashboard-screen")).toBeVisible({ timeout: 10_000 });
    await page1.getByRole("button", { name: "فاتورة جديدة", exact: true }).click({ timeout: 10_000 });
    const droppedModal = page1.getByTestId("invoice-modal");
    await droppedModal.getByLabel("حرة", { exact: true }).check({ timeout: 10_000 });
    await droppedModal.getByTestId("invoice-free-amount").fill("225");
    await droppedModal.getByTestId("invoice-save-btn").click({ timeout: 10_000 });
    await expect(droppedModal.getByTestId("invoice-validation-error")).toContainText("النتيجة غير مؤكدة", { timeout: 10_000 });
    await page1.unroute(`**/api/db/workspace/${uid}/ledger`);
    await droppedModal.getByRole("button", { name: "إلغاء", exact: true }).click({ timeout: 10_000 });

    // 5) Hung JSON export in FullSqliteImportModal times out cleanly instead of hanging forever
    await page1.route(`**/api/db/workspace/${uid}/export/json`, async () => {
      // Intentionally hold request open beyond 12s AbortController timeout
    });
    await page1.getByTestId("home-nav-profile").click({ timeout: 10_000 });
    await page1.getByTestId("settings-full-sqlite-import-btn").click({ timeout: 10_000 });
    const dbCenter = page1.getByRole("dialog");
    await dbCenter.getByTestId("legacy-export-json-btn").click({ timeout: 10_000 });
    await expect(dbCenter.getByText(/انتهت مهلة الاتصال/i)).toBeVisible({ timeout: 20_000 });
    await page1.unrouteAll({ behavior: "ignoreErrors" });
    await dbCenter.getByRole("button", { name: "✕" }).click({ timeout: 10_000 });
    await page1.getByLabel("رجوع", { exact: true }).click({ timeout: 10_000 });

    // 6) Two-session cross-tab sync: create group + account in Session 1, focus Session 2 -> appears automatically!
    const grpSalesRes = await page1.request.post(`/api/db/workspace/${uid}/groups`, {
      headers,
      data: { group: { name: "المبيعات", category: "sales", currencyCode: "ريال", sortOrder: 2 } },
    });
    const { group: grpSales } = await grpSalesRes.json();
    await page1.request.post(`/api/db/workspace/${uid}/accounts`, {
      headers,
      data: { account: { name: "حساب الجلسة الثانية", category: "sales", groupId: grpSales.id, currency: "ريال", codeNumber: 202 } },
    });
    await page2.bringToFront();
    await page2.waitForTimeout(900);
    await page2.evaluate(() => window.dispatchEvent(new Event("focus")));
    await expect(page2.getByTestId("account-groups-table")).toContainText("المبيعات", { timeout: 15_000 });
    await page2.getByRole("button", { name: "كشف حساب", exact: true }).click({ timeout: 10_000 });
    await page2.getByLabel("البحث عن الحساب").fill("حساب الجلسة الثانية");
    await expect(page2.getByRole("option", { name: "حساب الجلسة الثانية" }).first()).toBeVisible({ timeout: 10_000 });

    // 7) Dynamic Currencies manager ("العملات"): default is ONLY "ريال", and adding/deleting a currency updates dropdowns live
    await page1.bringToFront();
    await page1.getByRole("button", { name: "العملات", exact: true }).click({ timeout: 10_000 });
    const currModal = page1.getByTestId("currencies-modal");
    await expect(currModal).toBeVisible({ timeout: 10_000 });
    await expect(currModal.getByTestId("currency-row-ريال")).toBeVisible();
    await currModal.getByTestId("currency-name-input").fill("ريال سعودي");
    await currModal.getByTestId("currency-sell-rate-input").fill("140");
    await currModal.getByTestId("currency-buy-rate-input").fill("140");
    await currModal.getByTestId("currency-subunit-input").fill("هللة");
    await currModal.getByTestId("currency-symbol-input").fill("ر.س");
    await currModal.getByTestId("currency-save-btn").click({ timeout: 10_000 });
    await expect(currModal.getByTestId("currency-row-ريال سعودي")).toBeVisible({ timeout: 10_000 });
    // Delete the custom currency and verify default "ريال" remains
    await currModal.getByTestId("currency-row-ريال سعودي").click({ timeout: 10_000 });
    await currModal.getByTestId("currency-delete-btn").click({ timeout: 10_000 });
    await expect(currModal.getByTestId("currency-row-ريال سعودي")).toHaveCount(0);
    await currModal.getByRole("button", { name: "إغلاق العملات", exact: true }).click({ timeout: 10_000 });
  } finally {
    await page1.unrouteAll({ behavior: "ignoreErrors" }).catch(() => {});
    await page2.unrouteAll({ behavior: "ignoreErrors" }).catch(() => {});
    await context1.close();
    await context2.close();
  }
});
