import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sales_return_draft.dart';
import 'package:nasqo_pro_erp/screens/sales_return_views.dart';

SalesReturnSource source({bool deleted = false}) => SalesReturnSource(
        entry: LedgerEntryRecord(
            id: 'sale-1',
            accountId: 'customer',
            accountName: 'عميل اصطناعي',
            kind: LedgerKind.invoice,
            typeLabel: 'ف.مبيعات نقدية',
            payment: PaymentMethod.cash,
            direction: EntryDirection.debit,
            amount: 115,
            currency: CurrencyCode.usd,
            entryNumber: 23,
            entryDate: '2026-01-02',
            deleted: deleted),
        lines: const [
          SavedSaleLine(
              entryId: 'sale-1',
              position: 2,
              itemId: 'same-item',
              itemName: 'بند أول',
              unit: 'حبة',
              quantity: 5,
              unitPrice: 10),
          SavedSaleLine(
              entryId: 'sale-1',
              position: 7,
              itemId: 'same-item',
              itemName: 'بند ثان',
              unit: 'حبة',
              quantity: 2,
              unitPrice: 25),
        ]);
SalesReturnDraft draft({int revision = 1}) => SalesReturnDraft(
        id: 1,
        revision: revision,
        sourceEntryId: 'sale-1',
        date: '2026-02-01',
        reason: 'سبب اختبار',
        accountId: 'customer',
        accountName: 'عميل اصطناعي',
        warehouseId: 'wh_1',
        currency: CurrencyCode.usd,
        lines: const [
          SalesReturnDraftLine(
              position: 7,
              itemId: 'same-item',
              itemName: 'بند ثان',
              unit: 'حبة',
              quantity: 1,
              sourceQuantity: 2,
              unitPrice: 25)
        ]);

Future<void> tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openCreate(WidgetTester tester, SalesReturnSave save,
    {List<SalesReturnSource>? sales}) async {
  await tester.pumpWidget(MaterialApp(
      home: SalesReturnDraftsView(
          loadDrafts: () async => [],
          loadDraft: (_) async => null,
          loadSales: () async => sales ?? [source()],
          saveDraft: save)));
  await tester.pumpAndSettle();
  await tap(tester, find.text('إنشاء مسودة مرتجع'));
}

Future<void> selectSource(WidgetTester tester) async {
  await tap(tester, find.byKey(const Key('return-source')));
  await tester.tap(find.text('#23 • عميل اصطناعي • دولار').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('failed draft list reload can retry without writes',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
      home: SalesReturnDraftsView(
        loadDrafts: () async {
          if (++loads == 1) throw StateError('fixture');
          return [draft()];
        },
        loadDraft: (_) async => null,
        loadSales: () async => [],
        saveDraft: (
                {id,
                revision = 0,
                required sourceEntryId,
                required date,
                required reason,
                required selections}) async =>
            throw StateError('unexpected write'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعذر تحميل المسودات. إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('مسودة #1'), findsOneWidget);
    expect(loads, 2);
  });

  testWidgets(
      'partial draft uses stable positions and awaits save without duplicates',
      (tester) async {
    final pending = Completer<SalesReturnDraft>();
    var calls = 0;
    List<SalesReturnSelection>? selected;
    await openCreate(tester, (
        {int? id,
        int revision = 0,
        required String sourceEntryId,
        required String date,
        required String reason,
        required List<SalesReturnSelection> selections}) {
      calls++;
      selected = selections;
      expect(sourceEntryId, 'sale-1');
      expect(date, '2026-02-28');
      return pending.future;
    });
    await selectSource(tester);
    await tester.enterText(find.byKey(const Key('return-date')), '٢٠٢٦-٠٢-٢٨');
    await tester.enterText(find.byKey(const Key('return-reason')), 'طلب جزئي');
    await tester.enterText(find.byKey(const Key('return-qty-2')), '٢٫٥');
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('return-save')), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(find.text('تقدير جزئي قبل الضريبة: 25.00 دولار'), findsOneWidget);
    await tester.tap(find.byKey(const Key('return-save')));
    await tester.pump();
    expect(calls, 1);
    expect(selected!.single.position, 2);
    expect(selected!.single.quantity, 2.5);
    expect(find.text('جارٍ حفظ المسودة…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('return-save')), warnIfMissed: false);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(SalesReturnDraftEditor), findsOneWidget);
    pending.complete(draft());
    await tester.pumpAndSettle();
    expect(find.byType(SalesReturnDraftEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and Back never save; ineligible sources are excluded',
      (tester) async {
    var calls = 0;
    Future<SalesReturnDraft> save(
        {int? id,
        int revision = 0,
        required String sourceEntryId,
        required String date,
        required String reason,
        required List<SalesReturnSelection> selections}) async {
      calls++;
      return draft();
    }

    await openCreate(tester, save, sales: [source(deleted: true)]);
    expect(find.textContaining('لا توجد فاتورة أصلية مؤهلة'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('return-save')))
            .onPressed,
        isNull);
    await tap(tester, find.text('إلغاء دون حفظ'));
    expect(calls, 0);
    await tap(tester, find.text('إنشاء مسودة مرتجع'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('edit retains revision/source and failed save retains quantities',
      (tester) async {
    var calls = 0;
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
        home: SalesReturnDraftsView(
            loadDrafts: () async {
              loads++;
              return [draft()];
            },
            loadDraft: (_) async => draft(),
            loadSales: () async => [source()],
            saveDraft: (
                {int? id,
                int revision = 0,
                required String sourceEntryId,
                required String date,
                required String reason,
                required List<SalesReturnSelection> selections}) async {
              calls++;
              expect(id, 1);
              expect(revision, 1);
              expect(sourceEntryId, 'sale-1');
              expect(selections.single.position, 7);
              expect(selections.single.quantity, 1);
              if (calls == 1) throw StateError('synthetic failure');
              return draft(revision: 2);
            })));
    await tester.pumpAndSettle();
    await tap(tester, find.text('مسودة #1 • عميل اصطناعي'));
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
                find.byKey(const Key('return-source')))
            .onChanged,
        isNull);
    await tap(tester, find.byKey(const Key('return-save')));
    expect(find.textContaining('لم يتم تأكيد حفظ المسودة'), findsOneWidget);
    expect(find.byType(SalesReturnDraftEditor), findsOneWidget);
    await tap(tester, find.byKey(const Key('return-save')));
    expect(calls, 2);
    expect(loads, 2);
    expect(find.byType(SalesReturnDraftEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero/excess quantities never save and layout fits narrow RTL',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await openCreate(tester, (
        {int? id,
        int revision = 0,
        required String sourceEntryId,
        required String date,
        required String reason,
        required List<SalesReturnSelection> selections}) async {
      calls++;
      return draft();
    });
    await selectSource(tester);
    await tester.enterText(find.byKey(const Key('return-reason')), 'اختبار');
    await tap(tester, find.byKey(const Key('return-save')));
    expect(find.textContaining('حدد كمية موجبة'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, 500));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('return-qty-2')), '٦');
    await tap(tester, find.byKey(const Key('return-save')));
    expect(calls, 0);
    expect(find.textContaining('راجع الفاتورة الأصلية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
