import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';
import 'customer_list_sheet.dart';

class InvoiceFormSheet extends StatefulWidget {
  const InvoiceFormSheet({super.key, required this.controller, this.onSaving});

  final ErpController controller;
  final ValueChanged<bool>? onSaving;

  @override
  State<InvoiceFormSheet> createState() => _InvoiceFormSheetState();
}

class _InvoiceFormSheetState extends State<InvoiceFormSheet> {
  String? _selectedAccountId;
  String? _cashboxId;
  Iterable<AccountRecord> get _cashboxes => widget.controller.accounts.where((a) =>
      a.isCashAccount && a.currency == widget.controller.defaultCurrency);
  String? _selectedWhId;
  bool _useCustomCustomer = false;
  final _customNameCtrl = TextEditingController();
  final _documentNumberCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  PaymentMethod _payment = PaymentMethod.cash;
  bool _includeVat = true;
  bool _free = false;
  final _freeTotal = TextEditingController();
  String? _saleError;
  bool _saving = false;
  final List<InvoiceItemRow> _rows = [];

  @override
  void initState() {
    super.initState();
    final preferredAccounts = _clientAccounts;
    _selectedAccountId = preferredAccounts.firstOrNull?.id;
    _cashboxId = _cashboxes.firstOrNull?.id;
    _selectedWhId = widget.controller.warehouses.firstOrNull?.id;
    final firstItem = _stockItems.firstOrNull;
    _rows.add(
      InvoiceItemRow(
        id: 'row_${DateTime.now().millisecondsSinceEpoch}',
        itemId: firstItem?.id,
        productName: firstItem?.name ?? 'صنف افتراضي',
        quantity: 1,
        unitPrice: firstItem != null
            ? (firstItem.avgCost * 1.25).roundToDouble()
            : 100,
      ),
    );
  }

  @override
  void dispose() {
    _freeTotal.dispose();
    _customNameCtrl.dispose();
    _documentNumberCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  List<AccountRecord> get _clientAccounts {
    final list = widget.controller.accounts
        .where(
          (a) =>
              a.category == AccountCategory.clients ||
              a.category == AccountCategory.sales,
        )
        .toList();
    if (list.isEmpty) return widget.controller.accounts;
    // The shared picker also lists suppliers. Keep its selected account in
    // the dropdown rather than constructing an invalid dropdown value.
    final selected = widget.controller.accounts
        .where((a) => a.id == _selectedAccountId)
        .firstOrNull;
    if (selected != null && !list.any((a) => a.id == selected.id)) {
      list.add(selected);
    }
    return list;
  }

  Iterable<InventoryItemRecord> get _stockItems => widget.controller.inventory
      .where((item) => item.warehouseId == _selectedWhId);

  double _inputNumber(String value) {
    if (value.trim().isEmpty) return double.nan;
    final normalized =
        value.trim().replaceAllMapped(RegExp('[٠-٩۰-۹]'), (match) {
      final code = match[0]!.codeUnitAt(0);
      return (code - (code >= 0x06f0 ? 0x06f0 : 0x0660)).toString();
    }).replaceAll('٫', '.');
    return double.tryParse(normalized) ?? double.nan;
  }

  double get _subtotal => _free ? AccountingEngine.parseArabicNumber(_freeTotal.text) : _rows.fold(
      0.0, (sum, row) => sum + (row.lineTotal.isFinite ? row.lineTotal : 0));
  double get _vat {
    final scaled = _subtotal * 15;
    return _includeVat && scaled.isFinite && scaled <= 9007199254740991
        ? scaled.roundToDouble() / 100
        : 0;
  }

  double get _grandTotal => _subtotal + _vat;

  void _openCustomerList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerListSheet(
        controller: widget.controller,
        allowAdd: false,
        onSelectCustomer: (acc) {
          if (!mounted) return;
          setState(() {
            _selectedAccountId = acc.id;
            _useCustomCustomer = false;
          });
        },
      ),
    );
  }

  // Draft fields live only in this State. All dismissal paths simply pop the
  // route; persistence remains exclusively behind the explicit save action.
  void _cancel() {
    if (!_saving) Navigator.of(context).pop();
  }

  Future<void> _saveInvoice() async {
    if (_saving) return;
    if (widget.controller.accounts.isEmpty ||
        widget.controller.warehouses.isEmpty) {
      return;
    }
    final activeAcc = widget.controller.accounts.firstWhere(
      (a) => a.id == _selectedAccountId,
      orElse: () => widget.controller.accounts.first,
    );
    final wh = widget.controller.warehouses.firstWhere(
      (w) => w.id == _selectedWhId,
      orElse: () => widget.controller.warehouses.first,
    );
    final customerName =
        _useCustomCustomer ? _customNameCtrl.text.trim() : activeAcc.name;
    if (customerName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل اسم العميل أولًا')));
      return;
    }

    if (_payment == PaymentMethod.cash && _cashboxId == null) {
      setState(() => _saleError = 'أضف حسابًا نقديًا بعملة الفاتورة من دليل الحسابات ثم اختره هنا.');
      return;
    }
    setState(() {
      _saving = true;
      _saleError = null;
    });
    widget.onSaving?.call(true);
    try {
      await widget.controller.submitSalesInvoice(
        accountId: activeAcc.id,
        customerName: customerName,
        warehouse: wh,
        payment: _payment,
        cashboxAccountId: _payment == PaymentMethod.cash ? _cashboxId : null,
        includeVat: _includeVat,
        rows: _free ? [] : _rows,
        freeAmount: _free ? _inputNumber(_freeTotal.text) : null,
        documentNumber: _documentNumberCtrl.text,
        memo: _memoCtrl.text,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final message =
          'تمت إضافة الفاتورة للعميل ($customerName) بقيمة ${AccountingEngine.formatAmount(_grandTotal)} ${widget.controller.defaultCurrency.label}';
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on SaleValidationException catch (error) {
      if (mounted) setState(() => _saleError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _saleError = 'تعذر تأكيد حفظ الفاتورة. بقيت المسودة دون تغيير.');
      }
    } finally {
      if (mounted) { widget.onSaving?.call(false); setState(() => _saving = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyLabel = widget.controller.defaultCurrency.label;
    return PopScope(
        canPop: !_saving,
        child: AbsorbPointer(
            absorbing: _saving,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 10,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'إصدار فاتورة مبيعات جديدة',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('invoice-close'),
                            tooltip: 'إغلاق دون حفظ',
                            onPressed: _saving ? null : _cancel,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                    value: false, label: Text('حساب مسجل')),
                                ButtonSegment(
                                    value: true, label: Text('اسم حر')),
                              ],
                              selected: {_useCustomCustomer},
                              onSelectionChanged: (s) =>
                                  setState(() => _useCustomCustomer = s.first),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: _openCustomerList,
                            child: const Text('قائمة العملاء'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_useCustomCustomer)
                        TextField(
                          controller: _customNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم العميل أو الجهة',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: _selectedAccountId,
                          decoration: const InputDecoration(
                            labelText: 'العميل',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: _clientAccounts
                              .map(
                                (a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text(a.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _selectedAccountId = v);
                            }
                          },
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedWhId,
                              decoration: const InputDecoration(
                                labelText: 'المستودع',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: widget.controller.warehouses
                                  .map(
                                    (w) => DropdownMenuItem(
                                      value: w.id,
                                      child: Text(w.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v == null || v == _selectedWhId) return;
                                setState(() {
                                  _selectedWhId = v;
                                  final available = _stockItems
                                      .map((item) => item.id)
                                      .toSet();
                                  for (final row in _rows) {
                                    if (!available.contains(row.itemId)) {
                                      row.itemId = null;
                                      row.productName = '';
                                    }
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SegmentedButton<PaymentMethod>(
                            segments: const [
                              ButtonSegment(
                                value: PaymentMethod.cash,
                                label: Text('نقدي'),
                              ),
                              ButtonSegment(
                                value: PaymentMethod.credit,
                                label: Text('آجل'),
                              ),
                            ],
                            selected: {_payment},
                            onSelectionChanged: (s) =>
                                setState(() => _payment = s.first),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_payment == PaymentMethod.cash)
                        DropdownButtonFormField<String>(
                          key: const ValueKey('invoice-cashbox'),
                          value: _cashboxId, isExpanded: true,
                          decoration: const InputDecoration(labelText: 'صندوق النقدية'),
                          items: [for (final box in _cashboxes)
                            DropdownMenuItem(value: box.id, child: Text(box.name))],
                          onChanged: _saving ? null : (v) => setState(() => _cashboxId = v),
                        ),
                      TextField(
                        key: const Key('invoice-document-number'),
                        controller: _documentNumberCtrl,
                        maxLength: 32,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'رقم الفاتورة (اختياري)',
                          hintText: 'يولّد الرقم تلقائيًا إذا تُرك فارغًا',
                          border: OutlineInputBorder(),
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('invoice-memo'),
                        controller: _memoCtrl,
                        maxLength: 240,
                        decoration: const InputDecoration(
                          labelText: 'بيان الفاتورة (اختياري)',
                          border: OutlineInputBorder(),
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('ضريبة القيمة المضافة 15%'),
                        value: _includeVat,
                        onChanged: (v) =>
                            setState(() => _includeVat = v ?? true),
                      ),
                      SegmentedButton<bool>(segments: const [
                        ButtonSegment(value:false,label:Text('أصناف')),
                        ButtonSegment(value:true,label:Text('حرة')),
                      ],selected:{_free},onSelectionChanged:(v)=>setState(()=>_free=v.single)),
                      if (_free) TextField(controller:_freeTotal, keyboardType:const TextInputType.numberWithOptions(decimal:true),
                          onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'إجمالي مبلغ الفاتورة'))
                      else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'بنود الأصناف',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              final firstItem = _stockItems.firstOrNull;
                              setState(() {
                                _rows.add(
                                  InvoiceItemRow(
                                    id: 'row_${DateTime.now().millisecondsSinceEpoch}_${_rows.length}',
                                    itemId: firstItem?.id,
                                    productName: firstItem?.name ?? 'صنف جديد',
                                    quantity: 1,
                                    unitPrice: firstItem != null
                                        ? (firstItem.avgCost * 1.25)
                                            .roundToDouble()
                                        : 100,
                                  ),
                                );
                              });
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('إضافة صنف'),
                          ),
                        ],
                      ),
                      ..._rows.map((row) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          key: ValueKey(row.id),
                          child: Column(children:[Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String?>(
                                  key: ValueKey(
                                      'invoice-item-$_selectedWhId-${row.id}'),
                                  value: row.itemId,
                                  hint: const Text('اختر صنفًا'),
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _stockItems
                                      .map(
                                        (inv) => DropdownMenuItem(
                                          value: inv.id,
                                          child: Text(
                                            inv.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      row.itemId = val;
                                      final matched = widget
                                          .controller.inventory
                                          .where((i) => i.id == val)
                                          .firstOrNull;
                                      if (matched != null) {
                                        row.productName = matched.name;
                                        row.unitPrice = (matched.avgCost * 1.25)
                                            .roundToDouble();
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextFormField(
                                  initialValue: row.quantity.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'الكمية',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => setState(() {
                                    row.quantity = _inputNumber(v);
                                  }),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextFormField(
                                  initialValue: row.unitPrice.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'السعر',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => setState(() {
                                    row.unitPrice = _inputNumber(v);
                                  }),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: _rows.length > 1
                                    ? () => setState(() => _rows.remove(row))
                                    : null,
                              ),
                            ],
                          ),
                          TextFormField(initialValue:row.discount==0?'':row.discount.toString(),
                            keyboardType:const TextInputType.numberWithOptions(decimal:true),
                            decoration:const InputDecoration(labelText:'خصم السطر'),
                            onChanged:(v)=>setState(()=>row.discount=v.trim().isEmpty?0:_inputNumber(v))),
                          ]),
                        );
                      }),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          )
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            _summaryRow(
                              'المجموع الفرعي',
                              '${AccountingEngine.formatAmount(_subtotal)} $currencyLabel',
                            ),
                            if (_includeVat)
                              _summaryRow(
                                'الضريبة (15%)',
                                '${AccountingEngine.formatAmount(_vat)} $currencyLabel',
                              ),
                            const Divider(height: 10),
                            _summaryRow(
                              'الإجمالي النهائي',
                              '${AccountingEngine.formatAmount(_grandTotal)} $currencyLabel',
                              bold: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (widget.controller.accounts.isEmpty ||
                          widget.controller.warehouses.isEmpty)
                        const Text('يلزم حساب ومستودع قبل حفظ الفاتورة.'),
                      if (_saleError != null)
                        Semantics(
                            liveRegion: true,
                            child: Text(_saleError!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      OutlinedButton(
                        key: const Key('invoice-cancel'),
                        onPressed: _saving ? null : _cancel,
                        child: const Text('إلغاء دون حفظ'),
                      ),
                      FilledButton.icon(
                        key: const Key('invoice-save'),
                        onPressed: _saving ||
                                widget.controller.accounts.isEmpty ||
                                widget.controller.warehouses.isEmpty
                            ? null
                            : _saveInvoice,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline),
                        label: Text(_saving
                            ? 'جارٍ حفظ الفاتورة…'
                            : 'حفظ الفاتورة وترحيل المبيعات'),
                      ),
                    ],
                  ),
                ),
              ),
            )));
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: bold ? const Color(0xFF169B62) : null,
          ),
        ),
      ],
    );
  }
}
