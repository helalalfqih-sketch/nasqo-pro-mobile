import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sale_facts.dart';
import 'package:nasqo_pro_erp/screens/original_sale_facts_view.dart';
import 'package:nasqo_pro_erp/screens/workspace_views.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

class _Workspace extends ErpController {
  _Workspace() : super(autoInitDb: false);
  final List<String> reads = [];

  @override
  Future<SaleFacts?> loadOriginalSaleFacts(String entryId) async {
    reads.add(entryId);
    return null;
  }
}

void main() {
  testWidgets('stock movement links original sale number to a read-only view',
      (tester) async {
    final c = _Workspace();
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(820, 950);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = c.inventory.first;
    await c.submitSalesInvoice(
      accountId: c.accounts.first.id,
      customerName: 'Synthetic',
      warehouse: c.warehouses.firstWhere((w) => w.id == item.warehouseId),
      payment: PaymentMethod.cash,
      includeVat: true,
      rows: [
        InvoiceItemRow(
            id: 'synthetic',
            itemId: item.id,
            productName: item.name,
            quantity: 1,
            unitPrice: 0.3)
      ],
    );
    final entry = c.ledger.first;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StockMovementScreen(controller: c)),
    ));
    await tester.pumpAndSettle();
    final doc = find.text(entry.documentNumber);
    expect(doc, findsOneWidget);
    await tester.ensureVisible(doc);
    await tester.tap(doc);
    await tester.pumpAndSettle();
    expect(find.byType(OriginalSaleFactsView), findsOneWidget);
    expect(c.reads, [entry.id]);
    expect(c.ledger.first, same(entry));
    expect(tester.takeException(), isNull);
  });
}
