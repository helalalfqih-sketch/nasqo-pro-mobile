import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/dashboard_screen.dart';
import 'package:nasqo_pro_erp/services/web_backup.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

LedgerEntryRecord _entry(String id, CurrencyCode currency, double amount) =>
    LedgerEntryRecord(
      id: id,
      accountId: 'supplier-test',
      accountName: 'مورد اصطناعي',
      kind: LedgerKind.voucher,
      typeLabel: 'سند تجريبي',
      payment: PaymentMethod.credit,
      direction: EntryDirection.debit,
      amount: amount,
      currency: currency,
      exchangeRate: 9,
      entryNumber: 1,
      entryDate: '2026-01-01',
    );

void main() {
  testWidgets('home balance shows per-currency amounts and opens member detail',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 667);
    final controller = ErpController(autoInitDb: false);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      controller.dispose();
    });
    controller.accounts
      ..clear()
      ..add(const AccountRecord(
        id: 'supplier-test',
        name: 'مورد اصطناعي',
        category: AccountCategory.purchases,
        openingBalance: 100,
        openingDirection: EntryDirection.credit,
      ));
    controller.ledger
      ..clear()
      ..addAll([
        _entry('sar', CurrencyCode.sar, 40),
        _entry('usd', CurrencyCode.usd, 25),
      ]);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: GroupBalancesPanel(controller: controller)),
      ),
    ));
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('60-'), findsOneWidget);
    final filter = find.byKey(const ValueKey('balance-currency-purchases'));
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الكل').last);
    await tester.pumpAndSettle();
    expect(find.text('60- · ريال'), findsOneWidget);
    expect(find.text('25 · دولار'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('balance-group-purchases')));
    await tester.pumpAndSettle();
    expect(find.text('حسابات المشتريات'), findsOneWidget);
    expect(find.text('مورد اصطناعي'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('حسابات المشتريات'), findsNothing);
    expect(controller.ledger, hasLength(2));
    expect(controller.accounts.single.openingBalance, 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restored group name and balance open only its own accounts',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = ErpController(autoInitDb: false);
    addTearDown(controller.dispose);
    controller.accounts
      ..clear()
      ..addAll(const [
        AccountRecord(id: 'north', name: 'عميل الشمال', category: AccountCategory.clients,
            currency: CurrencyCode.usd, openingBalance: 25, openingDirection: EntryDirection.debit),
        AccountRecord(id: 'south', name: 'عميل الجنوب', category: AccountCategory.clients),
      ]);
    controller.ledger.clear();
    controller.restoredGroups = RestoredGroups.fromJson({
      'accountGroups': [
        {'id': 41, 'name': 'فرع الشمال'},
        {'id': 52, 'name': 'فرع الجنوب'},
      ],
      'accounts': [
        {'id': 'north', 'groupId': 41},
        {'id': 'south', 'groupId': 52},
      ],
    });
    await tester.pumpWidget(MaterialApp(home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: GroupBalancesPanel(controller: controller)),
    )));
    await tester.tap(find.byType(DropdownButton<CurrencyCode>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('دولار').last);
    await tester.pumpAndSettle();
    for (final label in ['فرع الشمال', '25']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('عميل الشمال'), findsOneWidget);
      expect(find.text('عميل الجنوب'), findsNothing);
      expect(find.text('25.00 دولار'), findsOneWidget);
      await tester.tap(find.text('عميل الشمال'));
      await tester.pumpAndSettle();
      expect(find.text('كشف حساب عميل الشمال'), findsOneWidget);
      expect(find.text('الرصيد الختامي: 25.00 دولار'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    expect(controller.ledger, isEmpty);
    expect(tester.takeException(), isNull);
  });

}
