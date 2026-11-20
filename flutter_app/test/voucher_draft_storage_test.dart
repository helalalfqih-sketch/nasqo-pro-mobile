import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/voucher_draft.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/services/voucher_draft_repository.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

VoucherDraft draft(
        {int? id,
        int revision = 0,
        VoucherDraftType type = VoucherDraftType.receipt,
        String party = 'party',
        String cash = 'cash',
        CurrencyCode currency = CurrencyCode.usd,
        double amount = 1.23456789,
        String date = '2026-01-02'}) =>
    VoucherDraft(
        id: id,
        revision: revision,
        type: type,
        date: date,
        partyAccountId: party,
        cashAccountId: cash,
        currency: currency,
        amount: amount,
        note: 'تركيبي');
Future<Map<String, Object?>> financial(Database db) async => {
      for (final t in [
        'accounts',
        'ledger_entries',
        'inventory_items',
        'warehouses',
        'sale_lines',
        'erp_state',
        'sale_facts',
        'sale_line_cost_facts',
        'nonposting_documents',
        'nonposting_lines',
        'sales_return_drafts',
        'sales_return_draft_lines'
      ])
        t: await db.query(t)
    };
void main() {
  late Directory dir;
  late LocalDatabase store;
  late VoucherDraftRepository repo;
  late Database db;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('voucher-draft-synthetic-');
    store = LocalDatabase.withFactory(
        createDatabaseFactoryFfi(ffiInit: _ffi), '${dir.path}/test.db');
    await store.saveSnapshot(
        accounts: [
          const AccountRecord(
              id: 'party',
              name: 'party',
              category: AccountCategory.clients,
              currency: CurrencyCode.usd),
          const AccountRecord(
              id: 'cash',
              name: 'cash',
              category: AccountCategory.transfers,
              currency: CurrencyCode.usd,
              isCashAccount: true),
          const AccountRecord(
              id: 'cash2',
              name: 'cash2',
              category: AccountCategory.transfers,
              currency: CurrencyCode.usd,
              isCashAccount: true),
          const AccountRecord(
              id: 'sar',
              name: 'sar',
              category: AccountCategory.clients,
              currency: CurrencyCode.sar)
        ],
        ledger: [],
        warehouses: [],
        inventory: [],
        saleLines: [],
        companyName: 'synthetic',
        isDarkMode: false,
        nextEntryNumber: 77);
    db = await store.database;
    await VoucherDraftRepository.createSchema(db);
    repo = VoucherDraftRepository(store);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test(
      'v5 upgrade creates only the voucher table and preserves financial state',
      () async {
    final before = await financial(db);
    await db.execute('DROP TABLE fx_drafts');
    await db.execute('DROP TABLE simple_journal_drafts');
    await db.execute('DROP TABLE cash_transfer_drafts');
    await db.execute('DROP TABLE voucher_drafts');
    await db.setVersion(5);
    await store.close();
    final upgraded = await store.database;
    expect(await upgraded.getVersion(), 9);
    expect(await financial(upgraded), before);
    expect(await repo.list(), isEmpty);
    expect((await repo.save(draft())).id, isNotNull);
    expect(await financial(upgraded), before);
  });

  test(
      'create/read/edit preserve exact amount and all financial records; reopen',
      () async {
    final before = await financial(db);
    final receipt = await repo.save(draft());
    final payment = await repo.save(draft(type: VoucherDraftType.payment));
    expect(receipt.id, isNot(payment.id));
    expect(receipt.revision, 1);
    expect(receipt.amount, 1.23456789);
    final edit =
        await repo.save(draft(id: receipt.id, revision: 1, amount: 2.3456789));
    expect(edit.id, receipt.id);
    expect(edit.revision, 2);
    expect((await repo.list(type: VoucherDraftType.receipt)).single.amount,
        2.3456789);
    expect((await repo.list(type: VoucherDraftType.payment)).single.id,
        payment.id);
    expect(await financial(db), before);
    await store.close();
    expect((await repo.get(receipt.id!))!.amount, 2.3456789);
  });
  test('stale/cross-type updates rejected and failed SQL update stays atomic',
      () async {
    final saved = await repo.save(draft());
    final before = await financial(db);
    await expectLater(
        repo.save(
            draft(id: saved.id, revision: 1, type: VoucherDraftType.payment)),
        throwsStateError);
    await db.execute(
        "CREATE TRIGGER fail_voucher BEFORE UPDATE ON voucher_drafts BEGIN SELECT RAISE(ABORT,'synthetic'); END");
    await expectLater(repo.save(draft(id: saved.id, revision: 1, amount: 8)),
        throwsA(isA<DatabaseException>()));
    expect((await repo.get(saved.id!))!.amount, saved.amount);
    expect((await repo.get(saved.id!))!.revision, 1);
    await db.execute('DROP TRIGGER fail_voucher');
    await repo.save(draft(id: saved.id, revision: 1, amount: 3));
    await expectLater(
        repo.save(draft(id: saved.id, revision: 1)), throwsStateError);
    expect(await financial(db), before);
  });
  test('reject nonexistent, same, noncash cash account, cash party and FX',
      () async {
    for (final d in [
      draft(party: 'missing'),
      draft(cash: 'missing'),
      draft(party: 'cash'),
      draft(cash: 'party'),
      draft(party: 'cash2'),
      draft(party: 'sar'),
      draft(currency: CurrencyCode.sar)
    ]) {
      await expectLater(repo.save(d), throwsA(anything));
    }
    expect(await repo.list(), isEmpty);
  });
  test(
      'date and positive finite amount checks, no rounding or invented defaults',
      () async {
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      await expectLater(repo.save(draft(amount: value)), throwsArgumentError);
    }
    for (final date in ['', '2026-02-30', '2026-1-2']) {
      await expectLater(repo.save(draft(date: date)), throwsArgumentError);
    }
    expect(await repo.list(), isEmpty);
  });
  test('schema additive and clear helper only removes drafts', () async {
    final before = await financial(db);
    await repo.save(draft());
    await VoucherDraftRepository.createSchema(db);
    expect((await repo.list()).length, 1);
    await db.transaction((txn) => VoucherDraftRepository.clearDrafts(txn));
    expect(await repo.list(), isEmpty);
    expect(await financial(db), before);
  });
}
