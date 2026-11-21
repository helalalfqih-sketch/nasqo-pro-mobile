import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/cash_supplier_statement_view.dart';
import 'package:nasqo_pro_erp/screens/local_entry_view.dart';
import 'package:nasqo_pro_erp/screens/web_auxiliary_views.dart';
import 'package:nasqo_pro_erp/screens/workspace_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  test('inferExpenseCategory classifies Arabic voucher descriptions accurately', () {
    expect(
      ErpController.inferExpenseCategory('صرف راتب شهر نوفمبر', 'موظف'),
      'رواتب وأجور',
    );
    expect(
      ErpController.inferExpenseCategory('شحن ونقل بضاعة', 'مؤسسة'),
      'شحن ونقل',
    );
    expect(
      ErpController.inferExpenseCategory('فاتورة كهرباء وصيانة', 'المحل'),
      'صيانة ومرافق',
    );
    expect(
      ErpController.inferExpenseCategory('إيجار المستودع السنوي', 'المالك'),
      'إيجار ومقر',
    );
  });

  testWidgets('local entry supports smart expense category and account swap with balance strips',
      (tester) async {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: LocalEntryView(
          controller: c,
          kind: LedgerKind.voucher,
          openDrafts: () {},
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'البيان'), 'دفع إيجار المقر');
    await tester.ensureVisible(find.byKey(const ValueKey('local-entry-smart-category')));
    await tester.tap(find.byKey(const ValueKey('local-entry-smart-category')));
    await tester.pumpAndSettle();
    expect(find.textContaining('اقتراح التصنيف الذكي: إيجار ومقر'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: LocalEntryView(
          controller: c,
          kind: LedgerKind.simpleEntry,
          openDrafts: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-entry-swap-accounts')), findsOneWidget);
    expect(find.textContaining('رصيد '), findsWidgets);
  });

  testWidgets('batchUpdateInventoryItems and transferWarehouseStock update local stock accurately',
      (tester) async {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    await c.saveWarehouse(name: 'المستودع الفرعي', details: 'فرع 2', isDefault: false);
    final targetWarehouse = c.warehouses.last;
    final firstItem = c.inventory.first;
    final oldQty = firstItem.quantity;

    final updated = await c.batchUpdateInventoryItems(
      {firstItem.id},
      priceMode: 'set',
      priceValue: 120,
      stockMode: 'delta',
      stockValue: 5,
      minThreshold: 15,
    );
    expect(updated, 1);
    final afterBatch = c.inventory.firstWhere((i) => i.id == firstItem.id);
    expect(afterBatch.avgCost, 120);
    expect(afterBatch.quantity, oldQty + 5);
    expect(afterBatch.minThreshold, 15);

    await c.transferWarehouseStock(
      itemId: firstItem.id,
      toWarehouseId: targetWarehouse.id,
      quantity: 3,
    );
    final srcAfter = c.inventory.firstWhere((i) => i.id == firstItem.id);
    final dstAfter = c.inventory.firstWhere(
      (i) => i.warehouseId == targetWarehouse.id && i.name == firstItem.name,
    );
    expect(srcAfter.quantity, oldQty + 2);
    expect(dstAfter.quantity, 3);
  });

  testWidgets('landscape invoice preview renders transaction 1140 two 1500 lines and 3000 total',
      (tester) async {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    const tx1140 = LedgerEntryRecord(
      id: 'tx_1140',
      accountId: 'supp_1',
      accountName: 'مورد نقدي',
      kind: LedgerKind.invoice,
      typeLabel: 'ف.مشتريات نقدية',
      payment: PaymentMethod.cash,
      direction: EntryDirection.credit,
      amount: 3000,
      currency: CurrencyCode.sar,
      entryNumber: 1140,
      entryDate: '2026-11-21',
      documentNumber: 'DOC-1140',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LandscapeInvoicePreviewDialog(
            controller: c,
            entry: tx1140,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('بند مشتريات نقدية (1)'), findsOneWidget);
    expect(find.text('بند مشتريات نقدية (2)'), findsOneWidget);
    expect(find.textContaining('3,000'), findsWidgets);
  });

  testWidgets('settings default currency and inventory action buttons work without layout errors',
      (tester) async {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    await c.setDefaultCurrency(CurrencyCode.usd);
    expect(c.defaultCurrency, CurrencyCode.usd);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCatalogScreen(controller: c),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inventory-bulk-edit-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('inventory-transfer-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('inventory-export-csv-btn')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockMovementScreen(controller: c),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stock-movement-pdf-print')), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-movement-excel-export')), findsOneWidget);
  });

  testWidgets('analytics charts and auxiliary modals render and handle user interaction',
      (tester) async {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    String? printAction;
    String? savedBackupName;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => SingleChildScrollView(
              child: Column(
                children: [
                  SalesTrendChartCard(
                    ledger: c.ledger,
                    currency: c.defaultCurrency,
                  ),
                  ExpenseTrendsChartCard(
                    accounts: c.accounts,
                    ledger: c.ledger,
                    currency: c.defaultCurrency,
                  ),
                  SupplierPerformanceChartCard(
                    accounts: c.accounts,
                    ledger: c.ledger,
                    currency: c.defaultCurrency,
                  ),
                  TextButton(
                    onPressed: () => showPrintOptionsModal(
                      context,
                      subjectLabel: 'كشف حساب',
                      onAction: (a) => printAction = a,
                    ),
                    child: const Text('فتح خيارات الطباعة'),
                  ),
                  TextButton(
                    onPressed: () => showBackupNameModal(
                      context,
                      onSaveLocal: (name) async => savedBackupName = name,
                    ),
                    child: const Text('فتح تسمية النسخة'),
                  ),
                  TextButton(
                    onPressed: () => showNasqoActivationDialog(context, c.companyName),
                    child: const Text('فتح التفعيل'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sales-trend-chart-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('expense-trends-chart-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('supplier-performance-chart-card')), findsOneWidget);

    await tester.ensureVisible(find.text('فتح خيارات الطباعة'));
    await tester.tap(find.text('فتح خيارات الطباعة'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('print-options-modal')), findsOneWidget);
    await tester.tap(find.text('طباعة'));
    await tester.pumpAndSettle();
    expect(printAction, contains('طباعة'));

    await tester.ensureVisible(find.text('فتح تسمية النسخة'));
    await tester.tap(find.text('فتح تسمية النسخة'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-name-modal')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('backup-name-input')),
      'nasqo_custom_backup',
    );
    await tester.tap(find.byKey(const ValueKey('backup-save-local-btn')));
    await tester.pumpAndSettle();
    expect(savedBackupName, 'nasqo_custom_backup');

    await tester.ensureVisible(find.text('فتح التفعيل'));
    await tester.tap(find.text('فتح التفعيل'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nasqo-activation-modal')), findsOneWidget);
    await tester.tap(find.text('تحقق وتفعيل'));
    await tester.pumpAndSettle();
    expect(find.textContaining('النسخة المحلية مفعلة'), findsOneWidget);
  });
}
