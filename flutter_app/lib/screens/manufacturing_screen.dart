import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';

class ManufacturingScreen extends StatelessWidget {
  const ManufacturingScreen({super.key, required this.controller});
  final ErpController controller;

  @override
  Widget build(BuildContext context) {
    final cur = controller.defaultCurrency.label;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('أوامر التصنيع (BOM)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...controller.productionOrders.map((order) => Card(
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
                        Text('${order.orderNumber} · ${order.finishedItemName}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Chip(label: Text(order.status.label)),
                      ],
                    ),
                    Text(
                        'الكمية المطلوبة: ${order.quantityToProduce.toInt()} · الخلطة: ${order.bomName}'),
                    if (order.status != ProductionOrderStatus.completed) ...[
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () {
                          final err =
                              controller.completeProductionOrder(order.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                err ??
                                    'تم تصنيع ${order.orderNumber} وتحديث مخزون الخامات والمنتج التام',
                              ),
                            ),
                          );
                        },
                        child: const Text('إتمام التصنيع وسحب الخامات'),
                      ),
                    ],
                  ],
                ),
              ),
            )),
        const SizedBox(height: 12),
        const Text('مراكز التكلفة والموازنات',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...controller.costCenters.map((cc) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${cc.code} · ${cc.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('المسؤول: ${cc.managerName}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        'الموازنة: ${AccountingEngine.formatAmount(cc.budget)} $cur'),
                    Text(
                      'المنصرف: ${AccountingEngine.formatAmount(cc.extraPostedSpend)} $cur',
                      style: const TextStyle(
                          color: Color(0xFFF39A16), fontSize: 12),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}
