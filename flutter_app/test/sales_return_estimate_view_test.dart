import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sale_facts.dart';
import 'package:nasqo_pro_erp/models/sales_return_draft.dart';
import 'package:nasqo_pro_erp/screens/sales_return_views.dart';

SalesReturnDraft draft({double qty = 2, int position = 3}) => SalesReturnDraft(
        id: 7,
        revision: 1,
        sourceEntryId: 'sale',
        date: '2026-01-03',
        reason: 'اختبار',
        accountId: 'customer',
        accountName: 'عميل اصطناعي',
        warehouseId: 'wh',
        currency: CurrencyCode.usd,
        lines: [
          SalesReturnDraftLine(
              position: position,
              itemId: 'item',
              itemName: 'صنف',
              unit: 'حبة',
              quantity: qty,
              sourceQuantity: 10,
              unitPrice: 10)
        ]);
SalesReturnSource source() => SalesReturnSource(
        entry: const LedgerEntryRecord(
            id: 'sale',
            accountId: 'customer',
            accountName: 'عميل اصطناعي',
            kind: LedgerKind.invoice,
            typeLabel: 'ف.مبيعات نقدية',
            payment: PaymentMethod.cash,
            direction: EntryDirection.debit,
            amount: 115,
            currency: CurrencyCode.usd,
            entryNumber: 1,
            entryDate: '2026-01-01'),
        lines: const [
          SavedSaleLine(
              entryId: 'sale',
              position: 3,
              itemId: 'item',
              itemName: 'صنف',
              unit: 'حبة',
              quantity: 10,
              unitPrice: 10)
        ]);
SaleFacts facts() => SaleFacts(
    entryId: 'sale',
    currency: CurrencyCode.usd,
    preTaxTotal: 100,
    taxEnabled: true,
    appliedTaxRate: .15,
    taxAmount: 15,
    finalTotal: 115,
    lineCosts: [const SaleLineCostFact(position: 3)]);
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 150,
      scrollable: find
          .descendant(
              of: find.byType(ListView).last, matching: find.byType(Scrollable))
          .first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'saved partial estimate from list is read only and back leaves list unchanged',
      (tester) async {
    var writes = 0;
    var listReads = 0;
    var draftReads = 0;
    final original = draft();
    await tester.pumpWidget(MaterialApp(
        home: SalesReturnDraftsView(
            loadDrafts: () async {
              listReads++;
              return [original];
            },
            loadDraft: (_) async {
              draftReads++;
              return original;
            },
            loadSales: () async => [source()],
            loadFacts: (id) async {
              expect(id, 'sale');
              return facts();
            },
            saveDraft: (
                {int? id,
                int revision = 0,
                required String sourceEntryId,
                required String date,
                required String reason,
                required List<SalesReturnSelection> selections}) async {
              writes++;
              return original;
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('estimate-draft-7')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('return-estimate-total')));
    expect(find.text('قبل الضريبة: 20.00 دولار'), findsOneWidget);
    expect(find.text('الضريبة التقديرية: 3.00 دولار'), findsOneWidget);
    expect(find.text('الإجمالي التقديري: 23.00 دولار'), findsOneWidget);
    expect(find.textContaining('لا تجمع تقديرات المسودات'), findsOneWidget);
    await reveal(tester, find.text('رجوع دون تغيير'));
    await tester.tap(find.text('رجوع دون تغيير'));
    await tester.pumpAndSettle();
    expect(listReads, 1);
    expect(draftReads, 1);
    expect(writes, 0);
    expect(original.lines.single.quantity, 2);
    expect(find.text('مسودة #7 • عميل اصطناعي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full estimate uses stored original totals on narrow RTL layout',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: SalesReturnEstimateView(
            draft: draft(qty: 10),
            source: source(),
            loadFacts: (_) async => facts())));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('return-estimate-total')));
    expect(find.text('الضريبة التقديرية: 15.00 دولار'), findsOneWidget);
    expect(find.text('الإجمالي التقديري: 115.00 دولار'), findsOneWidget);
    expect(find.textContaining('يستخدم مبالغ البيع الأصلية المحفوظة'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy missing facts do not become zero tax', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SalesReturnEstimateView(
            draft: draft(), source: source(), loadFacts: (_) async => null)));
    await tester.pumpAndSettle();
    expect(find.textContaining('لا توجد حقائق ضريبية أصلية محفوظة'),
        findsOneWidget);
    expect(find.byKey(const Key('return-estimate-tax')), findsNothing);
  });

  testWidgets(
      'read failure retries; mismatched original positions never produce estimate',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: SalesReturnEstimateView(
            draft: draft(position: 99),
            source: source(),
            loadFacts: (_) async {
              reads++;
              if (reads == 1) throw StateError('synthetic read failure');
              return facts();
            })));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('تعذر قراءة حقائق البيع الأصلية'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.textContaining('التقدير غير متاح'), findsOneWidget);
    expect(find.byKey(const Key('return-estimate-total')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
