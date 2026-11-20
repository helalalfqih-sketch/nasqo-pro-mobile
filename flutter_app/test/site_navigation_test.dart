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
    await open(LocalReport.category);
    expect(find.text('50 عليه'),findsOneWidget);
    await open(LocalReport.services);
    expect(find.text('صافي الخدمات: 40'),findsOneWidget);
    await open(LocalReport.stock);
    expect(find.text('إجمالي القيمة: 12'),findsOneWidget);
    expect(find.text('77'),findsOneWidget);
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
