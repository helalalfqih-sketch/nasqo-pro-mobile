# Flutter nonposting quotations and sales orders

- Add dedicated document headers and lines via SQLite v3, with atomic create/update, revision checks, and no impact on stock, cash or the financial ledger. Preserve v1/v2 data with additive migrations.
- Connect two independent RTL list and edit routes. Drawer shows lists; home shortcuts open drafts. Require explicit save, wait for SQLite commit, reject invalid input without closing, and keep Back/cancel free of writes.
- Add read-only account directory and deleted ledger list. Do not imply management or restore.
- Test application routing and synthetic SQLite reopening, editing, persistence failure, document isolation and financial data invariants. Verify ARM64 QA build independently.
- Do not convert, post, publish, modify real data, or disclose secrets. Existing Flutter sources are local; no WebView.
