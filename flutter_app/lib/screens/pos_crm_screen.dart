import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';
import 'invoice_form_sheet.dart';

class PosCrmScreen extends StatefulWidget {
  const PosCrmScreen({super.key, required this.controller});

  final ErpController controller;

  @override
  State<PosCrmScreen> createState() => _PosCrmScreenState();
}

class _PosCrmScreenState extends State<PosCrmScreen> {
  int _tabIndex = 0;
  final Map<String, int> _cart = {};
  bool _includeVat = true;
  bool _saving = false;
  String? _saleError;
  PaymentMethod _payment = PaymentMethod.cash;
  String? _selectedBox;
  Iterable<AccountRecord> get _cashboxes => widget.controller.accounts.where((a) =>
      a.isCashAccount && a.currency == widget.controller.defaultCurrency);
  String? get _cashboxId => _cashboxes.any((a) => a.id == _selectedBox)
      ? _selectedBox : _cashboxes.firstOrNull?.id;

  void _adjustCart(InventoryItemRecord item, int delta) {
    if (_saving) return;
    setState(() {
      final cur = _cart[item.id] ?? 0;
      final next = (cur + delta).clamp(0, item.quantity.toInt());
      if (next == 0) {
        _cart.remove(item.id);
      } else {
        _cart[item.id] = next;
      }
    });
  }

  Future<void> _checkout() async {
    if (_saving ||
        _cart.isEmpty ||
        widget.controller.accounts.isEmpty ||
        widget.controller.warehouses.isEmpty) {
      return;
    }
    setState(() {
      _saving = true;
      _saleError = null;
    });
    try {
      final rows = <InvoiceItemRow>[];
      for (final entry in _cart.entries) {
        final item =
            widget.controller.inventory.firstWhere((i) => i.id == entry.key);
        rows.add(
          InvoiceItemRow(
            id: 'pos_${item.id}',
            itemId: item.id,
            productName: item.name,
            quantity: entry.value.toDouble(),
            unitPrice: (item.avgCost * 1.25).roundToDouble(),
          ),
        );
      }
      final acc = widget.controller.accounts.firstWhere(
        (a) =>
            a.category == AccountCategory.sales ||
            a.category == AccountCategory.clients,
        orElse: () => widget.controller.accounts.first,
      );
      if (_payment == PaymentMethod.cash && _cashboxId == null) {
        throw const SaleValidationException('أضف حسابًا نقديًا بعملة الفاتورة لتحصيل البيع.');
      }
      await widget.controller.submitSalesInvoice(
        accountId: acc.id,
        customerName: acc.name,
        warehouse: widget.controller.warehouses.firstWhere(
          (warehouse) =>
              warehouse.id ==
              widget.controller.inventory
                  .firstWhere((item) => item.id == _cart.keys.first)
                  .warehouseId,
          orElse: () => widget.controller.warehouses.first,
        ),
        payment: _payment,
        cashboxAccountId: _payment == PaymentMethod.cash ? _cashboxId : null,
        includeVat: _includeVat,
        rows: rows,
      );
      if (!mounted) return;
      setState(() => _cart.clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم إتمام البيع وتحديث المخزون والأستاذ العام')));
    } on SaleValidationException catch (error) {
      if (mounted) setState(() => _saleError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _saleError = 'تعذر تأكيد حفظ البيع. بقيت السلة دون تغيير.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.controller.defaultCurrency.label;
    double subtotal = 0;
    for (final entry in _cart.entries) {
      final item =
          widget.controller.inventory.firstWhere((i) => i.id == entry.key);
      subtotal += entry.value * (item.avgCost * 1.25).roundToDouble();
    }
    final vat =
        _includeVat ? ((subtotal * 0.15) * 100).roundToDouble() / 100 : 0.0;
    final grandTotal = subtotal + vat;

    return PopScope(
        canPop: !_saving,
        child: AbsorbPointer(
            absorbing: _saving,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('نقطة البيع (POS)')),
                      ButtonSegment(
                          value: 1, label: Text('فرص المبيعات (CRM)')),
                    ],
                    selected: {_tabIndex},
                    onSelectionChanged: (s) =>
                        setState(() => _tabIndex = s.first),
                  ),
                ),
                Expanded(
                  child: _tabIndex == 0
                      ? ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  'كتالوج الأصناف للبيع السريع',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                FilledButton.icon(
                                  onPressed: () => showModalBottomSheet(
                                    enableDrag: false,
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (_) => InvoiceFormSheet(
                                        controller: widget.controller),
                                  ),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('فاتورة مفصلة'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...widget.controller.inventory.map((item) {
                              final qty = _cart[item.id] ?? 0;
                              final sellPrice =
                                  (item.avgCost * 1.25).roundToDouble();
                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  title: Text(item.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    'السعر: ${AccountingEngine.formatAmount(sellPrice)} $cur · المتاح: ${item.quantity.toInt()} ${item.unit}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        onPressed: qty > 0
                                            ? () => _adjustCart(item, -1)
                                            : null,
                                      ),
                                      Text('$qty',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                        onPressed: qty < item.quantity
                                            ? () => _adjustCart(item, 1)
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: widget.controller.deals.map((deal) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(deal.title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                        Text(
                                          '${AccountingEngine.formatAmount(deal.value)} ${deal.currency.label}',
                                          style: const TextStyle(
                                            color: Color(0xFF169B62),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${deal.clientName} · ${deal.stage.label} (${deal.probability}%)'),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        if (deal.stage != ErpDealStage.won &&
                                            deal.stage != ErpDealStage.lost)
                                          OutlinedButton(
                                            onPressed: () => widget.controller
                                                .advanceDeal(deal.id),
                                            child: const Text('ترقية المرحلة'),
                                          ),
                                        if (deal.convertedInvoiceEntryId ==
                                            null)
                                          FilledButton(
                                            onPressed: () => widget.controller
                                                .convertDealToInvoice(deal.id),
                                            child:
                                                const Text('تحويل إلى فاتورة'),
                                          )
                                        else
                                          const Chip(
                                              label:
                                                  Text('تم الترحيل لفاتورة')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                if (_tabIndex == 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 8)
                      ],
                    ),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_payment == PaymentMethod.cash)
                              DropdownButton<String>(
                                value: _cashboxId,
                                hint: const Text('صندوق النقدية'),
                                items: [for (final box in _cashboxes)
                                  DropdownMenuItem(value: box.id, child: Text(box.name))],
                                onChanged: _saving ? null : (v) => setState(() => _selectedBox = v),
                              ),
                            SegmentedButton<PaymentMethod>(
                              segments: const [
                                ButtonSegment(
                                    value: PaymentMethod.cash,
                                    label: Text('نقدي')),
                                ButtonSegment(
                                    value: PaymentMethod.credit,
                                    label: Text('آجل')),
                              ],
                              selected: {_payment},
                              onSelectionChanged: (s) =>
                                  setState(() => _payment = s.first),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: _includeVat,
                                  onChanged: (v) =>
                                      setState(() => _includeVat = v ?? true),
                                ),
                                const Text('VAT 15%'),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_saleError != null)
                          Semantics(
                              liveRegion: true,
                              child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(_saleError!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)))),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('pos-checkout'),
                            onPressed:
                                _saving || _cart.isEmpty ? null : _checkout,
                            icon: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.check_circle),
                            label: Text(
                              _saving
                                  ? 'جارٍ حفظ البيع…'
                                  : 'إتمام البيع (${AccountingEngine.formatAmount(grandTotal)} $cur)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            )));
  }
}
