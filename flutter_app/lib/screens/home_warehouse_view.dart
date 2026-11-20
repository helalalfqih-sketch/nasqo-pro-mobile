import 'package:flutter/material.dart';
import '../state/erp_controller.dart';
import 'workspace_views.dart';

/// Local read-only directory. Item records are counted, unlike quantities are
/// deliberately not summed across units. Warehouse creation/editing is absent.
class HomeWarehouseView extends StatelessWidget {
  const HomeWarehouseView({super.key, required this.controller});

  final ErpController controller;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('المخازن')),
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final itemCounts = <String, int>{};
              for (final item in controller.inventory) {
                itemCounts.update(item.warehouseId, (count) => count + 1,
                    ifAbsent: () => 1);
              }
              return ListView(
                key: const ValueKey('warehouse-directory'),
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('عرض محلي للقراءة فقط'),
                  const SizedBox(height: 12),
                  if (controller.warehouses.isEmpty)
                    const Text('لا توجد مخازن محلية'),
                  for (final warehouse in controller.warehouses)
                    Card(
                      key: ValueKey('warehouse-${warehouse.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(warehouse.name,
                                style: Theme.of(context).textTheme.titleMedium),
                            if (warehouse.details.isNotEmpty)
                              Text(warehouse.details),
                            if (warehouse.isDefault)
                              const Text('المخزن الافتراضي'),
                            Text(
                                'عدد الأصناف: ${itemCounts[warehouse.id] ?? 0}'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  key: ValueKey(
                                      'warehouse-inventory-${warehouse.id}'),
                                  icon: const Icon(Icons.inventory_2_outlined),
                                  label: const Text('عرض الأصناف'),
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => Directionality(
                                        textDirection: TextDirection.rtl,
                                        child: Scaffold(
                                          appBar: AppBar(
                                              title: Text(
                                                  'أصناف المخزن: ${warehouse.name}')),
                                          body: InventoryCatalogScreen(
                                            controller: controller,
                                            warehouseId: warehouse.id,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  key: ValueKey(
                                      'warehouse-movements-${warehouse.id}'),
                                  icon: const Icon(Icons.swap_horiz),
                                  label: const Text('حركة المخزون'),
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => Directionality(
                                        textDirection: TextDirection.rtl,
                                        child: Scaffold(
                                          appBar: AppBar(
                                              title: Text(
                                                  'حركة المخزون: ${warehouse.name}')),
                                          body: StockMovementScreen(
                                            controller: controller,
                                            warehouseId: warehouse.id,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
}
