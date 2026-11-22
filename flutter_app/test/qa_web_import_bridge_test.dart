import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/hybrid/qa_website_import.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> webFixture() => {
  'format': 'nasqo-pro-erp-backup',
  'version': 2,
  'workspace': {'companyName': 'شركة الويب التجريبية'},
  'accountGroups': [
    {'id': 17, 'legacyId': 7, 'name': 'مجموعة العملاء'}
  ],
  'accounts': [
    {
      'groupId': 17, 'id': 'web-customer', 'name': 'عميل الويب',
      'category': 'clients', 'currency': 'USD', 'creditLimit': 500,
      'isCashAccount': false, 'openingBalance': 20,
      'openingDirection': 'debit', 'codeNumber': 101,
    }
  ],
  'ledger': [
    {
      'id': 'web-invoice', 'accountId': 'web-customer',
      'accountName': 'عميل الويب', 'kind': 'invoice',
      'typeLabel': 'فاتورة بيع', 'payment': 'credit',
      'direction': 'debit', 'amount': 30, 'currency': 'USD',
      'exchangeRate': 3.75, 'entryNumber': 11, 'deleted': false,
      'entryDate': '2026-11-22', 'warehouseId': 'web-wh',
      'warehouseName': 'مخزن الويب',
      'lines': [
        {'inventoryItemId': 'web-item', 'itemName': 'صنف الويب',
         'unit': 'حبة', 'quantity': 2, 'price': 15}
      ]
    }
  ],
  'warehouses': [
    {'id': 'web-wh', 'name': 'مخزن الويب', 'details': '', 'isDefault': true}
  ],
  'inventory': [
    {'id': 'web-item', 'name': 'صنف الويب', 'unit': 'حبة',
     'warehouseId': 'web-wh', 'quantity': 7, 'avgCost': 15}
  ],
};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('offline native preview does not change live SQLite; confirmed import survives cold reopen', () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-web-import-qa-');
    final cache = Directory('${dir.path}/cache')..createSync();
    final staging = Directory('${cache.path}/nasqo-website-import')..createSync();
    const token = '0123456789abcdef0123456789abcdef';
    final backupFile = File('${staging.path}/$token.bin');
    await backupFile.writeAsString(jsonEncode(webFixture()));
    final database = LocalDatabase.withFactory(databaseFactoryFfi, '${dir.path}/nasqo_pro_erp.db');
    final controller = ErpController(autoInitDb: false, localDatabase: database,
      emptyOnFirstInstall: true);
    addTearDown(() async {
      controller.dispose();
      await database.close();
      await dir.delete(recursive: true);
    });
    await controller.initDatabase();
    final before = await database.loadSnapshot();
    final importer = QaWebsiteImport(controller,
      privateCache: () async => cache,
      selectFile: () async => {'token': token, 'sizeBytes': await backupFile.length()});
    final preview = await importer.pickAndPreview();
    expect(preview['requiresConfirmation'], true);
    expect((preview['trial'] as Map)['integrity'], 'ok');
    expect((preview['counts'] as Map)['accounts'], 1);
    expect((preview['counts'] as Map)['invoices'], 1);
    expect((preview['counts'] as Map)['items'], 1);
    expect((await database.loadSnapshot()).accounts.length, before.accounts.length,
      reason: 'Preview must not modify the live database');
    final saved = await importer.confirm(preview['session'] as String);
    expect(saved['committed'], true);
    expect(await backupFile.exists(), false, reason: 'Private staged file must be removed');
    await expectLater(importer.confirm(token), throwsStateError,
      reason: 'Import session cannot be replayed');
    await database.close();
    final reopened = await database.loadSnapshot();
    expect(reopened.accounts.single.name, 'عميل الويب');
    expect(reopened.ledger.single.amount, 30);
    expect(reopened.saleLines.single.quantity, 2);
    expect(reopened.inventory.single.quantity, 7);
    final db = await database.database;
    expect((await db.rawQuery('PRAGMA integrity_check')).single.values.single, 'ok');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('unsupported web backup version is rejected without changing live SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-web-invalid-');
    final cache = Directory('${dir.path}/cache')..createSync();
    final staging = Directory('${cache.path}/nasqo-website-import')..createSync();
    const token = 'fedcba9876543210fedcba9876543210';
    final file = File('${staging.path}/$token.bin');
    await file.writeAsString(jsonEncode({...webFixture(), 'version': 999}));
    final database = LocalDatabase.withFactory(databaseFactoryFfi, '${dir.path}/nasqo_pro_erp.db');
    final controller = ErpController(autoInitDb: false, localDatabase: database,
      emptyOnFirstInstall: true);
    addTearDown(() async {
      controller.dispose();
      await database.close();
      await dir.delete(recursive: true);
    });
    await controller.initDatabase();
    final importer = QaWebsiteImport(controller,
      privateCache: () async => cache,
      selectFile: () async => {'token': token, 'sizeBytes': await file.length()});
    await expectLater(importer.pickAndPreview(), throwsFormatException);
    expect(await file.exists(), false);
    expect((await database.loadSnapshot()).accounts, isEmpty);
  });
}
