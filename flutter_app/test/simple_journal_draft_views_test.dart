import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/simple_journal_draft.dart';
import 'package:nasqo_pro_erp/screens/simple_journal_draft_views.dart';

const accounts = [
  AccountRecord(
      id: 'party',
      name: 'حساب مدين دولار',
      category: AccountCategory.clients,
      currency: CurrencyCode.usd),
  AccountRecord(
      id: 'cash',
      name: 'صندوق دولار',
      category: AccountCategory.transfers,
      currency: CurrencyCode.usd,
      isCashAccount: true),
  AccountRecord(
      id: 'regular',
      name: 'حساب غير نقدي',
      category: AccountCategory.clients,
      currency: CurrencyCode.usd),
  AccountRecord(
      id: 'cash-sar',
      name: 'صندوق ريال',
      category: AccountCategory.transfers,
      isCashAccount: true),
];
const saved = SimpleJournalDraft(
    id: 4,
    revision: 1,
    date: '2026-02-28',
    debitAccountId: 'party',
    creditAccountId: 'cash',
    currency: CurrencyCode.usd,
    amount: 12.5);
Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, Key key, String text) async {
  final target = find.byKey(key);
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Widget view(SimpleJournalDraftSave save,
        {bool create = true,
        Future<List<SimpleJournalDraft>> Function()? load}) =>
    MaterialApp(
        home: SimpleJournalDraftsView(
            initialCurrency: CurrencyCode.usd,
            createOnOpen: create,
            loadDrafts: load ?? () async => [],
            loadDraft: (_) async => saved,
            loadAccounts: () async => accounts,
            saveDraft: save));
Future<void> fill(WidgetTester tester) async {
  await choose(tester, const ValueKey('journal-debit-usd'), 'حساب مدين دولار');
  await choose(tester, const ValueKey('journal-credit-usd'), 'صندوق دولار');
  await reveal(tester, find.byKey(const Key('journal-date')));
  await tester.enterText(find.byKey(const Key('journal-date')), '٢٠٢٦-٠٢-٢٨');
  await tester.enterText(find.byKey(const Key('journal-amount')), '١٢٫٥');
}

void main() {
  testWidgets(
      'create awaits commit, localized inputs and duplicate/back blocked',
      (tester) async {
    var writes = 0;
    SimpleJournalDraft? submitted;
    final pending = Completer<SimpleJournalDraft>();
    await tester.pumpWidget(view((d) {
      writes++;
      submitted = d;
      return pending.future;
    }));
    await tester.pumpAndSettle();
    await fill(tester);
    final destinations = tester
        .widget<DropdownButton<String>>(find.descendant(
            of: find.byKey(const ValueKey('journal-credit-usd')),
            matching:
                find.byWidgetPredicate((w) => w is DropdownButton<String>)))
        .items!
        .map((item) => item.value)
        .toList();
    expect(destinations, ['cash', 'regular']);
    await reveal(tester, find.byKey(const Key('journal-save')));
    expect(
        find.text(
            'طرف مدين: 12.5 دولار • طرف دائن: 12.5 دولار — تعادل مسودة فقط'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('journal-save')));
    await tester.pump();
    expect(submitted!.date, '2026-02-28');
    expect(submitted!.amount, 12.5);
    expect(submitted!.debitAccountId, 'party');
    expect(submitted!.creditAccountId, 'cash');
    expect(submitted!.currency, CurrencyCode.usd);
    expect(submitted!.id, isNull);
    expect(find.text('جارٍ حفظ المسودة…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('journal-save')),
        warnIfMissed: false);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(writes, 1);
    expect(find.byType(SimpleJournalDraftEditor), findsOneWidget);
    pending.complete(saved);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleJournalDraftEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and back never write', (tester) async {
    var writes = 0;
    await tester.pumpWidget(view((d) async {
      writes++;
      return saved;
    }));
    await tester.pumpAndSettle();
    await fill(tester);
    await reveal(tester, find.text('إلغاء دون حفظ'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء دون حفظ'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('إنشاء مسودة قيد'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(writes, 0);
  });

  testWidgets(
      'edit save failure retains draft, successful retry uses same id/revision',
      (tester) async {
    var writes = 0;
    var reads = 0;
    await tester.pumpWidget(view(
        (d) async {
          writes++;
          expect(d.id, 4);
          expect(d.revision, 1);
          expect(d.amount, 22.25);
          if (writes == 1) throw StateError('synthetic stale revision');
          return saved;
        },
        create: false,
        load: () async {
          reads++;
          return [saved];
        }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مسودة قيد #4'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('journal-amount')), '٢٢٫٢٥');
    await reveal(tester, find.byKey(const Key('journal-save')));
    await tester.tap(find.byKey(const Key('journal-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يتم تأكيد حفظ المسودة'), findsOneWidget);
    expect(find.byType(SimpleJournalDraftEditor), findsOneWidget);
    await reveal(tester, find.byKey(const Key('journal-save')));
    await tester.tap(find.byKey(const Key('journal-save')));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(reads, 2);
    expect(find.byType(SimpleJournalDraftEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'currency switch clears incompatible choices; narrow RTL validation',
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
    await choose(tester, const Key('journal-currency'), 'ريال');
    expect(find.textContaining('يلزم حسابان مختلفان'), findsOneWidget);
    expect(find.text('حساب مدين دولار'), findsNothing);
    await reveal(tester, find.byKey(const Key('journal-save')));
    await tester.tap(find.byKey(const Key('journal-save')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.textContaining('راجع التاريخ والمبلغ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list read error retries without writes', (tester) async {
    var reads = 0;
    var writes = 0;
    await tester.pumpWidget(view(
        (d) async {
          writes++;
          return saved;
        },
        create: false,
        load: () async {
          reads++;
          if (reads == 1) throw StateError('synthetic load error');
          return [saved];
        }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعذر تحميل القائمة. إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('مسودة قيد #4'), findsOneWidget);
    expect(reads, 2);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('zero amount is not a balanced valid draft and never saves',
      (tester) async {
    var writes = 0;
    await tester.pumpWidget(view((d) async {
      writes++;
      return saved;
    }));
    await tester.pumpAndSettle();
    await fill(tester);
    await tester.enterText(find.byKey(const Key('journal-amount')), '٠');
    await tester.pump();
    await reveal(tester, find.byKey(const Key('journal-save')));
    await tester.tap(find.byKey(const Key('journal-save')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('أدخل مبلغاً موجباً صالحاً'), findsOneWidget);
    expect(find.byKey(const Key('journal-balanced-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
