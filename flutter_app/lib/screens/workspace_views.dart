import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../models/sales_return_draft.dart';
import 'original_sale_facts_view.dart';
import '../state/erp_controller.dart';

String _number(double value) => value.isFinite
    ? value.toString().replaceFirst(RegExp(r'\.0$'), '')
    : 'غير صالح';

String _warehouseName(ErpController controller, String id) {
  for (final warehouse in controller.warehouses) {
    if (warehouse.id == id) return warehouse.name;
  }
  return id.isEmpty ? 'غير محدد' : 'مستودع غير معروف ($id)';
}

/// A read-only, RTL table. Put it inside a vertically scrolling page.
/// It owns its horizontal controller so multiple tables do not share scrolling.
class RtlScrollableTable extends StatefulWidget {
  const RtlScrollableTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'لا توجد سجلات للعرض.',
    this.firstCellAction,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final String emptyMessage;
  final void Function(int rowIndex)? firstCellAction;

  @override
  State<RtlScrollableTable> createState() => _RtlScrollableTableState();
}

class _RtlScrollableTableState extends State<RtlScrollableTable> {
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(widget.emptyMessage),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('مرّر الجدول أفقياً لعرض جميع الأعمدة.'),
          ),
          Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 16),
              child: DataTable(
                columns: widget.columns
                    .map((label) => DataColumn(label: Text(label)))
                    .toList(),
                rows: widget.rows.asMap().entries.map((entry) {
                  final row = entry.value;
                  return DataRow(
                    cells: List.generate(widget.columns.length, (index) {
                      return DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            index < row.length ? row[index] : '—',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: index == 0 && widget.firstCellAction != null
                                ? TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    decoration: TextDecoration.underline)
                                : null,
                          ),
                        ),
                        onTap: index == 0 && widget.firstCellAction != null
                            ? () => widget.firstCellAction!(entry.key)
                            : null,
                      );
                    }),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _notice(String text) =>
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(text)));

/// Informational only: no reset, edits, credentials, exports or network calls.
class WorkspaceSettingsScreen extends StatelessWidget {
  const WorkspaceSettingsScreen({
    super.key,
    required this.controller,
    this.openLocalBackups,
  });
  final ErpController controller;
  final VoidCallback? openLocalBackups;

  Future<void> _editName(BuildContext context) async {
    var name = controller.companyName;
    final value = await showDialog<String>(context: context, builder: (context) =>
      AlertDialog(title: const Text('اسم المنشأة'), content: TextFormField(
        initialValue: name, maxLength: 100, autofocus: true, onChanged: (v) => name = v),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, name.trim()), child: const Text('حفظ')),
        ]));
    if (value == null || !context.mounted) return;
    try {
      await controller.renameCompany(value);
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is SaleValidationException ? error.message : 'تعذر حفظ الاسم.')));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'إعدادات مساحة العمل',
                style: Theme.of(context).textTheme.headlineSmall,
              ),

              if (openLocalBackups != null)
                OutlinedButton.icon(
                  key: const ValueKey('settings-open-backup-workspace'),
                  onPressed: openLocalBackups,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('النسخ المحلية واختبار الاستعادة'),
                ),
              ListTile(
                title: const Text('اسم المنشأة'),
                subtitle: Text(controller.companyName),
                trailing: const Icon(Icons.edit_outlined), onTap: () => _editName(context),
              ),
              ListTile(
                title: const Text('العملة الافتراضية'),
                subtitle: Text(controller.defaultCurrency.label),
              ),
              SwitchListTile(
                value: controller.isDarkMode, onChanged: (_) => controller.toggleTheme(),
                title: const Text('المظهر المحدد'),
                subtitle: Text(controller.isDarkMode ? 'داكن' : 'فاتح'),
              ),
              ListTile(
                title: const Text('حالة تهيئة قاعدة البيانات المحلية'),
                subtitle: Text(
                  controller.dbReady
                      ? 'يشير التطبيق إلى اكتمال التهيئة.'
                      : 'لم تؤكد الحالة اكتمال التهيئة.',
                ),
              ),
              _notice(
                'حالة التهيئة ليست اختبار سلامة أو إثباتاً لوجود نسخة احتياطية. المعروض أدناه هو عدد السجلات المحمّلة في الذاكرة، وقد يتضمن بيانات البداية التجريبية.',
              ),
              RtlScrollableTable(
                columns: const ['المجموعة', 'السجلات المحمّلة'],
                rows: [
                  ['الحسابات', '${controller.accounts.length}'],
                  ['رؤوس العمليات', '${controller.ledger.length}'],
                  ['المستودعات', '${controller.warehouses.length}'],
                  ['الأصناف', '${controller.inventory.length}'],
                ],
              ),
            ],
          ),
        ),
      );
}

class InventoryCatalogScreen extends StatefulWidget {
  const InventoryCatalogScreen({
    super.key,
    required this.controller,
    this.warehouseId,
  });
  final ErpController controller;
  final String? warehouseId;

  @override
  State<InventoryCatalogScreen> createState() => _InventoryCatalogScreenState();
}

class _InventoryCatalogScreenState extends State<InventoryCatalogScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final query = _query.trim().toLowerCase();
          final items = controller.inventory
              .where(
                (item) =>
                    (widget.warehouseId == null ||
                        item.warehouseId == widget.warehouseId) &&
                    '${item.name} ${item.sku} ${item.id}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList();
          return Directionality(
            textDirection: TextDirection.rtl,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'دليل الأصناف والمخزون',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (widget.warehouseId != null)
                  Text(
                    'المستودع: ${_warehouseName(controller, widget.warehouseId!)}',
                  ),
                _notice(
                  'لقطة الكميات والتكلفة المحمّلة حالياً، وليست كشف حركة تاريخية أو نتيجة جرد معتمد. لا يحتوي سجل الصنف على عملة تكلفة مستقلة؛ لا تُجمع القيم بين العملات أو الوحدات.',
                ),
                TextField(
                  key: const ValueKey('inventory-catalog-search'),
                  decoration: const InputDecoration(
                    labelText: 'بحث باسم الصنف أو رمزه',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('الأصناف المعروضة: ${items.length}'),
                ),
                RtlScrollableTable(
                  columns: const [
                    'الصنف',
                    'الرمز',
                    'المستودع',
                    'الوحدة',
                    'الكمية الحالية',
                    'متوسط التكلفة المسجل',
                    'حد التنبيه',
                  ],
                  rows: items
                      .map(
                        (item) => [
                          item.name,
                          item.sku.isEmpty ? '—' : item.sku,
                          _warehouseName(controller, item.warehouseId),
                          item.unit,
                          _number(item.quantity),
                          _number(item.avgCost),
                          _number(item.minThreshold),
                        ],
                      )
                      .toList(),
                  emptyMessage: 'لا توجد أصناف تطابق البحث ونطاق المستودع.',
                ),
              ],
            ),
          );
        },
      );
}

/// Quantity evidence only for durable new sale lines. Legacy headers are separate.
class StockMovementScreen extends StatelessWidget {
  const StockMovementScreen({
    super.key,
    required this.controller,
    this.warehouseId,
  });
  final ErpController controller;
  final String? warehouseId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final entries = controller.ledger
              .where(
                (entry) =>
                    !entry.deleted &&
                    (entry.kind == LedgerKind.invoice ||
                        entry.kind == LedgerKind.returnEntry) &&
                    (warehouseId == null || entry.warehouseId == warehouseId),
              )
              .toList()
            ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
          final byId = {for (final entry in entries) entry.id: entry};
          final saleRows = controller.saleLines.where((line) {
            final entry = byId[line.entryId];
            return entry != null && isEligibleSalesReturnSource(entry);
          }).toList()
            ..sort((a, b) {
              final order = byId[b.entryId]!
                  .entryNumber
                  .compareTo(byId[a.entryId]!.entryNumber);
              return order == 0 ? a.position.compareTo(b.position) : order;
            });
          return Directionality(
            textDirection: TextDirection.rtl,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'حركة المخزون: حدود البيانات',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                _notice(
                  'يعرض المنصرف الموثق من بنود المبيعات الجديدة فقط. لا يُستنتج رصيد تاريخي أو وارد من المستندات القديمة.',
                ),
                if (warehouseId != null)
                  Text('المستودع: ${_warehouseName(controller, warehouseId!)}'),
                if (saleRows.isNotEmpty) ...[
                  const Text('منصرف المبيعات الموثق'),
                  const Text(
                      'اضغط رقم المستند لعرض تفاصيل البيع الأصلية المتاحة.'),
                  RtlScrollableTable(
                    columns: const [
                      'المستند',
                      'التاريخ',
                      'الصنف',
                      'المستودع',
                      'الكمية',
                      'الوحدة'
                    ],
                    rows: saleRows.map((line) {
                      final entry = byId[line.entryId]!;
                      return [
                        entry.documentNumber,
                        entry.entryDate,
                        line.itemName,
                        _warehouseName(controller, entry.warehouseId),
                        _number(line.quantity),
                        line.unit
                      ];
                    }).toList(),
                    firstCellAction: (index) {
                      final entry = byId[saleRows[index].entryId]!;
                      if (!isEligibleSalesReturnSource(entry)) return;
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => OriginalSaleFactsView(
                          entryId: entry.id,
                          loadFacts: controller.loadOriginalSaleFacts,
                        ),
                      ));
                    },
                    emptyMessage: 'لا يوجد منصرف مبيعات موثق.',
                  ),
                ],
                const Text(
                    'رؤوس الفواتير والمرتجعات المتاحة (قرائن مالية فقط)'),
                _notice(
                  'المبالغ التالية مبالغ مستندات، وليست كميات مخزون. لا تُستنتج حركة صنف من البيان النصي. تُستبعد العمليات المحذوفة وعروض الأسعار والطلبيات والحوالات؛ الحوالة المالية ليست تحويلاً مخزنياً.',
                ),
                RtlScrollableTable(
                  columns: const [
                    'رقم العملية',
                    'التاريخ',
                    'النوع',
                    'الحساب',
                    'المستودع',
                    'مبلغ المستند',
                    'العملة',
                  ],
                  rows: entries
                      .map(
                        (entry) => [
                          '${entry.entryNumber}',
                          entry.entryDate,
                          entry.typeLabel.isEmpty
                              ? (entry.kind == LedgerKind.returnEntry
                                  ? 'مرتجع'
                                  : 'فاتورة')
                              : entry.typeLabel,
                          entry.accountName,
                          _warehouseName(controller, entry.warehouseId),
                          _number(entry.amount),
                          entry.currency.label,
                        ],
                      )
                      .toList(),
                  emptyMessage:
                      'لا توجد رؤوس فواتير أو مرتجعات نشطة في هذا النطاق. هذا لا يثبت عدم وجود حركة مخزنية تاريخية.',
                ),
              ],
            ),
          );
        },
      );
}
