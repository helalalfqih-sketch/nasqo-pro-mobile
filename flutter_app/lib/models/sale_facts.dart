import 'erp_models.dart';

/// Stock average at sale time, not a certified historical accounting cost.
/// Null means unavailable; never substitute zero for an unknown cost.
class SaleLineCostFact {
  const SaleLineCostFact({required this.position, this.stockAverageCost});
  final int position;
  final double? stockAverageCost;
}

/// Append-only facts recorded with a newly committed sale. No legacy inference.
/// Rate is a decimal fraction, e.g. 0.15, not percentage points.
class SaleFacts {
  SaleFacts(
      {required this.entryId,
      required this.currency,
      required this.preTaxTotal,
      required this.taxEnabled,
      required this.appliedTaxRate,
      required this.taxAmount,
      required this.finalTotal,
      required List<SaleLineCostFact> lineCosts})
      : lineCosts = List.unmodifiable(lineCosts);
  final String entryId;
  final CurrencyCode currency;
  final double preTaxTotal, appliedTaxRate, taxAmount, finalTotal;
  final bool taxEnabled;
  final List<SaleLineCostFact> lineCosts;
}
