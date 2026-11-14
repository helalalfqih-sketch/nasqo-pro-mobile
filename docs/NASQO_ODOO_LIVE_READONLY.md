# NASQO Pro Mobile — Odoo 19 read-only integration and HTTPS cutover

## Verified status (2026-11-15)

**Not live on the production hostname yet.** The actual production Caddyfile is root-owned, and the current Remote Desktop Commander account cannot write it. This is a staging and operator handoff, not evidence of authenticated business-data access.

- Source repository: `helalalfqih-sketch/nasqo-pro-mobile`
- PR: `https://github.com/helalalfqih-sketch/nasqo-pro-mobile/pull/1` (draft)
- Source branch: `feat/nasqo-odoo-readonly`
- Target path: `https://erp.indexesstore.com/nasqo-mobile/`
- Existing Odoo 19 production hostname: `https://erp.indexesstore.com`
- Separate private-network app container: `nasqo-pro-mobile-erp` on `indexes-waha_default` (no published host port)
- App internal upstream: `nasqo-pro-mobile-erp:8080`
- Existing HTTP public prototype: `nasqo-pro-mobile-web`, unchanged, still demonstration-only.
- Production proxy: `indexes-waha-caddy-1` routes ERP to `nasqo-odoo19:8069`.

## App data integration contract

`src/liveOdoo.tsx` uses same-origin Odoo JSON-RPC with `credentials: 'same-origin'` and no stored API keys. Live data mode is enabled **only** on HTTPS at the exact ERP hostname with URL prefix `/nasqo-mobile`. Unauthenticated users see a login gate instead of synthetic data. Authorized users may read, subject to Odoo ACLs and record rules:

- `res.partner`: id, name, phone (up to 100)
- `stock.warehouse`: id, name, company_id (up to 100)
- `account.move`: id, name, partner_id, move_type, invoice_date, amount_total, state; sale/purchase invoices only (up to 100)

Counts do not represent full accounting totals. Financial posting, mutations, exports and messaging are NOT connected. An authenticated low-privilege login test and company-isolation test are still required.

## Build: separate paths, no global /assets proxy

Run from project checkout:

```sh
npm ci --no-audit --no-fund
npm run build
npm run build:erp
npm run test:sites
npm run test:erp
```

`build:erp` outputs `dist/erp-client` with JavaScript and CSS under `/nasqo-mobile/assets/`, while the existing `dist/client` preview retains root `/assets/`. This avoids diverting Odoo's general assets.

The protected mobile runtime still references these exact fixed public paths; the domain proxy must forward ONLY these additional prefixes to the mobile static container:

- `/assets/iphone/*`
- `/assets/android/*`
- `/assets/status/*`

Do **not** proxy all of `/assets/*`.

## Prebuilt Caddy change (root permission required)

- Root-owned live file: `/opt/indexes-waha/apps/shopify-admin/indexes-waha/deploy/Caddyfile`
- Prepared **non-active** copy: `/home/chatgpt-admin/nasqo-mobile-ops/Caddyfile.candidate` (mode 0600)
- Local smoke proxy config: `/home/chatgpt-admin/nasqo-mobile-ops/Caddyfile.staging`
- The candidate contains the existing complete Caddyfile with only the ERP site block changed.
- Existing root-owned file and Odoo production services were not modified.

The ERP site should contain the following directives *inside the existing host block*, retaining its `encode zstd gzip` setting:

```caddyfile
erp.indexesstore.com {
    encode zstd gzip

    redir /nasqo-mobile /nasqo-mobile/ 308

    handle_path /nasqo-mobile/* {
        reverse_proxy nasqo-pro-mobile-erp:8080
    }

    @nasqoMobileRuntimeAssets path /assets/iphone/* /assets/android/* /assets/status/*
    handle @nasqoMobileRuntimeAssets {
        reverse_proxy nasqo-pro-mobile-erp:8080
    }

    handle {
        reverse_proxy nasqo-odoo19:8069
    }
}
```

### Authorized operator cutover procedure

1. Confirm authorized administrative access to the root-owned Caddyfile. Do not use Docker as an alternative route to bypass filesystem ownership. Do not disclose credentials in chat.
2. Compare the current production Caddyfile with the staged candidate and **abort if the original has changed**. Make a timestamped backup of the original on the host.
3. Install the candidate using the authorized administrator's normal change workflow, preserving owner/group and mode.
4. Run Caddy config validation under the real container environment; only reload `indexes-waha-caddy-1` after successful validation. Keep backup and rollback accessible.
5. Verify `https://erp.indexesstore.com/`, `/web/login`, `/nasqo`, `/nasqo-mobile/`, its compiled JS/CSS, its iOS/Android/status images, and that other `/assets/` paths still go to Odoo.
6. Verify anonymous Odoo JSON-RPC is rejected and real Odoo users can log in, read only authorized companies/records, and receive proper permission errors.
7. Only after HTTPS and access-control tests succeed, remove the public HTTP 18175 host binding from the **old preview container only**. Avoid altering the Odoo, WAHA, PostgreSQL, or Shopify services. Decide whether to merge PR 1 after review.

### Tested before production activation

- Original source runtime check: 28 protected files PASS.
- `npm run build:erp`: PASS (TypeScript and Vite).
- `npm run test:erp`: 3/3 PASS.
- `npm run test:sites`: 4/4 PASS.
- Candidate Caddyfile validation with non-production placeholder hosts: PASS.
- Local-only Caddy route simulation (127.0.0.1:18176): `/nasqo-mobile/` HTTP 200, JS/CSS HTTP 200, iPhone/Android/status public assets HTTP 200, legacy Odoo `/web/login`, `/nasqo` and `/` HTTP 200, absent mobile API HTTP 404.
- Anonymous Odoo session-info through the local proxy returned JSON-RPC error code 100; no records were read.
- Full production hostname activation, authenticated user permissions, and real browser QA: NOT YET VERIFIED.

## Rollback

Restore the backed-up original Caddyfile and validate/reload only Caddy using the authorized change procedure; leave existing Odoo and WAHA containers and databases untouched. The additional internal mobile container can be stopped independently if needed. Rollback must not overwrite any Odoo data.
