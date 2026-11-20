import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/nonposting_document.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';

NonpostingDocument doc(
        {int? id,
        int revision = 0,
        NonpostingDocumentType type = NonpostingDocumentType.quote,
        String name = 'عميل تركيبي',
        double qty = 2}) =>
    NonpostingDocument(
        id: id,
        revision: revision,
        type: type,
        date: '2026-01-02',
        currency: CurrencyCode.usd,
        customerName: name,
        lines: [
          NonpostingLine(
              description: 'بند صناعي', quantity: qty, unitPrice: 3.5)
        ]);
void _initFfi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

void main() {
  late LocalDatabase store;
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nonposting-synthetic-');
    store = LocalDatabase.withFactory(
        createDatabaseFactoryFfi(ffiInit: _initFfi), '${dir.path}/test.db');
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test(
      'save/read/edit commits stable IDs and isolates type with no financial writes',
      () async {
    final quote = await store.saveNonpostingDocument(doc());
    final order = await store
        .saveNonpostingDocument(doc(type: NonpostingDocumentType.order));
    expect(order.id, isNot(quote.id));
    expect(quote.revision, 1);
    expect(
        (await store.getNonpostingDocument(quote.type, quote.id!))!.total, 7);
    expect(await store.getNonpostingDocument(order.type, quote.id!), isNull);
    final edited = await store
        .saveNonpostingDocument(doc(id: quote.id, revision: 1, qty: 4));
    expect(edited.id, quote.id);
    expect(edited.revision, 2);
    expect(edited.total, 14);
    expect((await store.listNonpostingDocuments(order.type)).single.total, 7);
    await expectLater(
        store.saveNonpostingDocument(doc(id: quote.id, revision: 1)),
        throwsStateError);
    await expectLater(
        store.saveNonpostingDocument(
            doc(id: quote.id, revision: 2, type: order.type)),
        throwsStateError);
    final db = await store.database;
    for (final table in [
      'accounts',
      'ledger_entries',
      'sale_lines',
      'inventory_items',
      'warehouses',
      'erp_state'
    ]) {
      expect(await db.query(table), isEmpty, reason: table);
    }
    await store.close();
    expect(
        (await store.getNonpostingDocument(quote.type, quote.id!))!.total, 14);
  });
  test('failed line insert rolls header and lines back atomically', () async {
    final saved = await store.saveNonpostingDocument(doc());
    final db = await store.database;
    await db.execute(
        "CREATE TRIGGER fail_nonposting BEFORE INSERT ON nonposting_lines BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END");
    await expectLater(
        store.saveNonpostingDocument(doc(id: saved.id, revision: 1, qty: 5)),
        throwsA(isA<DatabaseException>()));
    final kept = (await store.getNonpostingDocument(saved.type, saved.id!))!;
    expect(kept.revision, 1);
    expect(kept.total, 7);
    await expectLater(
        store.saveNonpostingDocument(doc(type: NonpostingDocumentType.order)),
        throwsA(isA<DatabaseException>()));
    expect(await store.listNonpostingDocuments(NonpostingDocumentType.order),
        isEmpty);
  });
  test('v2 migration additive, snapshot and clear semantics independent',
      () async {
    final db = await store.database;
    await db.insert('erp_state', {
      'stateKey': 'sentinel',
      'payloadJson': '{}',
      'updatedAt': 'synthetic'
    });
    await db.execute('DROP TABLE fx_drafts');
    await db.execute('DROP TABLE simple_journal_drafts');
    await db.execute('DROP TABLE cash_transfer_drafts');
    await db.execute('DROP TABLE voucher_drafts');
    await db.execute('DROP TABLE sale_line_cost_facts');
    await db.execute('DROP TABLE sale_facts');
    await db.execute('DROP TABLE sales_return_draft_lines');
    await db.execute('DROP TABLE sales_return_drafts');
    await db.execute('DROP TABLE nonposting_lines');
    await db.execute('DROP TABLE nonposting_documents');
    await db.setVersion(2);
    await store.close();
    final migrated = await store.database;
    expect(await migrated.getVersion(), 9);
    expect((await migrated.query('erp_state')).single['stateKey'], 'sentinel');
    final saved = await store.saveNonpostingDocument(doc());
    await store.saveSnapshot(
        saleLines: [],
        accounts: [],
        ledger: [],
        warehouses: [],
        inventory: [],
        companyName: 'synthetic',
        isDarkMode: false,
        nextEntryNumber: 1);
    expect(await store.getNonpostingDocument(saved.type, saved.id!), isNotNull);
    await store.clearAll();
    expect(await store.listNonpostingDocuments(saved.type), isEmpty);
    expect(await migrated.query('nonposting_lines'), isEmpty);
  });
  test('invalid input rejected without creating a document', () async {
    for (final qty in [0.0, -1.0, double.nan, double.infinity]) {
      await expectLater(
          store.saveNonpostingDocument(doc(qty: qty)), throwsArgumentError);
    }
    await expectLater(
        store.saveNonpostingDocument(doc(name: ' ')), throwsArgumentError);
    final invalidDate = NonpostingDocument(
        type: NonpostingDocumentType.order,
        date: '2026-02-31',
        currency: CurrencyCode.sar,
        customerName: 'test',
        lines: doc().lines);
    await expectLater(
        store.saveNonpostingDocument(invalidDate), throwsArgumentError);
    expect(await store.listNonpostingDocuments(NonpostingDocumentType.quote),
        isEmpty);
  });
}
