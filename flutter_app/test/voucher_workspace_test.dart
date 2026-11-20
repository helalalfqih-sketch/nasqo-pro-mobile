import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/models/voucher_draft.dart';
import 'package:nasqo_pro_erp/screens/voucher_draft_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

class _Workspace extends ErpController {
  _Workspace() : super(autoInitDb: false);
  final readTypes = <VoucherDraftType>[];
  @override
  Future<List<VoucherDraft>> loadVoucherDrafts(VoucherDraftType type) async {
    readTypes.add(type);
    return [];
  }
}

void main() {
  testWidgets('home receipt and payment lead to separate nonposting lists',
      (tester) async {
    final c = _Workspace();
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ledgerBefore = List.of(c.ledger);
    await tester.pumpWidget(NasqoProErpApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-vouchers')));
    await tester.pumpAndSettle();
    for (final (key, type) in [
      ('open-receipt-drafts', VoucherDraftType.receipt),
      ('open-payment-drafts', VoucherDraftType.payment),
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      final view = find.byType(VoucherDraftsView);
      expect(view, findsOneWidget);
      expect(tester.widget<VoucherDraftsView>(view).type, type);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(view, findsNothing);
    }
    expect(c.readTypes, VoucherDraftType.values);
    expect(c.ledger, ledgerBefore);
    expect(tester.takeException(), isNull);
  });
}
