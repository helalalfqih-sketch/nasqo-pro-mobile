# NASQO warehouse access error — verification and resolution

Date: 2026-11-15 (Asia/Aden)

## Observed production symptom

The dashboard previously showed:

`متصل بنسقو ERP · بيانات حقيقية وصلاحيات Odoo · تعذر تحميل: المخازن`

The live Odoo 19 application log contained **AccessError / warehouse access warnings** for `stock.warehouse` on 2026-11-14 around 23:02, 23:11 and 23:12 UTC. No credentials, partner names, or business records were inspected. Contact and invoice requests were not reported as failed by the user's UI.

Odoo model metadata confirms `stock.warehouse` exists, and the requested `name` and `company_id` fields are valid. Installed `stock`, `stock_account`, and `purchase_stock` modules are present. The failure is an authorization issue for the active login session, **not** a missing warehouse model or broken CSS.

## Existing Odoo access rules (read-only inspection)

Active warehouse ACLs grant read access to:
- `base.group_user` (Internal User) — read only.
- `sales_team.group_sale_salesman` — read only.
- `purchase.group_purchase_user` and `purchase.group_purchase_manager` — read only.
- `point_of_sale.group_pos_user` and `point_of_sale.group_pos_manager` — read only.
- `stock.group_stock_manager` — read, write, create and unlink.

This does not prove which groups the browser user has, nor whether a company-specific record rule denies access. Do not assign a broad group, change Odoo ACLs, expose a public warehouse endpoint, or create warehouse data to silence an error.

## What was changed

- Added `src/odooErrors.ts` with safe JSON-RPC error classification, distinguishing session expiration, Odoo `AccessError`/`AccessDenied`, and unrelated errors without showing backend tracebacks.
- Updated `src/liveOdoo.tsx` to retain the list of denied model sections separately from generic failures. Continue showing other permitted real datasets when warehouses are denied.
- Updated existing dashboard and warehouse message text in `src/Prototype.tsx` to explain permission failure and direct the user to their Odoo administrator. No JSX layouts, selectors, `src/prototype.css`, or protected mobile runtime files were changed.
- Added `tests/odoo-warehouse-access.test.mjs` with mocked classification and source wiring tests (4/4 passed).
- No production Odoo records or permissions were changed.

## Tests and deployment

- TypeScript: passed.
- ERP Vite build: passed.
- Warehouse permission tests: 4/4 passed.
- Sites tests: 4/4 passed.
- Odoo mocked integration tests: 5/5 passed.
- Browser-mode tests: 3/3 passed.
- Protected runtime check: 28 files passed.
- New build deployed under `https://erp.indexesstore.com/nasqo-mobile/`; HTML, JS, CSS, ERP login, storefront and homepage all returned HTTP 200.
- New JS: `/nasqo-mobile/assets/index-CXgfVEl_.js`, CSS unchanged: `/nasqo-mobile/assets/index-DT_QnIde.css`.
- Previous production entrypoint backup: `/home/chatgpt-admin/nasqo-mobile-ops/backups/warehouse-err-20261114T231543Z/index.html`. Prior hashed bundles retained; restore the saved entrypoint for rollback.
- Full login-specific end-to-end behavior was not independently verified (browser session unavailable). User must refresh their own authenticated browser to confirm the new message.

## To actually display warehouses

An authorized Odoo administrator should review the affected user's account type (Internal vs Portal), allowed companies, warehouse-related groups and `stock.warehouse` record rules, granting **only the least privileges justified by that user's role**. Do not assign Inventory Manager as a quick fix. Reopen the app after the authorization correction and verify that only warehouses permitted to the user are returned.

If the intended account must remain a portal user, do not turn it into an internal user automatically. Design and explicitly authorize a dedicated scoped read-only integration instead.
