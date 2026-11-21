import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/erp_models.dart';
import '../models/sales_return_draft.dart';
import '../services/accounting_engine.dart';
import 'original_sale_facts_view.dart';
import 'purchase_invoice_view.dart';
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

  Future<void> _editAppearance(BuildContext context) async {
    var primary=controller.primaryTint,secondary=controller.secondaryTint,radius=controller.homeRadius;
    const colors={0xff4338ca:'بنفسجي',0xff095a99:'أزرق',0xff0891b2:'فيروزي',0xff137652:'أخضر',0xffa85c00:'برتقالي'};
    final ok=await showDialog<bool>(context:context,builder:(dialog)=>StatefulBuilder(builder:(ctx,update)=>
      AlertDialog(title:const Text('تخصيص الواجهة الرئيسية'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final first in [true,false]) DropdownButtonFormField<int>(
          value:first?primary:secondary,decoration:InputDecoration(labelText:first?'لون الأزرار الأساسية':'لون الأزرار الثانوية'),
          items:[for(final color in {...colors,if(!colors.containsKey(first?primary:secondary)) (first?primary:secondary):'مخصص'}.entries)
            DropdownMenuItem(value:color.key,child:Row(children:[Icon(Icons.circle,color:Color(color.key)),const SizedBox(width:8),Text(color.value)]))],
          onChanged:(v)=>update((){if(first){primary=v!;}else{secondary=v!;}})),
        const Text('استدارة زوايا الأزرار'),
        Slider(value:radius,min:0,max:24,divisions:12,label:radius.round().toString(),onChanged:(v)=>update(()=>radius=v)),
        Wrap(spacing:4,children:[for(final label in ['سند جديد','البحث السريع']) Chip(label:Text(label,style:const TextStyle(color:Colors.white)),
          backgroundColor:Color(label=='سند جديد'?primary:secondary),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(radius)))]),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('إلغاء')),
        FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('حفظ المظهر'))])));
    if(ok!=true || !context.mounted) return;
    try{await controller.saveAppearance(primary,secondary,radius);}
    catch(e){if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }

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
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final picked = await showDialog<CurrencyCode>(
                    context: context,
                    builder: (dialogCtx) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: SimpleDialog(
                        title: const Text('اختر العملة الافتراضية'),
                        children: [
                          for (final c in CurrencyCode.values)
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(dialogCtx, c),
                              child: Text(c.label),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (picked != null && picked != controller.defaultCurrency && context.mounted) {
                    try {
                      await controller.setDefaultCurrency(picked);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    }
                  }
                },
              ),
              ListTile(leading:const Icon(Icons.palette_outlined),title:const Text('تخصيص الواجهة الرئيسية'),
                subtitle:const Text('ألوان الأزرار واستدارة الزوايا'),onTap:()=>_editAppearance(context)),
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
              TextButton.icon(
                key: const ValueKey('settings-reset-appearance'),
                onPressed: () async {
                  await controller.saveAppearance(0xff4338ca, 0xff0891b2, 24);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تمت استعادة الإعدادات الافتراضية للمظهر.')),
                    );
                  }
                },
                icon: const Icon(Icons.restore),
                label: const Text('استعادة المظهر الافتراضي'),
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
  bool _lowStockOnly = false;

  Future<void> _showTransferDialog(BuildContext context) async {
    final c = widget.controller;
    if (c.inventory.isEmpty || c.warehouses.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يلزم وجود صنف ومستودعين على الأقل للتحويل المخزني.')),
      );
      return;
    }
    var selectedItemId = c.inventory.first.id;
    var toWarehouseId = c.warehouses
        .firstWhere(
          (w) => w.id != c.inventory.first.warehouseId,
          orElse: () => c.warehouses.last,
        )
        .id;
    var qtyText = '1';
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, update) {
          final srcItem = c.inventory.firstWhere((i) => i.id == selectedItemId);
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تحويل مخزني بين المستودعات'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedItemId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'الصنف المصدر'),
                      items: [
                        for (final item in c.inventory)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text('${item.name} (${_warehouseName(c, item.warehouseId)} · متوفر: ${_number(item.quantity)})'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        final nextItem = c.inventory.firstWhere((i) => i.id == v);
                        update(() {
                          selectedItemId = v;
                          final alt = c.warehouses.where((w) => w.id != nextItem.warehouseId).firstOrNull;
                          if (alt != null) toWarehouseId = alt.id;
                        });
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: toWarehouseId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'إلى المستودع'),
                      items: [
                        for (final w in c.warehouses.where((w) => w.id != srcItem.warehouseId))
                          DropdownMenuItem(value: w.id, child: Text(w.name)),
                      ],
                      onChanged: (v) {
                        if (v != null) update(() => toWarehouseId = v);
                      },
                    ),
                    TextFormField(
                      initialValue: qtyText,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'الكمية المحولة (${srcItem.unit})',
                        helperText: 'الحد الأقصى المتاح: ${_number(srcItem.quantity)}',
                      ),
                      onChanged: (v) => qtyText = v,
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          update(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await c.transferWarehouseStock(
                              itemId: selectedItemId,
                              toWarehouseId: toWarehouseId,
                              quantity: AccountingEngine.parseArabicNumber(qtyText),
                            );
                            if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم تنفيذ التحويل المخزني بنجاح.')),
                              );
                            }
                          } catch (e) {
                            update(() {
                              busy = false;
                              error = e is SaleValidationException ? e.message : e.toString();
                            });
                          }
                        },
                  child: const Text('تنفيذ التحويل'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showBulkEditDialog(
    BuildContext context,
    List<InventoryItemRecord> visibleItems,
  ) async {
    if (visibleItems.isEmpty) return;
    final selected = <String>{for (final i in visibleItems) i.id};
    var priceMode = 'keep';
    var priceVal = '';
    var stockMode = 'keep';
    var stockVal = '';
    var thresholdVal = '';
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, update) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('التعديل الجماعي للمخزون (${selected.length} صنف)'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: priceMode,
                    decoration: const InputDecoration(labelText: 'تحديث التكلفة'),
                    items: const [
                      DropdownMenuItem(value: 'keep', child: Text('بدون تغيير')),
                      DropdownMenuItem(value: 'set', child: Text('تعيين تكلفة ثابتة')),
                      DropdownMenuItem(value: 'percent', child: Text('تعديل بنسبة مئوية (%)')),
                    ],
                    onChanged: (v) => update(() => priceMode = v ?? 'keep'),
                  ),
                  if (priceMode != 'keep')
                    TextFormField(
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(
                        labelText: priceMode == 'percent' ? 'النسبة المئوية (مثال: 10 أو -5)' : 'التكلفة الجديدة',
                      ),
                      onChanged: (v) => priceVal = v,
                    ),
                  DropdownButtonFormField<String>(
                    value: stockMode,
                    decoration: const InputDecoration(labelText: 'تحديث الكمية'),
                    items: const [
                      DropdownMenuItem(value: 'keep', child: Text('بدون تغيير')),
                      DropdownMenuItem(value: 'set', child: Text('تعيين كمية جرد ثابتة')),
                      DropdownMenuItem(value: 'delta', child: Text('إضافة / خصم كمية (+/-)')),
                    ],
                    onChanged: (v) => update(() => stockMode = v ?? 'keep'),
                  ),
                  if (stockMode != 'keep')
                    TextFormField(
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'قيمة الكمية'),
                      onChanged: (v) => stockVal = v,
                    ),
                  TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'حد التنبيه الأدنى (اختياري)'),
                    onChanged: (v) => thresholdVal = v,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        update(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          final count = await widget.controller.batchUpdateInventoryItems(
                            selected,
                            priceMode: priceMode,
                            priceValue: priceVal.trim().isEmpty
                                ? null
                                : AccountingEngine.parseArabicNumber(priceVal),
                            stockMode: stockMode,
                            stockValue: stockVal.trim().isEmpty
                                ? null
                                : AccountingEngine.parseArabicNumber(stockVal),
                            minThreshold: thresholdVal.trim().isEmpty
                                ? null
                                : AccountingEngine.parseArabicNumber(thresholdVal),
                          );
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تم تحديث $count صنف دفعة واحدة.')),
                            );
                          }
                        } catch (e) {
                          update(() {
                            busy = false;
                            error = e is SaleValidationException ? e.message : e.toString();
                          });
                        }
                      },
                child: const Text('تطبيق التعديل الجماعي'),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                    (!_lowStockOnly ||
                        (item.minThreshold > 0 && item.quantity < item.minThreshold)) &&
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
                  firstCellAction:(index)=>Navigator.of(context).push(MaterialPageRoute<void>(
                    builder:(_)=>CatalogItemEditor(controller:controller,item:items[index]))),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('منخفض المخزون فقط'),
                      selected: _lowStockOnly,
                      onSelected: (v) => setState(() => _lowStockOnly = v),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('inventory-bulk-edit-btn'),
                      onPressed: items.isEmpty ? null : () => _showBulkEditDialog(context, items),
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: const Text('التعديل الجماعي'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('inventory-transfer-btn'),
                      onPressed: () => _showTransferDialog(context),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('تحويل مخزني'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('inventory-export-csv-btn'),
                      onPressed: () async {
                        final csv = [
                          'الصنف,الرمز,المستودع,الوحدة,الكمية,متوسط التكلفة,حد التنبيه',
                          for (final item in items)
                            '"${item.name.replaceAll('"', '""')}","${item.sku}","${_warehouseName(controller, item.warehouseId)}","${item.unit}",${_number(item.quantity)},${_number(item.avgCost)},${_number(item.minThreshold)}',
                        ].join('\n');
                        await Clipboard.setData(ClipboardData(text: csv));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم نسخ جدول الأصناف CSV (${items.length} صنف).')),
                          );
                        }
                      },
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('تصدير CSV'),
                    ),
                  ],
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (key, label) in const [
                      ('pdf-print', 'طباعة PDF'),
                      ('pdf-share', 'مشاركة PDF'),
                      ('excel-export', 'تصدير Excel'),
                      ('excel-share', 'مشاركة Excel'),
                    ])
                      OutlinedButton(
                        key: ValueKey('stock-movement-$key'),
                        onPressed: () async {
                          final csv = [
                            'رقم العملية,التاريخ,النوع,الحساب,المستودع,المبلغ,العملة',
                            for (final e in entries)
                              '${e.entryNumber},${e.entryDate},"${e.typeLabel}","${e.accountName}","${_warehouseName(controller, e.warehouseId)}",${_number(e.amount)},${e.currency.label}',
                          ].join('\n');
                          await Clipboard.setData(ClipboardData(text: csv));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تم تجهيز التقرير ($label) ونسخ البيانات.')),
                            );
                          }
                        },
                        child: Text(label),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}
