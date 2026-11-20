import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/fx_draft.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/services/fx_draft_repository.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

FxDraft draft(
        {int? id,
        int revision = 0,
        String source = 'usd',
        String destination = 'sar',
        CurrencyCode sourceCurrency = CurrencyCode.usd,
        CurrencyCode destinationCurrency = CurrencyCode.sar,
        double sourceAmount = 1.23456789,
        double destinationAmount = 9.87654321,
        String date = '2026-01-02'}) =>
    FxDraft(
        id: id,
        revision: revision,
        date: date,
        sourceCashId: source,
        destinationCashId: destination,
        sourceCurrency: sourceCurrency,
        destinationCurrency: destinationCurrency,
        sourceAmount: sourceAmount,
        destinationAmount: destinationAmount,
        note: 'synthetic');
Future<Map<String, Object?>> otherTables(Database db) async {
  final names = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ('fx_drafts','sqlite_sequence') ORDER BY name");
  return {
    for (final n in names)
      n['name'] as String: await db.query(n['name'] as String)
  };
}

void main() {
  late Directory dir;
  late LocalDatabase store;
  late FxDraftRepository repo;
  late Database db;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fx-draft-synthetic-');
    store = LocalDatabase.withFactory(
        createDatabaseFactoryFfi(ffiInit: _ffi), '${dir.path}/test.db');
    await store.saveSnapshot(
        accounts: [
          const AccountRecord(
              id: 'usd',
              name: 'USDcash',
              category: AccountCategory.transfers,
              currency: CurrencyCode.usd,
              isCashAccount: true,
              openingBalance: 5),
          const AccountRecord(
              id: 'sar',
              name: 'SARcash',
              category: AccountCategory.transfers,
              currency: CurrencyCode.sar,
              isCashAccount: true,
              openingBalance: 9),
          const AccountRecord(
              id: 'party',
              name: 'party',
              category: AccountCategory.clients,
              currency: CurrencyCode.usd),
          const AccountRecord(
              id: 'usd2',
              name: 'USD2',
              category: AccountCategory.transfers,
              currency: CurrencyCode.usd,
              isCashAccount: true)
        ],
        ledger: [],
        warehouses: [],
        inventory: [],
        saleLines: [],
        companyName: 'synthetic',
        isDarkMode: false,
        nextEntryNumber: 88);
    db = await store.database;
    await FxDraftRepository.createSchema(db);
    repo = FxDraftRepository(store);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test('v8 upgrade adds FX drafts without modifying financial records',
      () async {
    final before = await otherTables(db);
    await db.execute('DROP TABLE fx_drafts');
    await db.setVersion(8);
    await store.close();
    final upgraded = await store.database;
    expect(await upgraded.getVersion(), 9);
    expect(await otherTables(upgraded), before);
    expect(await repo.list(), isEmpty);
    expect((await repo.save(draft())).id, isNotNull);
    expect(await otherTables(upgraded), before);
  });

  test('both manual amounts exact, stable edit/reopen, no impact outside draft',
      () async {
    final before = await otherTables(db);
    final saved = await repo.save(draft());
    expect(saved.revision, 1);
    expect(saved.sourceAmount, 1.23456789);
    expect(saved.destinationAmount, 9.87654321);
    final edit = await repo.save(draft(
        id: saved.id,
        revision: 1,
        sourceAmount: 3.14159,
        destinationAmount: .00012345));
    expect(edit.id, saved.id);
    expect(edit.revision, 2);
    expect((await repo.list()).single.destinationAmount, .00012345);
    expect(await otherTables(db), before);
    await store.close();
    final loaded = (await repo.get(saved.id!))!;
    expect(loaded.sourceAmount, 3.14159);
    expect(loaded.destinationAmount, .00012345);
  });
  test('failed update atomic; stale revision rejected', () async {
    final saved = await repo.save(draft());
    final before = await otherTables(db);
    await db.execute(
        "CREATE TRIGGER fail_fx BEFORE UPDATE ON fx_drafts BEGIN SELECT RAISE(ABORT,'synthetic'); END");
    await expectLater(
        repo.save(draft(id: saved.id, revision: 1, sourceAmount: 4)),
        throwsA(isA<DatabaseException>()));
    expect((await repo.get(saved.id!))!.sourceAmount, saved.sourceAmount);
    expect((await repo.get(saved.id!))!.revision, 1);
    await db.execute('DROP TRIGGER fail_fx');
    await repo.save(draft(id: saved.id, revision: 1));
    await expectLater(
        repo.save(draft(id: saved.id, revision: 1)), throwsStateError);
    expect(await otherTables(db), before);
  });
  test(
      'distinct accounts and currencies, matching cash flags and denominations',
      () async {
    for (final d in [
      draft(source: 'sar'),
      draft(source: 'missing'),
      draft(destination: 'missing'),
      draft(source: 'party'),
      draft(destination: 'usd2'),
      draft(sourceCurrency: CurrencyCode.sar),
      draft(destinationCurrency: CurrencyCode.usd)
    ]) {
      await expectLater(repo.save(d), throwsA(anything));
    }
    expect(await repo.list(), isEmpty);
    final saved = await repo.save(draft());
    await db.update('accounts', {'isCashAccount': 0},
        where: 'id = ?', whereArgs: ['sar']);
    await expectLater(
        repo.save(draft(id: saved.id, revision: 1)), throwsStateError);
    expect((await repo.get(saved.id!))!.revision, 1);
  });
  test('each amount independently positive finite, valid dates and revision',
      () async {
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      await expectLater(
          repo.save(draft(sourceAmount: value)), throwsArgumentError);
      await expectLater(
          repo.save(draft(destinationAmount: value)), throwsArgumentError);
    }
    for (final date in ['', '2026-02-30', '2026-1-2']) {
      await expectLater(repo.save(draft(date: date)), throwsArgumentError);
    }
    await expectLater(
        repo.save(draft(id: 1, revision: 0)), throwsArgumentError);
    expect(await repo.list(), isEmpty);
  });
  test('schema idempotent and clear only drafts; identifiers never reused',
      () async {
    final before = await otherTables(db);
    final saved = await repo.save(draft());
    await FxDraftRepository.createSchema(db);
    expect((await repo.list()).length, 1);
    await db.transaction((txn) => FxDraftRepository.clearDrafts(txn));
    expect(await repo.list(), isEmpty);
    expect(await otherTables(db), before);
    expect((await repo.save(draft())).id!, greaterThan(saved.id!));
  });
}
