import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/legacy_backup_inspection.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('legacy backup is inspected in isolation without changing source', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('legacy-preview-test-');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/legacy.back');
    final db = await databaseFactoryFfi.openDatabase(source.path);
    await db.execute('CREATE TABLE currencies(id INTEGER PRIMARY KEY)');
    await db.execute('CREATE TABLE customers(id INTEGER PRIMARY KEY, type INTEGER)');
    await db.execute('CREATE TABLE boxes(id INTEGER PRIMARY KEY)');
    await db.execute('CREATE TABLE products(id INTEGER PRIMARY KEY, cur INTEGER)');
    await db.execute('CREATE TABLE stores(id INTEGER PRIMARY KEY)');
    await db.execute('CREATE TABLE cboxes(id INTEGER PRIMARY KEY)');
    await db.execute('CREATE TABLE input_move(id INTEGER PRIMARY KEY, cur INTEGER, per_id INTEGER)');
    await db.execute('CREATE TABLE bill_details(id INTEGER PRIMARY KEY, bill_id INTEGER, prod_id INTEGER, store_id INTEGER)');
    await db.execute('CREATE TABLE trans_details(id INTEGER PRIMARY KEY)');
    await db.execute('INSERT INTO currencies VALUES(1)');
    await db.execute('INSERT INTO input_move VALUES(4,3,9)');
    await db.execute('INSERT INTO products VALUES(2,1)');
    await db.execute('INSERT INTO stores VALUES(1)');
    await db.execute('INSERT INTO bill_details VALUES(8,4,2,1)');
    await db.close();
    final original = await source.readAsBytes();
    final result = await inspectLegacyBackup(Uint8List.fromList(original));
    expect(result, isNotNull);
    expect(result!.integrityOk, true);
    expect(result.missingCurrencies, 1);
    expect(result.orphanInvoiceLines, 0);
    expect(result.orphanProducts, 0);
    expect(result.orphanAccounts, 1);
    expect(result.orphanWarehouses, 0);
    expect(result.missingProductCurrencies, 0);
    expect(result.safeForAutomaticRestore, false);
    expect(result.arabicSummary, contains('الاستعادة المباشرة موقوفة'));
    expect(await source.readAsBytes(), original);
  });

  test('v28 reports missing currency IDs and preserves source rate evidence', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('legacy-v28-test-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/fixture.back';
    final db = await databaseFactoryFfi.openDatabase(path);
    try {
      for (final sql in [
        'PRAGMA user_version = 28',
        'CREATE TABLE currencies(id INTEGER, name TEXT)',
        'CREATE TABLE boxes(id INTEGER, cur INTEGER)',
        'CREATE TABLE customers(id INTEGER, type INTEGER)',
        'CREATE TABLE products(id INTEGER, cur INTEGER)',
        'CREATE TABLE stores(id INTEGER)',
        'CREATE TABLE cboxes(id INTEGER, cur INTEGER)',
        'CREATE TABLE input_move(id INTEGER, per_id INTEGER, cur INTEGER, bill_type INTEGER, curprice TEXT)',
        'CREATE TABLE bill_details(id INTEGER, bill_id INTEGER, prod_id INTEGER, store_id INTEGER)',
        'CREATE TABLE store_trans(id INTEGER, store_id1 INTEGER, store_id2 INTEGER)',
        'CREATE TABLE trans_details(id INTEGER, bill_id INTEGER, prod_id INTEGER)',
        "INSERT INTO currencies VALUES(1, 'ريال')",
        'INSERT INTO boxes VALUES(1,1)',
        'INSERT INTO customers VALUES(1,1)',
        'INSERT INTO products VALUES(1,1)',
        'INSERT INTO cboxes VALUES(1,1)',
        'INSERT INTO trans_details VALUES(1,99,98)',
      ]) {
        await db.execute(sql);
      }
      for (var i = 0; i < 7; i++) {
        await db.insert('input_move', {'id': i+1, 'per_id': 1,
          'cur': i<2 ? 2 : 3, 'bill_type': i==0 ? 1 : 2,
          'curprice': i==0 ? '0' : '1'});
      }
    } finally { await db.close(); }
    final source = await File(path).readAsBytes();
    final report = (await inspectLegacyBackup(source))!;
    expect(report.integrityOk, isTrue);
    expect(report.missingCurrencyCounts, {'2':2,'3':5});
    expect(report.currencyReferences.first['sourceExchangeRate'], '0');
    expect(report.currencyReferences.first['documentType'], 1);
    expect(report.issues['بنود تحويل مخزني بمستند مفقود'], 1);
    expect(report.issues['بنود تحويل مخزني بصنف مفقود'], 1);
    expect(report.issues['أصناف تحتاج إلى كشف كميات حسب المستودع'], 1);
    expect(report.issues['حسابات تحتاج إلى إثبات الرصيد الافتتاحي واتجاهه'], 1);
    expect(report.issues['صناديق تحتاج إلى ربط صريح بالحساب'], 1);
    expect(report.toJson()['restored'], false);
    expect(await File(path).readAsBytes(), source);
  });

  test('non-SQLite input does not trigger legacy conversion', () async {
    expect(await inspectLegacyBackup(Uint8List.fromList([123, 125])), isNull);
  });
}
