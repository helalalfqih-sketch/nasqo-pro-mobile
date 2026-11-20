import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sale_facts.dart';
import 'package:nasqo_pro_erp/screens/original_sale_facts_view.dart';

SaleFacts facts({String id = 'sale-synthetic'}) => SaleFacts(
        entryId: id,
        currency: CurrencyCode.usd,
        preTaxTotal: 100.125,
        taxEnabled: true,
        appliedTaxRate: .15,
        taxAmount: 15.02,
        finalTotal: 115.145,
        lineCosts: const [
          SaleLineCostFact(position: 2, stockAverageCost: 7.123),
          SaleLineCostFact(position: 7)
        ]);

void main() {
  testWidgets(
      'shows original values without rounding or tax recomputation and distinct unknown cost',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: OriginalSaleFactsView(
            entryId: 'sale-synthetic',
            loadFacts: (id) async {
              calls++;
              expect(id, 'sale-synthetic');
              return facts();
            })));
    await tester.pumpAndSettle();
    expect(find.text('100.125 دولار'), findsOneWidget);
    expect(find.text('0.15'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('115.145 دولار'), 180,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(find.text('15.02 دولار'), findsOneWidget);
    expect(find.text('115.145 دولار'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('متوسط التكلفة التاريخي غير محفوظ؛ ليس صفراً.'), 180,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(find.text('البند 3 • الموضع الأصلي 2'), findsOneWidget);
    expect(
        find.text('متوسط التكلفة المحفوظ: 7.123 (دون تحويل)'), findsOneWidget);
    expect(find.text('متوسط التكلفة التاريخي غير محفوظ؛ ليس صفراً.'),
        findsOneWidget);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('legacy absent facts explicitly unknown with no zero substitute',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: OriginalSaleFactsView(
            entryId: 'legacy', loadFacts: (_) async => null)));
    await tester.pumpAndSettle();
    expect(find.textContaining('قد تكون الفاتورة قديمة'), findsOneWidget);
    expect(find.textContaining('لا تُستنتج القيم'), findsOneWidget);
    expect(find.text('مبلغ الضريبة المحفوظ'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('loading and failure are explicit and retry reads again',
      (tester) async {
    var calls = 0;
    final pending = Completer<SaleFacts?>();
    await tester.pumpWidget(MaterialApp(
        home: OriginalSaleFactsView(
            entryId: 'sale-synthetic',
            loadFacts: (_) {
              calls++;
              return calls == 1 ? pending.future : Future.value(facts());
            })));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('synthetic read failure'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('تعذر قراءة حقائق البيع المحلية'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('100.125 دولار'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong-entry facts are not presented as requested original',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: OriginalSaleFactsView(
            entryId: 'requested',
            loadFacts: (_) async => facts(id: 'other-entry'))));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('تعذر قراءة حقائق البيع المحلية'), findsOneWidget);
    expect(find.text('100.125 دولار'), findsNothing);
  });
}
