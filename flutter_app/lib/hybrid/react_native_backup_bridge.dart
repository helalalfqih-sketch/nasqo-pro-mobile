import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../models/erp_models.dart';
import '../services/local_backup_files.dart';
import '../services/smartpro_historical_archive.dart';
import '../services/web_backup.dart';
import '../services/website_backup_file.dart';
import '../services/website_restore_trial.dart';
import '../state/erp_controller.dart';

typedef NativeBackupChooser = Future<XFile?> Function();

/// All file contents stay in Dart. The React WebView receives only counts,
/// a short-lived opaque approval token, and a verified result receipt.
class ReactNativeBackupBridge {
  ReactNativeBackupBridge(this.controller, {NativeBackupChooser? chooseFile})
      : _chooseFile = chooseFile ?? _androidPicker;

  final ErpController controller;
  final NativeBackupChooser _chooseFile;
  SmartProHistoricalArchive get _historical => SmartProHistoricalArchive(controller.database);
  Uint8List? _historicalBytes;
  String? _historicalSha;
  String? _historicalToken;
  static const int maxBytes = LocalBackupFiles.maxBackupBytes;
  static const Duration previewLifetime = Duration(minutes: 10);

  WebBackup? _staged;
  Map<String, Object?>? _preview;
  String? _token;
  String? _sourceSha;
  DateTime? _expiresAt;
  String? _completedToken;
  String? _completedKey;
  Map<String, Object?>? _completedReceipt;

  static Future<XFile?> _androidPicker() => openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'NASQO Web backup', extensions: [
            'json', 'sqlite', 'sqlite3', 'db', 'backup', 'back', 'gz'
          ])
        ],
      );

  static String _newToken() {
    final rng = Random.secure();
    return List<int>.generate(24, (_) => rng.nextInt(256))
        .map((n) => n.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static int _countList(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is List ? value.length : 0;
  }

  static List<Map<String, Object?>> _unsupportedRows(
      Map<String, dynamic> document) {
    // Reject any populated collection not mapped to native SQLite rather
    // than silently discarding records after a seemingly successful import.
    const mapped = <String>{
      'accountGroups', 'accounts', 'currencies', 'ledger', 'inventory',
      'warehouses',
    };
    final skipped = <Map<String, Object?>>[
      for (final entry in document.entries)
        if (entry.value is List &&
            !mapped.contains(entry.key) &&
            (entry.value as List).isNotEmpty)
          {'section': entry.key, 'count': (entry.value as List).length},
    ];
    final currencies = document['currencies'];
    if (currencies is List) {
      final invalid = currencies.where((row) {
        if (row is! Map) return true;
        final value = (row['code'] ?? row['name'])?.toString();
        return !CurrencyCode.values.any(
          (c) => c.label == value ||
              c.name.toUpperCase() == value?.toUpperCase(),
        );
      }).length;
      if (invalid > 0) {
        skipped.add({'section': 'unsupportedCurrencies', 'count': invalid});
      }
    }
    return skipped..sort((a, b) =>
        (a['section'] as String).compareTo(b['section'] as String));
  }

  Future<Map<String, Object?>> chooseAndInspect(
      Map<String, Object?> payload) async {
    if (payload['purpose'] != 'restore-backup') {
      throw const FormatException(
          'يُتاح اختيار ملف النسخة الاحتياطية فقط عبر هذا المسار.');
    }
    // A second selection revokes every previous approval.
    _staged = null;
    _preview = null;
    _token = null;
    _historicalBytes = null;
    _historicalSha = null;
    _historicalToken = null;
    _sourceSha = null;
    _expiresAt = null;
    final selected = await _chooseFile();
    if (selected == null) return {'cancelled': true};
    final advertisedLength = await selected.length();
    if (advertisedLength < 1 || advertisedLength > maxBytes) {
      throw const FormatException('حجم ملف الاستيراد غير مدعوم (16 MiB حد أقصى).');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in selected.openRead()) {
      if (buffer.length + chunk.length > maxBytes) {
        throw const FormatException('حجم ملف الاستيراد تجاوز 16 MiB.');
      }
      buffer.add(chunk);
    }
    final bytes = buffer.takeBytes();
    final fileSha = sha256.convert(bytes).toString();
    final raw = await unpackWebsiteBackup(bytes, maxBytes);
    final isSqlite = raw.length >= 16 &&
        ascii.decode(raw.sublist(0, 16), allowInvalid: true) ==
            'SQLite format 3\u0000';
    // SmartPro 28 is historical evidence, not a supported mobile ledger
    // export. Do not run the strict financial converter against it or reject
    // extra columns, missing currency IDs and unknown document types.
    // The exact original bytes remain inside Dart and are never returned to
    // the React WebView. This branch deliberately blocks accounting posting.
    final schemaHeaderVersion = isSqlite && raw.length >= 64
        ? (raw[60] << 24) | (raw[61] << 16) | (raw[62] << 8) | raw[63]
        : -1;
    if (schemaHeaderVersion == 28) {
      if (raw.length != bytes.length ||
          sha256.convert(raw).toString() != fileSha) {
        throw const FormatException(
            'الأرشيف التاريخي يجب اختياره كملف SQLite أصلي غير مضغوط.');
      }
      final audit = await _historical.inspect(raw);
      final tables = (audit['counts'] as Map).cast<String, int>();
      final issues = (audit['issues'] as Map).cast<String, int>();
      final token = _newToken();
      _historicalBytes = bytes;
      _historicalSha = fileSha;
      _historicalToken = token;
      _expiresAt = DateTime.now().add(previewLifetime);
      final preview = <String, Object?>{
        'fileName': selected.name,
        'format': 'SQLite',
        'version': 28,
        'sizeBytes': bytes.length,
        'sourceSha256': fileSha,
        'counts': <String, int>{
          'accounts': tables['customers'] ?? 0,
          'groups': tables['boxes'] ?? 0,
          'currencies': tables['currencies'] ?? 0,
          // Document categories cannot safely be inferred from bill_type.
          'invoices': 0,
          'vouchers': 0,
          'movements': tables['input_move'] ?? 0,
          'invoiceLines': (tables['bill_details'] ?? 0) +
              (tables['bill_details2'] ?? 0),
          'warehouses': tables['stores'] ?? 0,
          'items': tables['products'] ?? 0,
        },
        'unsupported': [
          for (final issue in issues.entries)
            if (issue.value > 0)
              {'section': issue.key, 'count': issue.value},
        ],
        'trialIntegrity': audit['integrity'],
        'trialMatchedRecords': 0,
        'trialError': audit['postingBlockedReason'],
        'canRestore': false,
        'previewToken': token,
        'historicalArchive': {
          'tableCount': audit['tableCount'],
          'totalRows': audit['totalRows'],
          'tables': audit['tables'],
          'issues': audit['issues'],
          'documentTypes': audit['documentTypes'],
          'currencyReferences': audit['currencyReferences'],
          'sourceSha256': audit['sourceSha256'],
          'postingEligible': 0,
          'readOnly': true,
          'alreadyArchived': false,
        },
      };
      _preview = preview;
      return {
        'cancelled': false,
        'fileName': selected.name,
        'sizeBytes': bytes.length,
        'preview': preview,
        'previewToken': token,
      };
    }
    final source = await readWebsiteBackup(bytes, maxBytes);
    if (utf8.encode(source).length > maxBytes) {
      throw const FormatException('النسخة بعد التحويل تجاوزت الحد المدعوم.');
    }
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('تنسيق النسخة الاحتياطية غير مدعوم.');
    }
    // Includes strict format/version, unique IDs, currency and reference checks.
    final backup = WebBackup.parse(source);
    final unsupported = _unsupportedRows(data);
    Map<String, Object?>? trial;
    String? trialError;
    try {
      trial = await testWebsiteRestore(backup); // isolated SQLite, no live writes
    } catch (error) {
      trialError = error is FormatException
          ? error.message.toString()
          : 'لم تجتز النسخة اختبار الاستعادة المعزول.';
    }
    final canRestore = trial != null && unsupported.isEmpty;
    final counts = <String, int>{
      'accounts': backup.accounts.length,
      'groups': backup.groupData.groups.length,
      'currencies': _countList(data, 'currencies'),
      'invoices': backup.ledger.where((e) => e.kind == LedgerKind.invoice).length,
      'vouchers': backup.ledger.where((e) => e.kind == LedgerKind.voucher).length,
      'movements': backup.ledger.length,
      'invoiceLines': backup.lines.length,
      'warehouses': backup.warehouses.length,
      'items': backup.inventory.length,
    };
    final token = _newToken();
    final preview = <String, Object?>{
      'fileName': selected.name,
      'format': isSqlite ? 'SQLite' : 'JSON',
      'version': data['version'],
      'sizeBytes': bytes.length,
      'sourceSha256': fileSha,
      'counts': counts,
      'unsupported': unsupported,
      'trialIntegrity': trial?['integrity'] ?? 'failed',
      'trialMatchedRecords': trial?['matchedRecords'] ?? 0,
      'trialError': trialError,
      'canRestore': canRestore,
      'previewToken': token,
    };
    _staged = backup;
    _preview = preview;
    _token = token;
    _sourceSha = fileSha;
    _expiresAt = DateTime.now().add(previewLifetime);
    return {
      'cancelled': false,
      'fileName': selected.name,
      'sizeBytes': bytes.length,
      'preview': preview,
      'previewToken': token,
    };
  }

  /// Archive confirmation never invokes restoreWebBackup or financial writes.
  /// Saving identical source bytes twice is idempotent across app restarts.
  Future<Map<String, Object?>> saveHistoricalArchive(
      Map<String, Object?> payload) async {
    final sha = payload['sourceSha256'];
    if (sha is! String ||
        payload['previewToken'] != _historicalToken ||
        sha != _historicalSha ||
        DateTime.now().isAfter(
            _expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0)) ||
        _historicalBytes == null) {
      throw const FormatException(
          'انتهت صلاحية معاينة النسخة التاريخية؛ اختر الملف مجددًا.');
    }
    final result = await _historical.saveArchive(_historicalBytes!, sha);
    _historicalBytes = null;
    _historicalToken = null;
    _historicalSha = null;
    return result;
  }

  Future<List<Map<String, Object?>>> listHistoricalArchives() =>
      _historical.listArchives();

  Future<Map<String, Object?>> describeHistoricalArchive(
      Map<String, Object?> payload) async {
    final sha = payload['sourceSha256'];
    if (sha is! String) {
      throw const FormatException('بصمة الملف التاريخي مطلوبة.');
    }
    return _historical.describe(sha);
  }

  Future<Map<String, Object?>> pageHistoricalArchive(
      Map<String, Object?> payload) async {
    final sha = payload['sourceSha256'];
    final table = payload['table'];
    if (sha is! String || table is! String) {
      throw const FormatException('بصمة الأرشيف واسم الجدول مطلوبان.');
    }
    final offset = payload['offset'] is int ? payload['offset'] as int : 0;
    final limit = payload['limit'] is int ? payload['limit'] as int : 20;
    return _historical.page(sha, table, offset, limit);
  }

  Future<Map<String, Object?>> createLocalBackup(
      Map<String, Object?> payload) async {
    // Drive upload is still owned by React's existing authenticated workflow.
    // Creating its local safety copy here must not falsely claim cloud upload.
    if (payload['target'] != 'local' && payload['target'] != 'cloud') {
      throw const FormatException('وجهة النسخة غير مدعومة.');
    }
    final backup = await controller.createLocalBackup();
    await controller.testLocalBackupRestore(backup.id);
    return {
      'id': backup.id,
      'format': 'nasqo-local-qa-json-v1',
      'verified': true,
      'storedOnDevice': true,
      'cloudUploaded': false,
      'cloudUploadManagedByReact': payload['target'] == 'cloud',
    };
  }

  Future<Map<String, Object?>> restoreConfirmed(
      Map<String, Object?> payload, String? idempotencyKey) async {
    final token = payload['previewToken'];
    if (token is! String ||
        payload['confirmation'] != 'REPLACE_AFTER_VERIFIED_PREVIEW' ||
        idempotencyKey == null) {
      throw const FormatException('يلزم تأكيد الاستعادة صراحة بعد معاينة النسخة.');
    }
    if (token == _completedToken && idempotencyKey == _completedKey) {
      return _completedReceipt!;
    }
    final backup = _staged;
    final preview = _preview;
    if (backup == null ||
        token != _token ||
        preview == null ||
        preview['canRestore'] != true ||
        DateTime.now().isAfter(_expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0)) ||
        payload['sourceSha256'] != _sourceSha) {
      throw const FormatException(
          'انتهت صلاحية المعاينة أو لم تجتز فحوص السلامة؛ اختر الملف مجددًا.');
    }

    // Keep a durable, isolated-restorable private copy *before* writing to
    // the existing nasqo_pro_erp.db. No parallel database is made active.
    final rollback = await controller.createLocalBackup();
    await controller.testLocalBackupRestore(rollback.id);
    try {
      await controller.restoreWebBackup(backup);
      final db = await controller.database.database;
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 ||
          integrity.single.values.single != 'ok' ||
          (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw StateError('فشل فحص سلامة SQLite بعد الحفظ.');
      }
      final actual = await controller.database.loadSnapshot();
      if (actual.accounts.length != backup.accounts.length ||
          actual.ledger.length != backup.ledger.length ||
          actual.warehouses.length != backup.warehouses.length ||
          actual.inventory.length != backup.inventory.length ||
          actual.saleLines.length != backup.lines.length) {
        throw StateError('عدد السجلات بعد الحفظ لا يطابق النسخة المختبرة.');
      }
      final archived = await controller.database.readOriginalWebExport();
      if (archived == null ||
          jsonEncode(archived) != jsonEncode(jsonDecode(backup.original))) {
        throw StateError('النسخة المحفوظة لا تطابق أصل الملف المستورد.');
      }
      final receipt = <String, Object?>{
        'restored': preview['counts']!,
        'rollbackBackupId': rollback.id,
        'verified': true,
        'sourceSha256': _sourceSha!,
      };
      _completedToken = token;
      _completedKey = idempotencyKey;
      _completedReceipt = receipt;
      _staged = null;
      _preview = null;
      _token = null;
      return receipt;
    } catch (_) {
      try {
        await controller.restoreLocalBackup(rollback.id);
      } catch (_) {
        throw StateError('فشل الاستيراد وتعذّر التراجع تلقائيًا؛ احتفظ بنسخة الاسترداد الخاصة واتصل بالدعم.');
      }
      rethrow;
    }
  }
}
