import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/models/sale_tax_register.dart';
import 'package:nasqo_pro_erp/screens/sale_tax_register_view.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

class _Workspace extends ErpController {
  _Workspace() : super(autoInitDb: false);
  int reads = 0;

  @override
  Future<SaleTaxRegister> loadSaleTaxRegister(
      {String? from, String? through}) async {
    reads++;
    return SaleTaxRegister(
        from: from, through: through, rows: [], currencies: []);
  }
}

void main() {
  testWidgets('local finance opens a separate read-only recorded-tax register',
      (tester) async {
    final c = _Workspace();
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(990, 880);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ledgerBefore = List.of(c.ledger);
    await tester.pumpWidget(NasqoProErpApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-open-drawer')));
    await tester.pumpAndSettle();
    final review = find.byKey(const ValueKey('nasqo-drawer-finance'));
    await tester.scrollUntilVisible(review,250,
        scrollable:find.descendant(of:find.byKey(const Key('nasqo-web-drawer-list')),matching:find.byType(Scrollable)).first);
    await Scrollable.ensureVisible(tester.element(review),alignment:0.5);
    await tester.pumpAndSettle();
    await tester.tap(review);
    await tester.pumpAndSettle();
    await tester.tap(find.text('VAT 15%'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finance-recorded-sales-tax')));
    await tester.pumpAndSettle();
    expect(find.byType(SaleTaxRegisterView), findsOneWidget);
    expect(c.reads, 1);
    expect(c.ledger, ledgerBefore);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SaleTaxRegisterView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
