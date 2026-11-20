import 'erp_models.dart';
import 'sale_facts.dart';
import 'sales_return_draft.dart';

/// Indicative estimate for ONE saved, nonposting draft. It is not an approval,
/// credit note, refund, tax allocation ledger or remaining-return entitlement.
/// Independently rounded draft estimates MUST NOT be summed as approved tax.
class SalesReturnEstimate {
  const SalesReturnEstimate._(
      {required this.available,
      this.unavailableReason,
      this.preTaxTotal,
      this.taxAmount,
      this.finalTotal,
      this.isFullReturn = false});
  final bool available;
  final String? unavailableReason;
  final double? preTaxTotal, taxAmount, finalTotal;
  final bool isFullReturn;
}

SalesReturnEstimate calculateSalesReturnEstimate({
  required SalesReturnDraft draft,
  required List<SavedSaleLine> originalLines,
  required SaleFacts? facts,
}) {
  SalesReturnEstimate unavailable(String reason) =>
      SalesReturnEstimate._(available: false, unavailableReason: reason);
  bool valid(double v) => v.isFinite && v >= 0;
  bool close(double a, double b) =>
      a.isFinite && b.isFinite && (a - b).abs() <= 1e-7;
  if (facts == null) {
    return unavailable(
        'حقائق الضريبة الأصلية غير محفوظة؛ لا يمكن تقديرها من النص.');
  }
  if (draft.id <= 0 ||
      draft.revision <= 0 ||
      draft.sourceEntryId.isEmpty ||
      facts.entryId != draft.sourceEntryId ||
      facts.currency != draft.currency) {
    return unavailable('المسودة أو مرجع الفاتورة أو العملة غير متطابقة.');
  }
  if (![
        facts.preTaxTotal,
        facts.taxAmount,
        facts.finalTotal,
        facts.appliedTaxRate
      ].every(valid) ||
      facts.appliedTaxRate > 1 ||
      (!facts.taxEnabled &&
          (facts.taxAmount != 0 || facts.appliedTaxRate != 0)) ||
      !close(facts.preTaxTotal + facts.taxAmount, facts.finalTotal) ||
      (facts.preTaxTotal == 0 && facts.taxAmount != 0)) {
    return unavailable('المبالغ الأصلية غير متسقة.');
  }
  final originals = <int, SavedSaleLine>{};
  var originalNet = 0.0;
  final ordered = List<SavedSaleLine>.of(originalLines)
    ..sort((a, b) => a.position.compareTo(b.position));
  for (final line in ordered) {
    if (line.entryId != facts.entryId ||
        line.position < 0 ||
        originals.containsKey(line.position) ||
        line.itemId.isEmpty ||
        line.unit.isEmpty ||
        !valid(line.quantity) ||
        line.quantity == 0 ||
        !valid(line.unitPrice) ||
        !valid(line.quantity * line.unitPrice)) {
      return unavailable('بنود الأصل مفقودة أو غير متسقة.');
    }
    originals[line.position] = line;
    originalNet += line.quantity * line.unitPrice;
  }
  if (originals.isEmpty || !close(originalNet, facts.preTaxTotal)) {
    return unavailable('بنود الأصل لا تطابق الأساس المحفوظ.');
  }
  final costPositions = <int>{};
  for (final cost in facts.lineCosts) {
    if (!originals.containsKey(cost.position) ||
        !costPositions.add(cost.position) ||
        (cost.stockAverageCost != null && !valid(cost.stockAverageCost!))) {
      return unavailable('مواضع حقائق الأصل غير متطابقة.');
    }
  }
  if (costPositions.length != originals.length) {
    return unavailable('حقائق بنود الأصل غير مكتملة.');
  }
  final selected = <int>{};
  var selectedNet = 0.0;
  var full = draft.lines.length == originals.length;
  for (final line in draft.lines) {
    final source = originals[line.position];
    if (source == null ||
        !selected.add(line.position) ||
        line.itemId != source.itemId ||
        line.itemName != source.itemName ||
        line.unit != source.unit ||
        line.unitPrice != source.unitPrice ||
        line.sourceQuantity != source.quantity ||
        !valid(line.quantity) ||
        line.quantity == 0 ||
        line.quantity > source.quantity ||
        !valid(line.total)) {
      return unavailable('اختيار المرتجع لا يطابق بند الأصل أو يتجاوز كميته.');
    }
    selectedNet += line.total;
    full = full && line.quantity == source.quantity;
  }
  if (selected.isEmpty ||
      !valid(selectedNet) ||
      (selectedNet > originalNet && !close(selectedNet, originalNet))) {
    return unavailable('كمية أو قيمة المرتجع غير صالحة.');
  }
  if (full) {
    return SalesReturnEstimate._(
        available: true,
        isFullReturn: true,
        preTaxTotal: facts.preTaxTotal,
        taxAmount: facts.taxAmount,
        finalTotal: facts.finalTotal);
  }
  // Use stored tax, NOT a newly recomputed tax rate. The order of division
  // avoids intermediate overflow. Free lines / zero-base tax-free sale => 0.
  final rawTax =
      originalNet == 0 ? 0.0 : facts.taxAmount * (selectedNet / originalNet);
  if (!rawTax.isFinite || rawTax * 100 > 9007199254740991) {
    return unavailable('المبلغ خارج نطاق التقدير الآمن.');
  }
  final tax = ((rawTax * 100).roundToDouble() / 100)
      .clamp(0.0, facts.taxAmount)
      .toDouble();
  final total = selectedNet + tax;
  if (!total.isFinite) return unavailable('إجمالي التقدير غير صالح.');
  return SalesReturnEstimate._(
      available: true,
      preTaxTotal: selectedNet,
      taxAmount: tax,
      finalTotal: total);
}
