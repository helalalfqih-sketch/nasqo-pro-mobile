import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sale_facts.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

SaleFacts facts(
        {String id = 'sale',
        double tax = 15,
        int pos = 0,
        double? cost = 4,
        bool enabled = true}) =>
    SaleFacts(
        entryId: id,
        currency: CurrencyCode.usd,
        preTaxTotal: 100,
        taxEnabled: enabled,
        appliedTaxRate: enabled ? 0.15 : 0,
        taxAmount: tax,
        finalTotal: 100 + tax,
        lineCosts: [SaleLineCostFact(position: pos, stockAverageCost: cost)]);
Future<Map<String, Object?>> all(Database db) async => {
      for (final t in [
        'accounts',
        'ledger_entries',
        'sale_lines',
        'inventory_items',
        'warehouses',
        'erp_state',
        'sale_facts',
        'sale_line_cost_facts'
      ])
        t: await db.query(t)
    };
void main() {
  late Directory dir;
  late LocalDatabase store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sale-facts-synthetic-');
    store = LocalDatabase.withFactory(
        createDatabaseFactoryFfi(ffiInit: _ffi), '${dir.path}/test.db');
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<void> save({SaleFacts? append, double amount = 115}) =>
      store.saveSnapshot(
          accounts: [],
          warehouses: [],
          inventory: [],
          companyName: 'synthetic',
          isDarkMode: false,
          nextEntryNumber: 1,
          ledger: [
            LedgerEntryRecord(
                id: 'sale',
                accountId: 'a',
                accountName: 'test',
                kind: LedgerKind.invoice,
                typeLabel: 'ف.مبيعات آجل',
                payment: PaymentMethod.credit,
                direction: EntryDirection.debit,
                amount: amount,
                currency: CurrencyCode.usd,
                entryNumber: 1,
                entryDate: '2026-01-01')
          ],
          saleLines: [
            const SavedSaleLine(
                entryId: 'sale',
                position: 0,
                itemId: 'i',
                itemName: 'test',
                unit: 'حبة',
                quantity: 2,
                unitPrice: 50)
          ],
          appendedSaleFacts: append);
  test('v4 migration preserves legacy and leaves facts unknown', () async {
    await save();
    final db = await store.database;
    final before = await db.query('ledger_entries');
    await db.execute('DROP TABLE fx_drafts');
    await db.execute('DROP TABLE simple_journal_drafts');
    await db.execute('DROP TABLE cash_transfer_drafts');
    await db.execute('DROP TABLE voucher_drafts');
    await db.execute('DROP TABLE sale_line_cost_facts');
    await db.execute('DROP TABLE sale_facts');
    await db.setVersion(4);
    await store.close();
    expect(await (await store.database).getVersion(), 9);
    expect(await (await store.database).query('ledger_entries'), before);
    expect(await store.getSaleFacts('sale'), isNull);
  });
  test(
      'append committed facts, ordinary snapshot preserves, duplicate rejects, reopen',
      () async {
    await save(append: facts(cost: null));
    final saved = (await store.getSaleFacts('sale'))!;
    expect(saved.preTaxTotal, 100);
    expect(saved.taxAmount, 15);
    expect(saved.currency, CurrencyCode.usd);
    expect(saved.lineCosts.single.stockAverageCost, isNull);
    await save();
    expect((await store.getSaleFacts('sale'))!.finalTotal, 115);
    final before = await all(await store.database);
    await expectLater(save(append: facts()), throwsA(isA<DatabaseException>()));
    expect(await all(await store.database), before);
    await store.close();
    expect((await store.getSaleFacts('sale'))!.taxEnabled, true);
  });
  test('invalid linkage, positions, totals and disabled tax roll back snapshot',
      () async {
    await save();
    final before = await all(await store.database);
    for (final value in [
      facts(id: 'absent'),
      facts(pos: 9),
      facts(tax: 14),
      facts(tax: 15, enabled: false),
      facts(cost: -1)
    ]) {
      await expectLater(save(append: value), throwsA(anything));
      expect(await all(await store.database), before);
    }
    await save(append: facts(tax: 0, enabled: false), amount: 100);
    expect((await store.getSaleFacts('sale'))!.taxAmount, 0);
  });
  test('cost insert failure atomically rolls financial snapshot and facts back',
      () async {
    await save();
    final db = await store.database;
    final before = await all(db);
    await db.execute(
        "CREATE TRIGGER reject_cost BEFORE INSERT ON sale_line_cost_facts BEGIN SELECT RAISE(ABORT,'synthetic failure'); END");
    await expectLater(save(append: facts()), throwsA(isA<DatabaseException>()));
    expect(await all(db), before);
    expect(await store.getSaleFacts('sale'), isNull);
    await db.execute('DROP TRIGGER reject_cost');
    await save(append: facts());
    expect(
        (await store.getSaleFacts('sale'))!.lineCosts.single.stockAverageCost,
        4);
    await store.clearAll();
    expect(await store.getSaleFacts('sale'), isNull);
  });
}
