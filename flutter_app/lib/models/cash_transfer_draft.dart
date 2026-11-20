import 'erp_models.dart';

/// Nonposting internal transfer proposal only; not a cash movement or payment.
class CashTransferDraft {
  const CashTransferDraft(
      {this.id,
      this.revision = 0,
      required this.date,
      required this.sourceCashId,
      required this.destinationCashId,
      required this.currency,
      required this.amount,
      this.note = ''});
  final int? id;
  final int revision;
  final String date, sourceCashId, destinationCashId, note;
  final CurrencyCode currency;
  final double amount;
  void validate() {
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date ||
        sourceCashId.trim().isEmpty ||
        destinationCashId.trim().isEmpty ||
        sourceCashId == destinationCashId ||
        !amount.isFinite ||
        amount <= 0 ||
        (id == null ? revision != 0 : id! <= 0 || revision <= 0)) {
      throw ArgumentError('بيانات مسودة التحويل غير صالحة');
    }
  }
}
