# NASQO Pro Mobile — notifications, themes, QR scanning, dashboard personalization

Date: 2026-11-15. Branch: `feat/nasqo-odoo-readonly`. Production URL: `https://erp.indexesstore.com/nasqo-mobile/`.

## Implemented

1. **Notifications center** (`src/dashboardAlerts.ts`, `src/dashboardAlertMath.ts`): pending posted customer/vendor invoices due within the next seven days, based on `account.move.invoice_date_due` and `amount_residual>0`; last 14 days of readable Odoo `mail.message` notification subjects; and recently modified low-stock reordering rules from accessible `stock.warehouse.orderpoint` data. This last category reflects *recent updates of orderpoint records*, not proof of when a product first dropped below minimum. The dashboard header bell opens the in-app notification center. Odoo model access denials display appropriate unavailable states.
2. **Light / dark / system appearance**: settings on the dashboard with system preference listener. Applied only to the live NASQO browser view; protected phone simulator files remain unchanged.
3. **Brand color**: color picker updates NASQO's primary CSS color, readable foreground contrast, and the browser `meta[name=theme-color]`. Validated hexadecimal colors only. Locally stored separately per Odoo user.
4. **Camera QR and barcode scanner** (`src/DashboardScanner.tsx`): ZXing 0.1.5 and 0.21.3 (Node 22-compatible), dynamically loaded on a click requesting camera access. Scanned identifiers are sanitized (not treated as URLs/scripts), and looked up exactly against Odoo `product.product.barcode/default_code` with the user's same-origin Odoo session. Shows matched product; provides links to Odoo native product and stock-receipt workflows. **Does not directly create or update stock quantities** or choose warehouse for the user; inventory receipt is finalized only through Odoo, with normal ACL/business validations. Manual barcode input fallback when camera permission or browser support is unavailable. Video capture stops on completion/close.
5. **Drag-and-drop** (`src/DashboardReorder.tsx`, `src/dashboardReorderMath.ts`): touch, mouse/pointer, and keyboard sortable handles for three summary cards and eight dashboard widgets. Source data does not change when cards move; order persists per user in local browser storage.
6. **Favorites**: pin up to eight approved native Odoo report shortcuts or currently readable contact accounts. Only IDs are stored; names are resolved from the currently allowed contacts. Stored under a per-user browser key with safe validation. Favorites offer opening the chosen report or the selected contact's existing in-app invoice view.
7. **Haptic feedback**: vibrates on user button interactions, QR success, pin/unpin and drag completion when `navigator.vibrate` is available and reduced-motion is not requested. User can switch this off.
8. **Full-database export banner and notifications**: existing server backup artifacts were observed during a read-only audit; however there is **no authenticated Odoo endpoint that reports the latest complete backup reliably in real time**. The dashboard therefore explicitly displays `not available for automatic verification` by default, and allows the user to record a date they have verified **manually** on this browser. If the entered date is more than seven calendar days ago, it shows an in-app warning and can send one generic device notification per recorded date *only after explicit user opt-in and browser permission*. A manually entered timestamp is not proof of a new backup. **Automatic trusted export-status integration remains pending**, and no new DB export, Odoo ACL change or backup job was initiated.

## Data access and operational limits

- Odoo requests stay same-origin with existing authenticated JSON-RPC, using Odoo model ACL and record rules. No cookies, passwords, backup files or private records are embedded in public frontend assets.
- Camera is requested only via a user-initiated HTTPS action, not on page load. The QR decoder never opens external URLs or posts inventory writes.
- `mail.message` notification subjects are rendered as escaped React strings; message bodies are not fetched or injected as HTML.
- Local preferences contain theme/color/ordering, favorite IDs, haptics choice and manually entered date; never financial totals, authentication credentials or backup dump paths.
- Native device notification is conditional on user opt-in. In-app alerts work even if native notifications are unavailable.
- The existing D3 seven-day chart, invoice list, low-stock threshold list, PDF export, nine demo quick actions, original phone prototype and responsive production mode remain.

## Build, QA and rollout

- TypeScript and Vite Cloud/Sites + ERP production builds: PASS.
- Automated tests: 27 source/business/authorization tests, 4 Sites tests, 3 ERP asset tests, **34/34 PASS**.
- Protected mobile runtime: 28 files PASS. `npm ci --dry-run` PASS. `npm audit --omit=dev`: 0 reported known issues.
- HTTPS live: `/nasqo-mobile/`, main JS, CSS, lazy QR decoder, jsPDF, html2canvas, original Odoo `/`, `/nasqo`, `/web/login`, `/shop` all HTTP 200 after deployment.
- Live containers `nasqo-pro-mobile-erp` and `indexes-waha-caddy-1` remain up; restart count 0.
- Deployed static bundle main JS: `/nasqo-mobile/assets/index-DN34qPBL.js`, CSS: `/nasqo-mobile/assets/index-Dhmfxm17.css`.
- Backup for immediate rollback of static app entrypoint: `/home/chatgpt-admin/nasqo-mobile-ops/backups/dashboard-extras-20261115T000335Z/index.html`. Restore **only** this HTML to `dist/erp-client/index.html` if necessary. Prior hashed assets are preserved. No changes to Caddy/Odoo DB.

## Verification gaps and next steps

- No authenticated real-browser end-to-end QA, real camera permission test, drag gesture visual test, color theme screenshot or OS push notification acceptance test has been performed in this run. A low-privilege user must validate these on an actual device with appropriate Odoo access.
- Odoo `stock.warehouse` and `stock.warehouse.orderpoint` may deny the current login access. These alerts display permission warnings; no role escalation or bypass was attempted.
- An Odoo administrator can approve a narrow authenticated *read-only* backend endpoint exposing a verified successful full DB export completion timestamp, to replace the current explicitly manual backup-date status. Until then, no automated true-backup-age guarantees can be made.
- PR #1 should remain Draft until these acceptance checks are complete.
