import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/home_account_views.dart';
import 'package:nasqo_pro_erp/services/web_backup.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  testWidgets(
      'supplier currency filter includes both sides of live period entries',
      (tester) async {
    final controller = ErpController(autoInitDb: false);
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(410, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller.accounts.clear();
    for (final id in [
      'direct',
      'counterpart',
      'denominated',
      'deleted',
      'old',
      'other'
    ]) {
      controller.accounts.add(AccountRecord(
          id: id,
          name: 'QA-$id',
          category: AccountCategory.purchases,
          currency: id == 'denominated' ? CurrencyCode.usd : CurrencyCode.sar));
    }
    final today = DateTime.now().toIso8601String().substring(0, 10);
    LedgerEntryRecord invoice(String id,
            {bool deleted = false,
            String? date,
            CurrencyCode currency = CurrencyCode.usd}) =>
        LedgerEntryRecord(
            id: id,
            accountId: id,
            accountName: 'QA-$id',
            kind: LedgerKind.invoice,
            typeLabel: 'فاتورة شراء',
            payment: PaymentMethod.credit,
            direction: EntryDirection.credit,
            amount: 17.25,
            currency: currency,
            deleted: deleted,
            entryDate: date ?? today,
            entryNumber: 1);
    controller.ledger
      ..clear()
      ..addAll([
        invoice('direct'),
        invoice('deleted', deleted: true),
        invoice('old', date: '2001-01-01'),
        invoice('other', currency: CurrencyCode.sar)
      ]);
    controller.restoredGroups = RestoredGroups.fromJson({
      'ledger': [
        {'id': 'direct', 'counterpartAccountId': 'counterpart'}
      ]
    });
    await tester.pumpWidget(MaterialApp(
        home: HomeAccountsView(
            controller: controller, category: AccountCategory.purchases)));
    await tester.tap(find.byType(DropdownButton<CurrencyCode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دولار').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('فلاتر الحسابات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهري'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    for (final id in ['direct', 'counterpart', 'denominated']) {
      expect(find.text('QA-$id'), findsOneWidget);
    }
    for (final id in ['deleted', 'old', 'other']) {
      expect(find.text('QA-$id'), findsNothing);
    }
    await tester.tap(find.text('الكل'));
    await tester.pumpAndSettle();
    expect(find.text('QA-old'), findsOneWidget);
    expect(find.text('QA-deleted'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('QA-other'), findsOneWidget);
    expect(controller.ledger.where((e) => e.deleted).length, 1);
    expect(controller.ledger.length, 4);
    expect(tester.takeException(), isNull);
  });
}
