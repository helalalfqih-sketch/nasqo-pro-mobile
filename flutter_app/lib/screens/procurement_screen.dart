import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';

class ProcurementScreen extends StatelessWidget {
  const ProcurementScreen({super.key, required this.controller});
  final ErpController controller;

  @override
  Widget build(BuildContext context) {
    final cur = controller.defaultCurrency.label;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('أوامر الشراء والتوريد',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            FilledButton.icon(
              onPressed: () {
                final supplier = controller.accounts.firstWhere(
                  (a) => a.category == AccountCategory.purchases,
                  orElse: () => controller.accounts.first,
                );
                final item = controller.inventory.first;
                controller.createPurchaseOrder(
                  supplier: supplier,
                  warehouse: controller.warehouses.first,
                  item: item,
                  quantity: 10,
                  unitCost: item.avgCost,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('تم إنشاء أمر شراء سريع واعتماده')),
                );
              },
              icon: const Icon(Icons.add_shopping_cart, size: 16),
              label: const Text('أمر شراء جديد'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...controller.purchaseOrders.map((po) {
          final total = AccountingEngine.computePurchaseOrderTotal(po);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${po.poNumber} · ${po.supplierName}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Chip(label: Text(po.status.label)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'المستودع: ${po.warehouseName} · التاريخ: ${po.orderDate}'),
                  Text(
                    'الإجمالي: ${AccountingEngine.formatAmount(total)} $cur',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF0B5CA8)),
                  ),
                  if (po.status != PurchaseOrderStatus.received) ...[
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () {
                        controller.receivePurchaseOrder(po.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'تم استلام ${po.poNumber} وتحديث المخزون')),
                        );
                      },
                      child: const Text('استلام بالمخزن وترحيل التكلفة'),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
