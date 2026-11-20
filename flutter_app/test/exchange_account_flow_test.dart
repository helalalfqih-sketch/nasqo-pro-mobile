import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/local_entry_view.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  testWidgets('exchange can find an account by its Arabic code, create one and keep the entered amount', (tester) async {
    final controller = ErpController(autoInitDb: false);
    addTearDown(controller.dispose);
    final original = controller.accounts.last;
    final count = controller.ledger.length;
    await tester.pumpWidget(MaterialApp(home: LocalEntryView(controller: controller,
      kind: LedgerKind.currency, openDrafts: () {})));
    final search = find.widgetWithText(TextField, 'ابحث عن الاسم هنا');
    final code = original.codeNumber.toString().split('').map((c) => '٠١٢٣٤٥٦٧٨٩'[int.parse(c)]).join();
    await tester.enterText(search, code);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButtonFormField<String>>(find.byType(DropdownButtonFormField<String>)).initialValue, original.id);
    final amount = find.widgetWithText(TextField, 'المبلغ');
    await tester.enterText(amount, '12');
    final addAccount = find.byTooltip('إضافة حساب للصرف');
    await tester.ensureVisible(addAccount);
    await tester.tap(addAccount);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'اسم الحساب'), 'حساب صرف تجريبي');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'حفظ الحساب');
    await Scrollable.ensureVisible(tester.element(save), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final added = controller.accounts.singleWhere((a) => a.name == 'حساب صرف تجريبي');
    expect(tester.widget<DropdownButtonFormField<String>>(find.byType(DropdownButtonFormField<String>)).initialValue, added.id);
    expect(tester.widget<TextField>(amount).controller!.text, '12');
    expect(controller.ledger.length, count);
  });
}
