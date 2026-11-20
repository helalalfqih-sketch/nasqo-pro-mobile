import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/models/nonposting_document.dart';
import 'package:nasqo_pro_erp/screens/nonposting_document_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

class _Workspace extends ErpController {
  _Workspace() : super(autoInitDb: false);
  final loaded = <NonpostingDocumentType>[];
  int writes = 0;

  @override
  Future<List<NonpostingDocument>> loadNonpostingDocuments(
      NonpostingDocumentType type) async {
    loaded.add(type);
    return const [];
  }

  @override
  Future<NonpostingDocument> saveNonpostingDocument(
      NonpostingDocument document) async {
    writes++;
    return document;
  }
}

void main() {
  testWidgets('home and drawer distinguish direct drafts from document lists',
      (tester) async {
    final c = _Workspace();
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1212, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(NasqoProErpApp(controller: c));
    await tester.pumpAndSettle();
    for (final key in ['home-quote-new', 'home-order-new']) {
      final finder = find.byKey(ValueKey(key));
      expect(finder, findsOneWidget);
      expect(tester.widget<FilledButton>(finder).onPressed, isNotNull);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      final draft = find.byType(NonpostingDocumentEditor);
      expect(draft, findsOneWidget);
      expect(
          tester.widget<NonpostingDocumentEditor>(draft).type,
          key == 'home-quote-new'
              ? NonpostingDocumentType.quote
              : NonpostingDocumentType.order);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(draft, findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    expect(c.writes, 0);
    expect(c.loaded, containsAll(NonpostingDocumentType.values));
    await tester.tap(find.byKey(const ValueKey('home-open-drawer')));
    await tester.pumpAndSettle();
    for (final key in ['nasqo-drawer-quotes', 'nasqo-drawer-orders']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    final quotes = find.byKey(const ValueKey('nasqo-drawer-quotes'));
    await tester.ensureVisible(quotes);
    await tester.tap(quotes);
    await tester.pumpAndSettle();
    expect(find.byType(NonpostingDocumentsView), findsOneWidget);
    expect(find.byType(NonpostingDocumentEditor), findsNothing);
    expect(c.writes, 0);
    expect(tester.takeException(), isNull);
  });
}
