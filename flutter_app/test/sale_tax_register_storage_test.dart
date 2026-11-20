import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

Future<Map<String, Object?>> snapshot(Database db) async {
  final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
  return {
    for (final t in tables)
      t['name'] as String: await db.query(t['name'] as String)
  };
}

void main() {
  late Directory dir;
  late LocalDatabase store;
  late Database db;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tax-register-synthetic-');
    store = LocalDatabase.withFactory(
        createDatabaseFactoryFfi(ffiInit: _ffi), '${dir.path}/test.db');
    db = await store.database;
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<void> seed(String id,
      {String date = '2026-01-02',
      String currency = 'usd',
      String kind = 'invoice',
      String direction = 'debit',
      String label = 'ف.مبيعات آجل',
      bool deleted = false,
      bool hasFacts = true,
      bool enabled = true,
      double net = .4,
      double tax = .06}) async {
    await db.insert('ledger_entries', {
      'id': id,
      'accountId': 'a',
      'accountName': 'تركيبي',
      'kind': kind,
      'typeLabel': label,
      'payment': 'credit',
      'direction': direction,
      'amount': net + tax,
      'currency': currency,
      'exchangeRate': 999,
      'details': 'fixture',
      'documentNumber': 'INV-$id',
      'warehouseId': 'w',
      'warehouseName': 'تركيبي',
      'expenseCategory': '',
      'entryNumber': 1,
      'deleted': deleted ? 1 : 0,
      'entryDate': date
    });
    if (!hasFacts) return;
    await db.insert('sale_lines', {
      'entryId': id,
      'position': 0,
      'itemId': 'i',
      'itemName': 'تركيبي',
      'unit': 'حبة',
      'quantity': 1,
      'unitPrice': net
    });
    await db.insert('sale_facts', {
      'entryId': id,
      'currency': currency,
      'preTaxTotal': net,
      'taxEnabled': enabled ? 1 : 0,
      'appliedTaxRate': enabled ? .15 : 0,
      'taxAmount': tax,
      'finalTotal': net + tax
    });
    await db.insert('sale_line_cost_facts',
        {'entryId': id, 'position': 0, 'stockAverageCost': null});
  }

  test(
      'observed currencies separate; stored .06 exact and no FX or database writes',
      () async {
    await seed('usd');
    await seed('sar', currency: 'sar', net: 100, tax: 15);
    await seed('untaxed', currency: 'usd', net: 10, tax: 0, enabled: false);
    final before = await snapshot(db);
    final report = await store.loadSaleTaxRegister();
    expect(report.rows.length, 3);
    expect(report.rows.firstWhere((r) => r.entryId == 'usd').taxAmount, .06);
    final usd =
        report.currencies.firstWhere((c) => c.currency == CurrencyCode.usd);
    expect(usd.knownCount, 2);
    expect(usd.preTaxTotal, 10.4);
    expect(usd.taxAmount, .06);
    expect(usd.finalTotal, 10.46);
    expect(
        report.currencies
            .firstWhere((c) => c.currency == CurrencyCode.sar)
            .taxAmount,
        15);
    expect(await snapshot(db), before);
  });
  test(
      'range inclusive both ends; one-sided allowed and malformed bounds reject',
      () async {
    await seed('before', date: '2026-01-01');
    await seed('start', date: '2026-01-02');
    await seed('end', date: '2026-01-03');
    await seed('after', date: '2026-01-04');
    expect(
        (await store.loadSaleTaxRegister(
                from: '2026-01-02', through: '2026-01-03'))
            .rows
            .map((r) => r.entryId),
        ['end', 'start']);
    expect((await store.loadSaleTaxRegister(through: '2026-01-01')).rows.length,
        1);
    expect(
        (await store.loadSaleTaxRegister(from: '2026-01-04')).rows.length, 1);
    for (final bad in ['', '2026-02-30', '2026-1-02', 'not-a-date']) {
      await expectLater(
          store.loadSaleTaxRegister(from: bad), throwsArgumentError);
    }
    await expectLater(
        store.loadSaleTaxRegister(from: '2026-01-04', through: '2026-01-01'),
        throwsArgumentError);
  });
  test(
      'native missing and mismatched facts unknown; non-native excluded entirely',
      () async {
    await seed('legacy', hasFacts: false);
    await seed('wrong');
    await db.update('sale_facts', {'currency': 'sar'},
        where: 'entryId = ?', whereArgs: ['wrong']);
    await seed('purchase', direction: 'credit');
    await seed('deleted', deleted: true);
    await seed('return', kind: 'returnEntry');
    await seed('crm', label: 'فاتورة CRM');
    await seed('quote', kind: 'quote');
    final r = await store.loadSaleTaxRegister();
    expect(r.rows, isEmpty);
    expect(r.currencies.length, 1);
    expect(r.currencies.single.unknownCount, 2);
    expect(r.currencies.single.knownCount, 0);
  });
  test('inconsistent lines/amounts are unknown; malformed headers diagnostic',
      () async {
    await seed('line');
    await db.update('sale_lines', {'unitPrice': 9},
        where: 'entryId = ?', whereArgs: ['line']);
    await seed('amount');
    await db.update('ledger_entries', {'amount': 99},
        where: 'id = ?', whereArgs: ['amount']);
    await seed('missingcost');
    await db.delete('sale_line_cost_facts',
        where: 'entryId = ?', whereArgs: ['missingcost']);
    await seed('bad-date', date: '2026-02-31');
    await seed('bad-currency', currency: 'unrecognized');
    final r = await store.loadSaleTaxRegister();
    expect(r.rows, isEmpty);
    expect(r.currencies.single.unknownCount, 3);
    expect(r.invalidHeaderCount, 2);
  });
  test('empty read stays empty and zero-rate known distinct from missing',
      () async {
    expect((await store.loadSaleTaxRegister()).currencies, isEmpty);
    await seed('zero', enabled: false, net: 0, tax: 0);
    await seed('unknown', hasFacts: false);
    final r = await store.loadSaleTaxRegister();
    expect(r.rows.single.taxEnabled, false);
    expect(r.currencies.single.knownCount, 1);
    expect(r.currencies.single.unknownCount, 1);
  });
}
