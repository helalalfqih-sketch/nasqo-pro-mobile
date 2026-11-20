import 'package:nasqo_pro_erp/services/invoice_movement_report.dart';
import 'package:nasqo_pro_erp/screens/local_report_detail.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/web_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  testWidgets('offline reports reconcile synthetic categories, free invoices and dated stock', (tester) async {
    final c = ErpController(autoInitDb:false);
    addTearDown(c.dispose);
    c.accounts..clear()..add(const AccountRecord(id:'a',name:'عميل',category:AccountCategory.clients,
        openingBalance:10,openingDirection:EntryDirection.debit));
    c.ledger..clear()..add(const LedgerEntryRecord(id:'e',accountId:'a',accountName:'عميل',
        kind:LedgerKind.invoice,typeLabel:'خدمة',payment:PaymentMethod.credit,direction:EntryDirection.debit,
        amount:40,entryNumber:7,entryDate:'2026-01-01'));
    c.restoredGroups = RestoredGroups.fromJson({
      'ledger':[{'id':'e','invoiceContent':'free'}],
      'inventory':[{'id':'i','expiryDate':'2020-01-01','legacyId':77}]
    });
    c.inventory..clear()..add(const InventoryItemRecord(id:'i',name:'صنف اختبار',unit:'حبة',quantity:3,avgCost:4));
    Future<void> open(LocalReport report) async {
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:LocalReportDetail(
          key:ValueKey(report),controller:c,report:report))));
      await tester.pumpAndSettle();
    }
    await open(LocalReport.closing);
    expect(find.text('صافي الربح'),findsOneWidget);
    expect(find.text('52'),findsOneWidget);
    await open(LocalReport.category);
    expect(find.text('50 عليه'),findsOneWidget);
    await open(LocalReport.services);
    expect(find.text('صافي الخدمات: 40'),findsOneWidget);
    await open(LocalReport.stock);
    expect(find.text('إجمالي القيمة: 12'),findsOneWidget);
    expect(find.text('77'),findsOneWidget);
    c.ledger.clear();
    c.saleLines.clear();
    void post(String id,LedgerKind kind,EntryDirection direction,double qty,double price) {
      c.ledger.add(LedgerEntryRecord(id:id,accountId:'a',accountName:'عميل',
        kind:kind,typeLabel:'حركة',payment:PaymentMethod.credit,direction:direction,amount:qty*price,
        entryNumber:c.ledger.length+1,entryDate:'2026-01-01'));
      c.saleLines.add(SavedSaleLine(entryId:id,position:0,itemId:'i',itemName:'صنف اختبار',unit:'حبة',quantity:qty,unitPrice:price));
    }
    post('buy',LedgerKind.invoice,EntryDirection.credit,10,5);
    post('sale',LedgerKind.invoice,EntryDirection.debit,4,10);
    post('return',LedgerKind.returnEntry,EntryDirection.credit,1,10);
    await open(LocalReport.profit);
    expect(find.text('إجمالي المبيعات: 30'),findsOneWidget);
    expect(find.text('إجمالي الأرباح: 15'),findsOneWidget);
    await open(LocalReport.movement);
    expect(find.text('صافي كمية الشراء'),findsOneWidget);
    expect(find.text('إجمالي الأرباح: 15'),findsOneWidget);
    final transferData=RestoredGroups.fromJson({
      'stockTransfers':[{'id':1,'transferDate':'2026-02-10','fromWarehouseId':c.inventory.single.warehouseId,'toWarehouseId':'other'}],
      'stockTransferLines':[{'transferId':1,'inventoryItemId':'i','quantity':2,'unitNum':2}],
      'inventory':[{'id':'i','count2':3}]
    });
    final filtered=invoiceMovementReport(inventory:c.inventory,ledger:c.ledger,lines:c.saleLines,
      currency:c.defaultCurrency,metadata:transferData,warehouse:'other',from:'2026-02-01',through:'2026-02-28').single;
    expect(filtered.opening,0);
    expect(filtered.incoming,6);
    expect(filtered.remaining,6);
    final later=invoiceMovementReport(inventory:c.inventory,ledger:c.ledger,lines:c.saleLines,
      currency:c.defaultCurrency,metadata:transferData,warehouse:'other',from:'2026-03-01').single;
    expect(later.opening,6);
    expect(later.incoming,0);
    await open(LocalReport.expiry);
    expect(find.text('2020-01-01'),findsOneWidget);
    expect(find.textContaining('منتهي منذ'),findsOneWidget);
  });
  testWidgets('home quick actions resolve a stock code and receive its quantity', (tester) async {
    final controller = ErpController(autoInitDb: false);
    addTearDown(controller.dispose);
    final original = controller.inventory.first;
    await tester.pumpWidget(NasqoProErpApp(controller: controller));
    await tester.tap(find.byTooltip('الإجراءات السريعة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مسح باركود'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, original.id);
    await tester.tap(find.byTooltip('بحث'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '٢');
    await tester.ensureVisible(find.text('توريد للمخزون'));
    await tester.tap(find.text('توريد للمخزون'));
    await tester.pumpAndSettle();
    expect(controller.inventory.firstWhere((i) => i.id == original.id).quantity, original.quantity + 2);
    expect(find.byTooltip('الإجراءات السريعة'), findsOneWidget);
  });

  testWidgets('reports open the inventory and back returns to the report menu', (tester) async {
    final controller = ErpController(autoInitDb: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(NasqoProErpApp(controller: controller));
    await tester.tap(find.text('التقارير').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('المخزون المتبقي'));
    await tester.pumpAndSettle();
    expect(find.text('مخزن التقرير'), findsOneWidget);
    expect(find.textContaining('إجمالي القيمة:'), findsOneWidget);
    expect(find.text('الوحدة'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('المخزون المتبقي'), findsOneWidget);
  });
}
