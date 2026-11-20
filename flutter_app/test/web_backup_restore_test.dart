import 'dart:io';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/web_backup.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final warehouse = {'id': 'w1', 'name': 'المخزن', 'details': '', 'isDefault': true};
  final payload = {
    'format': 'nasqo-pro-erp-backup', 'version': 2,
    'workspace': {'companyName': 'شركة اختبار'}, 'accounts': [], 'ledger': [],
    'warehouses': [warehouse], 'inventory': [
      {'id': 'i1', 'name': 'صنف', 'unit': 'حبة', 'warehouseId': 'w1', 'quantity': 7, 'avgCost': 15},
    ],
  };
  test('rejects duplicate ids and unsupported versions', () {
    for (final invalid in [
      {...payload, 'version': 9},
      {...payload, 'warehouses': [warehouse, warehouse]},
      {...payload, 'warehouses': []},
    ]) {
      expect(() => WebBackup.parse(jsonEncode(invalid)), throwsFormatException);
    }
  });
  test('restores mobile records and retains the complete web export atomically', () async {
    sqfliteFfiInit();
    final db = LocalDatabase.withFactory(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    final backup = WebBackup.parse(jsonEncode(payload));
    Future<void> save(String company) => db.saveSnapshot(accounts: backup.accounts,
      ledger: backup.ledger, warehouses: backup.warehouses, inventory: backup.inventory,
      saleLines: backup.lines, companyName: company, isDarkMode: false,
      nextEntryNumber: 0, restoredWebExport: backup.original);
    await save(backup.company);
    final snapshot = await db.loadSnapshot();
    expect(snapshot.inventory.single.quantity, 7);
    expect(snapshot.companyName, backup.company);
    final sql = await db.database;
    final archive = await sql.query('erp_state', where: 'stateKey = ?', whereArgs: ['original_web_export']);
    expect(archive.single['payloadJson'], backup.original);
    await sql.execute("CREATE TRIGGER fail_restore BEFORE INSERT ON inventory_items BEGIN SELECT RAISE(ABORT, 'fail'); END");
    await expectLater(save('changed'), throwsA(anything));
    expect((await db.loadSnapshot()).companyName, backup.company);
    expect((await db.loadSnapshot()).inventory.single.quantity, 7);
  });
  test('web invoice, balance and stock survive a cold reopen', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('nasqo-web-reconcile');
    final store = LocalDatabase.withFactory(databaseFactoryFfi, '${dir.path}/data.db');
    final first = ErpController(autoInitDb: false, localDatabase: store);
    addTearDown(() async {
      first.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });
    await first.initDatabase();
    final export = {...payload, 'accounts': [
      {'id':'customer','name':'عميل','category':'clients','currency':'USD',
       'creditLimit':500,'isCashAccount':false,'openingBalance':20,
       'openingDirection':'debit','codeNumber':1}
    ], 'ledger': [
      {'id':'invoice','accountId':'customer','accountName':'عميل','kind':'invoice',
       'typeLabel':'فاتورة بيع','payment':'credit','direction':'debit','amount':30,
       'currency':'USD','exchangeRate':3.75,'entryNumber':11,'deleted':false,
       'entryDate':'2026-10-01','warehouseId':'w1','warehouseName':'المخزن',
       'lines':[{'inventoryItemId':'i1','itemName':'صنف','unit':'حبة','quantity':2,'price':15}]}
    ]};
    await first.restoreWebBackup(WebBackup.parse(jsonEncode(export)));
    await store.close();
    final snapshot = await store.loadSnapshot();
    final customer = snapshot.accounts.single;
    final invoice = snapshot.ledger.single;
    expect(invoice.accountId, customer.id);
    expect(invoice.currency, customer.currency);
    expect(invoice.direction.name, 'debit');
    expect(customer.openingBalance + invoice.amount, 50);
    expect(invoice.exchangeRate, 3.75);
    expect(snapshot.saleLines.single.entryId, invoice.id);
    expect(snapshot.saleLines.single.quantity * snapshot.saleLines.single.unitPrice, invoice.amount);
    expect(snapshot.inventory.single.warehouseId, snapshot.warehouses.single.id);
    expect(snapshot.inventory.single.quantity, 7);
  });
}
