import 'package:nasqo_pro_erp/models/nonposting_document.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/nonposting_document_views.dart';

NonpostingDocument document(
        {int? id = 1,
        int revision = 1,
        String notes = '',
        NonpostingDocumentType type = NonpostingDocumentType.quote}) =>
    NonpostingDocument(
        id: id,
        revision: revision,
        type: type,
        date: '2026-01-02',
        currency: CurrencyCode.usd,
        customerName: 'عميل اصطناعي',
        notes: notes,
        lines: [
          const NonpostingLine(
              description: 'خدمة اختبار', quantity: 2, unitPrice: 5)
        ]);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
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
  await tester.pump();
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('document-customer')), 'عميل جديد');
  await tester.enterText(find.byKey(const Key('document-date')), '٢٠٢٦-٠٢-٢٨');
  await tester.ensureVisible(find.byKey(const Key('line-description-0')));
  await tester.enterText(
      find.byKey(const Key('line-description-0')), 'بند تجريبي');
  await tester.enterText(find.byKey(const Key('line-quantity-0')), '٢٫٥');
  await tester.enterText(find.byKey(const Key('line-price-0')), '٤');
}

Widget listView(
        {required NonpostingSave save,
        bool create = false,
        Future<List<NonpostingDocument>> Function()? load,
        Future<NonpostingDocument?> Function(int)? get}) =>
    MaterialApp(
        home: NonpostingDocumentsView(
            type: NonpostingDocumentType.quote,
            initialCurrency: CurrencyCode.usd,
            createOnOpen: create,
            loadDocuments: load ?? () async => [],
            loadDocument: get ?? (_) async => null,
            saveDocument: save));

void main() {
  testWidgets(
      'createOnOpen, Arabic input, commit awaited and duplicate taps blocked',
      (tester) async {
    var calls = 0;
    NonpostingDocument? input;
    final pending = Completer<NonpostingDocument>();
    await tester.pumpWidget(listView(
        create: true,
        save: (d) {
          calls++;
          input = d;
          return pending.future;
        }));
    await tester.pumpAndSettle();
    await fill(tester);
    await tapVisible(tester, find.text('إضافة بند'));
    await tapVisible(tester, find.byKey(const Key('remove-line-1')));
    await tapVisible(tester, find.byKey(const Key('document-save')));
    expect(calls, 1);
    expect(input!.date, '2026-02-28');
    expect(input!.lines.single.quantity, 2.5);
    expect(input!.total, 10);
    expect(input!.currency, CurrencyCode.usd);
    expect(find.text('جارٍ الحفظ…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('document-save')),
        warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(NonpostingDocumentEditor), findsOneWidget);
    pending.complete(document());
    await tester.pumpAndSettle();
    expect(find.byType(NonpostingDocumentEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and system back never write', (tester) async {
    var calls = 0;
    await tester.pumpWidget(listView(
        create: true,
        save: (d) async {
          calls++;
          return d;
        }));
    await tester.pumpAndSettle();
    await fill(tester);
    await tapVisible(tester, find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tapVisible(tester, find.text('إنشاء عرض سعر'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(NonpostingDocumentEditor), findsNothing);
  });

  testWidgets('save failure stays in editor with values and explicit error',
      (tester) async {
    await tester.pumpWidget(listView(
        create: true,
        save: (_) async => throw StateError('synthetic failure')));
    await tester.pumpAndSettle();
    await fill(tester);
    await tapVisible(tester, find.byKey(const Key('document-save')));
    await tester.pumpAndSettle();
    expect(find.byType(NonpostingDocumentEditor), findsOneWidget);
    expect(find.textContaining('لم يتم تأكيد الحفظ'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, 1800));
    await tester.pumpAndSettle();
    final customer = tester
        .widget<TextFormField>(find.byKey(const Key('document-customer')));
    expect(customer.controller!.text, 'عميل جديد');
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit preserves id/revision, details update and list reloads',
      (tester) async {
    var stored = document();
    var loads = 0;
    NonpostingDocument? input;
    await tester.pumpWidget(listView(
        load: () async {
          loads++;
          return [stored];
        },
        get: (_) async => stored,
        save: (d) async {
          input = d;
          stored = NonpostingDocument(
              id: d.id,
              revision: d.revision + 1,
              type: d.type,
              date: d.date,
              currency: d.currency,
              customerName: d.customerName,
              notes: d.notes,
              lines: d.lines);
          return stored;
        }));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('عرض سعر #1'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('تعديل المستند'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('document-customer')), 'عميل معدل');
    await tapVisible(tester, find.byKey(const Key('document-save')));
    await tester.pumpAndSettle();
    expect(input!.id, 1);
    expect(input!.revision, 1);
    expect(find.text('عميل معدل'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.textContaining('عميل معدل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid date and quantity do not save; responsive RTL',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(listView(
        create: true,
        save: (d) async {
          calls++;
          return d;
        }));
    await tester.pumpAndSettle();
    await fill(tester);
    await tester.enterText(
        find.byKey(const Key('document-date')), '٢٠٢٦-٠٢-٣٠');
    await tester.enterText(find.byKey(const Key('line-quantity-0')), '٠');
    await tapVisible(tester, find.byKey(const Key('document-save')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('أدخل تاريخاً صحيحاً YYYY-MM-DD'), findsOneWidget);
    expect(find.text('أدخل كمية أكبر من صفر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
