import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sale_facts.dart';
import 'package:nasqo_pro_erp/models/sales_return_draft.dart';
import 'package:nasqo_pro_erp/models/sales_return_estimate.dart';

SavedSaleLine original({int position = 0, double qty = 3, double price = 10}) =>
    SavedSaleLine(
        entryId: 's',
        position: position,
        itemId: 'i',
        itemName: 'صنف',
        unit: 'حبة',
        quantity: qty,
        unitPrice: price);
SalesReturnDraftLine selected(
        {int position = 0,
        double qty = 1,
        double sourceQty = 3,
        double price = 10,
        String item = 'i'}) =>
    SalesReturnDraftLine(
        position: position,
        itemId: item,
        itemName: 'صنف',
        unit: 'حبة',
        quantity: qty,
        sourceQuantity: sourceQty,
        unitPrice: price);
SalesReturnDraft draft(List<SalesReturnDraftLine> lines,
        {String source = 's', CurrencyCode currency = CurrencyCode.usd}) =>
    SalesReturnDraft(
        id: 1,
        revision: 1,
        sourceEntryId: source,
        date: '2026-01-01',
        reason: 'test',
        accountId: 'a',
        accountName: 'test',
        warehouseId: 'w',
        currency: currency,
        lines: lines);
SaleFacts facts(
        {double net = 30,
        double tax = 4.5,
        bool enabled = true,
        List<int> positions = const [0]}) =>
    SaleFacts(
        entryId: 's',
        currency: CurrencyCode.usd,
        preTaxTotal: net,
        taxEnabled: enabled,
        appliedTaxRate: enabled ? .15 : 0,
        taxAmount: tax,
        finalTotal: net + tax,
        lineCosts:
            positions.map((p) => SaleLineCostFact(position: p)).toList());
void main() {
  test('partial uses exact stored tax share; full preserves exact facts', () {
    final f = facts(
        tax:
            0.01); // deliberately verifies stored-tax allocation, not recomputation
    final part = calculateSalesReturnEstimate(
        draft: draft([selected()]), originalLines: [original()], facts: f);
    expect(part.available, true);
    expect(part.preTaxTotal, 10);
    expect(part.taxAmount, 0);
    expect(part.isFullReturn, false);
    final full = calculateSalesReturnEstimate(
        draft: draft([selected(qty: 3)]),
        originalLines: [original()],
        facts: f);
    expect(full.isFullReturn, true);
    expect(full.taxAmount, f.taxAmount);
    expect(full.finalTotal, f.finalTotal);
    expect(full.preTaxTotal, f.preTaxTotal);
  });
  test('partial rounded allocation and source inputs unchanged', () {
    final lines = [original()];
    final d = draft([selected(qty: 2)]);
    final e = calculateSalesReturnEstimate(
        draft: d, originalLines: lines, facts: facts(tax: 1));
    expect(e.taxAmount, .67);
    expect(e.finalTotal, 20.67);
    expect(lines.single.quantity, 3);
    expect(d.lines.single.quantity, 2);
  });
  test('missing facts and invalid links never fabricate estimate', () {
    for (final d in [
      draft([selected()], source: 'other'),
      draft([selected()], currency: CurrencyCode.sar)
    ]) {
      expect(
          calculateSalesReturnEstimate(
                  draft: d, originalLines: [original()], facts: facts())
              .available,
          false);
    }
    final e = calculateSalesReturnEstimate(
        draft: draft([selected()]), originalLines: [original()], facts: null);
    expect(e.available, false);
    expect(e.taxAmount, isNull);
    expect(e.unavailableReason, isNotEmpty);
  });
  test(
      'duplicates, ceilings, stale price/source quantity/identity and NaN reject',
      () {
    for (final picks in [
      <SalesReturnDraftLine>[],
      [selected(), selected()],
      [selected(qty: 4)],
      [selected(price: 11)],
      [selected(sourceQty: 4)],
      [selected(item: 'other')],
      [selected(qty: double.nan)],
      [selected(position: 8)]
    ]) {
      expect(
          calculateSalesReturnEstimate(
                  draft: draft(picks),
                  originalLines: [original()],
                  facts: facts())
              .available,
          false);
    }
    expect(
        calculateSalesReturnEstimate(
                draft: draft([selected()]),
                originalLines: [original(), original()],
                facts: facts())
            .available,
        false);
    expect(
        calculateSalesReturnEstimate(
                draft: draft([selected()]),
                originalLines: [original(qty: double.infinity)],
                facts: facts())
            .available,
        false);
  });
  test('zero base requires zero tax; free partial stays zero', () {
    final d = draft([selected(price: 0)]);
    final lines = [original(price: 0)];
    final e = calculateSalesReturnEstimate(
        draft: d,
        originalLines: lines,
        facts: facts(net: 0, tax: 0, enabled: false));
    expect(e.available, true);
    expect(e.finalTotal, 0);
    expect(
        calculateSalesReturnEstimate(
                draft: d, originalLines: lines, facts: facts(net: 0, tax: 1))
            .available,
        false);
  });
  test(
      'same item different positions remains distinct; full includes free lines',
      () {
    final lines = [original(), original(position: 1, qty: 1, price: 0)];
    final f = facts(positions: [0, 1]);
    final partial = calculateSalesReturnEstimate(
        draft: draft([selected(qty: 3)]), originalLines: lines, facts: f);
    expect(partial.available, true);
    expect(partial.isFullReturn, false);
    final full = calculateSalesReturnEstimate(
        draft: draft([
          selected(position: 1, qty: 1, sourceQty: 1, price: 0),
          selected(qty: 3)
        ]),
        originalLines: lines,
        facts: f);
    expect(full.isFullReturn, true);
    expect(full.finalTotal, 34.5);
  });
  test(
      'mismatched original base, disabled-tax inconsistency or missing positions reject',
      () {
    for (final f in [
      facts(net: 31),
      facts(enabled: false),
      facts(positions: [])
    ]) {
      expect(
          calculateSalesReturnEstimate(
                  draft: draft([selected()]),
                  originalLines: [original()],
                  facts: f)
              .available,
          false);
    }
  });
}
