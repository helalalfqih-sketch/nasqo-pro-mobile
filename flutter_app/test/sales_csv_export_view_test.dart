import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/sales_csv_export_view.dart';

const sale = LedgerEntryRecord(
    id: 'synthetic',
    accountId: 'a',
    accountName: 'عميل اصطناعي',
    kind: LedgerKind.invoice,
    typeLabel: 'ف.مبيعات نقدية',
    payment: PaymentMethod.cash,
    direction: EntryDirection.debit,
    amount: 125.5,
    entryNumber: 1,
    entryDate: '2026-11-19');
Widget app(
        {Future<List<LedgerEntryRecord>> Function()? load,
        Future<bool> Function(Uint8List, String)? save}) =>
    MaterialApp(
        home: SalesCsvExportView(
            loadEntries: load ?? () async => [sale],
            saveToChosenFile: save ?? (_, __) async => true));
Future<void> tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

void main() {
  testWidgets(
      'no entry export; preview then cancelled/saved destination distinction',
      (tester) async {
    var loads = 0;
    var saves = 0;
    await tester.pumpWidget(app(load: () async {
      loads++;
      return [sale];
    }, save: (bytes, name) async {
      expect(utf8.decode(bytes), contains('عميل اصطناعي'));
      expect(name.endsWith('.csv'), isTrue);
      saves++;
      return saves > 1;
    }));
    await tester.pumpAndSettle();
    expect(loads, 0);
    expect(saves, 0);
    await tap(tester, 'إعداد المعاينة');
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(saves, 0);
    await tap(tester, 'اختيار الوجهة وحفظ CSV');
    await tester.pumpAndSettle();
    expect(find.text('أُلغي اختيار الوجهة. لم يُحفظ ملف.'), findsOneWidget);
    await tap(tester, 'اختيار الوجهة وحفظ CSV');
    await tester.pumpAndSettle();
    expect(find.text('تم حفظ ملف CSV في الوجهة التي اخترتها.'), findsOneWidget);
  });
  testWidgets(
      'await save guards duplicate taps and Back; error retains preview',
      (tester) async {
    final pending = Completer<bool>();
    var saves = 0;
    await tester.pumpWidget(app(save: (_, __) {
      saves++;
      return pending.future;
    }));
    await tap(tester, 'إعداد المعاينة');
    await tester.pumpAndSettle();
    await tap(tester, 'اختيار الوجهة وحفظ CSV');
    await tester.tap(find.text('اختيار الوجهة وحفظ CSV'));
    await tester.pump();
    expect(saves, 1);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, false);
    pending.completeError(StateError('synthetic'));
    await tester.pumpAndSettle();
    expect(find.textContaining('قد يوجد ملف غير مكتمل'), findsOneWidget);
    expect(find.text('اختيار الوجهة وحفظ CSV'), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, true);
  });
  testWidgets(
      'Arabic date filter and edits invalidate stale preview; no empty export',
      (tester) async {
    var saves = 0;
    await tester.pumpWidget(app(save: (_, __) async {
      saves++;
      return true;
    }));
    await tester.enterText(find.byType(TextField).first, '٢٠٢٦-١١-١٩');
    await tap(tester, 'إعداد المعاينة');
    await tester.pumpAndSettle();
    expect(find.text('عدد سجلات المبيعات: 1'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '٢٠٢٦-١١-٢٠');
    await tester.pump();
    expect(find.text('اختيار الوجهة وحفظ CSV'), findsNothing);
    await tap(tester, 'إعداد المعاينة');
    await tester.pumpAndSettle();
    expect(find.text('عدد سجلات المبيعات: 0'), findsOneWidget);
    expect(saves, 0);
  });
  testWidgets('read errors and invalid dates do not invent rows; narrow RTL',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loads = 0;
    await tester.pumpWidget(app(load: () async {
      loads++;
      throw StateError('synthetic');
    }));
    await tester.enterText(find.byType(TextField).first, '2026-02-30');
    await tap(tester, 'إعداد المعاينة');
    await tester.pumpAndSettle();
    expect(loads, 0);
    await tester.enterText(find.byType(TextField).first, '');
    await tap(tester, 'إعداد المعاينة');
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.textContaining('تعذر إعداد CSV'), findsOneWidget);
    expect(find.text('اختيار الوجهة وحفظ CSV'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
