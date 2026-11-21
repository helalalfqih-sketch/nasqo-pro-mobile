import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/legacy_backup_inspection.dart';
import 'package:nasqo_pro_erp/services/web_backup.dart';
import 'package:nasqo_pro_erp/services/website_backup_file.dart';
import 'package:nasqo_pro_erp/services/website_restore_trial.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Uint8List> fixture(Directory dir,
    {List<String> changes = const []}) async {
  final f = File('${dir.path}/source.back');
  final db = await databaseFactoryFfi.openDatabase(f.path);
  try {
    for (final sql in [
      'CREATE TABLE workspaces(id INTEGER,company_name TEXT)',
      "INSERT INTO workspaces VALUES(1,'منشأة اختبار')",
      'CREATE TABLE currencies(id INTEGER,name TEXT,amount REAL,amount2 REAL)',
      "INSERT INTO currencies VALUES(9,'دولار',2.5,2.4)",
      'CREATE TABLE boxes(id INTEGER,name TEXT,cur INTEGER)',
      "INSERT INTO boxes VALUES(3,'العملاء',9)",
      'CREATE TABLE customers(id INTEGER,name TEXT,type INTEGER,phone TEXT,lim REAL,opening_balance REAL,opening_direction TEXT)',
      "INSERT INTO customers VALUES(11,'عميل اختبار',3,'',15,12.25,'credit')",
      'CREATE TABLE stores(id INTEGER,name TEXT,details TEXT,is_default INTEGER)',
      "INSERT INTO stores VALUES(4,'مخزن اختبار','',1)",
      'CREATE TABLE products(id INTEGER,name TEXT,barcode TEXT,unit TEXT,store_id INTEGER,quantity REAL,price2 REAL,min_threshold REAL)',
      "INSERT INTO products VALUES(22,'صنف اختبار','A1','حبة',4,17.25,4,2)",
      'CREATE TABLE input_move(id INTEGER,bill TEXT,per_id INTEGER,bill_type INTEGER,year INTEGER,month INTEGER,day INTEGER,dain REAL,madin REAL,cur INTEGER,curprice REAL,details TEXT,bstate INTEGER)',
      "INSERT INTO input_move VALUES(31,'B31',11,2,2024,2,29,10.5,0,9,2.5,'',1)",
      'CREATE TABLE bill_details(id INTEGER,bill_id INTEGER,prod_id INTEGER,store_id INTEGER,unit TEXT,amount REAL,price REAL,total REAL,discount REAL)',
      "INSERT INTO bill_details VALUES(44,31,22,4,'حبة',1.5,7,10.5,0)",
      ...changes
    ]) {
      await db.execute(sql);
    }
  } finally {
    await db.close();
  }
  return f.readAsBytes();
}

void main() {
  late Directory dir;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('legacy-fixture-');
  });
  tearDown(() => dir.delete(recursive: true));
  test('SQLite source values survive a mobile cold reopen in isolation',
      () async {
    final bytes = await fixture(dir);
    final audit = (await inspectLegacyBackup(bytes))!;
    expect(audit.checksum, sha256.convert(bytes).toString());
    expect(audit.issues.values.every((v) => v == 0), isTrue);
    final raw = await readWebsiteBackup(bytes, 1 << 20);
    final backup = WebBackup.parse(raw);
    expect(backup.accounts.single.openingBalance, 12.25);
    expect(backup.inventory.single.quantity, 17.25);
    expect(backup.lines.single.quantity, 1.5);
    expect(backup.ledger.single.amount, 10.5);
    expect(backup.ledger.single.exchangeRate, 2.5);
    expect(backup.ledger.single.entryDate, '2024-02-29');
    final result = await testWebsiteRestore(backup);
    expect(result['before'], result['after']);
    expect(result['matchedRecords'], 5);
    expect(jsonDecode(raw)['ledger'][0]['lines'][0]['legacyId'], 44);
    expect(await File('${dir.path}/source.back').readAsBytes(), bytes);
  });
  test('all seven currency orphans are identifiable without guessing',
      () async {
    final bytes = await fixture(dir, changes: [
      for (var i = 0; i < 7; i++)
        "INSERT INTO input_move VALUES(${100 + i},'V',11,1,2024,1,1,1,0,${i < 2 ? 2 : 3},1,'',1)"
    ]);
    final audit = (await inspectLegacyBackup(bytes))!;
    expect(audit.missingCurrencies, 7);
    expect(
        audit.currencyReferences.where((r) => r['currencyId'] == 2).length, 2);
    expect(
        audit.currencyReferences.where((r) => r['currencyId'] == 3).length, 5);
    await expectLater(readWebsiteBackup(bytes, 1 << 20), throwsFormatException);
  });
  for (final entry in {
    'missing product': 'UPDATE bill_details SET prod_id=77',
    'invalid date': 'UPDATE input_move SET year=2023',
    'duplicate account': 'INSERT INTO customers SELECT * FROM customers',
    'unreconciled invoice': 'UPDATE bill_details SET total=500',
    'unverified stock': 'UPDATE products SET quantity=NULL',
    'unknown financial column': 'ALTER TABLE input_move ADD COLUMN vat REAL',
    'unsupported nonempty transfer table':
        'CREATE TABLE trans_details AS SELECT 1 AS id',
  }.entries) {
    test('blocks ${entry.key}', () async {
      final bytes = await fixture(dir, changes: [entry.value]);
      await expectLater(
          readWebsiteBackup(bytes, 1 << 20), throwsFormatException);
    });
  }
}
