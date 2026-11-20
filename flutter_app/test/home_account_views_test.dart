import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/home_account_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

LedgerEntryRecord entry(String id,
        {double amount = 10,
        CurrencyCode currency = CurrencyCode.sar,
        bool deleted = false,
        LedgerKind kind = LedgerKind.voucher,
        String accountId = 'customer',
        EntryDirection direction = EntryDirection.debit,
        int number = 1}) =>
    LedgerEntryRecord(
        id: id,
        accountId: accountId,
        accountName: 'عميل الاختبار',
        kind: kind,
        typeLabel: 'سند',
        payment: PaymentMethod.credit,
        direction: direction,
        amount: amount,
        currency: currency,
        deleted: deleted,
        entryNumber: number,
        entryDate: '2026-01-01');

const customer = AccountRecord(
    id: 'customer',
    name: 'عميل الاختبار',
    category: AccountCategory.clients,
    openingBalance: 50,
    openingDirection: EntryDirection.debit);

void main() {
  test('statement isolates currency/account and excludes non-posted records',
      () {
    final ledger = [
      entry('b', amount: 20, number: 2),
      entry('a', amount: 5, direction: EntryDirection.credit),
      entry('usd', amount: 1000, currency: CurrencyCode.usd),
      entry('deleted', deleted: true),
      entry('quote', kind: LedgerKind.quote),
      entry('order', kind: LedgerKind.order),
      entry('other', accountId: 'other')
    ];
    final s = LocalAccountStatement(customer, ledger, CurrencyCode.sar);
    expect(s.entries.map((e) => e.id), ['a', 'b']);
    expect(s.opening, 50);
    expect(s.debit, 20);
    expect(s.credit, 5);
    expect(s.closing, 65);
    final usd = LocalAccountStatement(customer, ledger, CurrencyCode.usd);
    expect(usd.opening, 0);
    expect(usd.closing, 1000);
    expect(ledger.first.id, 'b');
    expect(() => s.entries.clear(), throwsUnsupportedError);
  });

  testWidgets('customer list opens statement and cashboxes only use cash flag',
      (tester) async {
    final controller = ErpController(autoInitDb: false);
    addTearDown(controller.dispose);
    controller.accounts
      ..clear()
      ..addAll([
        customer,
        const AccountRecord(
            id: 'cash',
            name: 'صندوق الاختبار',
            category: AccountCategory.transfers,
            isCashAccount: true)
      ]);
    controller.ledger
      ..clear()
      ..add(entry('one'));
    await tester.pumpWidget(
        MaterialApp(home: HomeAccountsView(controller: controller)));
    expect(find.text('عميل الاختبار'), findsOneWidget);
    expect(find.text('صندوق الاختبار'), findsNothing);
    await tester.tap(find.text('عميل الاختبار'));
    await tester.pumpAndSettle();
    expect(find.text('كشف حساب عميل الاختبار'), findsOneWidget);
    expect(find.text('الرصيد الختامي: 60.00 ريال'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
        key: const ValueKey('cash-home'),
        home: HomeCashboxesView(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('صندوق الاختبار'), findsOneWidget);
    expect(find.text('عميل الاختبار'), findsNothing);
    expect(controller.ledger.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing account is explicit and narrow screen does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ErpController(autoInitDb: false);
    addTearDown(controller.dispose);
    controller.accounts.clear();
    controller.ledger.clear();
    await tester.pumpWidget(MaterialApp(
        home: HomeAccountStatementView(
            controller: controller, accountId: 'missing')));
    expect(find.text('الحساب غير موجود في الدفتر المحلي.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
