# Next gate: truthful posted invoice acknowledgement

Current quote/order saves already await a separate SQLite transaction. For posted
sales, the prior controller still mutates memory then invokes unawaited
whole-snapshot persistence, which can fail silently. Do not treat current QA
build as production-safe for posted sales.

1. Add synthetic Flutter + SQLite tests first: failure leaves the draft, ledger,
   lines, inventory, and next number identical in memory and after reopening;
   duplicate save taps perform one write; success becomes visible only after
   commit; failed/in-flight startup does not write over existing data. Verify
   the POS uses the same stock validation and commit result.
2. Establish one mutation order for invoice posting and all other financial or
   inventory writers that can overwrite the same SQLite snapshot. An isolated
   transaction alone cannot prevent queued stale snapshots. Consider an
   explicit serial write boundary using immutable snapshots or narrowly scoped
   conditional writes; do not change unrelated purchase/HR posting semantics
   on guesses. Reject or safely serialize overlapping submissions.
3. Stage validated header, exact line quantities, inventory changes, and next
   number first. Commit one atomic unit and publish success to the controller
   and UI only after SQLite confirms it. Retain form values on failure and allow
   safe retry. Freeze dismissal while committing; include an accessible inline
   explanation.
4. Use SQLite v3 migration fixtures and full tests before a local QA build.
   No real records, external writes or publish. Returns/refunds remain separate.
