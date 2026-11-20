import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/models/cash_transfer_draft.dart';
import 'package:nasqo_pro_erp/screens/cash_transfer_draft_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

class _Workspace extends ErpController {
  _Workspace() : super(autoInitDb: false);
  int reads = 0;
  @override
  Future<List<CashTransferDraft>> loadCashTransferDrafts() async {
    reads++;
    return [];
  }
}

void main() {
  testWidgets('home opens a nonposting internal cash-transfer workspace',
      (tester) async {
    final c = _Workspace();
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = List.of(c.ledger);
    await tester.pumpWidget(NasqoProErpApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-cash-transfer-drafts')));
    await tester.pumpAndSettle();
    expect(find.byType(CashTransferDraftsView), findsOneWidget);
    expect(c.reads, 1);
    expect(c.ledger, before);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CashTransferDraftsView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
