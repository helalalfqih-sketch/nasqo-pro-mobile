import 'erp_models.dart';

enum VoucherDraftType { receipt, payment }

/// Nonposting cash voucher proposal, NOT a receipt/payment or approval.
class VoucherDraft {
  const VoucherDraft(
      {this.id,
      this.revision = 0,
      required this.type,
      required this.date,
      required this.partyAccountId,
      required this.cashAccountId,
      required this.currency,
      required this.amount,
      this.note = ''});
  final int? id;
  final int revision;
  final VoucherDraftType type;
  final String date, partyAccountId, cashAccountId, note;
  final CurrencyCode currency;
  final double amount;

  void validate() {
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date ||
        !amount.isFinite ||
        amount <= 0 ||
        partyAccountId.trim().isEmpty ||
        cashAccountId.trim().isEmpty ||
        partyAccountId == cashAccountId ||
        (id == null ? revision != 0 : id! <= 0 || revision <= 0)) {
      throw ArgumentError('بيانات مسودة السند غير صالحة');
    }
  }
}
