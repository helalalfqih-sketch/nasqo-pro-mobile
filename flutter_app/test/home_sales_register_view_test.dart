import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/home_sales_register_view.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

LedgerEntryRecord sale(String id,
        {String type = 'ف.مبيعات نقدية',
        bool deleted = false,
        CurrencyCode currency = CurrencyCode.usd}) =>
    LedgerEntryRecord(
        id: id,
        accountId: 'customer',
        accountName: 'عميل $id',
        kind: LedgerKind.invoice,
        typeLabel: type,
        payment: PaymentMethod.cash,
        direction: EntryDirection.debit,
        amount: 115.125,
        currency: currency,
        documentNumber: 'DOC-$id',
        entryNumber: 1,
        entryDate: '2026-11-19',
        deleted: deleted,
        details: 'صنف وهمي | 100 × 20');

void main() {
  late ErpController controller;
  setUp(() {
    controller = ErpController(autoInitDb: false);
    controller.ledger
      ..clear()
      ..addAll([
        sale('saved'),
        sale('legacy', currency: CurrencyCode.sar),
        sale('deleted', deleted: true),
        sale('unknown', type: 'فاتورة مستوردة')
      ]);
    controller.saleLines
      ..clear()
      ..addAll(const [
        SavedSaleLine(
            entryId: 'saved',
            position: 7,
            itemId: 'same',
            itemName: 'ثاني محفوظ',
            unit: 'علبة',
            quantity: 2,
            unitPrice: 25),
        SavedSaleLine(
            entryId: 'saved',
            position: 2,
            itemId: 'same',
            itemName: 'أول محفوظ',
            unit: 'حبة',
            quantity: 5,
            unitPrice: 10),
      ]);
  });
  tearDown(() => controller.dispose());
  Future<void> start(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: HomeSalesRegisterView(controller: controller)));
  }

  testWidgets(
      'register filters active known sales and searches documents and customers',
      (tester) async {
    await start(tester);
    expect(find.text('عميل saved'), findsOneWidget);
    expect(find.text('عميل legacy'), findsOneWidget);
    expect(find.text('عميل deleted'), findsNothing);
    expect(find.text('عميل unknown'), findsNothing);
    expect(find.text('115.125 دولار'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'DOC-saved');
    await tester.pump();
    expect(find.text('عميل legacy'), findsNothing);
    await tester.enterText(find.byType(TextField), 'legacy');
    await tester.pump();
    expect(find.text('عميل legacy'), findsOneWidget);
    expect(find.text('عميل saved'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('saved lines keep stable positions and do not mutate state',
      (tester) async {
    final before = List.of(controller.saleLines);
    final ledgerBefore = List.of(controller.ledger);
    await start(tester);
    await tester.tap(find.byKey(const ValueKey('sales-entry-saved')));
    await tester.pumpAndSettle();
    expect(find.text('أول محفوظ'), findsOneWidget);
    expect(find.byKey(const ValueKey('invoice-pdf-saved')), findsOneWidget);
    expect(find.text('ثاني محفوظ'), findsOneWidget);
    expect(tester.getTopLeft(find.text('أول محفوظ')).dy,
        lessThan(tester.getTopLeft(find.text('ثاني محفوظ')).dy));
    expect(find.text('الموضع الأصلي: 2'), findsOneWidget);
    expect(find.text('الموضع الأصلي: 7'), findsOneWidget);
    expect(find.textContaining('صنف وهمي'), findsNothing);
    expect(controller.saleLines, orderedEquals(before));
    expect(controller.ledger, orderedEquals(ledgerBefore));
    expect(tester.takeException(), isNull);
  });
  testWidgets('legacy missing lines explicitly remain unknown', (tester) async {
    await start(tester);
    await tester.tap(find.byKey(const ValueKey('sales-entry-legacy')));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'تفاصيل الأصناف غير متاحة لهذا المستند القديم؛ لا تُستنتج من الملاحظات.'),
        findsOneWidget);
    expect(find.textContaining('صنف وهمي'), findsNothing);
    expect(find.text('115.125 ريال'), findsOneWidget);
    expect(find.text('تعديل'), findsNothing);
    expect(find.text('حذف'), findsNothing);
  });
  testWidgets('no matching sales has honest empty state', (tester) async {
    controller.ledger.clear();
    await start(tester);
    expect(find.text('لا توجد فواتير مبيعات محلية مطابقة'), findsOneWidget);
  });
}
