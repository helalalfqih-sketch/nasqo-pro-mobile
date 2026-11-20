import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/home_warehouse_view.dart';
import 'package:nasqo_pro_erp/screens/workspace_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  late ErpController controller;
  setUp(() {
    controller = ErpController(autoInitDb: false);
    controller.warehouses
      ..clear()
      ..addAll(const [
        WarehouseRecord(id: 'a', name: 'مخزن أ'),
        WarehouseRecord(id: 'b', name: 'مخزن ب'),
      ]);
    controller.inventory
      ..clear()
      ..addAll(const [
        InventoryItemRecord(
            id: '1',
            name: 'أرز',
            unit: 'كيلو',
            quantity: 100,
            avgCost: 1,
            warehouseId: 'a'),
        InventoryItemRecord(
            id: '2',
            name: 'علب',
            unit: 'حبة',
            quantity: 500,
            avgCost: 2,
            warehouseId: 'a'),
      ]);
  });
  tearDown(() => controller.dispose());
  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: HomeWarehouseView(controller: controller)));
  }

  testWidgets('lists local warehouses and counts item records, not quantities',
      (tester) async {
    await start(tester);
    expect(find.text('مخزن أ'), findsOneWidget);
    expect(find.text('مخزن ب'), findsOneWidget);
    expect(find.text('عدد الأصناف: 2'), findsOneWidget);
    expect(find.text('عدد الأصناف: 0'), findsOneWidget);
    expect(find.textContaining('600'), findsNothing);
    expect(
        Directionality.of(
            tester.element(find.byKey(const ValueKey('warehouse-directory')))),
        TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'opens existing inventory and movement screens scoped by ID without mutation',
      (tester) async {
    final inventoryBefore = List.of(controller.inventory);
    final ledgerBefore = List.of(controller.ledger);
    await start(tester);
    await tester.tap(find.byKey(const ValueKey('warehouse-inventory-a')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<InventoryCatalogScreen>(find.byType(InventoryCatalogScreen))
            .warehouseId,
        'a');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('warehouse-movements-b')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<StockMovementScreen>(find.byType(StockMovementScreen))
            .warehouseId,
        'b');
    expect(controller.inventory, orderedEquals(inventoryBefore));
    expect(controller.ledger, orderedEquals(ledgerBefore));
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty directory is explicit and read only', (tester) async {
    controller.warehouses.clear();
    await start(tester);
    expect(find.text('لا توجد مخازن محلية'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
