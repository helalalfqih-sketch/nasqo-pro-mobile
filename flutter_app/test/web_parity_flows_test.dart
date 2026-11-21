import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/cash_supplier_statement_view.dart';
import 'package:nasqo_pro_erp/screens/local_entry_view.dart';
import 'package:nasqo_pro_erp/screens/web_auxiliary_views.dart';
import 'package:nasqo_pro_erp/screens/workspace_views.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

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

  test('transferWarehouseStock isolates same-name different-SKU items and persists across SQLite reopen',
      () async {
    final dir = await Directory.systemTemp.createTemp('transfer-sku-isolation-');
    final dbPath = '${dir.path}/transfer_test.db';
    final factory = createDatabaseFactoryFfi(ffiInit: _ffi);
    var store = LocalDatabase.withFactory(factory, dbPath);
    var c = ErpController(autoInitDb: false, localDatabase: store);
    try {
      await c.initDatabase();
      await c.saveWarehouse(name: 'المستودع الفرعي', details: 'فرع 2', isDefault: false);
      final wh1 = c.warehouses.first.id;
      final wh2 = c.warehouses.last.id;

      // Two distinct products sharing the exact same Arabic name but different SKUs.
      await c.receiveStock(
        name: 'قهوة عربية فاخرة',
        sku: 'COF-A',
        unit: 'كجم',
        warehouseId: wh1,
        quantity: 10,
        avgCost: 40,
      );
      await c.receiveStock(
        name: 'قهوة عربية فاخرة',
        sku: 'COF-B',
        unit: 'كجم',
        warehouseId: wh2,
        quantity: 5,
        avgCost: 80,
      );

      final itemAWh1 = c.inventory.singleWhere(
        (i) => i.warehouseId == wh1 && i.sku == 'COF-A',
      );

      // Transfer 4 units of COF-A from wh1 to wh2. Must NOT merge into COF-B!
      await c.transferWarehouseStock(
        itemId: itemAWh1.id,
        toWarehouseId: wh2,
        quantity: 4,
      );

      // Update COF-A cost in wh1 to 70 and transfer 2 more units to wh2 to verify weighted average on COF-A.
      await c.batchUpdateInventoryItems(
        {itemAWh1.id},
        priceMode: 'set',
        priceValue: 70,
      );
      await c.transferWarehouseStock(
        itemId: itemAWh1.id,
        toWarehouseId: wh2,
        quantity: 2,
      );

      // Ambiguous match rejection: same SKU in destination with different unit must throw.
      await c.receiveStock(
        name: 'صنف ملتبس',
        sku: 'AMB-1',
        unit: 'كرتون',
        warehouseId: wh1,
        quantity: 5,
        avgCost: 100,
      );
      await c.receiveStock(
        name: 'صنف ملتبس',
        sku: 'AMB-1',
        unit: 'حبة',
        warehouseId: wh2,
        quantity: 5,
        avgCost: 10,
      );
      final ambWh1 = c.inventory.singleWhere(
        (i) => i.warehouseId == wh1 && i.sku == 'AMB-1',
      );
      await expectLater(
        c.transferWarehouseStock(
          itemId: ambWh1.id,
          toWarehouseId: wh2,
          quantity: 1,
        ),
        throwsA(isA<SaleValidationException>()),
      );

      // Close and reopen SQLite to verify persisted quantities and weighted average costs.
      c.dispose();
      await store.close();

      store = LocalDatabase.withFactory(factory, dbPath);
      c = ErpController(autoInitDb: false, localDatabase: store);
      await c.initDatabase();

      final reopenedAWh1 = c.inventory.singleWhere(
        (i) => i.warehouseId == wh1 && i.sku == 'COF-A',
      );
      final reopenedAWh2 = c.inventory.singleWhere(
        (i) => i.warehouseId == wh2 && i.sku == 'COF-A',
      );
      final reopenedBWh2 = c.inventory.singleWhere(
        (i) => i.warehouseId == wh2 && i.sku == 'COF-B',
      );

      expect(reopenedAWh1.quantity, 4);
      expect(reopenedAWh1.avgCost, 70);
      expect(reopenedAWh2.quantity, 6);
      expect(reopenedAWh2.avgCost, closeTo(50, 1e-6)); // (4*40 + 2*70) / 6 = 50
      expect(reopenedBWh2.quantity, 5);
      expect(reopenedBWh2.avgCost, 80);
    } finally {
      c.dispose();
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('computeSupplierMetrics uses dated deliveries, prioritizes explicit receipt id over duplicate doc numbers, and excludes opening balances and vouchers', () {
    const s1 = AccountRecord(
      id: 'sup_1',
      name: 'المورد الأول',
      category: AccountCategory.purchases,
      openingBalance: 5000,
      codeNumber: 201,
    );
    const s2 = AccountRecord(
      id: 'sup_2',
      name: 'المورد الثاني',
      category: AccountCategory.purchases,
      openingBalance: 3000,
      codeNumber: 202,
    );
    const sOpeningOnly = AccountRecord(
      id: 'sup_opening_only',
      name: 'مورد رصيد افتتاحي فقط',
      category: AccountCategory.purchases,
      openingBalance: 12000,
      openingDirection: EntryDirection.credit,
      codeNumber: 203,
    );
    const sAmbiguous = AccountRecord(
      id: 'sup_ambiguous',
      name: 'مورد مستند مكرر بدون معرف',
      category: AccountCategory.purchases,
      codeNumber: 204,
    );

    const ledger = [
      // Another supplier's entry with the exact same documentNumber 'PO-1' and earlier date
      LedgerEntryRecord(
        id: 'led_other_supplier_same_doc',
        accountId: 'sup_2',
        accountName: 'المورد الثاني',
        kind: LedgerKind.voucher,
        typeLabel: 'سند صرف',
        payment: PaymentMethod.cash,
        direction: EntryDirection.debit,
        amount: 250,
        documentNumber: 'PO-1',
        entryNumber: 1,
        entryDate: '2026-11-01',
      ),
      // Another purchase invoice on sup_1 with the SAME documentNumber 'PO-1' but different id
      LedgerEntryRecord(
        id: 'led_po_1_duplicate_doc',
        accountId: 'sup_1',
        accountName: 'المورد الأول',
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مشتريات آجل',
        payment: PaymentMethod.credit,
        direction: EntryDirection.credit,
        amount: 500,
        documentNumber: 'PO-1',
        entryNumber: 2,
        entryDate: '2026-11-20',
      ),
      // The explicit linked receipt entry for po_1
      LedgerEntryRecord(
        id: 'led_po_1',
        accountId: 'sup_1',
        accountName: 'المورد الأول',
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مشتريات (استلام PO)',
        payment: PaymentMethod.credit,
        direction: EntryDirection.credit,
        amount: 1000,
        documentNumber: 'PO-1',
        entryNumber: 3,
        entryDate: '2026-11-05',
      ),
      LedgerEntryRecord(
        id: 'led_po_2',
        accountId: 'sup_1',
        accountName: 'المورد الأول',
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مشتريات (استلام PO)',
        payment: PaymentMethod.credit,
        direction: EntryDirection.credit,
        amount: 2000,
        documentNumber: 'PO-2',
        entryNumber: 4,
        entryDate: '2026-11-12',
      ),
      // Supplier 2: 1 SAR purchase invoice + 1 SAR payment voucher (above) + 1 USD purchase invoice
      LedgerEntryRecord(
        id: 'led_direct_s2',
        accountId: 'sup_2',
        accountName: 'المورد الثاني',
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مشتريات آجل',
        payment: PaymentMethod.credit,
        direction: EntryDirection.credit,
        amount: 600,
        documentNumber: 'PUR-9',
        entryNumber: 5,
        entryDate: '2026-11-15',
      ),
      LedgerEntryRecord(
        id: 'led_direct_s2_usd',
        accountId: 'sup_2',
        accountName: 'المورد الثاني',
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مشتريات آجل',
        payment: PaymentMethod.credit,
        direction: EntryDirection.credit,
        amount: 900,
        currency: CurrencyCode.usd,
        documentNumber: 'PUR-USD-1',
        entryNumber: 6,
        entryDate: '2026-11-15',
      ),
      // Supplier 4 (ambiguous): two purchase invoices sharing 'PO-DUP' and PO has no postedLedgerEntryId
      LedgerEntryRecord(
        id: 'led_amb_1',
        accountId: 'sup_ambiguous',
        accountName: 'مورد مستند مكرر بدون معرف',
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مشتريات آجل',
        payment: PaymentMethod.credit,
        direction: EntryDirection.credit,
        amount: 400,
        documentNumber: 'PO-DUP',
        entryNumber: 7,
        entryDate: '2026-11-03',
      ),
      LedgerEntryRecord(
        id: 'led_amb_2',
        accountId: 'sup_ambiguous',
        accountName: 'مورد مستند مكرر بدون معرف',
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مشتريات آجل',
        payment: PaymentMethod.credit,
        direction: EntryDirection.credit,
        amount: 400,
        documentNumber: 'PO-DUP',
        entryNumber: 8,
        entryDate: '2026-11-09',
      ),
    ];

    const purchaseOrders = [
      ErpPurchaseOrder(
        id: 'po_1',
        poNumber: 'PO-1',
        supplierAccountId: 'sup_1',
        supplierName: 'المورد الأول',
        warehouseId: 'wh_1',
        warehouseName: 'المخزن الرئيسي',
        orderDate: '2026-11-01',
        expectedDate: '2026-11-06',
        status: PurchaseOrderStatus.received,
        postedLedgerEntryId: 'led_po_1',
        lines: [],
      ),
      ErpPurchaseOrder(
        id: 'po_2',
        poNumber: 'PO-2',
        supplierAccountId: 'sup_1',
        supplierName: 'المورد الأول',
        warehouseId: 'wh_1',
        warehouseName: 'المخزن الرئيسي',
        orderDate: '2026-11-06',
        expectedDate: '2026-11-10',
        status: PurchaseOrderStatus.received,
        postedLedgerEntryId: 'led_po_2',
        lines: [],
      ),
      ErpPurchaseOrder(
        id: 'po_amb',
        poNumber: 'PO-DUP',
        supplierAccountId: 'sup_ambiguous',
        supplierName: 'مورد مستند مكرر بدون معرف',
        warehouseId: 'wh_1',
        warehouseName: 'المخزن الرئيسي',
        orderDate: '2026-11-01',
        expectedDate: '2026-11-05',
        status: PurchaseOrderStatus.received,
        lines: [],
      ),
    ];

    final forward = computeSupplierMetrics(
      [s1, s2, sOpeningOnly, sAmbiguous],
      ledger,
      CurrencyCode.sar,
      purchaseOrders: purchaseOrders,
    );
    final reversed = computeSupplierMetrics(
      [sAmbiguous, sOpeningOnly, s2, s1],
      ledger.reversed.toList(),
      CurrencyCode.sar,
      purchaseOrders: purchaseOrders.reversed.toList(),
    );

    // Supplier with opening balance only and no purchase invoices must be excluded.
    expect(forward.where((m) => m.accountId == 'sup_opening_only'), isEmpty);
    expect(reversed.where((m) => m.accountId == 'sup_opening_only'), isEmpty);

    // Supplier 1: explicit postedLedgerEntryId wins over duplicate doc numbers in any ledger order.
    final m1Forward = forward.singleWhere((m) => m.accountId == 'sup_1');
    final m1Reversed = reversed.singleWhere((m) => m.accountId == 'sup_1');
    expect(m1Forward.avgDeliveryDays, 5.0); // (4 days + 6 days) / 2
    expect(m1Forward.onTimeScore, 50); // PO-1 on time (5<=6), PO-2 late (12>10)
    expect(m1Forward.orderCount, 3); // 3 purchase invoices (500 + 1000 + 2000), openingBalance excluded
    expect(m1Forward.totalSpend, 3500);
    expect(m1Reversed.avgDeliveryDays, m1Forward.avgDeliveryDays);
    expect(m1Reversed.onTimeScore, m1Forward.onTimeScore);
    expect(m1Reversed.totalSpend, m1Forward.totalSpend);
    expect(m1Reversed.orderCount, m1Forward.orderCount);

    // Supplier 2: 1 SAR purchase invoice (600) + 1 SAR payment voucher (250) + 1 USD purchase invoice (900) + 3000 opening.
    // Only the 1 SAR purchase invoice (600) is counted!
    final m2Forward = forward.singleWhere((m) => m.accountId == 'sup_2');
    final m2Reversed = reversed.singleWhere((m) => m.accountId == 'sup_2');
    expect(m2Forward.orderCount, 1);
    expect(m2Forward.totalSpend, 600);
    expect(m2Forward.avgOrderCost, 600);
    expect(m2Forward.avgDeliveryDays, isNull);
    expect(m2Forward.onTimeScore, isNull);
    expect(m2Reversed.orderCount, 1);
    expect(m2Reversed.totalSpend, 600);

    // USD check for Supplier 2
    final usdMetrics = computeSupplierMetrics(
      [s1, s2, sOpeningOnly],
      ledger,
      CurrencyCode.usd,
      purchaseOrders: purchaseOrders,
    );
    expect(usdMetrics.single.accountId, 'sup_2');
    expect(usdMetrics.single.orderCount, 1);
    expect(usdMetrics.single.totalSpend, 900);

    // Supplier 4 (ambiguous duplicate documentNumber without explicit postedLedgerEntryId) -> unavailable (null)
    final mAmbForward = forward.singleWhere((m) => m.accountId == 'sup_ambiguous');
    final mAmbReversed = reversed.singleWhere((m) => m.accountId == 'sup_ambiguous');
    expect(mAmbForward.avgDeliveryDays, isNull);
    expect(mAmbForward.onTimeScore, isNull);
    expect(mAmbReversed.avgDeliveryDays, isNull);
    expect(mAmbReversed.onTimeScore, isNull);
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

  testWidgets('analytics charts show unavailable delivery when undated and auxiliary modals work',
      (tester) async {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    c.purchaseOrders.clear();
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
                    purchaseOrders: c.purchaseOrders,
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
    expect(find.textContaining('متوسط التوريد: غير متاح'), findsWidgets);

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
