import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/home_directory_views.dart';
import 'package:nasqo_pro_erp/screens/home_account_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  late ErpController controller;
  setUp(() {
    controller = ErpController(autoInitDb: false);
    controller.accounts
      ..clear()
      ..addAll(const [
        AccountRecord(
            id: 'a',
            name: 'عميل ألف',
            category: AccountCategory.clients,
            codeNumber: 1201,
            currency: CurrencyCode.usd),
        AccountRecord(
            id: 'b',
            name: 'مورد باء',
            category: AccountCategory.purchases,
            codeNumber: 2101),
      ]);
    controller.ledger.clear();
    for (final deleted in [false, true]) {
      controller.ledger.add(LedgerEntryRecord(
          id: deleted ? 'old' : 'active',
          accountId: 'a',
          accountName: deleted ? 'محذوف قديم' : 'قيد نشط',
          kind: LedgerKind.voucher,
          typeLabel: 'سند',
          payment: PaymentMethod.credit,
          direction: EntryDirection.debit,
          amount: 10,
          entryNumber: deleted ? 2 : 1,
          entryDate: '2026-11-19',
          deleted: deleted));
    }
  });
  tearDown(() => controller.dispose());
  Future<void> start(WidgetTester tester, Widget view) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(body: view)));
  }

  testWidgets(
      'directory exposes metadata and searches by name and Arabic code digits',
      (tester) async {
    await start(tester, HomeChartOfAccountsView(controller: controller));
    expect(find.text('عميل ألف'), findsOneWidget);
    expect(find.textContaining('1201'), findsOneWidget);
    expect(find.textContaining('دولار'), findsOneWidget);
    expect(find.textContaining('العملاء'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '٢١٠١');
    await tester.pump();
    expect(find.text('مورد باء'), findsOneWidget);
    expect(find.text('عميل ألف'), findsNothing);
    await tester.enterText(find.byType(TextField), 'عميل');
    await tester.pump();
    expect(find.text('عميل ألف'), findsOneWidget);
    expect(find.text('مورد باء'), findsNothing);
    await tester.enterText(find.byType(TextField), 'لايوجد');
    await tester.pump();
    expect(find.text('لا توجد حسابات مطابقة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('directory opens real statement without changing state',
      (tester) async {
    final before = List.of(controller.ledger);
    await start(tester, HomeChartOfAccountsView(controller: controller));
    await tester.tap(find.text('عميل ألف'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<HomeAccountStatementView>(
                find.byType(HomeAccountStatementView))
            .accountId,
        'a');
    expect(controller.ledger, orderedEquals(before));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'trash exposes only deleted legacy records and has no mutation controls',
      (tester) async {
    final before = List.of(controller.ledger);
    await start(tester, HomeTrashView(controller: controller));
    expect(find.text('محذوف قديم'), findsOneWidget);
    expect(find.text('قيد نشط'), findsNothing);
    expect(find.textContaining('لا تشمل سجل إلغاء المستندات'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(controller.ledger, orderedEquals(before));
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty local collections have explicit empty states',
      (tester) async {
    controller.accounts.clear();
    controller.ledger.clear();
    await start(tester, HomeChartOfAccountsView(controller: controller));
    expect(find.text('لا توجد حسابات محلية'), findsOneWidget);
    await start(tester, HomeTrashView(controller: controller));
    expect(find.text('لا توجد قيود محذوفة قديمة'), findsOneWidget);
  });
}
