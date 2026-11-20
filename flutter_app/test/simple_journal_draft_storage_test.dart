import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/simple_journal_draft.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/services/simple_journal_draft_repository.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

SimpleJournalDraft draft(
        {int? id,
        int revision = 0,
        String source = 'a',
        String destination = 'b',
        CurrencyCode currency = CurrencyCode.usd,
        double amount = 1.23456789,
        String date = '2026-01-02'}) =>
    SimpleJournalDraft(
        id: id,
        revision: revision,
        date: date,
        debitAccountId: source,
        creditAccountId: destination,
        currency: currency,
        amount: amount,
        note: 'synthetic');
Future<Map<String, Object?>> unchangedTables(Database db) async {
  final names = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ('simple_journal_drafts','sqlite_sequence') ORDER BY name");
  return {
    for (final n in names)
      n['name'] as String: await db.query(n['name'] as String)
  };
}

void main() {
  late Directory dir;
  late LocalDatabase store;
  late SimpleJournalDraftRepository repo;
  late Database db;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('journal-draft-synthetic-');
    store = LocalDatabase.withFactory(
        createDatabaseFactoryFfi(ffiInit: _ffi), '${dir.path}/test.db');
    await store.saveSnapshot(
        accounts: [
          const AccountRecord(
              id: 'a',
              name: 'cashA',
              category: AccountCategory.transfers,
              currency: CurrencyCode.usd,
              isCashAccount: true,
              openingBalance: 5),
          const AccountRecord(
              id: 'b',
              name: 'cashB',
              category: AccountCategory.transfers,
              currency: CurrencyCode.usd,
              isCashAccount: true,
              openingBalance: 9),
          const AccountRecord(
              id: 'party',
              name: 'party',
              category: AccountCategory.clients,
              currency: CurrencyCode.usd),
          const AccountRecord(
              id: 'sar',
              name: 'cashSAR',
              category: AccountCategory.transfers,
              currency: CurrencyCode.sar,
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
    await SimpleJournalDraftRepository.createSchema(db);
    repo = SimpleJournalDraftRepository(store);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test('v7 upgrade only adds a draft table and preserves other records',
      () async {
    final before = await unchangedTables(db);
    await db.execute('DROP TABLE fx_drafts');
    await db.execute('DROP TABLE simple_journal_drafts');
    await db.setVersion(7);
    await store.close();
    final upgraded = await store.database;
    expect(await upgraded.getVersion(), 9);
    expect(await unchangedTables(upgraded), before);
    expect(await repo.list(), isEmpty);
    expect((await repo.save(draft())).id, isNotNull);
    expect(await unchangedTables(upgraded), before);
  });

  test(
      'stable create/edit/reopen preserves precision with zero effects outside draft table',
      () async {
    final before = await unchangedTables(db);
    final a = await repo.save(draft(source: 'party'));
    final b = await repo.save(draft(source: 'b', destination: 'a'));
    expect(a.id, isNot(b.id));
    expect(a.amount, 1.23456789);
    expect(a.revision, 1);
    final edited = await repo.save(
        draft(id: a.id, revision: 1, source: 'party', amount: 9.87654321));
    expect(edited.id, a.id);
    expect(edited.revision, 2);
    expect((await repo.list()).length, 2);
    expect(await unchangedTables(db), before);
    await store.close();
    expect((await repo.get(a.id!))!.amount, 9.87654321);
    expect((await repo.get(a.id!))!.debitAccountId, 'party');
  });
  test(
      'atomic failure and stale revisions cannot modify draft or financial tables',
      () async {
    final saved = await repo.save(draft());
    final before = await unchangedTables(db);
    await db.execute(
        "CREATE TRIGGER reject_transfer BEFORE UPDATE ON simple_journal_drafts BEGIN SELECT RAISE(ABORT,'synthetic'); END");
    await expectLater(repo.save(draft(id: saved.id, revision: 1, amount: 8)),
        throwsA(isA<DatabaseException>()));
    expect((await repo.get(saved.id!))!.revision, 1);
    expect((await repo.get(saved.id!))!.amount, saved.amount);
    await db.execute('DROP TRIGGER reject_transfer');
    await repo.save(draft(id: saved.id, revision: 1, amount: 7));
    await expectLater(
        repo.save(draft(id: saved.id, revision: 1)), throwsStateError);
    expect(await unchangedTables(db), before);
  });
  test('reject same, unknown and differing currency; revalidate saved accounts',
      () async {
    for (final d in [
      draft(destination: 'a'),
      draft(source: 'missing'),
      draft(destination: 'sar'),
      draft(currency: CurrencyCode.sar)
    ]) {
      await expectLater(repo.save(d), throwsA(anything));
    }
    expect(await repo.list(), isEmpty);
    final saved = await repo.save(draft());
    await db.update('accounts', {'currency': 'sar'},
        where: 'id = ?', whereArgs: ['b']);
    await expectLater(
        repo.save(draft(id: saved.id, revision: 1)), throwsStateError);
    expect((await repo.get(saved.id!))!.revision, 1);
  });
  test('invalid dates/amounts/ids reject before persistence', () async {
    for (final v in [0.0, -1.0, double.nan, double.infinity]) {
      await expectLater(repo.save(draft(amount: v)), throwsArgumentError);
    }
    for (final date in ['', '2026-02-30', '2026-1-2']) {
      await expectLater(repo.save(draft(date: date)), throwsArgumentError);
    }
    await expectLater(
        repo.save(draft(id: 1, revision: 0)), throwsArgumentError);
    expect(await repo.list(), isEmpty);
  });
  test('schema repeat and clear helper affect only drafts; IDs not reused',
      () async {
    final before = await unchangedTables(db);
    final saved = await repo.save(draft());
    await SimpleJournalDraftRepository.createSchema(db);
    expect((await repo.list()).length, 1);
    await db
        .transaction((txn) => SimpleJournalDraftRepository.clearDrafts(txn));
    expect(await repo.list(), isEmpty);
    expect(await unchangedTables(db), before);
    expect((await repo.save(draft())).id!, greaterThan(saved.id!));
  });
}
