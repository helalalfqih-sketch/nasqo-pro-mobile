import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/hybrid/react_native_backup_bridge.dart';
import 'package:nasqo_pro_erp/hybrid/react_workspace.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> sampleWebBackup() => {
  'format': 'nasqo-pro-erp-backup',
  'version': 2,
  'workspace': {'companyName': 'شركة اختبار الاستيراد'},
  'currencies': [{'code': 'USD', 'name': 'دولار'}],
  'accountGroups': [{'id': 17, 'legacyId': 7, 'name': 'مجموعة تجريبية'}],
  'accounts': [
    {
      'id': 'customer', 'groupId': 17, 'name': 'عميل ويب',
      'category': 'clients', 'currency': 'USD',
      'creditLimit': 500, 'isCashAccount': false, 'openingBalance': 20,
      'openingDirection': 'debit', 'codeNumber': 1,
    }
  ],
  'ledger': [
    {
      'id': 'invoice', 'accountId': 'customer', 'accountName': 'عميل ويب',
      'kind': 'invoice', 'typeLabel': 'فاتورة بيع', 'payment': 'credit',
      'direction': 'debit', 'amount': 30, 'currency': 'USD',
      'exchangeRate': 3.75, 'entryNumber': 11, 'deleted': false,
      'entryDate': '2026-11-22', 'warehouseId': 'w1',
      'warehouseName': 'المخزن',
      'lines': [
        {
          'inventoryItemId': 'i1', 'itemName': 'صنف ويب',
          'unit': 'حبة', 'quantity': 2, 'price': 15,
        }
      ],
    },
    {
      'id': 'voucher', 'accountId': 'customer', 'accountName': 'عميل ويب',
      'kind': 'voucher', 'typeLabel': 'سند قبض', 'payment': 'cash',
      'direction': 'credit', 'amount': 5, 'currency': 'USD',
      'exchangeRate': 1, 'entryNumber': 12, 'deleted': false,
      'entryDate': '2026-11-22', 'warehouseId': 'w1',
      'warehouseName': 'المخزن',
    },
  ],
  'warehouses': [
    {'id': 'w1', 'name': 'المخزن', 'details': '', 'isDefault': true},
  ],
  'inventory': [
    {
      'id': 'i1', 'name': 'صنف ويب', 'unit': 'حبة',
      'warehouseId': 'w1', 'quantity': 7, 'avgCost': 15,
    },
  ],
};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late LocalDatabase local;
  late ErpController controller;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nasqo-react-native-import-');
    local = LocalDatabase.withFactory(
        databaseFactoryFfi, '${dir.path}/nasqo_pro_erp.db');
    controller = ErpController(
        autoInitDb: false, localDatabase: local, emptyOnFirstInstall: true);
    await controller.initDatabase();
    expect(controller.dbReady, isTrue);
  });
  tearDown(() async {
    controller.dispose();
    await local.close();
    await dir.delete(recursive: true);
  });

  test('JSON preview is read only; explicit consent, rollback, financial data and reopen',
      () async {
    final file = File('${dir.path}/web.json')
        ..writeAsStringSync(jsonEncode(sampleWebBackup()));
    final gateway = ReactNativeBackupBridge(
        controller, chooseFile: () async => XFile(file.path));
    final app = ReactWorkspace(controller, allowWrites: true, backupBridge: gateway);
    var n = 0;
    Future<Map> command(String action, Map payload, [String? key]) async {
      final raw = await app.handle(jsonEncode({
        'protocolVersion': '1.0.0', 'kind': 'request',
        'action': action, 'requestId': 'native_web_${++n}',
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
        'payload': payload,
        if (key != null) 'idempotencyKey': key,
      }));
      return jsonDecode(raw) as Map;
    }

    final staged = await command('pickFile', {
      'purpose': 'restore-backup', 'accept': ['.json']
    });
    expect(staged['ok'], isTrue, reason: staged.toString());
    final result = staged['data'] as Map;
    expect(result.containsKey('base64Content'), false);
    final preview = result['preview'] as Map;
    expect(preview['canRestore'], true, reason: preview.toString());
    final counts = preview['counts'] as Map;
    expect(counts['accounts'], 1);
    expect(counts['groups'], 1);
    expect(counts['invoices'], 1);
    expect(counts['vouchers'], 1);
    expect(counts['warehouses'], 1);
    expect(counts['items'], 1);
    expect(controller.accounts, isEmpty);
    expect(controller.ledger, isEmpty);

    final forbidden = await command('restoreWorkspace', {
      'workspaceId': 'local-erp-workspace',
      'previewToken': preview['previewToken'],
      'sourceSha256': preview['sourceSha256'],
    }, 'native-import-consent-1');
    expect(forbidden['ok'], false);
    expect(controller.accounts, isEmpty);

    final before = await controller.createLocalBackup();
    final applied = await command('restoreWorkspace', {
      'workspaceId': 'local-erp-workspace',
      'previewToken': preview['previewToken'],
      'sourceSha256': preview['sourceSha256'],
      'confirmation': 'REPLACE_AFTER_VERIFIED_PREVIEW',
    }, 'native-import-consent-2');
    expect(applied['ok'], true, reason: applied.toString());
    final saved = applied['data'] as Map;
    expect(saved['verified'], true);
    expect(saved['rollbackBackupId'], isNotNull);
    expect(controller.accounts.single.name, 'عميل ويب');
    expect(controller.ledger.length, 2);
    expect(controller.inventory.single.quantity, 7);
    expect((saved['snapshot'] as Map)['accounts'], hasLength(1));

    final replay = await command('restoreWorkspace', {
      'workspaceId': 'local-erp-workspace',
      'previewToken': preview['previewToken'],
      'sourceSha256': preview['sourceSha256'],
      'confirmation': 'REPLACE_AFTER_VERIFIED_PREVIEW',
    }, 'native-import-consent-2');
    expect(replay['ok'], true);
    expect(controller.ledger.length, 2);

    await local.close();
    final reopened = await local.loadSnapshot();
    expect(reopened.accounts.single.id, 'customer');
    expect(reopened.ledger.length, 2);
    expect(reopened.inventory.single.quantity, 7);
    expect(reopened.saleLines.single.unitPrice, 15);
    final backupFiles = await controller.loadLocalBackups();
    expect(backupFiles.any((f) => f.id == saved['rollbackBackupId']), true);
    expect(backupFiles.any((f) => f.id == before.id), true);
  });

  test('unsupported and failed scratch restore never change live SQLite',
      () async {
    final invalid = {
      ...sampleWebBackup(),
      'priceOffers': [{'id': 'unsupported-web-document'}],
    };
    final file = File('${dir.path}/web-unsupported.json')
        ..writeAsStringSync(jsonEncode(invalid));
    final bridge = ReactNativeBackupBridge(
        controller, chooseFile: () async => XFile(file.path));
    final before = await local.loadSnapshot();
    final selected = await bridge.chooseAndInspect({'purpose': 'restore-backup'});
    final preview = selected['preview'] as Map;
    expect(preview['canRestore'], false);
    expect(preview['unsupported'], isNotEmpty);
    await expectLater(
        bridge.restoreConfirmed({
          'previewToken': preview['previewToken'],
          'sourceSha256': preview['sourceSha256'],
          'confirmation': 'REPLACE_AFTER_VERIFIED_PREVIEW',
        }, 'unsupported-approval'),
        throwsFormatException);
    final after = await local.loadSnapshot();
    expect(after.accounts.length, before.accounts.length);
    expect(after.ledger.length, before.ledger.length);
  });

  test('SQLite Web export is inspected natively without replacing the live DB',
      () async {
    final src = File('${dir.path}/web-export.sqlite');
    final db = await databaseFactoryFfi.openDatabase(src.path);
    await db.execute('CREATE TABLE workspaces(id TEXT,company_name TEXT)');
    await db.execute("INSERT INTO workspaces VALUES('w','شركة اختبار')");
    for (final table in ['accounts', 'account_groups', 'ledger_entries', 'inventory_items']) {
      await db.execute('CREATE TABLE $table(workspace_id TEXT)');
    }
    await db.execute('CREATE TABLE warehouses(id TEXT, workspace_id TEXT, name TEXT, is_default INTEGER)');
    await db.execute("INSERT INTO warehouses VALUES('w1','w','المخزن',1)");
    await db.close();
    final bridge = ReactNativeBackupBridge(
        controller, chooseFile: () async => XFile(src.path));
    final selected = await bridge.chooseAndInspect({'purpose': 'restore-backup'});
    final preview = selected['preview'] as Map;
    expect(preview['format'], 'SQLite');
    expect(preview['version'], 2);
    expect((preview['counts'] as Map)['warehouses'], 1);
    expect(preview['canRestore'], true, reason: preview.toString());
    expect(controller.accounts, isEmpty);
    expect(controller.ledger, isEmpty);
  });
}
