import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sale_tax_register.dart';
import 'package:nasqo_pro_erp/screens/sale_tax_register_view.dart';

SaleTaxRegister fixture() => SaleTaxRegister(rows: [], currencies: [
      const SaleTaxCurrencySummary(
          currency: CurrencyCode.sar,
          knownCount: 2,
          unknownCount: 3,
          preTaxTotal: 0.4,
          taxAmount: 0.06,
          finalTotal: 0.46),
      const SaleTaxCurrencySummary(
          currency: CurrencyCode.usd,
          knownCount: 1,
          unknownCount: 0,
          preTaxTotal: 100,
          taxAmount: 15,
          finalTotal: 115),
    ]);
Future<void> show(
    WidgetTester tester,
    Future<SaleTaxRegister> Function({String? from, String? through})
        load) async {
  await tester
      .pumpWidget(MaterialApp(home: SaleTaxRegisterView(loadRegister: load)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'stored tax and unknown records shown separately by currency, readonly RTL',
      (tester) async {
    await show(tester, ({from, through}) async => fixture());
    expect(find.text('الضريبة المحفوظة: 0.06 ريال'), findsOneWidget);
    expect(find.text('مبيعات قديمة أو غير موثقة ضريبياً: 3'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('الضريبة المحفوظة: 15.00 دولار'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('الضريبة المحفوظة: 15.00 دولار'), findsOneWidget);
    expect(find.textContaining('15.06'), findsNothing);
    expect(find.text('حفظ'), findsNothing);
    expect(Directionality.of(tester.element(find.byType(Scaffold))),
        TextDirection.rtl);
  });
  testWidgets('optional dates forwarded inclusively after applying',
      (tester) async {
    final calls = <List<String?>>[];
    await show(tester, ({from, through}) async {
      calls.add([from, through]);
      return SaleTaxRegister(rows: [], currencies: []);
    });
    expect(calls.single, [null, null]);
    await tester.enterText(find.byKey(const Key('tax-from')), '2026-01-01');
    await tester.enterText(find.byKey(const Key('tax-through')), '2026-01-01');
    await tester.tap(find.text('تطبيق الفترة'));
    await tester.pumpAndSettle();
    expect(calls.last, ['2026-01-01', '2026-01-01']);
    expect(
        find.text('لا توجد مبيعات محلية ضمن الفترة المحددة.'), findsOneWidget);
  });
  testWidgets('invalid and reversed dates do not request register',
      (tester) async {
    var calls = 0;
    await show(tester, ({from, through}) async {
      calls++;
      return fixture();
    });
    await tester.enterText(find.byKey(const Key('tax-from')), '2026-02-30');
    await tester.tap(find.text('تطبيق الفترة'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('أدخل تاريخاً صحيحاً YYYY-MM-DD'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tax-from')), '2026-03-01');
    await tester.enterText(find.byKey(const Key('tax-through')), '2026-02-01');
    await tester.tap(find.text('تطبيق الفترة'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('تاريخ البداية يجب ألا يتجاوز النهاية'), findsOneWidget);
  });
  testWidgets('error retry loads empty result without exposing exception',
      (tester) async {
    var calls = 0;
    await show(tester, ({from, through}) async {
      if (++calls == 1) throw Exception('private path');
      return SaleTaxRegister(rows: [], currencies: []);
    });
    expect(find.textContaining('تعذر تحميل'), findsOneWidget);
    expect(find.textContaining('private path'), findsNothing);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
        find.text('لا توجد مبيعات محلية ضمن الفترة المحددة.'), findsOneWidget);
  });
  testWidgets('unknown-only and invalid headers not misrepresented as empty',
      (tester) async {
    await show(
        tester,
        ({from, through}) async => SaleTaxRegister(
            rows: [],
            invalidHeaderCount: 2,
            currencies: [
              const SaleTaxCurrencySummary(
                  currency: CurrencyCode.sar,
                  knownCount: 0,
                  unknownCount: 4,
                  preTaxTotal: 0,
                  taxAmount: 0,
                  finalTotal: 0)
            ]));
    expect(
        find.text('رؤوس غير صالحة مستبعدة من الإجماليات: 2'), findsOneWidget);
    expect(find.text('لا توجد مبيعات محلية ضمن الفترة المحددة.'), findsNothing);
    expect(find.text('مبيعات قديمة أو غير موثقة ضريبياً: 4'), findsOneWidget);
    expect(find.textContaining('0.00 ريال'), findsNothing);
  });
}
