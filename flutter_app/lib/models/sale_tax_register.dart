import 'erp_models.dart';

/// Observed LOCAL native sales only. Not a tax declaration or net VAT report:
/// purchases, returns, refunds and non-native documents are excluded. No FX.
class SaleTaxRegister {
  SaleTaxRegister(
      {this.from,
      this.through,
      required List<SaleTaxRegisterRow> rows,
      required List<SaleTaxCurrencySummary> currencies,
      this.invalidHeaderCount = 0})
      : rows = List.unmodifiable(rows),
        currencies = List.unmodifiable(currencies);
  final String? from, through;
  final List<SaleTaxRegisterRow> rows;
  final List<SaleTaxCurrencySummary> currencies;

  /// Eligible native headers with malformed date/currency. Invalid dates cannot
  /// be assigned to a period; count is diagnostic, never an included amount.
  final int invalidHeaderCount;
}

class SaleTaxRegisterRow {
  const SaleTaxRegisterRow(
      {required this.entryId,
      required this.entryNumber,
      required this.documentNumber,
      required this.date,
      required this.accountName,
      required this.currency,
      required this.preTaxTotal,
      required this.taxAmount,
      required this.finalTotal,
      required this.taxEnabled,
      required this.appliedTaxRate});
  final String entryId, documentNumber, date, accountName;
  final int entryNumber;
  final CurrencyCode currency;
  final double preTaxTotal, taxAmount, finalTotal, appliedTaxRate;
  final bool taxEnabled;
}

class SaleTaxCurrencySummary {
  const SaleTaxCurrencySummary(
      {required this.currency,
      required this.knownCount,
      required this.unknownCount,
      required this.preTaxTotal,
      required this.taxAmount,
      required this.finalTotal});
  final CurrencyCode currency;
  final int knownCount, unknownCount;

  /// Totals of known rows ONLY; unknown-only currency has no known amounts.
  /// UI must display unknownCount, not present these as a complete tax balance.
  final double preTaxTotal, taxAmount, finalTotal;
}
