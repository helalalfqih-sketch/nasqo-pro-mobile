# Next gate: preserve original sale facts before return posting

1. Persist structured sale facts for **new** sales created after this change:
   original currency, original pre-tax total, original tax-enabled policy and
   rate actually used by the existing calculation, its tax amount and final
   total, plus per-line inventory cost snapshot if available. Preserve the
   original observed numbers and current calculations; do not invent a business
   tax rate or change the app's existing policy in this step.
2. Write these facts in the same atomic transaction as the stock, ledger,
   identifiers, and line amounts. Failing one write must revert everything.
   Snapshot writers and unrelated document edits must preserve the facts.
3. Add only new tables/columns. Existing persisted sales do not gain fake
   tax/cost histories. A draft referencing an old sale remains a draft; do
   not parse descriptions or compute an assumed historical refund.
4. Separate future credit documentation from cash settlement. Before any live
   posting feature, prove cumulative movement limits, transaction/duplicate
   guards, tax and quantity conservation calculations, and correct classification
   in income and VAT reports. Do not infer web policy from local code.
5. Synthetic tests, locally signed QA APK where verified, no publication/data
   transfers outside the user’s trusted private delivery.
