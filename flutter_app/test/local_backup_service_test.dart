import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/nonposting_document.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/services/local_backup_service.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

String canonical(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sort(v[key])};
    }
    if (v is List) return v.map(sort).toList();
    return v;
  }

  return jsonEncode(sort(value));
}

Future<String> sha(String value) async {
  final process = await Process.start('sha256sum', []);
  process.stdin.write(value);
  await process.stdin.close();
  final out = await utf8.decoder.bind(process.stdout).join();
  expect(await process.exitCode, 0);
  return out.split(' ').first;
}

Future<String> signed(Map<String, dynamic> root) async {
  root['checksum'] = await sha(canonical(root['payload']));
  return canonical(root);
}

void main() {
  late Directory dir;
  late LocalDatabase store;
  late LocalBackupService service;
  late Database db;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup-qa-synthetic-');
    final factory = createDatabaseFactoryFfi(ffiInit: _ffi);
    store = LocalDatabase.withFactory(factory, '${dir.path}/live.db');
    service = LocalBackupService(store, factory: factory);
    await store.saveSnapshot(
        accounts: [
          const AccountRecord(
              id: 'a',
              name: 'عميل صناعي',
              category: AccountCategory.clients,
              openingBalance: 3.14159)
        ],
        ledger: [],
        warehouses: [],
        inventory: [],
        saleLines: [],
        companyName: 'synthetic',
        isDarkMode: false,
        nextEntryNumber: 8123);
    await store.saveNonpostingDocument(NonpostingDocument(
        type: NonpostingDocumentType.quote,
        date: '2026-01-01',
        currency: CurrencyCode.sar,
        customerName: 'صناعي',
        lines: [
          const NonpostingLine(
              description: "نص ' ; DROP TABLE accounts; --",
              quantity: 1,
              unitPrice: 2.345)
        ]));
    db = await store.database;
    await db.update('sqlite_sequence', {'seq': 44},
        where: 'name = ?', whereArgs: ['nonposting_documents']);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test(
      'canonical roundtrip includes exact sequences/settings, disposable scratch, live unchanged',
      () async {
    final before = await service.createBackup();
    final decoded = jsonDecode(before) as Map<String, dynamic>;
    expect(decoded['checksum'], await sha(canonical(decoded['payload'])));
    final inspected = await service.inspectBackup(before);
    expect(inspected.scratchPath, '');
    expect(inspected.tableCounts['accounts'], 1);
    expect(inspected.tableCounts['nonposting_lines'], 1);
    final result = await service.verifyRestore(before);
    expect(result.checksum, decoded['checksum']);
    expect(result.scratchPath, contains('nasqo_qa_backups'));
    expect(await File(result.scratchPath).exists(), false);
    expect(await service.createBackup(), before);
    expect(await db.getVersion(), 9);
    final second = await service.verifyRestore(before);
    expect(second.scratchPath, isNot(result.scratchPath));
    expect(await service.createBackup(), before);
  });
  test(
      'malformed, tampered, incompatible and unexpected table rejected without live changes',
      () async {
    final before = await service.createBackup();
    for (final invalid in [
      '{}',
      '[]',
      'not json',
      before.replaceFirst('عميل صناعي', 'تغيير')
    ]) {
      await expectLater(service.verifyRestore(invalid), throwsA(anything));
    }
    final version = jsonDecode(before) as Map<String, dynamic>;
    version['payload']['schemaVersion'] = 8;
    await expectLater(
        service.verifyRestore(await signed(version)), throwsFormatException);
    final extra = jsonDecode(before) as Map<String, dynamic>;
    extra['payload']['data']['accounts; DROP TABLE ledger_entries'] = [];
    await expectLater(
        service.verifyRestore(await signed(extra)), throwsFormatException);
    final mismatch = jsonDecode(before) as Map<String, dynamic>;
    mismatch['payload']['schema']['accounts']['sql'] =
        'CREATE TABLE accounts (bogus TEXT)';
    mismatch['payload']['schemaFingerprint'] =
        await sha(canonical(mismatch['payload']['schema']));
    await expectLater(
        service.verifyRestore(await signed(mismatch)), throwsFormatException);
    expect(await service.createBackup(), before);
  });
  test(
      'bound values preserve SQL-looking text; relational failure rolls isolated restore back',
      () async {
    final before = await service.createBackup();
    final broken = jsonDecode(before) as Map<String, dynamic>;
    broken['payload']['data']['nonposting_lines'][0]['documentId'] = 999;
    await expectLater(
        service.verifyRestore(await signed(broken)), throwsA(anything));
    expect(await service.createBackup(), before);
    final qa = Directory('${dir.path}/nasqo_qa_backups');
    if (await qa.exists()) expect(await qa.list().toList(), isEmpty);
  });
  test('size limit and private QA symlink guard fail closed', () async {
    final before = await service.createBackup();
    await expectLater(
        service.inspectBackup('x' * (LocalBackupService.maxBytes + 1)),
        throwsFormatException);
    final elsewhere =
        await Directory.systemTemp.createTemp('backup-unrelated-');
    try {
      await Link('${dir.path}/nasqo_qa_backups').create(elsewhere.path);
      await expectLater(service.verifyRestore(before), throwsStateError);
      expect(await elsewhere.list().toList(), isEmpty);
      expect(await service.createBackup(), before);
    } finally {
      await Link('${dir.path}/nasqo_qa_backups').delete();
      await elsewhere.delete();
    }
  });
  test('oversized source is refused before row loading', () async {
    await db.rawInsert(
        'INSERT INTO erp_state(stateKey,payloadJson,updatedAt) VALUES (?, CAST(zeroblob(?) AS TEXT), ?)',
        ['large-synthetic', LocalBackupService.maxBytes + 1, 'synthetic']);
    await expectLater(service.createBackup(), throwsStateError);
  });

  test('unknown custom schema is deliberately unsupported', () async {
    await db.execute('CREATE TABLE extra_custom (id INTEGER)');
    await expectLater(service.createBackup(), throwsStateError);
  });
}
