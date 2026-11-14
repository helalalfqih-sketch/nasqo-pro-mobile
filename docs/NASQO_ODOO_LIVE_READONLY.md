# NASQO Pro Mobile — Odoo read-only integration

## Scope
The mobile UI can read permitted contacts, warehouses and the most recent 100 purchase/sales invoices from NASQO's existing Odoo 19 using Odoo's own session and ORM access controls. It does **not** modify accounts, post invoices, send WhatsApp messages, or expose any Odoo service credentials.

- Source branch: `feat/nasqo-odoo-readonly`
- Intended HTTPS location: `https://erp.indexesstore.com/nasqo-mobile/`
- Login: same-origin `/web/login?redirect=%2Fnasqo-mobile%2F`
- JSON-RPC (same-origin): `/web/session/get_session_info` and `/web/dataset/call_kw/<model>/search_read`
- Models requested: `res.partner`, `stock.warehouse`, `account.move`.
- Read limit: 100 records per model; counts are **not** full business totals.
- The existing IP/HTTP preview is still a demo. Live API calls are enabled **only** when the browser is on HTTPS at `erp.indexesstore.com` under `/nasqo-mobile`.
- Authorization is always by Odoo's logged-in user; no `sudo` or API token is used.
- Unsupported screens remain non-live and are blocked from the live navigation. Financial writes remain disabled.

## Build and verification on the authorized host
1. `npm ci --no-audit --no-fund`
2. `npm run check:runtime`
3. `npm run build`
4. `npm run test:sites`

Actual checks: protected runtime check PASS (28 files); TypeScript + Vite production build PASS; 4/4 Sites tests PASS. The remote Odoo endpoint returned `Odoo Session Expired` to an anonymous JSON-RPC POST, as intended. No authenticated user integration or browser end-to-end test has been performed.

## HTTPS reverse proxy blocker (operator action required)
The live host Caddyfile is currently at
`/opt/indexes-waha/apps/shopify-admin/indexes-waha/deploy/Caddyfile`
and is owned by `root:root` with permissions `0644`. The connected `chatgpt-admin` user cannot write it. **No Caddyfile or existing Odoo service was changed.**

The separate `nasqo-pro-mobile-web` container has been attached to `indexes-waha_default` and is resolvable from `indexes-waha-caddy-1` as `http://nasqo-pro-mobile-web:8080/`.

An authorized Caddy operator must review and add a narrow HTTPS site route under `erp.indexesstore.com`, without replacing existing Odoo handling:

```caddyfile
redir /nasqo-mobile /nasqo-mobile/ 308
handle_path /nasqo-mobile/* {
    reverse_proxy nasqo-pro-mobile-web:8080
}
handle /assets/* {
    reverse_proxy nasqo-pro-mobile-web:8080
}
handle {
    reverse_proxy nasqo-odoo19:8069
}
```

**Important:** These are directives *inside* the existing `erp.indexesstore.com` site, not a second site block. Review the `/assets/*` matcher for possible collision with any other Odoo/storefront content, and verify the static bundle's `/assets` paths. Keep the existing `encode zstd gzip` and other security directives. Back up the entire Caddyfile, run `caddy validate` before reloading, and verify the existing ERP homepage, authenticated login, static assets, and mobile route, with immediate rollback if any fails.

Until this HTTPS route is active, **do not enter genuine business data into the public-IP HTTP prototype**. Production Odoo business records were not accessed or modified.

## Follow-up
- Obtain authorized change access for the Caddy route; explicitly confirm the final desired NASQO hostname if distinct from `erp.indexesstore.com`.
- Validate Odoo's logged-in session and model permissions using a real low-privilege user; check unauthenticated access is denied.
- Test the mobile UI on a real browser and verify company isolation / permitted record visibility.
- Consider narrowing the model queries and adding paginated navigation before broad deployment.
- Remove the old publicly bound HTTP port `18175` after HTTPS is tested, by recreating only `nasqo-pro-mobile-web` on the internal network with no host-port publishing.
