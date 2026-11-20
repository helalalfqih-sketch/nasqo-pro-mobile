import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/home_balance_groups.dart';

AccountRecord account(String id,
        {AccountCategory category = AccountCategory.clients,
        CurrencyCode currency = CurrencyCode.sar,
        double opening = 0,
        EntryDirection direction = EntryDirection.debit,
        bool cash = false}) =>
    AccountRecord(
        id: id,
        name: id,
        category: category,
        currency: currency,
        openingBalance: opening,
        openingDirection: direction,
        isCashAccount: cash);
LedgerEntryRecord entry(String id,
        {String accountId = 'a',
        double amount = 10,
        EntryDirection direction = EntryDirection.debit,
        LedgerKind kind = LedgerKind.voucher,
        CurrencyCode currency = CurrencyCode.sar,
        bool deleted = false,
        double rate = 1,
        PaymentMethod payment = PaymentMethod.credit}) =>
    LedgerEntryRecord(
        id: id,
        accountId: accountId,
        accountName: accountId,
        kind: kind,
        typeLabel: 'تركيبي',
        payment: payment,
        direction: direction,
        amount: amount,
        currency: currency,
        exchangeRate: rate,
        deleted: deleted,
        entryNumber: 1,
        entryDate: '2026-01-01');
HomeBalanceGroup clients(List<AccountRecord> a, List<LedgerEntryRecord> e,
        {CurrencyCode currency = CurrencyCode.sar}) =>
    computeHomeBalanceGroups(a, e, currency: currency)
        .firstWhere((g) => g.category == AccountCategory.clients);

void main() {
  test('six stable category buckets, empty neutral, immutable output', () {
    final result = computeHomeBalanceGroups([], [], currency: CurrencyCode.sar);
    expect(result.map((g) => g.category), AccountCategory.values);
    expect(result.every((g) => g.accountCount == 0 && g.balanceLabel == 'متزن'),
        true);
    expect(() => result.clear(), throwsUnsupportedError);
  });
  test('opening and opposite directions preserve web debit minus credit', () {
    final g = clients([
      account('a', opening: 100),
      account('b', opening: 40, direction: EntryDirection.credit)
    ], [
      entry('1', amount: 25),
      entry('2', accountId: 'b', amount: 5, direction: EntryDirection.credit)
    ]);
    expect(g.debitTotal, 125);
    expect(g.creditTotal, 45);
    expect(g.netDebitMinusCredit, 80);
    expect(g.balanceLabel, 'عليه');
    expect(g.accountCount, 2);
    final credit = clients(
        [account('a', opening: 20, direction: EntryDirection.credit)], []);
    expect(credit.netDebitMinusCredit, -20);
    expect(credit.magnitude, 20);
    expect(credit.balanceLabel, 'له');
  });
  test('deleted, quote, order and unknown account have no financial effect',
      () {
    final g = clients([
      account('a')
    ], [
      entry('1', deleted: true),
      entry('2', kind: LedgerKind.quote),
      entry('3', kind: LedgerKind.order),
      entry('4', accountId: 'missing'),
      entry('5',
          kind: LedgerKind.returnEntry,
          direction: EntryDirection.credit,
          amount: 7)
    ]);
    expect(g.debitTotal, 0);
    expect(g.creditTotal, 7);
  });
  test('filter entry currency independently from account; do not convert rates',
      () {
    final accounts = [
      account('a', currency: CurrencyCode.usd, opening: 100),
      account('b', opening: 20)
    ];
    final entries = [
      entry('1', amount: 7, rate: 1500),
      entry('2', accountId: 'b', currency: CurrencyCode.usd, amount: 3, rate: 4)
    ];
    final sar = clients(accounts, entries);
    final usd = clients(accounts, entries, currency: CurrencyCode.usd);
    expect(sar.debitTotal, 27);
    expect(usd.debitTotal, 103);
    expect(sar.accountCount, 2);
    expect(usd.accountCount, 2);
  });
  test('group balance does not apply account-summary cash washing', () {
    final g = clients(
        [account('a', cash: true)], [entry('1', payment: PaymentMethod.cash)]);
    expect(g.debitTotal, 10);
    expect(g.creditTotal, 0);
  });
  test('category isolation and unique account counts; no input mutation', () {
    final a = account('a');
    final accounts = [a, a, account('p', category: AccountCategory.purchases)];
    final entries = [entry('1'), entry('2', accountId: 'p', amount: 3)];
    final result =
        computeHomeBalanceGroups(accounts, entries, currency: CurrencyCode.sar);
    expect(
        result
            .firstWhere((g) => g.category == AccountCategory.clients)
            .accountCount,
        1);
    expect(
        result
            .firstWhere((g) => g.category == AccountCategory.purchases)
            .debitTotal,
        3);
    expect(accounts.length, 3);
    expect(entries.length, 2);
  });
  test(
      'display tolerance does not erase unrounded value; negative opening ignored',
      () {
    final g =
        clients([account('a', opening: -100)], [entry('1', amount: 0.004)]);
    expect(g.balanceLabel, 'متزن');
    expect(g.netDebitMinusCredit, 0.004);
  });
}
