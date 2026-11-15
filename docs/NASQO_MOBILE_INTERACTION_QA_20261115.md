# NASQO Pro Mobile — Mobile interaction QA and tap fix

Date: 2026-11-15 · Target: `https://erp.indexesstore.com/nasqo-mobile/` · Source: `feat/nasqo-odoo-readonly`.

## Method and safeguards

- Real Chromium headless browser tested with **Pixel 7 and iPhone 13 mobile viewports**, device touch emulation, and a simulated camera source. The iPhone viewport test uses the **Chromium engine, not Safari/WebKit**.
- Served isolated built candidate HTML/CSS/JS via Playwright response routing on the application's genuine HTTPS origin. Intercepted **all Odoo `/web/*` requests**, returned synthetic Odoo RPC fixtures for partners, invoices, warehouses, low-stock rules, system notifications and product lookup. **No actual Odoo authenticated session or financial/customer records were accessed or modified.**
- Used a fake camera source and explicit permission; verified video track becomes live and stops when user presses Stop. Tested manual barcode lookup against synthetic `product.product` and opening/closing QR scanner without a stock write.
- Mocked native Notification and Vibration APIs; checked user opt-in, alert age, and disabled haptics without OS notifications.
- Recorded QA screenshots at `/home/chatgpt-admin/nasqo-mobile-ops/mobile-browser-qa` on the server. The screenshot content contains synthetic customer/product names only.
- Browser shell and four missing shared libraries were installed **only inside the chatgpt-admin QA directory**; no packages or browser dependencies installed globally or in the production Docker images.

## Defect reproduced

The existing protected `src/mobile/FlowStack.tsx` uses a touch/edge-swipe gesture binding with a capture-stage click filter. On mobile touch-capable browsers it **canceled trusted button clicks** inside the live dashboard. Symptoms: resetting the primary color, pinning favorites, opening QR, recording a backup date, and toggling haptics appeared to do nothing. A trusted native click was visibly prevented at the React `.flow-stack` capture handler, while a synthetic click on the exact same target activated the UI. This was confirmed with browser event propagation instrumentation, not inferred from unit tests.

## Minimal production-only repair

- `src/Prototype.tsx`: live dashboard now uses normal browser-native scroll markup with the original CSS classes; the standalone phone simulator continues using protected `MobileScroll`.
- `src/prototype.css`: isolated `body.nasqo-browser-mode` CSS enables native touch scrolling and preserves the original visual hierarchy.
- `src/NasqoDashboard.tsx` and `src/DashboardScanner.tsx`: isolated interactive pointer-down gestures so that inherited FlowStack drag activation does not interfere with buttons; dnd-kit sort handles retain their normal drag handlers.
- New `src/dashboardMobileTap.ts`: narrowly scoped mobile/coarse-pointer compatibility bridge replays **only trusted, canceled, non-drag dashboard/QR control clicks**, never a DnD sort handle or pointer travel greater than 12px. It does nothing for a normal successful click or untrusted/synthetic events.
- No changes to `src/mobile/`, `src/App.tsx`, `src/styles.css`, the user-selected NASQO brand palette, Odoo RPC, permissions, Caddy, or database.

## Automated browser results (synthetic data only)

Each run passed **12/12** in both mobile viewport profiles:

1. Dashboard renders edge-to-edge without Pixel/iPhone simulator chrome.
2. Real simulated touch swipes scroll the long dashboard.
3. In-app pending invoice alerts, system messages, and low-stock rows render from mocked Odoo data.
4. Light/dark/system themes work and persist across reload.
5. Primary brand color updates CSS/meta theme-color and resets to default.
6. Favorites pin, persist across reload, and remove.
7. Summary tiles reorder using mouse drag without data loss.
8. Summary tiles reorder with actual CDP touch event stream (long-press + move).
9. QR dialog opens, fake camera video track starts/stops, barcode lookup returns the expected product, dialog closes.
10. A manually entered 9-day-old backup date creates the expected alert; opt-in generates a mocked device notification only.
11. Haptic feedback triggers when enabled and does not trigger after disabling.
12. No Odoo production create/write/unlink or other API mutation requests; JavaScript page errors: none.

Test runner: `tests/mobile-interactions.qa.mjs`. Run from project checkout with `NASQO_QA_ASSETS_DIR=dist/erp-mobile-qa` and `LD_LIBRARY_PATH=/home/chatgpt-admin/nasqo-mobile-ops/playwright-libs/root/usr/lib/x86_64-linux-gnu`; optional `NASQO_QA_DEVICE='iPhone 13'`. The browser is installed at `~/.cache/ms-playwright`. Browser QA requires the separate local-only Chromium dependencies but no production credentials.

## Not verified

- **Real physical phone camera** and a true QR optical scan, as opposed to fake camera stream + manual barcode entry.
- Native iOS Safari/WebKit gesture behavior, actual OS push notifications, physical vibration motor.
- Authenticated production-user Odoo ACL/record rules, stocks from the user's real companies, and financial writes.

## Deployment and rollback

Use isolated Vite staging output and verify first. Deploy by copying hashed static assets then atomically replacing only `dist/erp-client/index.html`; maintain the previous HTML entrypoint in a timestamped private backup. Validate HTTPS JS/CSS, original Odoo routes, and Docker service health. Preserve PR #1 as Draft pending real device and ACL acceptance.

## Final production verification — 2026-11-15

- Final mobile touch fix is deployed on https://erp.indexesstore.com/nasqo-mobile/; bundle /nasqo-mobile/assets/index-DGWPUhKP.js and stylesheet /nasqo-mobile/assets/index-SlqVNKiH.css both HTTP 200.
- Final HTML SHA256: cc8e9c6793367dbe794053cda288e3c58542b054e15ec616682cd3fb8bcb0fa4.
- Immediate rollback copy of the previous live index: /home/chatgpt-admin/nasqo-mobile-ops/backups/mobile-switch-20261115T114423Z/index.html. To roll back, restore ONLY that file to dist/erp-client/index.html; older hashed assets are retained. No Caddy or DB modification necessary.
- The haptic checkbox had one intermittent failure in mobile touch E2E despite a prior pass. Replaced it with an accessible role=switch button with aria-checked, styled to match the former compact square. Repeated both mobile profiles successfully.
- Pre-deployment unit/source suites: 29 tests passed; Sites 4 tests passed; ERP asset bundle 3 tests passed, **36/36 total**. TypeScript, Vite Sites and ERP builds passed, 28 protected runtime files passed, npm audit --omit=dev reported no known issues.
- Actual deployed HTTPS assets retested using Chromium Pixel 7 and iPhone 13 mobile viewport emulation (Chromium, not Safari), 12/12 on each; Odoo calls were intercepted with synthetic fixture data and no writes. Touch scroll, drag/drop with genuine CDP touch stream, theme/meta color, persistent favorites, fake camera stream + barcode lookup, scanner close, mocked backup alert/native Notification, haptic on/off, and absence of JS page errors all passed.
- Follow-up needed: actual user device (Safari/Android), physical camera QR optical decode, physical vibration/OS notifications, and authorized Odoo company-scoped account access. No live business records read or changed by QA.
