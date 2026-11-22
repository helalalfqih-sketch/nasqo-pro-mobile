import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'local_database.dart';

/// Original SmartPro databases are archived read-only; their rows are never
/// inserted into nasqo_pro_erp.db and cannot become financial postings here.
/// The archive is a private immutable evidence file, not another ERP ledger.
class SmartProHistoricalArchive {
  SmartProHistoricalArchive(this.live);

  final LocalDatabase live;
  static const maxBytes = 16 * 1024 * 1024;
  static final RegExp _hashPattern = RegExp(r'^[a-f0-9]{64}$');
  static final RegExp _filePattern =
      RegExp(r'^smartpro-([a-f0-9]{64})[.]back$');

  static String _ident(String name) =>
      '"${name.replaceAll('"', '""')}"';

  Future<Directory> _directory() async {
    final db = await live.database;
    final location = db.path;
    if (location == inMemoryDatabasePath || !p.isAbsolute(location)) {
      throw StateError('يلزم وجود قاعدة Android محلية لنسخ الأرشيف.');
    }
    final path = p.join(p.dirname(location), 'nasqo_smartpro_archives');
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        type == FileSystemEntityType.file) {
      throw StateError('مسار الأرشيف الخاص غير آمن.');
    }
    final dir = Directory(path);
    if (type == FileSystemEntityType.notFound) await dir.create();
    return dir;
  }

  Future<File> _archived(String sha) async {
    if (!_hashPattern.hasMatch(sha)) {
      throw const FormatException('بصمة الأرشيف غير صالحة.');
    }
    final dir = await _directory();
    final file = File(p.join(dir.path, 'smartpro-$sha.back'));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('الأرشيف المطلوب غير موجود محليًا.');
    }
    return file;
  }

  static void _validateHeader(Uint8List bytes) {
    if (bytes.length < 100 ||
        bytes.length > maxBytes ||
        String.fromCharCodes(bytes.take(16)) != 'SQLite format 3\x00') {
      throw const FormatException('الملف ليس قاعدة SQLite مدعومة.');
    }
  }

  Future<T> _readOnly<T>(
      Uint8List bytes, Future<T> Function(Database db) body) async {
    _validateHeader(bytes);
    final dir = await Directory.systemTemp.createTemp('nasqo-sp-v28-');
    final path = p.join(dir.path, 'source.back');
    Database? db;
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      await db.execute('PRAGMA trusted_schema=OFF');
      await db.execute('PRAGMA query_only=ON');
      return await body(db);
    } finally {
      if (db != null) await db.close();
      await dir.delete(recursive: true);
    }
  }

  static int _intQuery(List<Map<String, Object?>> rows) {
    final value = rows.first.values.first;
    return value is int ? value : (value as num).toInt();
  }

  static Future<int> _count(Database db, String statement) async =>
      _intQuery(await db.rawQuery(statement));

  Future<Map<String, Object?>> inspect(Uint8List bytes) async {
    final sourceHash = sha256.convert(bytes).toString();
    return _readOnly(bytes, (db) async {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 ||
          integrity.single.values.single != 'ok') {
        throw const FormatException('فشل فحص سلامة SQLite.');
      }
      final userVersion = _intQuery(await db.rawQuery('PRAGMA user_version'));
      if (userVersion != 28) {
        throw FormatException(
            'المخطط $userVersion ليس ملف SmartPro v28 المستهدف.');
      }
      final names = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"))
          .map((row) => row['name'] as String)
          .toList(growable: false);
      const required = {
        'customers', 'products', 'input_move', 'bill_details', 'bill_details2',
        'stores', 'store_trans', 'trans_details', 'currencies', 'boxes', 'cboxes',
        'offers',
      };
      if (!names.toSet().containsAll(required)) {
        throw const FormatException(
            'بعض جداول SmartPro الأساسية مفقودة؛ لا يمكن فحص هذا الملف كنسخة v28.');
      }
      final tables = <Map<String, Object?>>[];
      final counts = <String, int>{};
      var totalRows = 0;
      for (final name in names) {
        final columns = await db.rawQuery('PRAGMA table_info(${_ident(name)})');
        final count = await _count(db, 'SELECT COUNT(*) FROM ${_ident(name)}');
        totalRows += count;
        counts[name] = count;
        tables.add({
          'name': name,
          'rows': count,
          'columns': [
            for (final column in columns) column['name'] as String,
          ],
        });
      }

      final issues = <String, int>{
        'missingMovementCurrencies': await _count(db,
            'SELECT COUNT(*) FROM input_move m WHERE m.cur IS NOT NULL '
            'AND NOT EXISTS(SELECT 1 FROM currencies c WHERE c.id=m.cur)'),
        'missingCustomerReferences': await _count(db,
            'SELECT COUNT(*) FROM input_move m WHERE m.per_id IS NOT NULL '
            'AND NOT EXISTS(SELECT 1 FROM customers c WHERE c.id=m.per_id)'),
        'missingInvoiceProducts': await _count(db,
            'SELECT COUNT(*) FROM bill_details b WHERE b.prod_id IS NOT NULL '
            'AND NOT EXISTS(SELECT 1 FROM products p WHERE p.id=b.prod_id)'),
        'missingInvoiceWarehouses': await _count(db,
            'SELECT COUNT(*) FROM bill_details b WHERE b.store_id IS NOT NULL '
            'AND NOT EXISTS(SELECT 1 FROM stores s WHERE s.id=b.store_id)'),
        'missingTransferOrigins': await _count(db,
            'SELECT COUNT(*) FROM store_trans t WHERE t.store_id1 IS NOT NULL '
            'AND NOT EXISTS(SELECT 1 FROM stores s WHERE s.id=t.store_id1)'),
        'missingTransferDestinations': await _count(db,
            'SELECT COUNT(*) FROM store_trans t WHERE t.store_id2 IS NOT NULL '
            'AND NOT EXISTS(SELECT 1 FROM stores s WHERE s.id=t.store_id2)'),
        'unknownOpeningBalances': counts['customers'] ?? 0,
        'unknownWarehouseQuantities': counts['products'] ?? 0,
        'unconfirmedFinancialDocumentKinds': counts['input_move'] ?? 0,
      };
      final currencyDistribution = await db.rawQuery(
          'SELECT CAST(cur AS TEXT) AS id, COUNT(*) AS count '
          'FROM input_move GROUP BY cur ORDER BY count DESC');
      final kinds = await db.rawQuery(
          'SELECT CAST(bill_type AS TEXT) AS id, COUNT(*) AS count '
          'FROM input_move GROUP BY bill_type ORDER BY count DESC');
      final declaredFkIssues =
          (await db.rawQuery('PRAGMA foreign_key_check')).length;
      return <String, Object?>{
        'archiveOnly': true,
        'canRestore': false,
        'kind': 'smartpro-v28',
        'userVersion': userVersion,
        'sourceSha256': sourceHash,
        'bytes': bytes.length,
        'integrity': 'ok',
        'foreignKeyErrors': declaredFkIssues,
        'tableCount': tables.length,
        'totalRows': totalRows,
        'counts': counts,
        'tables': tables,
        'issues': issues,
        'currencyReferences': [
          for (final row in currencyDistribution)
            {'id': row['id'], 'count': row['count']},
        ],
        'documentTypes': [
          for (final row in kinds)
            {'id': row['id'], 'count': row['count'],
             'status': 'requires-mapping'},
        ],
        'postingEligible': 0,
        'postingBlockedReason':
            'لا يمكن إثبات الأرصدة الافتتاحية والعملات المفقودة '
            'وكميات الأصناف حسب المخزن وأنواع المستندات من بنية v28 وحدها.',
      };
    });
  }

  /// Immutable exact file preservation, keyed by content SHA-256. No writes to
  /// financial SQLite tables. Repeated import is idempotent across restarts.
  Future<Map<String, Object?>> saveArchive(
      Uint8List bytes, String expectedSha) async {
    _validateHeader(bytes);
    final hash = sha256.convert(bytes).toString();
    if (hash != expectedSha || !_hashPattern.hasMatch(hash)) {
      throw const FormatException('تغيرت بصمة المصدر بعد المعاينة.');
    }
    final reviewed = await inspect(bytes);
    final dir = await _directory();
    final target = File(p.join(dir.path, 'smartpro-$hash.back'));
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      final existing = await target.readAsBytes();
      if (sha256.convert(existing).toString() != hash) {
        throw StateError('أرشيف موجود ببصمة غير مطابقة؛ أُوقفت العملية.');
      }
      return {...reviewed, 'saved': true, 'alreadySaved': true};
    }
    if (type != FileSystemEntityType.notFound) {
      throw StateError('وجهة الأرشيف غير آمنة.');
    }
    final random = Random.secure();
    final suffix = List.generate(12,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final pending = File(p.join(dir.path, '.$hash-$suffix.pending'));
    var created = false;
    try {
      await pending.create(exclusive: true);
      created = true;
      await pending.writeAsBytes(bytes, flush: true);
      if (sha256.convert(await pending.readAsBytes()).toString() != hash) {
        throw StateError('فشل تطابق الأرشيف المنسوخ.');
      }
      await pending.rename(target.path);
    } finally {
      if (created && await pending.exists()) await pending.delete();
    }
    return {...reviewed, 'saved': true, 'alreadySaved': false};
  }

  Future<List<Map<String, Object?>>> listArchives() async {
    final dir = await _directory();
    final out = <Map<String, Object?>>[];
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      final match = _filePattern.firstMatch(p.basename(entry.path));
      if (match == null) continue;
      final hash = match.group(1)!;
      final length = await entry.length();
      out.add({'sourceSha256': hash, 'sizeBytes': length});
    }
    out.sort((a, b) =>
        (a['sourceSha256'] as String).compareTo(b['sourceSha256'] as String));
    return out;
  }

  Future<Map<String, Object?>> describe(String sha) async {
    final source = await _archived(sha);
    final bytes = await source.readAsBytes();
    if (sha256.convert(bytes).toString() != sha) {
      throw StateError('تغيرت محتويات الأرشيف المحفوظ.');
    }
    return {...await inspect(bytes), 'saved': true};
  }

  /// Only a safe SELECT on a table listed in the archive's sqlite_master.
  /// Table identifiers cannot enter SQL without membership check and quoting.
  Future<Map<String, Object?>> page(
      String sha, String table, int offset, int limit) async {
    final source = await _archived(sha);
    final bytes = await source.readAsBytes();
    if (sha256.convert(bytes).toString() != sha) {
      throw StateError('فشلت مطابقة SHA-256 لملف الأرشيف الأصلي.');
    }
    if (offset < 0 || limit < 1 || limit > 50) {
      throw const FormatException('حدود صفحة السجلات غير صالحة.');
    }
    return _readOnly(bytes, (db) async {
      final allowed = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toSet();
      if (!allowed.contains(table)) {
        throw const FormatException('اسم الجدول غير مسموح به.');
      }
      final cols = await db.rawQuery('PRAGMA table_info(${_ident(table)})');
      final names = [
        for (final c in cols) c['name'] as String,
      ];
      final primary = cols.where((c) => (c['pk'] as int) > 0).toList();
      primary.sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
      final order = primary.isEmpty
          ? ''
          : ' ORDER BY ${primary.map((c) => _ident(c['name'] as String)).join(', ')}';
      final count = await _count(db, 'SELECT COUNT(*) FROM ${_ident(table)}');
      final results = await db.rawQuery(
          'SELECT * FROM ${_ident(table)}$order LIMIT ? OFFSET ?',
          [limit, offset]);
      Object? safeValue(Object? value) {
        if (value is Uint8List) {
          return <String, Object?>{
            'type': 'BLOB',
            'bytes': value.length,
            'sha256': sha256.convert(value).toString(),
          };
        }
        if (value is String && value.length > 32768) {
          return <String, Object?>{
            'type': 'TEXT',
            'preview': value.substring(0, 32768),
            'truncated': true,
            'originalCharacters': value.length,
          };
        }
        return value;
      }
      return {
        'archiveOnly': true,
        'table': table,
        'sourceSha256': sha,
        'columns': names,
        'total': count,
        'offset': offset,
        'limit': limit,
        'rows': [
          for (final row in results)
            {for (final c in row.keys) c: safeValue(row[c])},
        ],
      };
    });
  }
}
