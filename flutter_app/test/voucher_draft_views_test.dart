import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/voucher_draft.dart';
import 'package:nasqo_pro_erp/screens/voucher_draft_views.dart';

const accounts = [
  AccountRecord(
      id: 'party',
      name: 'عميل دولار',
      category: AccountCategory.clients,
      currency: CurrencyCode.usd),
  AccountRecord(
      id: 'cash',
      name: 'صندوق دولار',
      category: AccountCategory.transfers,
      currency: CurrencyCode.usd,
      isCashAccount: true),
  AccountRecord(
      id: 'cash-sar',
      name: 'صندوق ريال',
      category: AccountCategory.transfers,
      isCashAccount: true),
];
const saved = VoucherDraft(
    id: 4,
    revision: 1,
    type: VoucherDraftType.receipt,
    date: '2026-02-28',
    partyAccountId: 'party',
    cashAccountId: 'cash',
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
  await tester.ensureVisible(target);
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

Widget view(VoucherDraftSave save,
        {bool create = true,
        VoucherDraftType type = VoucherDraftType.receipt,
        Future<List<VoucherDraft>> Function()? load}) =>
    MaterialApp(
        home: VoucherDraftsView(
            type: type,
            initialCurrency: CurrencyCode.usd,
            createOnOpen: create,
            loadDrafts: load ?? () async => [],
            loadDraft: (_) async => saved,
            loadAccounts: () async => accounts,
            saveDraft: save));
Future<void> fill(WidgetTester tester) async {
  await choose(tester, const ValueKey('voucher-party-usd'), 'عميل دولار');
  await choose(tester, const ValueKey('voucher-cash-usd'), 'صندوق دولار');
  await reveal(tester, find.byKey(const Key('voucher-date')));
  await tester.enterText(find.byKey(const Key('voucher-date')), '٢٠٢٦-٠٢-٢٨');
  await tester.enterText(find.byKey(const Key('voucher-amount')), '١٢٫٥');
}

void main() {
  testWidgets(
      'create awaits commit, localized inputs and duplicate/back blocked',
      (tester) async {
    var writes = 0;
    VoucherDraft? submitted;
    final pending = Completer<VoucherDraft>();
    await tester.pumpWidget(view((d) {
      writes++;
      submitted = d;
      return pending.future;
    }));
    await tester.pumpAndSettle();
    await fill(tester);
    await reveal(tester, find.byKey(const Key('voucher-save')));
    await tester.tap(find.byKey(const Key('voucher-save')));
    await tester.pump();
    expect(submitted!.date, '2026-02-28');
    expect(submitted!.amount, 12.5);
    expect(submitted!.partyAccountId, 'party');
    expect(submitted!.cashAccountId, 'cash');
    expect(submitted!.currency, CurrencyCode.usd);
    expect(submitted!.id, isNull);
    expect(find.text('جارٍ حفظ المسودة…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voucher-save')),
        warnIfMissed: false);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(writes, 1);
    expect(find.byType(VoucherDraftEditor), findsOneWidget);
    pending.complete(saved);
    await tester.pumpAndSettle();
    expect(find.byType(VoucherDraftEditor), findsNothing);
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
    await tester.tap(find.text('إلغاء دون حفظ'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('إنشاء مسودة قبض'));
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
          expect(d.type, VoucherDraftType.receipt);
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
    await tester.tap(find.text('مسودة سند قبض #4'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('voucher-amount')), '٢٢٫٢٥');
    await reveal(tester, find.byKey(const Key('voucher-save')));
    await tester.tap(find.byKey(const Key('voucher-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يتم تأكيد حفظ المسودة'), findsOneWidget);
    expect(find.byType(VoucherDraftEditor), findsOneWidget);
    await reveal(tester, find.byKey(const Key('voucher-save')));
    await tester.tap(find.byKey(const Key('voucher-save')));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(reads, 2);
    expect(find.byType(VoucherDraftEditor), findsNothing);
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
    await choose(tester, const Key('voucher-currency'), 'ريال');
    expect(find.textContaining('يلزم حساب طرف غير نقدي'), findsOneWidget);
    expect(find.text('عميل دولار'), findsNothing);
    await reveal(tester, find.byKey(const Key('voucher-save')));
    await tester.tap(find.byKey(const Key('voucher-save')));
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
    expect(find.text('مسودة سند قبض #4'), findsOneWidget);
    expect(reads, 2);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('payment draft remains nonposting and preserves selected type',
      (tester) async {
    VoucherDraft? submitted;
    await tester.pumpWidget(view((d) async {
      submitted = d;
      return d;
    }, type: VoucherDraftType.payment));
    await tester.pumpAndSettle();
    expect(find.text('إنشاء مسودة سند صرف'), findsOneWidget);
    await fill(tester);
    await reveal(tester, find.byKey(const Key('voucher-save')));
    await tester.tap(find.byKey(const Key('voucher-save')));
    await tester.pumpAndSettle();
    expect(submitted!.type, VoucherDraftType.payment);
    expect(submitted!.partyAccountId, 'party');
    expect(submitted!.cashAccountId, 'cash');
    expect(submitted!.amount, 12.5);
    expect(tester.takeException(), isNull);
  });
}
