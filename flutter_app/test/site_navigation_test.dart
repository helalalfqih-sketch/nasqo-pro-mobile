import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
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
    expect(find.byKey(const ValueKey('inventory-catalog-search')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('المخزون المتبقي'), findsOneWidget);
  });
}
