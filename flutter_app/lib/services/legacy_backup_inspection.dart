import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'legacy_website_converter.dart';

/// Evidence gathered on a private, read-only copy. No live database handle.
class LegacyBackupInspection {
  const LegacyBackupInspection(
      this.counts,
      this.columns,
      this.issues,
      this.currencyReferences,
      this.checksum,
      this.size,
      this.version,
      this.integrityOk);
  final Map<String, int> counts, issues;
  final Map<String, Map<String, String>> columns;
  final List<Map<String, Object?>> currencyReferences;
  final String checksum;
  final int size, version;
  final bool integrityOk;

  bool get safeForAutomaticRestore => false;
  int get missingCurrencies => issues['حركات بعملة غير معرفة'] ?? 0;
  int get orphanInvoiceLines => issues['بنود بفاتورة مفقودة'] ?? 0;
  int get orphanProducts => issues['بنود بصنف مفقود'] ?? 0;
  int get orphanAccounts => issues['حركات بحساب مفقود'] ?? 0;
  int get orphanAccountGroups => issues['حسابات بمجموعة مفقودة'] ?? 0;
  int get orphanWarehouses => issues['بنود بمخزن مفقود'] ?? 0;
  int get missingProductCurrencies => issues['أصناف بعملة غير معرفة'] ?? 0;

  Map<String, int> get missingCurrencyCounts {
    final counts = <String, int>{};
    for (final row in currencyReferences) {
      final id = row['currencyId']?.toString() ?? 'NULL';
      counts.update(id, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  String get arabicSummary => [
        'نسخة SQLite قديمة من الموقع • إصدار المخطط $version',
        'فحص SQLite: ${integrityOk ? "سليم" : "فشل"}',
        'الحسابات: ${counts["customers"]} • الأصناف: ${counts["products"]} • المخازن: ${counts["stores"]}',
        'الحركات: ${counts["input_move"]} • بنود الفواتير: ${counts["bill_details"]}',
        for (final e in missingCurrencyCounts.entries)
          'معرّف العملة ${e.key}: ${e.value} حركة بلا تعريف في دليل العملات.',
        for (final e in issues.entries)
          if (e.value > 0) '${e.key}: ${e.value}',
        'الاستعادة المباشرة موقوفة حتى مطابقة القيم والمراجع.',
      ].join('\n');

  Map<String, Object?> toJson() => {
        'format': 'nasqo-legacy-inspection-v1',
        'sourceSha256': checksum,
        'bytes': size,
        'userVersion': version,
        'integrityOk': integrityOk,
        'rowCounts': counts,
        'sourceColumns': columns,
        'recognizedFields': {
          for (final e in columns.entries)
            e.key: e.value.keys
                .where((c) => legacyMappedColumns[e.key]?.contains(c) == true)
                .toList()
        },
        'unmappedFields': {
          for (final e in columns.entries)
            e.key: e.value.keys
                .where((c) => legacyMappedColumns[e.key]?.contains(c) != true)
                .toList()
        },
        'unmappedPopulatedTables': {
          for (final e in counts.entries)
            if (e.value > 0 &&
                e.key != 'android_metadata' &&
                !legacyMappedColumns.containsKey(e.key))
              e.key: e.value
        },
        'issues': issues,
        'missingMovementCurrencyCounts': missingCurrencyCounts,
        'unresolvedMovementCurrencies': currencyReferences,
        'restored': false,
      };
}

String _ident(String name) => '"${name.replaceAll('"', '""')}"';

Future<LegacyBackupInspection?> inspectLegacyBackup(Uint8List bytes) async {
  if (bytes.length < 16 ||
      String.fromCharCodes(bytes.take(16)) != 'SQLite format 3\x00') {
    return null;
  }
  final dir = await Directory.systemTemp.createTemp('nasqo-legacy-');
  try {
    final path = (await File('${dir.path}/source.db').writeAsBytes(bytes)).path;
    final db = await openDatabase(path, readOnly: true, singleInstance: false);
    try {
      await db.execute('PRAGMA trusted_schema=OFF');
      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*' ORDER BY name"))
          .map((r) => r['name'] as String)
          .toSet();
      if (!tables.containsAll({'customers', 'products', 'stores'})) return null;
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      final ok =
          integrity.length == 1 && integrity.single.values.single == 'ok';
      final version = (await db.rawQuery('PRAGMA user_version'))
          .single
          .values
          .single as int;
      final counts = <String, int>{}, issues = <String, int>{};
      final columns = <String, Map<String, String>>{};
      final missing = <Map<String, Object?>>[];
      Future<int> count(String sql) async =>
          (await db.rawQuery(sql)).single.values.single as int;
      if (ok) {
        final schema = await db
            .rawQuery("SELECT name,sql FROM sqlite_master WHERE type='table'");
        if (schema.any((r) => RegExp(r'^CREATE\s+VIRTUAL', caseSensitive: false)
            .hasMatch(r['sql'].toString()))) {
          throw const FormatException(
              'تتضمن النسخة جداول افتراضية غير مدعومة.');
        }
        for (final t in tables) {
          final name = _ident(t);
          counts[t] = await count('SELECT count(*) FROM $name');
          columns[t] = {
            for (final r in await db.rawQuery('PRAGMA table_info($name)'))
              r['name'] as String: r['type'].toString()
          };
          if (columns[t]!.containsKey('id')) {
            issues['معرف مكرر أو مفقود في $t'] =
                await count('SELECT count(*) - count(DISTINCT id) FROM $name');
          }
        }
        const required = {
          'customers': ['id', 'type'],
          'products': ['id'],
          'stores': ['id'],
          'currencies': ['id', 'name'],
          'boxes': ['id'],
          'input_move': ['id', 'cur', 'per_id'],
          'bill_details': ['id', 'bill_id', 'prod_id', 'store_id']
        };
        for (final e in required.entries) {
          for (final c in e.value) {
            if (columns[e.key]?.containsKey(c) != true)
              issues['عمود مطلوب مفقود ${e.key}.$c'] = 1;
          }
        }
        Future<void> reference(
            String t, String c, String target, String label) async {
          if (columns[t]?.containsKey(c) != true ||
              columns[target]?.containsKey('id') != true) return;
          final predicate =
              'NOT EXISTS (SELECT 1 FROM $target p WHERE p.id = s.$c)';
          issues[label] =
              await count('SELECT count(*) FROM $t s WHERE $predicate');
          if (t == 'input_move' &&
              c == 'cur' &&
              columns[t]!.containsKey('id')) {
            final fields = [
              'id AS movementId', 'cur AS currencyId',
              if (columns[t]!.containsKey('bill_type')) 'bill_type AS documentType',
              if (columns[t]!.containsKey('curprice')) 'curprice AS sourceExchangeRate',
            ];
            missing.addAll(await db.rawQuery(
                'SELECT ${fields.join(", ")} FROM input_move s WHERE $predicate ORDER BY cur,id'));
          }
        }

        await reference(
            'input_move', 'cur', 'currencies', 'حركات بعملة غير معرفة');
        await reference(
            'products', 'cur', 'currencies', 'أصناف بعملة غير معرفة');
        await reference('customers', 'type', 'boxes', 'حسابات بمجموعة مفقودة');
        await reference(
            'input_move', 'per_id', 'customers', 'حركات بحساب مفقود');
        await reference(
            'bill_details', 'prod_id', 'products', 'بنود بصنف مفقود');
        await reference(
            'bill_details', 'bill_id', 'input_move', 'بنود بفاتورة مفقودة');
        await reference(
            'bill_details', 'store_id', 'stores', 'بنود بمخزن مفقود');
        await reference('bill_details2', 'bill_id', 'input_move', 'بنود حرة بمستند مفقود');
        await reference('trans_details', 'bill_id', 'store_trans', 'بنود تحويل مخزني بمستند مفقود');
        await reference('trans_details', 'prod_id', 'products', 'بنود تحويل مخزني بصنف مفقود');
        await reference('store_trans', 'store_id1', 'stores', 'تحويلات بمخزن مصدر مفقود');
        await reference('store_trans', 'store_id2', 'stores', 'تحويلات بمخزن وجهة مفقود');
        await reference('boxes', 'cur', 'currencies', 'مجموعات بعملة غير معرفة');
        await reference('cboxes', 'cur', 'currencies', 'صناديق بعملة غير معرفة');
        await reference('offers', 'cur', 'currencies', 'عروض بعملة غير معرفة');
        if (version == 28) {
          void requireEvidence(String table, List<String> fields, String reason) {
            final n = counts[table] ?? 0;
            if (n > 0 && !fields.every((key) => columns[table]!.containsKey(key))) {
              issues[reason] = n;
            }
          }
          requireEvidence('products', ['store_id', 'quantity'],
              'أصناف تحتاج إلى كشف كميات حسب المستودع');
          requireEvidence('customers', ['opening_balance', 'opening_direction'],
              'حسابات تحتاج إلى إثبات الرصيد الافتتاحي واتجاهه');
          requireEvidence('cboxes', ['account_id'],
              'صناديق تحتاج إلى ربط صريح بالحساب');
        }
        issues['مخالفات المفاتيح الخارجية المعلنة'] =
            (await db.rawQuery('PRAGMA foreign_key_check')).length;
      }
      return LegacyBackupInspection(counts, columns, issues, missing,
          sha256.convert(bytes).toString(), bytes.length, version, ok);
    } finally {
      await db.close();
    }
  } finally {
    await dir.delete(recursive: true);
  }
}
