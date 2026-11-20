import 'erp_models.dart';

class SalesReturnSelection {
  const SalesReturnSelection({required this.position, required this.quantity});
  final int position;
  final double quantity;
}

class SalesReturnDraftLine {
  const SalesReturnDraftLine(
      {required this.position,
      required this.itemId,
      required this.itemName,
      required this.unit,
      required this.quantity,
      required this.sourceQuantity,
      required this.unitPrice});
  final int position;
  final String itemId, itemName, unit;
  final double quantity, sourceQuantity, unitPrice;
  double get total => quantity * unitPrice;
}

/// Nonposting request only: neither reserves stock nor consumes return capacity.
/// Subtotal is a pre-tax estimate, never an approved credit/refund amount.
class SalesReturnDraft {
  SalesReturnDraft(
      {required this.id,
      required this.revision,
      required this.sourceEntryId,
      required this.date,
      required this.reason,
      required this.accountId,
      required this.accountName,
      required this.warehouseId,
      required this.currency,
      required List<SalesReturnDraftLine> lines})
      : lines = List.unmodifiable(lines);
  final int id, revision;
  final String sourceEntryId, date, reason, accountId, accountName, warehouseId;
  final CurrencyCode currency;
  final List<SalesReturnDraftLine> lines;
  double get subtotal => lines.fold(0, (sum, line) => sum + line.total);
}

/// Header eligibility only; callers must also require saved source lines.
bool isEligibleSalesReturnSource(LedgerEntryRecord entry) =>
    !entry.deleted &&
    entry.kind == LedgerKind.invoice &&
    entry.direction == EntryDirection.debit &&
    ['ف.مبيعات نقدية', 'ف.مبيعات آجل'].contains(entry.typeLabel);
