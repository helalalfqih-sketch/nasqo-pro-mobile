import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/hybrid/react_backup_commands.dart';
import 'package:nasqo_pro_erp/hybrid/react_workspace.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final source = <String, Object?>{
    'format': 'nasqo-pro-erp-backup',
    'version': 2,
    'workspace': {'companyName': 'شركة اختبار الويب'},
    'accountGroups': [{'id': 19, 'name': 'العملاء', 'legacyId': 19}],
    'currencies': [{'code': 'USD', 'symbol': r'}],
    'accounts': [{
      'id': 'a1', 'groupId': 19, 'name': 'عميل اختبار',
      'category': 'clients', 'currency': 'USD',
      'openingBalance': 20, 'openingDirection': 'debit',
      'creditLimit': 100, 'isCashAccount': false, 'codeNumber': 7
    }],
    'warehouses': [{'id': 'w1', 'name': 'مخزن الويب', 'isDefault': true}],
    'inventory': [{
      'id': 'i1', 'warehouseId': 'w1', 'name': 'صنف تجريبي',
      'unit': 'حبة', 'quantity': 7, 'avgCost': 2
    }],
    'ledger': [
      {
        'id': 'inv1', 'accountId': 'a1', 'accountName': 'عميل اختبار',
        'kind': 'invoice', 'typeLabel': 'فاتورة بيع',
        'payment': 'credit', 'direction': 'debit', 'amount': 30,
        'currency': 'USD', 'exchangeRate': 3.75, 'entryNumber': 11,
        'deleted': false, 'entryDate': '2026-11-22',
        'warehouseId': 'w1', 'warehouseName': 'مخزن الويب',
        'lines': [{
          'inventoryItemId': 'i1', 'itemName': 'صنف تجريبي',
          'unit': 'حبة', 'quantity': 2, 'price': 15
        }]
      },
      {
        'id': 'v1', 'accountId': 'a1', 'accountName': 'عميل اختبار',
        'kind': 'voucher', 'typeLabel': 'سند قبض',
        'payment': 'cash', 'direction': 'credit', 'amount': 5,
        'currency': 'USD', 'exchangeRate': 3.75, 'entryNumber': 12,
        'deleted': false, 'entryDate': '2026-11-22'
      }
    ]
  };

  test('native import previews web records then commits once and survives cold reopen',
      () async {
    final folder = await Directory.systemTemp.createTemp('nasqo-import-qa-');
    final dbPath = folder.path + '/nasqo_pro_erp.db';
    final database = LocalDatabase.withFactory(databaseFactoryFfi, dbPath);
    var controller = ErpController(
        autoInitDb: false, localDatabase: database, emptyOnFirstInstall: true);
    await controller.initDatabase();
    final service = ReactBackupCommands(controller,
        confirmRestore: (_) async => true);
    addTearDown(() async {
      service.dispose();
      controller.dispose();
      await database.close();
      await folder.delete(recursive: true);
    });
    final preview = await service.prepareBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(source))), 'web.json');
    expect(preview['restorable'], true, reason: preview.toString());
    final counts = preview['counts'] as Map;
    expect(counts['accounts'], 1);
    expect(counts['groups'], 1);
    expect(counts['invoices'], 1);
    expect(counts['vouchers'], 1);
    expect(counts['items'], 1);
    expect(counts['warehouses'], 1);
    expect(controller.accounts, isEmpty);
    final token = preview['previewToken'] as String;
    expect((await service.restoreWorkspace(token, 'website-restore-qa-10022'))
        ['restored'], true);
    expect((await service.restoreWorkspace(token, 'website-restore-qa-10022'))
        ['replayed'], true);
    var restored = await database.loadSnapshot();
    expect(restored.accounts.single.id, 'a1');
    expect(restored.inventory.single.quantity, 7);
    expect(restored.ledger.length, 2);
    expect(restored.saleLines.single.quantity, 2);
    expect((await controller.loadLocalBackups()).isNotEmpty, true);
    await database.close();
    controller.dispose();
    controller = ErpController(autoInitDb: false, localDatabase: database);
    await controller.initDatabase();
    expect(controller.dbReady, true);
    restored = await database.loadSnapshot();
    expect(restored.ledger.length, 2);
    expect(restored.inventory.single.quantity, 7);
    final react = ReactWorkspace(controller, allowWrites: true);
    final snapshot = await react.snapshot();
    expect((snapshot['accounts'] as List).length, 1);
    expect((snapshot['ledger'] as List).length, 2);
    expect((snapshot['inventory'] as List).length, 1);
  });

  test('unsupported records and version errors cannot modify phone SQLite',
      () async {
    final folder = await Directory.systemTemp.createTemp('nasqo-bad-qa-');
    final database = LocalDatabase.withFactory(
        databaseFactoryFfi, folder.path + '/nasqo_pro_erp.db');
    final controller = ErpController(
        autoInitDb: false, localDatabase: database, emptyOnFirstInstall: true);
    await controller.initDatabase();
    final service = ReactBackupCommands(controller,
        confirmRestore: (_) async => true);
    addTearDown(() async {
      service.dispose();
      controller.dispose();
      await database.close();
      await folder.delete(recursive: true);
    });
    Future<Map<String, Object?>> inspect(Map<String, Object?> json) =>
        service.prepareBytes(
            Uint8List.fromList(utf8.encode(jsonEncode(json))), 'bad.json');
    final unsupported = await inspect({
      ...source, 'priceOffers': [{'id': 'unsupported'}]
    });
    expect(unsupported['restorable'], false);
    expect((unsupported['unsupportedRecords'] as Map)['priceOffers'], 1);
    await expectLater(
        service.restoreWorkspace(
            unsupported['previewToken'] as String, 'invalid-restoration'),
        throwsFormatException);
    final version = await inspect({...source, 'version': 999});
    expect(version['restorable'], false);
    expect(controller.ledger, isEmpty);
    expect(controller.accounts, isEmpty);
  });
}
}],
    'accounts': [{
      'id': 'a1', 'groupId': 19, 'name': 'عميل اختبار',
      'category': 'clients', 'currency': 'USD',
      'openingBalance': 20, 'openingDirection': 'debit',
      'creditLimit': 100, 'isCashAccount': false, 'codeNumber': 7
    }],
    'warehouses': [{'id': 'w1', 'name': 'مخزن الويب', 'isDefault': true}],
    'inventory': [{
      'id': 'i1', 'warehouseId': 'w1', 'name': 'صنف تجريبي',
      'unit': 'حبة', 'quantity': 7, 'avgCost': 2
    }],
    'ledger': [
      {
        'id': 'inv1', 'accountId': 'a1', 'accountName': 'عميل اختبار',
        'kind': 'invoice', 'typeLabel': 'فاتورة بيع',
        'payment': 'credit', 'direction': 'debit', 'amount': 30,
        'currency': 'USD', 'exchangeRate': 3.75, 'entryNumber': 11,
        'deleted': false, 'entryDate': '2026-11-22',
        'warehouseId': 'w1', 'warehouseName': 'مخزن الويب',
        'lines': [{
          'inventoryItemId': 'i1', 'itemName': 'صنف تجريبي',
          'unit': 'حبة', 'quantity': 2, 'price': 15
        }]
      },
      {
        'id': 'v1', 'accountId': 'a1', 'accountName': 'عميل اختبار',
        'kind': 'voucher', 'typeLabel': 'سند قبض',
        'payment': 'cash', 'direction': 'credit', 'amount': 5,
        'currency': 'USD', 'exchangeRate': 3.75, 'entryNumber': 12,
        'deleted': false, 'entryDate': '2026-11-22'
      }
    ]
  };

  test('native import previews web records then commits once and survives cold reopen',
      () async {
    final folder = await Directory.systemTemp.createTemp('nasqo-import-qa-');
    final dbPath = folder.path + '/nasqo_pro_erp.db';
    final database = LocalDatabase.withFactory(databaseFactoryFfi, dbPath);
    var controller = ErpController(
        autoInitDb: false, localDatabase: database, emptyOnFirstInstall: true);
    await controller.initDatabase();
    final service = ReactBackupCommands(controller,
        confirmRestore: (_) async => true);
    addTearDown(() async {
      service.dispose();
      controller.dispose();
      await database.close();
      await folder.delete(recursive: true);
    });
    final preview = await service.prepareBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(source))), 'web.json');
    expect(preview['restorable'], true, reason: preview.toString());
    final counts = preview['counts'] as Map;
    expect(counts['accounts'], 1);
    expect(counts['groups'], 1);
    expect(counts['invoices'], 1);
    expect(counts['vouchers'], 1);
    expect(counts['items'], 1);
    expect(counts['warehouses'], 1);
    expect(controller.accounts, isEmpty);
    final token = preview['previewToken'] as String;
    expect((await service.restoreWorkspace(token, 'website-restore-qa-10022'))
        ['restored'], true);
    expect((await service.restoreWorkspace(token, 'website-restore-qa-10022'))
        ['replayed'], true);
    var restored = await database.loadSnapshot();
    expect(restored.accounts.single.id, 'a1');
    expect(restored.inventory.single.quantity, 7);
    expect(restored.ledger.length, 2);
    expect(restored.saleLines.single.quantity, 2);
    expect((await controller.loadLocalBackups()).isNotEmpty, true);
    await database.close();
    controller.dispose();
    controller = ErpController(autoInitDb: false, localDatabase: database);
    await controller.initDatabase();
    expect(controller.dbReady, true);
    restored = await database.loadSnapshot();
    expect(restored.ledger.length, 2);
    expect(restored.inventory.single.quantity, 7);
    final react = ReactWorkspace(controller, allowWrites: true);
    final snapshot = await react.snapshot();
    expect((snapshot['accounts'] as List).length, 1);
    expect((snapshot['ledger'] as List).length, 2);
    expect((snapshot['inventory'] as List).length, 1);
  });

  test('unsupported records and version errors cannot modify phone SQLite',
      () async {
    final folder = await Directory.systemTemp.createTemp('nasqo-bad-qa-');
    final database = LocalDatabase.withFactory(
        databaseFactoryFfi, folder.path + '/nasqo_pro_erp.db');
    final controller = ErpController(
        autoInitDb: false, localDatabase: database, emptyOnFirstInstall: true);
    await controller.initDatabase();
    final service = ReactBackupCommands(controller,
        confirmRestore: (_) async => true);
    addTearDown(() async {
      service.dispose();
      controller.dispose();
      await database.close();
      await folder.delete(recursive: true);
    });
    Future<Map<String, Object?>> inspect(Map<String, Object?> json) =>
        service.prepareBytes(
            Uint8List.fromList(utf8.encode(jsonEncode(json))), 'bad.json');
    final unsupported = await inspect({
      ...source, 'priceOffers': [{'id': 'unsupported'}]
    });
    expect(unsupported['restorable'], false);
    expect((unsupported['unsupportedRecords'] as Map)['priceOffers'], 1);
    await expectLater(
        service.restoreWorkspace(
            unsupported['previewToken'] as String, 'invalid-restoration'),
        throwsFormatException);
    final version = await inspect({...source, 'version': 999});
    expect(version['restorable'], false);
    expect(controller.ledger, isEmpty);
    expect(controller.accounts, isEmpty);
  });
}
