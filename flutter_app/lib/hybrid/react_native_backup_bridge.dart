import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../models/erp_models.dart';
import '../services/local_backup_files.dart';
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
    const unsupported = <String>{
      'priceOffers',
      'stockTransfers',
      'stockTransferLines',
      'cashboxes',
      'attachments',
      'bankTransactions',
      'files',
      'auditEvents',
    };
    return [
      for (final key in unsupported)
        if (_countList(document, key) > 0)
          {'section': key, 'count': _countList(document, key)},
    ]..sort((a, b) =>
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
