import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/models/simple_journal_draft.dart';
import 'package:nasqo_pro_erp/screens/simple_journal_draft_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

class _Workspace extends ErpController {
  _Workspace() : super(autoInitDb: false);
  int reads = 0;
  @override
  Future<List<SimpleJournalDraft>> loadSimpleJournalDrafts() async {
    reads++;
    return [];
  }
}

void main() {
  testWidgets('home routes to nonposting balanced simple journal drafts',
      (tester) async {
    final c = _Workspace();
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ledger = List.of(c.ledger);
    final inventory = List.of(c.inventory);
    await tester.pumpWidget(NasqoProErpApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-simple-journal-drafts')));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleJournalDraftsView), findsOneWidget);
    expect(c.reads, 1);
    expect(c.ledger, ledger);
    expect(c.inventory, inventory);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SimpleJournalDraftsView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
