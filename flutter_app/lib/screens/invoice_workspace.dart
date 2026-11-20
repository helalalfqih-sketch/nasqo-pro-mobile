import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../services/account_csv.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';
import 'invoice_form_sheet.dart';
import 'purchase_invoice_view.dart';

class InvoiceWorkspace extends StatefulWidget {
  const InvoiceWorkspace({super.key, required this.controller, this.salesReturnBuilder});
  final ErpController controller;
  final Widget Function(ValueChanged<bool>)? salesReturnBuilder;

  @override
  State<InvoiceWorkspace> createState() => _InvoiceWorkspaceState();
}

class _InvoiceWorkspaceState extends State<InvoiceWorkspace> {
  bool sale = false;
  bool visitedSale = false;
  bool saving = false;

  void onSaving(bool value) { if (mounted) setState(() => saving = value); }

  @override
  Widget build(BuildContext context) {
    final returns = widget.salesReturnBuilder != null;
    return PopScope(canPop: !saving, child: Scaffold(
      appBar: AppBar(title: Text(returns ? 'مردود جديد' : 'فاتورة جديدة')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(returns ? 'مردود شراء' : 'فاتورة شراء')),
              ButtonSegment(value: true, label: Text(returns ? 'مردود بيع' : 'فاتورة بيع')),
            ], selected: {sale}, onSelectionChanged: saving ? null : (values) => setState(() {
              sale = values.single;
              visitedSale = visitedSale || sale;
            }),
          )),
        Expanded(child: IndexedStack(index: sale ? 1 : 0, children: [
          if (returns) _PurchaseReturnForm(controller: widget.controller, onSaving: onSaving)
          else PurchaseInvoiceView(controller: widget.controller, onSaving: onSaving),
          if (!visitedSale) const SizedBox.shrink()
          else widget.salesReturnBuilder?.call(onSaving) ?? InvoiceFormSheet(controller: widget.controller, onSaving: onSaving),
        ])),
      ])),
    ));
  }
}

class _PurchaseReturnForm extends StatefulWidget {
  const _PurchaseReturnForm({required this.controller, required this.onSaving});
  final ErpController controller;
  final ValueChanged<bool> onSaving;
  @override
  State<_PurchaseReturnForm> createState() => _PurchaseReturnFormState();
}

class _PurchaseReturnFormState extends State<_PurchaseReturnForm> {
  String? sourceId;
  final quantities = <int,String>{};
  final requestId = DateTime.now().microsecondsSinceEpoch.toString();
  bool saving = false;
  String error = '';

  Future<void> post() async {
    if (saving || sourceId == null) return;
    setState(() { saving = true; error = ''; });
    widget.onSaving(true);
    try {
      final selected = <int,double>{};
      for (final entry in quantities.entries) {
        if (entry.value.trim().isEmpty) continue;
        final quantity = parseAccountAmount(entry.value);
        if (quantity != 0) selected[entry.key] = quantity;
      }
      final number = await widget.controller.postPurchaseReturn(
        sourceId: sourceId!, requestId: requestId, quantities: selected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ترحيل مردود الشراء رقم $number')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {widget.onSaving(false); setState(() => saving = false);}
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final eligible = c.returnablePurchases;
    final source = eligible.where((e) => e.id == sourceId).firstOrNull;
    final remaining = source == null ? <int,double>{} : c.remainingPurchaseQuantities(source.id);
    final lines = c.saleLines.where((l) => l.entryId == sourceId && (remaining[l.position] ?? 0) > 0);
    return ListView(padding: const EdgeInsets.all(16), children: [
      DropdownButtonFormField<String>(value:sourceId, isExpanded:true,
        decoration: const InputDecoration(labelText:'فاتورة الشراء الأصلية'),
        items:[for (final e in eligible) DropdownMenuItem(value:e.id,
          child: Text('${e.documentNumber} · ${e.accountName}'))],
        onChanged:saving ? null : (v) => setState(() {sourceId=v; quantities.clear(); error='';})),
      if(eligible.isEmpty) const Text('لا توجد فواتير شراء محلية مؤهلة للمردود.'),
      if(source!=null) ...[
        Text('${source.warehouseName} · ${source.currency.label} · ${source.payment.label}'),
        if(lines.isEmpty) const Text('رُدّت جميع البنود.'),
        for(final line in lines) TextFormField(key:ValueKey('${source.id}/${line.position}'),
          enabled:!saving,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:InputDecoration(labelText:'كمية مردود ${line.itemName}',
            helperText:'المتبقي: ${AccountingEngine.formatAmount(remaining[line.position]!)} · سعر الوحدة بعد الخصم: ${AccountingEngine.formatAmount(line.unitPrice)}'),
          onChanged:(v)=>setState(()=>quantities[line.position]=v)),
      ],
      if(source!=null) Text('إجمالي المردود: ${AccountingEngine.formatAmount(lines.fold<double>(0,(sum,l) {
        final qty=AccountingEngine.parseArabicNumber(quantities[l.position]??'');
        return qty.isFinite && qty>0 && qty<=remaining[l.position]! ?
            sum+SavedSaleLine.returnedValue(l.quantity,l.unitPrice,l.quantity-remaining[l.position]!,qty) : sum;
      }))} ${source.currency.label}'),
      if(error.isNotEmpty) Text(error),
      FilledButton(onPressed:saving || lines.isEmpty ? null : post, child:const Text('ترحيل مردود الشراء')),
    ]);
  }
}
