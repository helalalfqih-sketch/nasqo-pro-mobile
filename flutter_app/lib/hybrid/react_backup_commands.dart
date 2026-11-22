import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../services/local_backup_files.dart';
import '../services/legacy_backup_inspection.dart';
import '../services/legacy_website_converter.dart';
import '../services/web_backup.dart';
import '../services/website_backup_file.dart';
import '../services/website_restore_trial.dart';
import '../state/erp_controller.dart';

/// Native-only backup session. No backup bytes are exposed to WebView.
class ReactBackupCommands {
  ReactBackupCommands(this.controller, {this.chooseFile, this.confirmRestore});
  final ErpController controller;
  final Future<XFile?> Function()? chooseFile;
  final Future<bool> Function(Map<String, Object?> preview)? confirmRestore;
  WebBackup? _prepared;
  String? _token;
  Map<String, Object?>? _preview;
  final _completedKeys = <String>{};
  static const maxBytes = LocalBackupFiles.maxBackupBytes;

  Future<Map<String, Object?>> pickFile() async {
    final file = await (chooseFile ?? openFile)();
    if (file == null) return {'cancelled': true};
    if (await file.length() > maxBytes) {
      throw const FormatException('ملف النسخة أكبر من 16 MiB.');
    }
    final collector = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (collector.length + chunk.length > maxBytes) {
        throw const FormatException('ملف النسخة أكبر من 16 MiB.');
      }
      collector.add(chunk);
    }
    return prepareBytes(collector.takeBytes(), file.name);
  }

  /// Also used by deterministic QA tests, without an Android picker.
  Future<Map<String, Object?>> prepareBytes(Uint8List input, String name) async {
    _prepared = null;
    _token = null;
    _preview = null;
    if (input.isEmpty || input.length > maxBytes) {
      throw const FormatException('حجم النسخة غير صالح.');
    }
    final digest = sha256.convert(input).toString();
    final bytes = await unpackWebsiteBackup(input, maxBytes);
    final isSqlite = bytes.length >= 16 &&
        String.fromCharCodes(bytes.take(16)) == 'SQLite format 3\x00';
    final inspection = isSqlite ? await inspectLegacyBackup(bytes) : null;
    final unsupported = <String, int>{
      if (inspection != null)
        for (final entry in inspection.issues.entries)
          if (entry.value > 0) entry.key: entry.value,
      if (inspection != null)
        for (final entry in inspection.counts.entries)
          if (entry.value > 0 &&
              !legacyMappedColumns.containsKey(entry.key) &&
              entry.key != 'android_metadata')
            entry.key: entry.value,
    };
    final result = <String, Object?>{
      'fileName': name,
      'bytes': input.length,
      'sourceSha256': digest,
      'format': isSqlite ? 'SQLite' : 'JSON',
      'sourceVersion': inspection?.version,
      'unsupportedRecords': unsupported,
      'integrity': inspection == null ? 'pending' : (inspection.integrityOk ? 'ok' : 'failed')
    };
    if (inspection != null &&
        (!inspection.integrityOk || inspection.issues.values.any((v) => v > 0))) {
      result['restorable'] = false;
      result['reason'] = inspection.arabicSummary;
    } else {
      try {
        final source = await readWebsiteBackup(bytes, maxBytes);
        final root = jsonDecode(source);
        if (root is! Map<String, dynamic>) {
          throw const FormatException('بنية JSON غير صالحة.');
        }
        result['sourceVersion'] = root['version'];
        result['dataFormat'] = root['format'];
        final candidate = WebBackup.parse(source);
        int countKind(String kind) =>
            candidate.ledger.where((l) => l.kind.name == kind).length;
        final currencies = {
          ...candidate.accounts.map((a) => a.currency.name),
          ...candidate.ledger.map((l) => l.currency.name)
        };
        result['counts'] = {
          'accounts': candidate.accounts.length,
          'groups': candidate.groupData.groups.length,
          'currencies': currencies.length,
          'invoices': countKind('invoice'),
          'vouchers': countKind('voucher'),
          'ledger': candidate.ledger.length,
          'warehouses': candidate.warehouses.length,
          'items': candidate.inventory.length,
          'invoiceLines': candidate.lines.length
        };
        for (final field in const ['priceOffers', 'priceOfferLines']) {
          if (root[field] is List && (root[field] as List).isNotEmpty) {
            unsupported[field] = (root[field] as List).length;
          }
        }
        if (unsupported.isNotEmpty) {
          result['restorable'] = false;
          result['reason'] = 'توجد سجلات لم تطابق؛ الاستعادة موقوفة.';
        } else {
          result['trial'] = await testWebsiteRestore(candidate);
          result['integrity'] = 'ok';
          result['restorable'] = true;
          _prepared = candidate;
        }
      } on FormatException catch (e) {
        result['restorable'] = false;
        result['reason'] = e.message.toString();
      } catch (_) {
        result['restorable'] = false;
        result['reason'] = 'لم ينجح اختبار الاستعادة المعزول.';
      }
    }
    _token = sha256.convert(utf8.encode(
        digest + ':' + DateTime.now().microsecondsSinceEpoch.toString())).toString();
    result['previewToken'] = _token;
    _preview = Map.unmodifiable(result);
    return result;
  }

  Future<Map<String, Object?>> backupWorkspace() async {
    final file = await controller.createLocalBackup();
    final verified = await controller.testLocalBackupRestore(file.id);
    return {
      'backupId': file.id,
      'bytes': file.bytes,
      'checksum': verified.checksum,
      'verifiedInIsolatedSqlite': true
    };
  }

  Future<Map<String, Object?>> restoreWorkspace(
      String previewToken, String idempotencyKey) async {
    if (_completedKeys.contains(idempotencyKey)) {
      return {'restored': true, 'replayed': true};
    }
    if (_prepared == null || _preview?['restorable'] != true ||
        previewToken.isEmpty || previewToken != _token) {
      throw const FormatException('اختَر ملفًا صالحًا وافحصه قبل الاستعادة.');
    }
    final approved = await (confirmRestore?.call(_preview!) ?? Future.value(false));
    if (!approved) return {'cancelled': true, 'restored': false};
    await controller.restoreWebBackup(_prepared!);
    _completedKeys.add(idempotencyKey);
    _prepared = null;
    _token = null;
    _preview = null;
    return {'restored': true, 'replayed': false};
  }

  void dispose() {
    _prepared = null;
    _token = null;
    _preview = null;
  }
}
