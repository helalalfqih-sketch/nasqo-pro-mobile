import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/hybrid/react_native_backup_bridge.dart';
import 'package:nasqo_pro_erp/hybrid/react_workspace.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/services/smartpro_historical_archive.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late LocalDatabase store;
  late ErpController controller;
  final fixture = File('test/fixtures/smartpro_v28_synthetic.back');

  setUp(() async {
    expect(await fixture.exists(), true,
        reason: 'Run python3 qa/smartpro_v28/generate_synthetic.py '
            'flutter_app/test/fixtures/smartpro_v28_synthetic.back first');
    dir = await Directory.systemTemp.createTemp('nasqo-smartpro-qa-');
    store = LocalDatabase.withFactory(
        databaseFactoryFfi, '${dir.path}/nasqo_pro_erp.db');
    controller = ErpController(
        autoInitDb: false, localDatabase: store, emptyOnFirstInstall: true);
    await controller.initDatabase();
    expect(controller.dbReady, isTrue);
  });

  tearDown(() async {
    controller.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  test('SmartPro v28 archive retains 22 source tables, all 26001 rows, '
      'all columns and exact bytes without posting financial data', () async {
    final bytes = await fixture.readAsBytes();
    final originalSha = sha256.convert(bytes).toString();
    final archive = SmartProHistoricalArchive(store);
    final before = await store.loadSnapshot();
    final inspected = await archive.inspect(bytes);
    expect(inspected['userVersion'], 28);
    expect(inspected['integrity'], 'ok');
    expect(inspected['sourceSha256'], originalSha);
    expect(inspected['totalRows'], 26001);
    expect(inspected['tableCount'], 23); // incl. sqlite_sequence
    final counts = (inspected['counts'] as Map).cast<String, int>();
    expect(counts['customers'], 125);
    expect(counts['products'], 1402);
    expect(counts['input_move'], 8703);
    expect(counts['bill_details'], 13536);
    expect(counts['bill_details2'], 258);
    expect(counts['stores'], 5);
    expect(counts['store_trans'], 25);
    expect(counts['offers'], 4);
    final issues = (inspected['issues'] as Map).cast<String, int>();
    expect(issues['missingMovementCurrencies'], 7);
    expect(issues['missingTransferOrigins'], 4);
    expect(issues['missingTransferDestinations'], 4);
    expect(issues['unknownOpeningBalances'], 125);
    expect(issues['unknownWarehouseQuantities'], 1402);
    expect(inspected['archiveOnly'], true);
    expect(inspected['postingEligible'], 0);

    final saved = await archive.saveArchive(bytes, originalSha);
    expect(saved['saved'], true);
    expect(saved['alreadySaved'], false);
    final privateCopy = File(
        '${dir.path}/nasqo_smartpro_archives/smartpro-$originalSha.back');
    expect(await privateCopy.exists(), true);
    expect(await privateCopy.readAsBytes(), bytes);
    expect(await archive.saveArchive(bytes, originalSha), containsPair('alreadySaved', true));
    expect((await archive.listArchives()).length, 1);

    final freshService = SmartProHistoricalArchive(store);
    final again = await freshService.describe(originalSha);
    expect(again['totalRows'], 26001);
    final tables = (again['tables'] as List).cast<Map<String, Object?>>();
    expect(tables.any((t) => t['name'] == 'bill_details2'), true);
    for (final table in tables) {
      final page = await freshService.page(originalSha, table['name'] as String, 0, 5);
      expect((page['total'] as int), (table['rows'] as int));
      expect((page['columns'] as List).length, (table['columns'] as List).length);
      expect((page['rows'] as List).length, (table['rows'] as int).clamp(0, 5));
    }
    final last = await freshService.page(originalSha, 'bill_details', 13531, 10);
    expect((last['rows'] as List).length, 5);
    await expectLater(
        freshService.page(originalSha, 'customers"; DROP TABLE accounts;--', 0, 10),
        throwsFormatException);
    await expectLater(
        freshService.page(originalSha, 'customers', -1, 10),
        throwsFormatException);

    final after = await store.loadSnapshot();
    expect(after.accounts.length, before.accounts.length);
    expect(after.ledger.length, before.ledger.length);
    expect(after.warehouses.length, before.warehouses.length);
    expect(after.inventory.length, before.inventory.length);
  });

  test('React native v28 file preview stores only metadata and blocks direct '
      'ledger replacement even with explicit financial bridge writes', () async {
    final bytes = Uint8List.fromList(await fixture.readAsBytes());
    final fileSha = sha256.convert(bytes).toString();
    final backup = ReactNativeBackupBridge(
        controller, chooseFile: () async => XFile(fixture.path));
    final app = ReactWorkspace(controller, allowWrites: true, backupBridge: backup);
    var seq = 0;
    Future<Map> request(String action, Map payload, [String? idempotencyKey]) async {
      final reply = await app.handle(jsonEncode({
        'protocolVersion': '1.0.0',
        'kind': 'request',
        'requestId': 'smartpro_test_${++seq}',
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
        'action': action,
        'payload': payload,
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      }));
      return jsonDecode(reply) as Map;
    }
    final response = await request('pickFile', {
      'purpose': 'restore-backup',
      'accept': ['.back'],
    });
    expect(response['ok'], true, reason: response.toString());
    final result = response['data'] as Map;
    expect(result.containsKey('base64Content'), false);
    final preview = result['preview'] as Map;
    expect(preview['canRestore'], false);
    expect(preview['sourceSha256'], fileSha);
    expect((preview['historicalArchive'] as Map)['totalRows'], 26001);
    final forbidden = await request('restoreWorkspace', {
      'workspaceId': 'local-erp-workspace',
      'previewToken': preview['previewToken'],
      'sourceSha256': fileSha,
      'confirmation': 'REPLACE_AFTER_VERIFIED_PREVIEW',
    }, 'sp28-rejected-mutation');
    expect(forbidden['ok'], false);
    expect(controller.accounts, isEmpty);
    expect(controller.ledger, isEmpty);
    final saved = await request('saveLegacyArchive', {
      'previewToken': preview['previewToken'],
      'sourceSha256': fileSha,
    });
    expect(saved['ok'], true, reason: saved.toString());
    final listings = await request('listLegacyArchives', {});
    expect((listings['data'] as List).length, 1);
    final part = await request('queryLegacyArchive', {
      'sourceSha256': fileSha,
      'table': 'input_move',
      'offset': 100,
      'limit': 20,
    });
    expect(part['ok'], true);
    expect(((part['data'] as Map)['rows'] as List).length, 20);
    expect(controller.ledger, isEmpty);

    // Persisted source is available from a new bridge after a cold reopen.
    await store.close();
    final reloaded = SmartProHistoricalArchive(store);
    final archive = await reloaded.describe(fileSha);
    expect(archive['sourceSha256'], fileSha);
    expect((await store.loadSnapshot()).ledger, isEmpty);
  });

  test('malformed header and unsupported schema version fail closed', () async {
    final good = Uint8List.fromList(await fixture.readAsBytes());
    final invalidHeader = Uint8List.fromList(good)..[0] = 0;
    final archive = SmartProHistoricalArchive(store);
    await expectLater(archive.inspect(invalidHeader), throwsFormatException);
    final wrongVersion = Uint8List.fromList(good)
      ..[60] = 0
      ..[61] = 0
      ..[62] = 0
      ..[63] = 29;
    await expectLater(archive.inspect(wrongVersion), throwsFormatException);
    expect(controller.ledger, isEmpty);
  });
}
