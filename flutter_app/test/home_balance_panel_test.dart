import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/dashboard_screen.dart';
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
    expect(find.text('60 له'), findsOneWidget);
    final filter = find.byKey(const ValueKey('balance-currency-purchases'));
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الكل').last);
    await tester.pumpAndSettle();
    expect(find.text('60 له · ريال'), findsOneWidget);
    expect(find.text('25 عليه · دولار'), findsOneWidget);

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
}
