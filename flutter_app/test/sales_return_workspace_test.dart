import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/models/sales_return_draft.dart';
import 'package:nasqo_pro_erp/screens/sales_return_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

class _ReturnWorkspace extends ErpController {
  _ReturnWorkspace() : super(autoInitDb: false);
  int reads = 0;
  @override
  Future<List<SalesReturnDraft>> loadSalesReturnDrafts() async {
    reads++;
    return const [];
  }
}

void main() {
  testWidgets('home opens only the unposted return workspace', (tester) async {
    final controller = _ReturnWorkspace();
    addTearDown(controller.dispose);
    final before = controller.ledger.length;
    tester.view.physicalSize = const Size(1212, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(NasqoProErpApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-sales-return-drafts')));
    await tester.pumpAndSettle();
    expect(find.byType(SalesReturnDraftsView), findsOneWidget);
    expect(controller.reads, 1);
    expect(controller.ledger, hasLength(before));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SalesReturnDraftsView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
