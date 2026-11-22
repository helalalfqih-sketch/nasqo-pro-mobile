import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/web_backup.dart';
import '../services/website_backup_file.dart';
import '../services/website_restore_trial.dart';
import '../state/erp_controller.dart';

/// One-shot, private, on-device import session. No backup bytes cross WebView.
/// All accounting records remain in the existing nasqo_pro_erp.db.
class QaWebsiteImport {
  QaWebsiteImport(this.controller,
      {Future<Directory> Function()? privateCache,
       Future<Map<String, Object?>?> Function()? selectFile})
      : _privateCache = privateCache ?? getTemporaryDirectory,
        _selectFile = selectFile ??
            (() => _channel.invokeMapMethod<String, Object?>('selectWebsiteBackup'));
  final ErpController controller;
  final Future<Directory> Function() _privateCache;
  final Future<Map<String, Object?>?> Function() _selectFile;
  static const _channel = MethodChannel('com.indexesstore.nasqo_qa/website_import');
  static const maxBytes = 32 * 1024 * 1024;
  String? _token;
  WebBackup? _validated;
  String? _digest;
  DateTime? _created;
  bool _busy = false;

  Future<Map<String, Object?>> pickAndPreview() async {
    if (_busy) throw StateError('عملية استيراد أخرى قيد التنفيذ.');
    _busy = true;
    try {
      await discard();
      final selected = await _selectFile();
      if (selected == null) return {'cancelled': true};
      final token = selected['token'];
      if (token is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
        throw const FormatException('معرف ملف Android غير صالح.');
      }
      _token = token;
      final bytes = await _readPrivate(token);
      final decoded = await readWebsiteBackup(bytes, maxBytes);
      final parsed = WebBackup.parse(decoded);
      // Never touch live SQLite during preview. Verify the actual round-trip,
      // financial balances, currencies and stock in a disposable database.
      final trial = await testWebsiteRestore(parsed);
      final original = jsonDecode(parsed.original) as Map<String, dynamic>;
      final supported = <String>{
        'format','version','name','exportedAt','workspace','erpData',
        'accountGroups','cashboxes','accounts','ledger','warehouses',
        'inventory','currencies','stockTransfers','stockTransferLines',
        'legacySourceTotals',
      };
      final unsupported = original.keys.where((k) => !supported.contains(k))
          .toList(growable: false);
      _validated = parsed;
      _digest = sha256.convert(bytes).toString();
      _created = DateTime.now();
      return {
        'cancelled': false,
        'session': token,
        'fileSha256': _digest,
        'sizeBytes': bytes.length,
        'format': original['format']?.toString() ?? '',
        'version': original['version'] ?? 0,
        'counts': <String, Object?>{
          'accounts': parsed.accounts.length,
          'groups': parsed.groupData.groups.length,
          'currencies': original['currencies'] is List
              ? (original['currencies'] as List).length : 0,
          'invoices': parsed.ledger.where((e) => e.kind.name == 'invoice').length,
          'vouchers': parsed.ledger.where((e) => e.kind.name == 'voucher').length,
          'ledger': parsed.ledger.length,
          'warehouses': parsed.warehouses.length,
          'items': parsed.inventory.length,
          'invoiceLines': parsed.lines.length,
        },
        'unsupportedFields': unsupported,
        'trial': trial,
        'requiresConfirmation': true,
      };
    } catch (_) {
      await discard();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, Object?>> confirm(String session) async {
    if (_busy) throw StateError('عملية استيراد أخرى قيد التنفيذ.');
    if (_validated == null || _token != session || _digest == null ||
        _created == null ||
        DateTime.now().difference(_created!) > const Duration(minutes: 10)) {
      throw StateError('المعاينة غير صالحة أو انتهت صلاحيتها. اختر الملف مجددًا.');
    }
    _busy = true;
    try {
      final bytes = await _readPrivate(session);
      if (sha256.convert(bytes).toString() != _digest) {
        throw StateError('تغير الملف بعد المعاينة. تم إلغاء الاستيراد.');
      }
      final backup = _validated!;
      // Re-validate immediately before the live commit.
      await testWebsiteRestore(backup);
      await controller.restoreWebBackup(backup);
      final database = await controller.database.database;
      final integrity = await database.rawQuery('PRAGMA integrity_check');
      if (integrity.single.values.single != 'ok' ||
          (await database.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw StateError('فشل فحص سلامة SQLite بعد الاستعادة.');
      }
      return {
        'committed': true,
        'counts': {
          'accounts': controller.accounts.length,
          'ledger': controller.ledger.length,
          'warehouses': controller.warehouses.length,
          'inventory': controller.inventory.length,
        },
      };
    } finally {
      await discard();
      _busy = false;
    }
  }

  Future<Uint8List> _readPrivate(String token) async {
    final dir = await _privateCache();
    final root = p.join(dir.path, 'nasqo-website-import');
    final file = File(p.join(root, '$token.bin'));
    if (p.dirname(file.path) != root ||
        await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const FormatException('ملف الاستيراد الخاص غير موجود.');
    }
    final size = await file.length();
    if (size == 0 || size > maxBytes) {
      throw const FormatException('حجم النسخة غير صالح.');
    }
    return file.readAsBytes();
  }

  Future<void> discard() async {
    final token = _token;
    _token = null;
    _validated = null;
    _digest = null;
    _created = null;
    if (token == null) return;
    final dir = await _privateCache();
    final file = File(p.join(dir.path, 'nasqo-website-import', '$token.bin'));
    if (await file.exists()) await file.delete();
  }
}
