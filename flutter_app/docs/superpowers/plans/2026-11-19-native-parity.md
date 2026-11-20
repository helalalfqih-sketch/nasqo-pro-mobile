# Native NASQO parity: first functional release

**Goal:** close high-risk invoice and inventory gaps, then enable real read-only shortcuts using locally available records.

- Write failing tests for aggregated duplicate lines, mismatched warehouse, bad inputs, and durable line IDs and quantities. Reject the entire sale before mutation; keep both invoice form and POS on failure.
- Persist immutable invoice lines with an additive SQLite v1→v2 migration. Preserve existing ledger row identifiers; never reconstruct old quantities from text.
- Expose known line movements separately from legacy financial-only headers. Connect daily movement/search, statements/cashboxes, and warehouse navigation only after synthetic tests.
- Re-run Flutter static checks, test suite, and ARM64 debug build. Verify version, APK integrity and debug certificate. Do not write to GitHub/AI Studio or use production data. Never label partial implementation exact website parity.
