import 'dart:convert';
import 'dart:typed_data';
import '../models/erp_models.dart';
import '../models/sales_return_draft.dart';

class LocalSalesCsvResult {
  LocalSalesCsvResult._(List<int> data, this.rowCount)
      : _data = List<int>.unmodifiable(data);
  final List<int> _data;

  /// Defensive copy: callers cannot alter another consumer's export payload.
  Uint8List get bytes => Uint8List.fromList(_data);
  final int rowCount;
  int get byteLength => _data.length;
}

/// Native sale HEADERS only, not a VAT declaration, net sales report or invoice
/// line export. Includes eligible old native headers without guessing tax/net.
/// No FX, aggregation, import, filesystem access, uploads or posting.
class LocalSalesCsv {
  static const maxRows = 10000;
  static const maxBytes = 8 * 1024 * 1024;
  static bool _iso(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.toIso8601String().substring(0, 10) == value;
  }

  /// Strip leading invisible/control/whitespace characters so they cannot hide
  /// a formula sigil. Preserve embedded CR/LF, commas, quotes and Arabic text.
  /// Apostrophe marks spreadsheet-dangerous strings as text. This intentional
  /// defensive transformation means the CSV is not a lossless import format.
  static String safeText(String value) {
    var clean =
        value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    clean = clean.replaceFirst(
        RegExp(
            r'^[\u0000-\u0020\u007f-\u00a0\u1680\u180e\u2000-\u200f\u2028-\u202f\u205f-\u206f\u3000\ufeff]+'),
        '');
    if (clean.isNotEmpty && '=+-@'.contains(clean[0])) clean = "'$clean";
    return clean;
  }

  static String _quote(String value) => '"${value.replaceAll('"', '""')}"';

  static LocalSalesCsvResult export(List<LedgerEntryRecord> entries,
      {CurrencyCode? currency, String? from, String? through}) {
    if ((from != null && !_iso(from)) ||
        (through != null && !_iso(through)) ||
        (from != null && through != null && from.compareTo(through) > 0)) {
      throw ArgumentError('الفترة غير صالحة؛ استخدم YYYY-MM-DD');
    }
    final selected = <LedgerEntryRecord>[];
    for (final entry in entries) {
      if (!isEligibleSalesReturnSource(entry) ||
          (currency != null && entry.currency != currency)) {
        continue;
      }
      if (!_iso(entry.entryDate)) {
        throw ArgumentError('تاريخ فاتورة محلية غير صالح');
      }
      if ((from != null && entry.entryDate.compareTo(from) < 0) ||
          (through != null && entry.entryDate.compareTo(through) > 0)) {
        continue;
      }
      if (!entry.amount.isFinite || entry.amount < 0) {
        throw ArgumentError('مبلغ الفاتورة غير صالح');
      }
      selected.add(entry);
      if (selected.length > maxRows) {
        throw StateError('تجاوز عدد صفوف التصدير المسموح');
      }
    }
    selected.sort((a, b) {
      final date = b.entryDate.compareTo(a.entryDate);
      if (date != 0) {
        return date;
      }
      final number = b.entryNumber.compareTo(a.entryNumber);
      return number != 0 ? number : a.id.compareTo(b.id);
    });
    final bytes = <int>[0xef, 0xbb, 0xbf];
    void append(List<String> cells) {
      // Conservative pre-encoding bound also handles a single oversized field.
      if (cells.fold<int>(0, (sum, c) => sum + c.length) > maxBytes) {
        throw StateError('تجاوز حجم التصدير المسموح');
      }
      final row = utf8.encode('${cells.map(_quote).join(',')}\r\n');
      if (bytes.length + row.length > maxBytes) {
        throw StateError('تجاوز حجم التصدير المسموح');
      }
      bytes.addAll(row);
    }

    append(['رقم المستند', 'التاريخ', 'العميل', 'العملة', 'الإجمالي المسجل']);
    for (final entry in selected) {
      // Avoid making an oversized sanitized copy from untrusted text.
      if (entry.documentNumber.length + entry.accountName.length > maxBytes) {
        throw StateError('تجاوز حجم التصدير المسموح');
      }
      append([
        safeText(entry.documentNumber),
        entry.entryDate,
        safeText(entry.accountName),
        entry.currency.label,
        entry.amount.toString()
      ]);
    }
    return LocalSalesCsvResult._(bytes, selected.length);
  }
}
