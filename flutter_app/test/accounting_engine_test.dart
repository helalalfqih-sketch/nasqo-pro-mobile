import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/accounting_engine.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  test('parses Arabic-Indic digits and formats amounts', () {
    expect(AccountingEngine.parseArabicNumber('١٢٥٠٫٥'), 1250.5);
    expect(AccountingEngine.formatAmount(12500.5), '12,500.5');
  });

  test('weighted average cost updates accurately', () {
    final avg = AccountingEngine.computeWeightedAverageCost(10, 100, 10, 140);
    expect(avg, 120);
  });

  test('submitting sales invoice updates ledger and deducts inventory',
      () async {
    final controller = ErpController(autoInitDb: false);
    addTearDown(controller.dispose);
    final initialLedgerCount = controller.ledger.length;
    final item = controller.inventory.first;
    final initialQty = item.quantity;

    await controller.submitSalesInvoice(
      accountId: controller.accounts.first.id,
      customerName: 'عميل تجريبي',
      warehouse: controller.warehouses.first,
      payment: PaymentMethod.cash,
      includeVat: true,
      rows: [
        InvoiceItemRow(
          id: 'r1',
          itemId: item.id,
          productName: item.name,
          quantity: 2,
          unitPrice: 100,
        ),
      ],
    );

    expect(controller.ledger.length, initialLedgerCount + 1);
    expect(controller.ledger.first.amount, 230); // 200 + 15% VAT
    expect(controller.inventory.first.quantity, initialQty - 2);
  });
}
