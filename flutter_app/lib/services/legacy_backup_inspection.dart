import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';

/// Read-only inspection of the older NASQO website SQLite backup schema.
/// Never maps unknown currencies to defaults or writes to the live phone DB.
class LegacyBackupInspection {
  const LegacyBackupInspection({
    required this.counts,
    required this.integrityOk,
    required this.missingCurrencies,
    required this.orphanInvoiceLines,
    required this.orphanProducts,
    required this.orphanAccounts,
    required this.orphanAccountGroups,
    required this.orphanWarehouses,
    required this.missingProductCurrencies,
  });
  final Map<String, int> counts;
  final bool integrityOk;
  final int missingCurrencies;
  final int orphanInvoiceLines;
  final int orphanProducts;
  final int orphanAccounts;
  final int orphanAccountGroups;
  final int orphanWarehouses;
  final int missingProductCurrencies;

  bool get safeForAutomaticRestore => false;

  String get arabicSummary =>
      'تم التعرف على نسخة موقع قديمة دون تغيير بيانات الهاتف. '
      'العملاء: ${counts['customers'] ?? 0}، الأصناف: ${counts['products'] ?? 0}، '
      'الحركات: ${counts['input_move'] ?? 0}، بنود الفواتير: ${counts['bill_details'] ?? 0}. '
      'فحص SQLite: ${integrityOk ? 'سليم' : 'فشل'}. '
      'حركات بعملة غير معرفة: $missingCurrencies، '
      'بنود بفاتورة مفقودة: $orphanInvoiceLines، '
      'بنود بصنف مفقود: $orphanProducts، '
      'حركات بحساب مفقود: $orphanAccounts، '
      'حسابات بمجموعة مفقودة: $orphanAccountGroups، '
      'بنود بمخزن مفقود: $orphanWarehouses، '
      'أصناف بعملة غير معرفة: $missingProductCurrencies. '
      'الاستعادة المباشرة موقوفة حتى اكتمال مطابقة الحسابات والعملات والمخزون. '
      'احتفظ بالملف الأصلي.';
}

Future<LegacyBackupInspection?> inspectLegacyBackup(Uint8List bytes) async {
  if (bytes.length < 16 ||
      !String.fromCharCodes(bytes.take(16)).startsWith('SQLite format 3\x00')) {
    return null;
  }
  final directory = await Directory.systemTemp.createTemp('nasqo-legacy-inspect-');
  try {
    final file = File('${directory.path}/source.sqlite');
    await file.writeAsBytes(bytes, flush: true);
    final db = await openDatabase(file.path, readOnly: true, singleInstance: false);
    try {
      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"))
          .map((row) => row['name']).toSet();
      const required = {
        'currencies', 'customers', 'products', 'stores',
        'cboxes', 'boxes', 'input_move', 'bill_details', 'trans_details'
      };
      if (!tables.containsAll(required)) return null;
      final check = await db.rawQuery('PRAGMA quick_check(1)');
      final integrityOk = check.length == 1 &&
          check.single.values.single == 'ok';
      final counts = <String, int>{};
      for (final table in required) {
        final result = await db.rawQuery('SELECT COUNT(*) AS total FROM "$table"');
        counts[table] = (result.single['total'] as num).toInt();
      }
      Future<int> count(String sql) async =>
          ((await db.rawQuery(sql)).single.values.single as num).toInt();
      final missingCurrencies = await count(
        'SELECT COUNT(*) FROM input_move m WHERE m.cur IS NOT NULL '
        'AND m.cur != 0 AND NOT EXISTS '
        '(SELECT 1 FROM currencies c WHERE c.id = m.cur)');
      final orphanInvoices = await count(
        'SELECT COUNT(*) FROM bill_details d WHERE NOT EXISTS '
        '(SELECT 1 FROM input_move m WHERE m.id = d.bill_id)');
      final orphanProducts = await count(
        'SELECT COUNT(*) FROM bill_details d WHERE NOT EXISTS '
        '(SELECT 1 FROM products p WHERE p.id = d.prod_id)');
      final orphanAccounts = await count(
        'SELECT COUNT(*) FROM input_move m WHERE NOT EXISTS '
        '(SELECT 1 FROM customers c WHERE c.id = m.per_id)');
      final orphanAccountGroups = await count(
        'SELECT COUNT(*) FROM customers c WHERE NOT EXISTS '
        '(SELECT 1 FROM boxes b WHERE b.id = c.type)');
      final orphanWarehouses = await count(
        'SELECT COUNT(*) FROM bill_details d WHERE NOT EXISTS '
        '(SELECT 1 FROM stores s WHERE s.id = d.store_id)');
      final missingProductCurrencies = await count(
        'SELECT COUNT(*) FROM products p WHERE p.cur IS NOT NULL '
        'AND p.cur != 0 AND NOT EXISTS '
        '(SELECT 1 FROM currencies c WHERE c.id = p.cur)');
      return LegacyBackupInspection(
        counts: counts,
        integrityOk: integrityOk,
        missingCurrencies: missingCurrencies,
        orphanInvoiceLines: orphanInvoices,
        orphanProducts: orphanProducts,
        orphanAccounts: orphanAccounts,
        orphanAccountGroups: orphanAccountGroups,
        orphanWarehouses: orphanWarehouses,
        missingProductCurrencies: missingProductCurrencies,
      );
    } finally {
      await db.close();
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
