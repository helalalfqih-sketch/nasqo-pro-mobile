import 'erp_models.dart';
import 'sale_facts.dart';
import 'sales_return_draft.dart';

/// Immutable values captured in one read of the committed local invoice.
class InvoicePrintSnapshot {
  InvoicePrintSnapshot(this.entry, Iterable<SavedSaleLine> lines, this.facts)
      : lines = List.unmodifiable(
            lines.toList()..sort((a, b) => a.position.compareTo(b.position))) {
    final purchase = entry.id.startsWith('purchase_') && !entry.deleted &&
        entry.kind == LedgerKind.invoice && entry.direction == EntryDirection.credit &&
        entry.typeLabel.startsWith('ف.مشتريات');
    if ((!isEligibleSalesReturnSource(entry) && !purchase) ||
        !entry.amount.isFinite ||
        entry.amount < 0 ||
        this.lines.any((line) =>
            line.entryId != entry.id ||
            !line.quantity.isFinite ||
            line.quantity <= 0 ||
            !line.unitPrice.isFinite ||
            line.unitPrice < 0 ||
            !(line.quantity * line.unitPrice).isFinite)) {
      throw const FormatException('Invalid saved invoice.');
    }
    final tax = facts;
    if (tax != null &&
        (tax.entryId != entry.id ||
            tax.currency != entry.currency ||
            tax.finalTotal != entry.amount ||
            [tax.preTaxTotal, tax.taxAmount]
                .any((v) => !v.isFinite || v < 0))) {
      throw const FormatException('Invalid saved tax facts.');
    }
  }

  final LedgerEntryRecord entry;
  final List<SavedSaleLine> lines;
  final SaleFacts? facts;
}
