import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/fx_draft.dart';
import 'package:nasqo_pro_erp/screens/fx_draft_views.dart';

const accounts = [
  AccountRecord(
      id: 'usd',
      name: 'مصدر',
      category: AccountCategory.transfers,
      isCashAccount: true,
      currency: CurrencyCode.usd),
  AccountRecord(
      id: 'usd2',
      name: 'دولار آخر',
      category: AccountCategory.transfers,
      isCashAccount: true,
      currency: CurrencyCode.usd),
  AccountRecord(
      id: 'sar',
      name: 'وجهة',
      category: AccountCategory.transfers,
      isCashAccount: true),
  AccountRecord(
      id: 'regular', name: 'غير نقدي', category: AccountCategory.clients),
];
const saved = FxDraft(
    id: 4,
    revision: 1,
    date: '2026-02-28',
    sourceCashId: 'usd',
    destinationCashId: 'sar',
    sourceCurrency: CurrencyCode.usd,
    destinationCurrency: CurrencyCode.sar,
    sourceAmount: 100.25,
    destinationAmount: 375.5);
Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, Finder target, String label) async {
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await choose(tester, find.byKey(const Key('fx-source')), 'مصدر • دولار');
  await choose(
      tester, find.byKey(const ValueKey('fx-destination-usd')), 'وجهة • ريال');
  await reveal(tester, find.byKey(const Key('fx-date')));
  await tester.enterText(find.byKey(const Key('fx-date')), '٢٠٢٦-٠٢-٢٨');
  await tester.enterText(find.byKey(const Key('fx-source-amount')), '١٠٠٫٢٥');
  await reveal(tester, find.byKey(const Key('fx-destination-amount')));
  expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('fx-destination-amount')))
          .controller!
          .text,
      isEmpty);
  await tester.enterText(
      find.byKey(const Key('fx-destination-amount')), '٣٧٥٫٥');
}

Widget view(FxDraftSave save,
        {bool create = true,
        Future<List<FxDraft>> Function()? load,
        List<AccountRecord> boxes = accounts}) =>
    MaterialApp(
        home: FxDraftsView(
            loadDrafts: load ?? () async => [],
            loadDraft: (_) async => saved,
            loadAccounts: () async => boxes,
            saveDraft: save,
            createOnOpen: create));
void main() {
  testWidgets(
      'manual independent localized amounts await commit and prevent duplicate/back',
      (tester) async {
    var writes = 0;
    FxDraft? input;
    final pending = Completer<FxDraft>();
    await tester.pumpWidget(view((d) {
      input = d;
      writes++;
      return pending.future;
    }));
    await tester.pumpAndSettle();
    await fill(tester);
    await reveal(tester, find.byKey(const Key('fx-save')));
    await tester.tap(find.byKey(const Key('fx-save')));
    await tester.pump();
    expect(writes, 1);
    expect(input!.sourceAmount, 100.25);
    expect(input!.destinationAmount, 375.5);
    expect(input!.sourceCurrency, CurrencyCode.usd);
    expect(input!.destinationCurrency, CurrencyCode.sar);
    expect(input!.date, '2026-02-28');
    expect(input!.sourceCashId, 'usd');
    expect(input!.destinationCashId, 'sar');
    await tester.tap(find.byKey(const Key('fx-save')), warnIfMissed: false);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(writes, 1);
    expect(find.byType(FxDraftEditor), findsOneWidget);
    pending.complete(saved);
    await tester.pumpAndSettle();
    expect(find.byType(FxDraftEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'cancel/back no writes; same-currency and noncash destinations excluded',
      (tester) async {
    var writes = 0;
    await tester.pumpWidget(view((d) async {
      writes++;
      return saved;
    }));
    await tester.pumpAndSettle();
    await choose(tester, find.byKey(const Key('fx-source')), 'مصدر • دولار');
    final choices = tester
        .widget<DropdownButton<String>>(find.descendant(
            of: find.byKey(const ValueKey('fx-destination-usd')),
            matching:
                find.byWidgetPredicate((w) => w is DropdownButton<String>)))
        .items!
        .map((i) => i.value);
    expect(choices, ['sar']);
    await reveal(tester, find.text('إلغاء دون حفظ'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء دون حفظ'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('إنشاء مسودة صرف عملات'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(writes, 0);
  });
  testWidgets('edit failure keeps amounts and retry preserves id/revision',
      (tester) async {
    var writes = 0;
    var reads = 0;
    await tester.pumpWidget(view(
        (d) async {
          writes++;
          expect(d.id, 4);
          expect(d.revision, 1);
          expect(d.sourceAmount, 100.25);
          expect(d.destinationAmount, 400.01);
          if (writes == 1) throw StateError('synthetic failure');
          return saved;
        },
        create: false,
        load: () async {
          reads++;
          return [saved];
        }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مسودة صرف عملات #4'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('fx-destination-amount')));
    await tester.enterText(
        find.byKey(const Key('fx-destination-amount')), '٤٠٠٫٠١');
    await reveal(tester, find.byKey(const Key('fx-save')));
    await tester.tap(find.byKey(const Key('fx-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يتم تأكيد حفظ المسودة'), findsOneWidget);
    expect(find.byType(FxDraftEditor), findsOneWidget);
    await reveal(tester, find.byKey(const Key('fx-save')));
    await tester.tap(find.byKey(const Key('fx-save')));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('zero destination is invalid and never inferred; narrow RTL',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var writes = 0;
    await tester.pumpWidget(view((d) async {
      writes++;
      return saved;
    }));
    await tester.pumpAndSettle();
    await fill(tester);
    await tester.enterText(find.byKey(const Key('fx-destination-amount')), '٠');
    await reveal(tester, find.byKey(const Key('fx-save')));
    await tester.tap(find.byKey(const Key('fx-save')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('أدخل مبلغاً موجباً يدوياً'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'no viable cross-currency pair never writes and gives explicit notice',
      (tester) async {
    var writes = 0;
    await tester.pumpWidget(view((d) async {
      writes++;
      return saved;
    }, boxes: accounts.take(2).toList()));
    await tester.pumpAndSettle();
    expect(find.textContaining('يلزم صندوقان نقديان'), findsOneWidget);
    await reveal(tester, find.byKey(const Key('fx-save')));
    await tester.tap(find.byKey(const Key('fx-save')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed list loading retries without persistence',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(view((d) async => throw StateError('must not save'),
        create: false, load: () async {
      reads++;
      if (reads == 1) throw StateError('synthetic read');
      return [saved];
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعذر تحميل القائمة. إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('مسودة صرف عملات #4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
