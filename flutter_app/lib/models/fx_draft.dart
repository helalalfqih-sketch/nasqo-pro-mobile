import 'erp_models.dart';

/// Nonposting proposal with two independently entered amounts. No rate, fee,
/// conversion or execution is calculated or implied by this model.
class FxDraft {
  const FxDraft(
      {this.id,
      this.revision = 0,
      required this.date,
      required this.sourceCashId,
      required this.destinationCashId,
      required this.sourceCurrency,
      required this.destinationCurrency,
      required this.sourceAmount,
      required this.destinationAmount,
      this.note = ''});
  final int? id;
  final int revision;
  final String date, sourceCashId, destinationCashId, note;
  final CurrencyCode sourceCurrency, destinationCurrency;
  final double sourceAmount, destinationAmount;
  void validate() {
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date ||
        sourceCashId.trim().isEmpty ||
        destinationCashId.trim().isEmpty ||
        sourceCashId == destinationCashId ||
        sourceCurrency == destinationCurrency ||
        !sourceAmount.isFinite ||
        sourceAmount <= 0 ||
        !destinationAmount.isFinite ||
        destinationAmount <= 0 ||
        (id == null ? revision != 0 : id! <= 0 || revision <= 0)) {
      throw ArgumentError('بيانات مسودة المصارفة غير صالحة');
    }
  }
}
