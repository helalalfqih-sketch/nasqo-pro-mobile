import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sales_return_draft.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

Future<Map<String, Object?>> financial(Database db) async => {
      for (final t in [
        'accounts',
        'ledger_entries',
        'sale_lines',
        'inventory_items',
        'warehouses',
        'erp_state'
      ])
        t: await db.query(t)
    };
void main() {
  late Directory dir;
  late LocalDatabase store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('return-draft-synthetic-');
    store = LocalDatabase.withFactory(
        createDatabaseFactoryFfi(ffiInit: _ffi), '${dir.path}/test.db');
    await store.saveSnapshot(
        accounts: [],
        warehouses: [],
        inventory: [],
        companyName: 'test',
        isDarkMode: false,
        nextEntryNumber: 99,
        ledger: [
          const LedgerEntryRecord(
              id: 'sale',
              accountId: 'a',
              accountName: 'عميل صناعي',
              kind: LedgerKind.invoice,
              typeLabel: 'ف.مبيعات آجل',
              payment: PaymentMethod.credit,
              direction: EntryDirection.debit,
              amount: 40,
              currency: CurrencyCode.usd,
              warehouseId: 'w',
              entryNumber: 99,
              entryDate: '2026-01-01')
        ],
        saleLines: [
          const SavedSaleLine(
              entryId: 'sale',
              position: 0,
              itemId: 'same',
              itemName: 'صنف',
              unit: 'حبة',
              quantity: 2,
              unitPrice: 10),
          const SavedSaleLine(
              entryId: 'sale',
              position: 1,
              itemId: 'same',
              itemName: 'صنف',
              unit: 'حبة',
              quantity: 4,
              unitPrice: 5)
        ]);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<SalesReturnDraft> save(
          {int? id,
          int revision = 0,
          List<SalesReturnSelection> picks = const [
            SalesReturnSelection(position: 0, quantity: 1)
          ]}) =>
      store.saveSalesReturnDraft(
          id: id,
          revision: revision,
          sourceEntryId: 'sale',
          date: '2026-01-02',
          reason: 'سبب تجريبي',
          selections: picks);
  test(
      'v3 migration preserves financial rows; locked source values and stable edit',
      () async {
    final db = await store.database;
    final before = await financial(db);
    await db.execute('DROP TABLE fx_drafts');
    await db.execute('DROP TABLE simple_journal_drafts');
    await db.execute('DROP TABLE cash_transfer_drafts');
    await db.execute('DROP TABLE voucher_drafts');
    await db.execute('DROP TABLE sale_line_cost_facts');
    await db.execute('DROP TABLE sale_facts');
    await db.execute('DROP TABLE sales_return_draft_lines');
    await db.execute('DROP TABLE sales_return_drafts');
    await db.setVersion(3);
    await store.close();
    final migrated = await store.database;
    expect(await migrated.getVersion(), 9);
    expect(await financial(migrated), before);
    final d = await save();
    expect(d.currency, CurrencyCode.usd);
    expect(d.lines.single.unitPrice, 10);
    expect(d.subtotal, 10);
    final edited = await save(
        id: d.id,
        revision: d.revision,
        picks: const [SalesReturnSelection(position: 1, quantity: 3)]);
    expect(edited.id, d.id);
    expect(edited.revision, 2);
    expect(edited.subtotal, 15);
    expect(edited.lines.single.sourceQuantity, 4);
    await expectLater(save(id: d.id, revision: 1), throwsStateError);
    expect(await financial(migrated), before);
    await store.close();
    expect((await store.getSalesReturnDraft(d.id))!.subtotal, 15);
  });
  test('membership, duplicate position, ceiling and nonfinite rejection',
      () async {
    final before = await financial(await store.database);
    for (final picks in [
      <SalesReturnSelection>[],
      const [SalesReturnSelection(position: 2, quantity: 1)],
      const [SalesReturnSelection(position: 0, quantity: 3)],
      const [
        SalesReturnSelection(position: 0, quantity: 1),
        SalesReturnSelection(position: 0, quantity: 1)
      ],
      const [SalesReturnSelection(position: 0, quantity: double.nan)]
    ]) {
      await expectLater(save(picks: picks), throwsA(anything));
    }
    expect(await store.listSalesReturnDrafts(), isEmpty);
    expect(await financial(await store.database), before);
  });
  test('reject deleted, untyped, non-sale and legacy without saved lines',
      () async {
    final db = await store.database;
    for (final patch in [
      {'deleted': 1},
      {'typeLabel': 'فاتورة'},
      {'kind': 'quote'},
      {'direction': 'credit'}
    ]) {
      await db.update('ledger_entries', patch,
          where: 'id = ?', whereArgs: ['sale']);
      await expectLater(save(), throwsStateError);
      await db.update(
          'ledger_entries',
          {
            'deleted': 0,
            'typeLabel': 'ف.مبيعات آجل',
            'kind': 'invoice',
            'direction': 'debit'
          },
          where: 'id = ?',
          whereArgs: ['sale']);
    }
    await db.delete('sale_lines');
    await expectLater(save(), throwsStateError);
  });
  test('line insert failure rolls draft edit back and never posts', () async {
    final d = await save();
    final db = await store.database;
    final before = await financial(db);
    await db.execute(
        "CREATE TRIGGER reject_return BEFORE INSERT ON sales_return_draft_lines BEGIN SELECT RAISE(ABORT,'synthetic'); END");
    await expectLater(
        save(
            id: d.id,
            revision: 1,
            picks: const [SalesReturnSelection(position: 0, quantity: 2)]),
        throwsA(isA<DatabaseException>()));
    expect((await store.getSalesReturnDraft(d.id))!.revision, 1);
    expect((await store.getSalesReturnDraft(d.id))!.subtotal, 10);
    expect(await financial(db), before);
    await db.execute('DROP TRIGGER reject_return');
    await store.clearAll();
    expect(await store.listSalesReturnDrafts(), isEmpty);
  });
}
