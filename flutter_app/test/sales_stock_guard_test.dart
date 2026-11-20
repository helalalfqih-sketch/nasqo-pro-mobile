import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  late ErpController controller;
  setUp(() => controller = ErpController(autoInitDb: false));
  tearDown(() => controller.dispose());

  InvoiceItemRow row(InventoryItemRecord item, double qty,
          {double price = 10}) =>
      InvoiceItemRow(
          id: 'test',
          itemId: item.id,
          productName: item.name,
          quantity: qty,
          unitPrice: price);

  Future<void> submit(List<InvoiceItemRow> rows,
          {WarehouseRecord? warehouse}) =>
      controller.submitSalesInvoice(
        accountId: controller.accounts.first.id,
        customerName: 'Synthetic',
        warehouse: warehouse ?? controller.warehouses.first,
        payment: PaymentMethod.cash,
        includeVat: false,
        rows: rows,
      );

  test(
      'combined duplicate demand rejects whole sale without ledger or stock change',
      () async {
    final item = controller.inventory.first;
    final qty = item.quantity;
    final before = controller.ledger.length;
    await expectLater(
        submit([row(item, qty - 1), row(item, 2)]), throwsException);
    expect(controller.inventory.first.quantity, qty);
    expect(controller.ledger.length, before);
  });

  test('a warehouse mismatch rejects whole sale', () async {
    final item = controller.inventory.first;
    final other =
        controller.warehouses.firstWhere((w) => w.id != item.warehouseId);
    final before = controller.ledger.length;
    await expectLater(
        submit([row(item, 1)], warehouse: other), throwsException);
    expect(controller.inventory.first.quantity, item.quantity);
    expect(controller.ledger.length, before);
  });

  test(
      'non-finite, negative, zero quantity and empty invoices reject before mutation',
      () async {
    final item = controller.inventory.first;
    final before = controller.ledger.length;
    for (final rows in <List<InvoiceItemRow>>[
      [],
      [row(item, -1)],
      [row(item, 0)],
      [row(item, 1, price: -1)],
      [row(item, 1, price: double.infinity)],
    ]) {
      await expectLater(submit(rows), throwsException);
    }
    expect(controller.inventory.first.quantity, item.quantity);
    expect(controller.ledger.length, before);
  });

  test('exact stock boundary accepts and never makes stock negative', () async {
    final item = controller.inventory.first;
    final originalLedger = controller.ledger.length;
    await submit([row(item, item.quantity - 1), row(item, 1)]);
    expect(controller.inventory.first.quantity, 0);
    expect(controller.ledger.length, originalLedger + 1);
    expect(controller.ledger.first.amount, item.quantity * 10);
  });
}
