import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/models/fx_draft.dart';
import 'package:nasqo_pro_erp/screens/dashboard_screen.dart';
import 'package:nasqo_pro_erp/screens/fx_draft_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

class _Workspace extends ErpController {
  _Workspace() : super(autoInitDb: false);
  int reads = 0;
  @override
  Future<List<FxDraft>> loadFxDrafts() async {
    reads++;
    return [];
  }
}

void main() {
  testWidgets('home tiles are navigable and FX is nonposting', (tester) async {
    final c = _Workspace();
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1220, 950);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ledger = List.of(c.ledger);
    final inventory = List.of(c.inventory);
    await tester.pumpWidget(NasqoProErpApp(controller: c));
    await tester.pumpAndSettle();
    final tiles = find.descendant(
        of: find.byType(DashboardScreen), matching: find.byType(FilledButton));
    expect(tiles, findsNWidgets(23));
    expect(
        tester
            .widgetList<FilledButton>(tiles)
            .every((b) => b.onPressed != null),
        isTrue);
    await tester.tap(find.byKey(const ValueKey('home-fx-drafts')));
    await tester.pumpAndSettle();
    expect(find.byType(FxDraftsView), findsOneWidget);
    expect(c.reads, 1);
    expect(c.ledger, ledger);
    expect(c.inventory, inventory);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FxDraftsView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
