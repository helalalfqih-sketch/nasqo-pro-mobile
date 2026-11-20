import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:nasqo_pro_erp/screens/home_lookup_views.dart';

LedgerEntryRecord row(String id,
        {String date = '2026-01-02',
        bool deleted = false,
        LedgerKind kind = LedgerKind.invoice,
        CurrencyCode currency = CurrencyCode.sar}) =>
    LedgerEntryRecord(
        id: id,
        accountId: 'a',
        accountName: 'أحمد',
        kind: kind,
        typeLabel: 'تجريبي',
        payment: PaymentMethod.credit,
        direction: EntryDirection.debit,
        amount: 12,
        currency: currency,
        entryNumber: 123,
        entryDate: date,
        deleted: deleted,
        documentNumber: 'DOC-123',
        details: 'وصف تركيبي فقط');
ErpController fixture() {
  final c = ErpController(autoInitDb: false);
  c.accounts.clear();
  c.inventory.clear();
  c.ledger.clear();
  c.accounts.add(const AccountRecord(
      id: 'a', name: 'أحمد', category: AccountCategory.clients));
  addTearDown(c.dispose);
  return c;
}

Future<void> open(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search normalizes Arabic names and digits, hides deleted',
      (tester) async {
    final c = fixture();
    c.ledger.addAll([row('ok'), row('gone', deleted: true)]);
    await open(tester, HomeQuickSearchScreen(controller: c));
    expect(find.text('اكتب كلمة أو رقماً لبدء البحث.'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('quick-search-query')), 'احمد');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lookup-account-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('lookup-entry-ok')), findsOneWidget);
    expect(find.byKey(const ValueKey('lookup-entry-gone')), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('quick-search-query')), '١٢٣');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lookup-entry-ok')), findsOneWidget);
    expect(find.byKey(const ValueKey('lookup-account-a')), findsNothing);
  });
  testWidgets('read-only detail opens and closes without changing records',
      (tester) async {
    final c = fixture();
    c.ledger.add(row('ok'));
    final original = c.ledger.single;
    await open(tester, HomeQuickSearchScreen(controller: c));
    await tester.enterText(
        find.byKey(const ValueKey('quick-search-query')), 'DOC');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lookup-entry-ok')));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل القيد 123'), findsOneWidget);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(c.ledger.single, same(original));
    expect(c.dbReady, false);
  });
  testWidgets('day filters date and deleted but labels quote nonfinancial',
      (tester) async {
    final c = fixture();
    c.ledger.addAll([
      row('ok', kind: LedgerKind.quote),
      row('other', date: '2026-01-01'),
      row('gone', deleted: true),
      row('usd', currency: CurrencyCode.usd)
    ]);
    await open(tester,
        DailyMovementScreen(controller: c, initialDate: DateTime(2026, 1, 2)));
    expect(find.text('عدد السجلات: 2'), findsOneWidget);
    expect(find.textContaining('غير مالي'), findsWidgets);
    expect(find.byKey(const ValueKey('lookup-entry-other')), findsNothing);
    expect(find.byKey(const ValueKey('lookup-entry-gone')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('daily-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دولار').last);
    await tester.pumpAndSettle();
    expect(find.text('عدد السجلات: 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('lookup-entry-usd')), findsOneWidget);
  });
  testWidgets(
      'empty day and no search match are explicit and narrow layout safe',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture();
    await open(tester,
        DailyMovementScreen(controller: c, initialDate: DateTime(2026, 1, 2)));
    expect(find.text('لا توجد قيود مطابقة لهذا اليوم.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await open(tester, HomeQuickSearchScreen(controller: c));
    await tester.enterText(
        find.byKey(const ValueKey('quick-search-query')), 'لايوجد');
    await tester.pumpAndSettle();
    expect(find.text('لا توجد نتائج مطابقة.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
