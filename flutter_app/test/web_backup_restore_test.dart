import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'dart:typed_data';
import 'package:nasqo_pro_erp/services/website_backup_file.dart';
import 'dart:io';
import 'package:nasqo_pro_erp/screens/home_account_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/web_backup.dart';
import 'package:nasqo_pro_erp/services/website_restore_trial.dart';
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
  test('reads a gzip-wrapped unified SQLite backup without touching the live database', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('nasqo-back-fixture');
    addTearDown(() => dir.delete(recursive:true));
    final file = File('${dir.path}/sample.back');
    final db = await databaseFactoryFfi.openDatabase(file.path);
    await db.execute('CREATE TABLE workspaces(id TEXT,company_name TEXT)');
    await db.execute("INSERT INTO workspaces VALUES('w','شركة اختبار')");
    for (final table in ['accounts','account_groups','ledger_entries','inventory_items']) {
      await db.execute('CREATE TABLE $table(workspace_id TEXT)');
    }
    await db.execute('CREATE TABLE warehouses(id TEXT,workspace_id TEXT,name TEXT,is_default INTEGER)');
    await db.execute("INSERT INTO warehouses VALUES('wh','w','المخزن',1)");
    await db.close();
    final bytes = Uint8List.fromList(gzip.encode(await file.readAsBytes()));
    final backup = WebBackup.parse(await readWebsiteBackup(bytes,1<<20));
    expect(backup.company,'شركة اختبار');
    expect(backup.warehouses.single.isDefault,isTrue);
    await expectLater(readWebsiteBackup(bytes,100),throwsFormatException);
  });
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
    final export = {...payload, 'accountGroups':[{'id':17,'legacyId':7,'name':'أصول المحل'}], 'accounts': [
      {'groupId':17,'id':'customer','name':'عميل','category':'clients','currency':'USD',
       'creditLimit':500,'isCashAccount':false,'openingBalance':20,
       'openingDirection':'debit','codeNumber':1}
    ], 'ledger': [
      {'id':'invoice','accountId':'customer','accountName':'عميل','kind':'invoice',
       'typeLabel':'فاتورة بيع','payment':'credit','direction':'debit','amount':30,
       'currency':'USD','exchangeRate':3.75,'entryNumber':11,'deleted':false,
       'entryDate':'2026-10-01','warehouseId':'w1','warehouseName':'المخزن',
       'lines':[{'inventoryItemId':'i1','itemName':'صنف','unit':'حبة','quantity':2,'price':15}]}
    ]};
    final validated = WebBackup.parse(jsonEncode(export));
    final preview = await testWebsiteRestore(validated);
    expect(preview['integrity'], 'ok');
    expect(preview['coldReopen'], true);
    expect((preview['before'] as Map)['accounts'], 1);
    expect((preview['before'] as Map)['invoices'], 1);
    expect((preview['before'] as Map)['items'], 1);
    await first.restoreWebBackup(validated);
    await store.close();
    final snapshot = await store.loadSnapshot();
    final customer = snapshot.accounts.single;
    final invoice = snapshot.ledger.single;
    expect(invoice.accountId, customer.id);
    expect(invoice.currency, customer.currency);
    expect(invoice.direction.name, 'debit');
    final reopened = ErpController(autoInitDb:false,localDatabase:store);
    addTearDown(reopened.dispose);
    await reopened.initDatabase();
    final groups = reopened.restoredGroups!;
    expect(groups.groups.single.number,7);
    expect(groups.groups.single.name,'أصول المحل');
    expect(groups.membership[customer.id],17);
    expect(groups.balances(snapshot.accounts,snapshot.ledger,{},customer.currency)[17],50);
    final rawLedger = (export['ledger'] as List).cast<Map<String,Object>>();
    final split = WebBackup.parse(jsonEncode({...export, 'ledger':[
      {...rawLedger.single, 'rawDain':3, 'rawMadin':51},
      {...rawLedger.single,'id':'settled','rawDain':30,'rawMadin':30,'settledOnReceipt':true}
    ]}));
    expect(split.groupData.balances(split.accounts,split.ledger,{},customer.currency)[17],-28);
    expect(split.groupData.balances(split.accounts,split.ledger,{17:CurrencyCode.sar},customer.currency)[17] ?? 0,0);

    final statement = LocalAccountStatement(customer, snapshot.ledger, customer.currency);
    expect(statement.opening, 20);
    expect(statement.debit, 30);
    expect(statement.credit, 0);
    expect(statement.closing, 50);
    expect(invoice.exchangeRate, 3.75);
    expect(snapshot.saleLines.single.entryId, invoice.id);
    expect(snapshot.saleLines.single.quantity * snapshot.saleLines.single.unitPrice, invoice.amount);
    expect(snapshot.inventory.single.warehouseId, snapshot.warehouses.single.id);
    expect(snapshot.inventory.single.quantity, 7);
  });
}
