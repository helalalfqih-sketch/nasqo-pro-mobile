import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/screens/home_sales_register_view.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  testWidgets(
      'sales register opens preview-only export and returns without mutating ledger',
      (tester) async {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(820, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = List.of(c.ledger);
    await tester.pumpWidget(NasqoProErpApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-open-drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nasqo-drawer-sales-register')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeSalesRegisterView), findsOneWidget);
    final export = find.text('تصدير المبيعات CSV');
    expect(export, findsOneWidget);
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(find.text('إعداد المعاينة'), findsOneWidget);
    expect(find.text('اختيار الوجهة وحفظ CSV'), findsNothing);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(HomeSalesRegisterView), findsOneWidget);
    expect(c.ledger, before);
    expect(tester.takeException(), isNull);
  });
}
