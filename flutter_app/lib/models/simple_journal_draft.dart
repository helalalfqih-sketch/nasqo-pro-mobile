import 'erp_models.dart';

/// Nonposting two-leg journal proposal. One exact amount for both legs by construction.
class SimpleJournalDraft {
  const SimpleJournalDraft(
      {this.id,
      this.revision = 0,
      required this.date,
      required this.debitAccountId,
      required this.creditAccountId,
      required this.currency,
      required this.amount,
      this.note = ''});
  final int? id;
  final int revision;
  final String date, debitAccountId, creditAccountId, note;
  final CurrencyCode currency;
  final double amount;
  void validate() {
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date ||
        debitAccountId.trim().isEmpty ||
        creditAccountId.trim().isEmpty ||
        debitAccountId == creditAccountId ||
        !amount.isFinite ||
        amount <= 0 ||
        (id == null ? revision != 0 : id! <= 0 || revision <= 0)) {
      throw ArgumentError('بيانات مسودة القيد غير صالحة');
    }
  }
}
