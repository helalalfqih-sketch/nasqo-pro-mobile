import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/invoice_workspace.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  testWidgets('switching invoice modes preserves the typed drafts and posts only the visible free purchase', (tester) async {
    final c = ErpController(autoInitDb:false);
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(390,844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final supplier = c.accounts.firstWhere((a) => a.category == AccountCategory.purchases);
    final stock = {for(final i in c.inventory) i.id:i.quantity};
    final oldCount = c.ledger.length;
    await tester.pumpWidget(MaterialApp(builder:(_,child)=>Directionality(textDirection:TextDirection.rtl,child:child!),home:Scaffold(body:Builder(builder:(context) =>
      TextButton(child:const Text('فتح'), onPressed:() => Navigator.push<void>(context,
          MaterialPageRoute(builder:(_) => InvoiceWorkspace(controller:c))))))));
    Future<void> tap(Finder target) async {
      await Scrollable.ensureVisible(tester.element(target),alignment:.5);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    await tap(find.text('فتح'));
    await tap(find.widgetWithText(DropdownButtonFormField<String>,'المورد'));
    await tap(find.text(supplier.name).last);
    await tap(find.widgetWithText(DropdownButtonFormField<String>,'المستودع'));
    await tap(find.text(c.warehouses.first.name).last);
    await tap(find.text('حرة'));
    final amount = find.widgetWithText(TextField,'إجمالي مبلغ الفاتورة');
    await tester.enterText(amount,'٤٠');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tap(find.text('فاتورة بيع'));
    expect(tester.widget<SegmentedButton<PaymentMethod>>(find.byType(SegmentedButton<PaymentMethod>)).selected,
        {PaymentMethod.credit});
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,isFalse);
    await tap(find.text('حرة'));
    await tester.enterText(amount,'١٠٠');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tap(find.text('فاتورة شراء'));
    expect(tester.widget<TextField>(amount).controller!.text,'٤٠');
    expect(c.ledger.length,oldCount);
    await tap(find.text('حفظ وترحيل المشتريات'));
    expect(c.ledger.length,oldCount+1);
    expect(c.ledger.first.amount,40);
    expect(c.ledger.first.accountId,supplier.id);
    expect({for(final i in c.inventory) i.id:i.quantity},stock);
    expect(find.byType(InvoiceWorkspace),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
