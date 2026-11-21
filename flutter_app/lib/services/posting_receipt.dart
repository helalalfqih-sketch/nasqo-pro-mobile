import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../models/erp_models.dart';

/// Store the receipt in the primary ledger ID. Existing SQLite transactions,
/// exports and restores preserve it together with the actual financial posting.
class PostingReceipt {
  PostingReceipt(String operation, String requestId, List<Object?> fields) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(requestId)) {
      throw const SaleValidationException('معرّف محاولة الحفظ غير صالح.');
    }
    marker = '_r${_hash([operation, requestId])}_';
    fingerprint = _hash(fields);
  }

  late final String marker;
  late final String fingerprint;

  static final _random = Random.secure();
  static String newRequest() => List.generate(
      16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  static String _hash(List<Object?> data) =>
      sha256.convert(utf8.encode(jsonEncode(data))).toString().substring(0, 32);

  static List<Object?> row(InvoiceItemRow line) => [
        line.itemId,
        line.productName,
        line.quantity.toString(),
        line.unitPrice.toString(),
        line.discount.toString(),
        line.roundLineTotal,
      ];

  String primaryId(String prefix) => '$prefix$marker$fingerprint';

  LedgerEntryRecord? previous(Iterable<LedgerEntryRecord> ledger) {
    for (final entry in ledger) {
      final split = entry.id.indexOf(marker);
      if (split < 0) continue;
      final saved = entry.id.substring(split + marker.length);
      // Settlements and returns have a suffix or a parent ID in their path.
      if (entry.id.substring(0, split).contains('/') ||
          !RegExp(r'^[a-f0-9]{32}
      if (saved != fingerprint || entry.deleted) {
        throw const SaleValidationException(
            'محاولة الحفظ مرتبطة بمستند سابق. راجع المستند قبل إنشاء آخر.');
      }
      return entry;
    }
    return null;
  }
}
).hasMatch(saved)) {
        continue;
      }
      if (saved != fingerprint || entry.deleted) {
        throw const SaleValidationException(
            'محاولة الحفظ مرتبطة بمستند سابق. راجع المستند قبل إنشاء آخر.');
      }
      return entry;
    }
    return null;
  }
}
