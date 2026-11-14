# NASQO Pro Mobile — ERP live dashboard, seven-day D3 trend and PDF export

Date: 2026-11-15 · Source branch: `feat/nasqo-odoo-readonly` · Draft PR #1

## Requested behavior, implemented

Added `src/NasqoDashboard.tsx` into the existing `DashboardPage` on the live HTTPS ERP URL only, preserving the original blue/orange RTL presentation, original nine quick actions, and original standalone phone simulator demo.

The new live dashboard provides:
- Summary cards for **net sales over the last seven calendar days** by currency, the recent readable invoices (from the existing Odoo invoice list), and the count of low-stock orderpoints
- A D3.js SVG seven-day line chart with localized numbers and point labels
- A recent invoices list with dates, partners, amounts, and currency labels
- A named low-stock list showing product, stock location, quantity on hand, and configured minimum
- Explicit quick actions for customer invoice, purchase order, and new contact (reuse existing Odoo workflows and authorization)
- Client-side export/download PDF and optional native share with browser fallback

## Data sources and calculations

- Sales source: logged-in Odoo `account.move` through same-origin `search_count` and `search_read`, domain `state=posted`, move types `out_invoice` and `out_refund`, and invoice date inclusive from today minus six days to today. The signed net is `abs(out_invoice.amount_total)-abs(out_refund.amount_total)` grouped by `currency_id`. **Do not add different currencies together**.
- Invoice lists: existing `res.partner` and `account.move` context, now also reading `currency_id` for invoice amounts. Dashboard shows five most recent accessible invoices; the original source list is limited to 100 latest records.
- Low stock source: authorized `stock.warehouse.orderpoint` records with `product_min_qty>0`; alert when `qty_on_hand<product_min_qty`, including product, location, and UoM. This respects Odoo session ACLs and company record rules. **This is reordering-rule-based low stock**, not an arbitrary universal threshold applied to products without rules.
- Pagination uses at most 3,000 records per model. If the count exceeds the cap, data fetching fails closed (no incomplete "total" displayed). Non-finite and malformed data is not silently counted.
- No example amounts, synthetic supplier names, or fabricated stock alerts are injected into the live dashboard.
- Important: accounts lacking access to `stock.warehouse.orderpoint` get a visible permission warning instead of false zero stock alerts. Existing `stock.warehouse` AccessError can remain until an authorized Odoo administrator grants required scoped access. We did NOT modify Odoo roles or business records.

## PDF

- `src/dashboardPdf.ts` generates report PDF entirely on the user's device via `html2canvas` and `jsPDF`; the Arabic report is rasterized to preserve shaping. It includes sales-by-currency figures and daily totals, available recent invoices, and the named low-stock list (up to 100 item lines, with a visible truncation notice if more).
- Uses `textContent` for all ERP-derived strings, not `innerHTML`, to avoid HTML/script injection.
- `download` creates a local PDF file. `share` invokes the browser's file share sheet where supported, otherwise falls back to download. Explicit user cancellation does not initiate download.
- PDF creation is disabled while dashboard data is loading or if both sales and stock datasets are unavailable. If one dataset is denied, the report includes a clear unavailable-data warning, not fictitious totals.
- No external PDF processing or telemetry API is called. File sharing is a direct user gesture to the browser.

## Tests and deployment

- TypeScript compilation and Vite production build PASS.
- Dashboard tests 6/6 PASS (date window, currency separation, refunds, low-stock filtering, safe PDF path, D3 component).
- Existing protected runtime checks 28 files PASS.
- Existing Sites tests 4/4, ERP asset tests 3/3, Odoo mocked tests 5/5, warehouse permission tests 4/4, browser-mode tests 3/3 PASS.
- `npm audit --omit=dev`: no reported vulnerabilities at the time of execution.
- Live app uses HTTPS at `https://erp.indexesstore.com/nasqo-mobile/`, and the server-side Caddy/ERP setup remains unchanged.
- Source-only changes: `src/NasqoDashboard.tsx`, `src/dashboardData.ts`, `src/dashboardMath.ts`, `src/dashboardPdf.ts`, `src/Prototype.tsx`, `src/liveOdoo.tsx`, app-owned `src/prototype.css`, dependencies/lockfile, and `tests/dashboard.test.mjs`.
- No protected `src/mobile/`, `src/App.tsx`, `src/styles.css`, or platform chrome changes.

## Limitations / acceptance

- No authenticated user browser E2E could run from the available connector. Chart display, actual PDF visual pagination/Arabic glyphs, Web Share on a phone, and low-stock list with the actual login must be verified on the user's device.
- The dashboard is **not** an all-time revenue total. It uses a rolling seven-day calendar window, posted invoices only, net of refunds.
- When products have no configured reordering rule, they do not appear in the low-stock list. Configuring thresholds is an Odoo inventory-administration task.
- No accounting writes, inventory adjustments, Odoo permission changes, or external file shares were performed during deployment.
- Source remains in Draft PR #1 pending authenticated end-to-end acceptance; do not merge prematurely.
