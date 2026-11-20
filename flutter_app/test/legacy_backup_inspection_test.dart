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
    await db.execute('CREATE TABLE input_move(id INTEGER PRIMARY KEY, cur INTEGER)');
    await db.execute('CREATE TABLE bill_details(id INTEGER PRIMARY KEY, bill_id INTEGER, prod_id INTEGER, store_id INTEGER)');
    await db.execute('CREATE TABLE trans_details(id INTEGER PRIMARY KEY)');
    await db.execute('INSERT INTO currencies VALUES(1)');
    await db.execute('INSERT INTO input_move VALUES(4,3)');
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

  test('non-SQLite input does not trigger legacy conversion', () async {
    expect(await inspectLegacyBackup(Uint8List.fromList([123, 125])), isNull);
  });
}
