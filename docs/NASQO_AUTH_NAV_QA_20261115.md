# NASQO Pro Mobile — authentication and navigation verification
Date: 2026-11-15 (Asia/Aden)

## Environment and scope
- User task: test Odoo 19 authorization and button navigation after login **without creating real records**; do not alter UI design.
- Source: `AI_HANDOFF.md` and `docs/NASQO_ACTION_AUDIT.md` in `/home/chatgpt-admin/nasqo-pro-mobile-deploy`; GitHub draft PR #1.
- Target: `https://erp.indexesstore.com/nasqo-mobile/`.
- No test user credentials or authenticated browser/session is connected to this tool run. Browser plugin returned "requires originating browser context"; Opera Browser Connector returned "browser not connected". The independent Browser Use project reported insufficient credits previously.
- No authentication cookies were accessed or copied. No business records were read or created. This report is **not** evidence that post-login navigation or multi-company isolation passes.

## Performed read-only tests

| ID | Test | Result | Evidence |
|---|---|---|---|
| NAV-01 | All 31 declared native Odoo action IDs exist in installed `ir.actions.act_window` | PASS 31/31 | Read-only SQL Odoo 19 metadata query |
| NAV-02 | Each of the 31 action IDs points to the expected Odoo `res_model` | PASS 31/31 | Compared `src/odooNavigation.ts` map with `ir_act_window.id,res_model` |
| AUTH-01 | Anonymous GET `/odoo/action-<id>` for every configured action | PASS 31/31 | All returned HTTP 303 to Odoo `/web/login?redirect=...`; no unexpected response |
| AUTH-02 | Anonymous JSON-RPC POST `res.partner.search_read` | PASS (denied) | HTTP 200 JSON-RPC error code 100, no record list |
| ACL-01 | Read-only `ir_model_access` metadata audit of 13 key model classes | PASS (metadata inspection) | No active ACL records with null `group_id` for the inspected models; group-dependent permissions are present |
| ACL-02 | `base.group_public` / `base.group_portal` direct ACL entries inspected | PASS (metadata inspection) | Direct entries for inspected models were read-only, where present, and none directly granted create/write/unlink |
| ACL-03 | Selected action `groups_id` restrictions checked | PASS (metadata inspection) | No entries in `ir_act_window_group_rel` for the 31 configured actions; model ACLs, record rules and menu permissions still apply |
| SAFE-01 | Existing mocked `saveOdooContact` authentication/permission tests | PASS 5/5 | `npm run test:odoo`, no network writes |
| UI-01 | Protected mobile runtime | PASS | `npm run check:runtime` 28 protected files |
| UI-02 | CSS / mobile runtime remains unchanged relative to feature PR source | PASS | `git diff --quiet FETCH_HEAD -- src/prototype.css src/mobile` |

**Important interpretation:** An unauthenticated redirect and database ACL metadata cannot establish the permission outcome of a particular logged-in user. Also, successful routing does not validate which Odoo form appears after authentication, nor does it prove user record-rule isolation.

## Pending tests — requires a browser session with a test Odoo user

The user should sign in directly on `https://erp.indexesstore.com/web/login` using a **dedicated low-privilege test account**; credentials must not be sent into ChatGPT.

1. Navigate to `https://erp.indexesstore.com/nasqo-mobile/` and confirm the login gate clears without showing demo figures or other users' data.
2. Open the original 9 dashboard shortcuts and 8 metric cards; verify expected Odoo actions rather than sign-in redirect loops or generic access errors. Actual workflows still require Odoo's native forms.
3. For read-only actions, test contacts, invoices, partner ledger, purchase/sale reports, warehouses, stock moves, payments listing, currency list, and WAHA status view (admin-only).
4. Repeat the same actions as a restricted user and as a user belonging to a different allowed company; verify Odoo Access Denied and record rules where appropriate without exposing record details in reports.
5. Open Create Partner / Edit Partner dialogs but **cancel** confirmation; verify no HTTP `create`/`write` is dispatched and no records are created.
6. Open invoice/payment/stock native forms but do **not** submit. Confirm the correct model and required fields are displayed.
7. Keep visual classes/CSS unchanged; document only navigation, authorization and functionality defects.

## Status and action

- **PASS:** server-side URL wiring, anonymous authentication enforcement, and action/model metadata mapping.
- **PENDING:** authenticated browser E2E, authorized/unauthorized user ACL, multi-company record-rule isolation, and true navigation UI after login.
- **No code/CSS/deployment changes in this verification stage.**
- PR #1 should remain Draft until these pending checks have passed.
