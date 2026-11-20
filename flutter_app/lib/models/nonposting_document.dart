import 'erp_models.dart';

enum NonpostingDocumentType { quote, order }

/// Independent non-posting document. Never an invoice or inventory movement.
class NonpostingLine {
  const NonpostingLine(
      {this.itemId = '',
      required this.description,
      required this.quantity,
      required this.unitPrice});
  final String itemId;
  final String description;
  final double quantity;
  final double unitPrice;
  double get total => quantity * unitPrice;
}

class NonpostingDocument {
  NonpostingDocument(
      {this.id,
      this.revision = 0,
      required this.type,
      required this.date,
      required this.currency,
      required this.customerName,
      this.accountId = '',
      this.notes = '',
      required List<NonpostingLine> lines})
      : lines = List.unmodifiable(lines);
  final int? id;
  final int revision;
  final NonpostingDocumentType type;
  final String date;
  final CurrencyCode currency;
  final String customerName;
  final String accountId;
  final String notes;
  final List<NonpostingLine> lines;
  double get total => lines.fold(0, (sum, line) => sum + line.total);

  void validate() {
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date) {
      throw ArgumentError('تاريخ المستند غير صالح');
    }
    if (customerName.trim().isEmpty ||
        lines.isEmpty ||
        (id != null && (id! <= 0 || revision < 1)) ||
        (id == null && revision != 0)) {
      throw ArgumentError('بيانات المستند غير مكتملة');
    }
    for (final line in lines) {
      if (line.description.trim().isEmpty ||
          !line.quantity.isFinite ||
          line.quantity <= 0 ||
          !line.unitPrice.isFinite ||
          line.unitPrice < 0 ||
          !line.total.isFinite) {
        throw ArgumentError('بند المستند غير صالح');
      }
    }
    if (!total.isFinite) throw ArgumentError('إجمالي المستند غير صالح');
  }
}
