import 'package:flutter/material.dart';
import '../state/erp_controller.dart';
import '../models/erp_models.dart';
import 'workspace_views.dart';

class HomeWarehouseView extends StatefulWidget {
  const HomeWarehouseView({super.key, required this.controller});
  final ErpController controller;
  @override
  State<HomeWarehouseView> createState() => _WarehouseState();
}

class _WarehouseState extends State<HomeWarehouseView> {
  ErpController get controller => widget.controller;
  String search = '';

  Future<void> edit([WarehouseRecord? warehouse]) async {
    var name = warehouse?.name ?? '', details = warehouse?.details ?? '';
    var isDefault = warehouse?.isDefault ?? controller.warehouses.isEmpty;
    var saving = false;
    String? error;
    await showDialog<void>(context: context, barrierDismissible: false, builder: (context) =>
      StatefulBuilder(builder: (context, update) => PopScope(canPop: !saving,
        child: AlertDialog(title: Text(warehouse == null ? 'إضافة مخزن' : 'تعديل المخزن'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(initialValue: name, maxLength: 100, autofocus: true,
              decoration: const InputDecoration(labelText: 'اسم المخزن'), onChanged: (v) => name = v),
            TextFormField(initialValue: details, maxLength: 300,
              decoration: const InputDecoration(labelText: 'التفاصيل'), onChanged: (v) => details = v),
            SwitchListTile(title: const Text('المخزن الافتراضي'), value: isDefault,
              onChanged: saving || warehouse?.isDefault == true || controller.warehouses.isEmpty ? null :
                (v) => update(() => isDefault = v)),
            if (error != null) Text(error!),
          ])),
          actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(onPressed: saving ? null : () async {
              update(() => saving = true);
              try {
                await controller.saveWarehouse(id: warehouse?.id, name: name, details: details, isDefault: isDefault);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) update(() { saving = false; error = e is SaleValidationException ? e.message : 'تعذر حفظ المخزن.'; });
              }
            }, child: const Text('حفظ'))])))));
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('المخازن'), actions: [IconButton(
            tooltip: 'إضافة مخزن', onPressed: () => edit(), icon: const Icon(Icons.add))]),
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
                  TextField(decoration: const InputDecoration(labelText: 'ابحث عن المخزن', prefixIcon: Icon(Icons.search)),
                    onChanged: (value) => setState(() => search = value.trim().toLowerCase())),
                  const SizedBox(height: 12),
                  if (controller.warehouses.isEmpty)
                    const Text('لا توجد مخازن محلية'),
                  for (final warehouse in controller.warehouses.where((w) => w.name.toLowerCase().contains(search)))
                    Card(
                      key: ValueKey('warehouse-${warehouse.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(contentPadding: EdgeInsets.zero, title: Text(warehouse.name),
                              trailing: IconButton(tooltip: 'تعديل المخزن', onPressed: () => edit(warehouse), icon: const Icon(Icons.edit_outlined))),
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
