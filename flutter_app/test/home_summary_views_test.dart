import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/home_summary_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

LedgerEntryRecord entry(String label,
        {CurrencyCode currency = CurrencyCode.sar,
        double amount = 10,
        bool deleted = false,
        LedgerKind kind = LedgerKind.invoice}) =>
    LedgerEntryRecord(
        id: label,
        accountId: 'a',
        accountName: 'Test',
        kind: kind,
        typeLabel: label,
        payment: PaymentMethod.credit,
        direction: EntryDirection.debit,
        amount: amount,
        currency: currency,
        deleted: deleted,
        entryNumber: 1,
        entryDate: '2026-01-01');
void main() {
  test(
      'sales are isolated by currency and exclude purchases returns drafts unknown deleted',
      () {
    final rows = [
      entry('ف.مبيعات آجل'),
      entry('فاتورة مبيعات (CRM)', currency: CurrencyCode.usd, amount: 50),
      entry('ف.مشتريات مخزنية'),
      entry('مرتجع مبيعات'),
      entry('ف.مبيعات نقدية', deleted: true),
      entry('ف.مبيعات نقدية', kind: LedgerKind.quote),
      entry('فاتورة'),
      entry('مبيعات', kind: LedgerKind.returnEntry)
    ];
    expect(LocalSalesSummary(rows, CurrencyCode.sar).count, 1);
    expect(LocalSalesSummary(rows, CurrencyCode.sar).total, 10);
    expect(LocalSalesSummary(rows, CurrencyCode.usd).total, 50);
    expect(LocalSalesSummary(rows, CurrencyCode.eur).total, 0);
  });
  testWidgets(
      'currency directory lists enum, default and counts without editing',
      (tester) async {
    final c = ErpController(autoInitDb: false);
    c.accounts.clear();
    c.accounts.add(const AccountRecord(
        id: 'a',
        name: 'Test',
        category: AccountCategory.clients,
        currency: CurrencyCode.usd));
    c.defaultCurrency = CurrencyCode.usd;
    await tester.pumpWidget(
        MaterialApp(home: HomeCurrencyDirectoryView(controller: c)));
    for (final currency in CurrencyCode.values) {
      expect(find.text(currency.label), findsOneWidget);
    }
    expect(find.text('الافتراضية'), findsOneWidget);
    expect(find.text('عدد الحسابات: 1'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    c.dispose();
  });
  testWidgets(
      'sales dashboard labels limited local scope and never totals mixed currencies',
      (tester) async {
    final c = ErpController(autoInitDb: false);
    c.ledger
      ..clear()
      ..addAll([
        entry('ف.مبيعات آجل', amount: 17),
        entry('ف.مبيعات نقدية', amount: 23, currency: CurrencyCode.usd)
      ]);
    await tester
        .pumpWidget(MaterialApp(home: HomeSalesOverviewView(controller: c)));
    expect(find.text('17.00 ريال'), findsOneWidget);
    expect(find.text('23.00 دولار'), findsOneWidget);
    expect(find.textContaining('محلي محدود'), findsOneWidget);
    expect(find.textContaining('40.00'), findsNothing);
    c.dispose();
  });
}
