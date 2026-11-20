import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/screens/dashboard_screen.dart';
import 'package:nasqo_pro_erp/screens/erp_hub_screen.dart';
import 'package:nasqo_pro_erp/screens/finance_screen.dart';
import 'package:nasqo_pro_erp/screens/hr_screen.dart';
import 'package:nasqo_pro_erp/screens/manufacturing_screen.dart';
import 'package:nasqo_pro_erp/screens/pos_crm_screen.dart';
import 'package:nasqo_pro_erp/screens/procurement_screen.dart';
import 'package:nasqo_pro_erp/screens/workspace_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

Future<void> _start(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 580);
  final controller = ErpController(autoInitDb: false);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    controller.dispose();
  });
  await tester.pumpWidget(NasqoProErpApp(controller: controller));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String key) async {
  final tile = find.byKey(ValueKey(key));
  if (key.startsWith('home-') && key != 'home-open-drawer') {
    final list = find.byKey(const PageStorageKey('nasqo-home-scroll'));
    await tester.scrollUntilVisible(tile.hitTestable(), 120,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
  }
  expect(tile.hitTestable(), findsOneWidget);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

ScrollableState _position(WidgetTester tester, Finder page, Axis axis) {
  final states = tester.stateList<ScrollableState>(
    find.descendant(of: page, matching: find.byType(Scrollable)),
  );
  return states.firstWhere(
      (s) => s.position.axis == axis && s.position.maxScrollExtent > 0);
}

void main() {
  testWidgets('existing ERP modules open from the drawer and return by Back',
      (tester) async {
    await _start(tester);
    for (final (label, screen) in [
      ('القوائم المالية والأستاذ العام', FinanceScreen),
      ('المبيعات ونقطة البيع (POS / CRM)', PosCrmScreen),
      ('المشتريات وسلسلة التوريد', ProcurementScreen),
      ('الموارد البشرية والرواتب', HrScreen),
      ('التصنيع ومراكز التكلفة', ManufacturingScreen),
    ]) {
      await _open(tester, 'home-open-drawer');
      final drawer = find.byType(Drawer);
      final drawerList =
          find.descendant(of: drawer, matching: find.byType(Scrollable));
      final tile = find.descendant(of: drawer, matching: find.text(label));
      await tester.scrollUntilVisible(tile.hitTestable(), 90,
          scrollable: drawerList);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: label);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget, reason: label);
    }
    await _open(tester, 'home-erp');
    expect(find.byType(ErpHubScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL home scrolls and platform Back closes the drawer first',
      (tester) async {
    await _start(tester);
    final home = find.byType(DashboardScreen);
    expect(Directionality.of(tester.element(home)), TextDirection.rtl);
    final list = find.byKey(const PageStorageKey('nasqo-home-scroll'));
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
        _position(tester, home, Axis.vertical).position.pixels, greaterThan(0));
    await _open(tester, 'home-open-drawer');
    expect(find.byKey(const ValueKey('nasqo-drawer-home')).hitTestable(),
        findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nasqo-drawer-home')).hitTestable(),
        findsNothing);
    expect(home, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'settings can scroll vertically and Back returns to the home route',
      (tester) async {
    await _start(tester);
    await _open(tester, 'home-settings');
    final page = find.byType(WorkspaceSettingsScreen);
    expect(page, findsOneWidget);
    final list = find.descendant(of: page, matching: find.byType(ListView));
    await tester.drag(list, const Offset(0, -330));
    await tester.pumpAndSettle();
    expect(
        _position(tester, page, Axis.vertical).position.pixels, greaterThan(0));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (route, type, lastColumn) in [
    ('home-inventory', InventoryCatalogScreen, 'حد التنبيه'),
    ('home-stock-movement', StockMovementScreen, 'العملة'),
  ]) {
    testWidgets(
        '$route: RTL table drag reaches final column without moving page',
        (tester) async {
      await _start(tester);
      await _open(tester, route);
      final page = find.byType(type);
      expect(page, findsOneWidget);
      final table =
          find.descendant(of: page, matching: find.byType(RtlScrollableTable));
      final scroll = find.descendant(
          of: table, matching: find.byType(SingleChildScrollView));
      final pageList =
          find.descendant(of: page, matching: find.byType(ListView));
      for (var swipe = 0;
          swipe < 12 && scroll.hitTestable().evaluate().isEmpty;
          swipe++) {
        await tester.drag(pageList, const Offset(0, -125));
        await tester.pumpAndSettle();
      }
      expect(scroll.hitTestable(), findsOneWidget);
      await tester.pumpAndSettle();
      final horizontal = _position(tester, page, Axis.horizontal).position;
      expect(horizontal.axisDirection, AxisDirection.left);
      final verticals = tester
          .stateList<ScrollableState>(
            find.descendant(of: page, matching: find.byType(Scrollable)),
          )
          .where((s) => s.position.axis == Axis.vertical)
          .toList();
      final before = verticals.map((s) => s.position.pixels).toList();
      expect(horizontal.pixels, closeTo(0, 1));
      for (var drag = 0; drag < 5 && horizontal.extentAfter > 1; drag++) {
        await tester.drag(scroll, const Offset(310, 0));
        await tester.pumpAndSettle();
      }
      expect(horizontal.pixels, closeTo(horizontal.maxScrollExtent, 1));
      expect(find.text(lastColumn).hitTestable(), findsOneWidget);
      expect(verticals.map((s) => s.position.pixels).toList(), before);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
