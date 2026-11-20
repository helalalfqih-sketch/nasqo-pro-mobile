import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';

class LocalEntryView extends StatefulWidget {
  const LocalEntryView({super.key, required this.controller, required this.exchange, required this.openDrafts});
  final ErpController controller;
  final bool exchange;
  final VoidCallback openDrafts;
  @override
  State<LocalEntryView> createState() => _LocalEntryState();
}

class _LocalEntryState extends State<LocalEntryView> {
  String? accountId, error;
  late CurrencyCode currency, fromCurrency;
  EntryDirection direction = EntryDirection.debit;
  PaymentMethod payment = PaymentMethod.cash;
  final amount = TextEditingController(), rate = TextEditingController(text: '1'), note = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final first = widget.controller.accounts.firstOrNull;
    accountId = first?.id;
    fromCurrency = first?.currency ?? widget.controller.defaultCurrency;
    currency = widget.exchange ? CurrencyCode.values.firstWhere((c) => c != fromCurrency) : fromCurrency;
  }

  @override
  void dispose() { amount.dispose(); rate.dispose(); note.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (saving) return;
    setState(() { saving = true; error = null; });
    try {
      final number = await widget.controller.postLocalEntry(accountId: accountId ?? '',
        kind: widget.exchange ? LedgerKind.currency : LedgerKind.voucher, direction: direction,
        payment: payment, amount: AccountingEngine.parseArabicNumber(amount.text), currency: currency,
        fromCurrency: widget.exchange ? fromCurrency : null, exchangeRate: widget.exchange
          ? AccountingEngine.parseArabicNumber(rate.text) : 1, note: note.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ العملية رقم $number')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e is SaleValidationException ? e.message : 'تعذر حفظ العملية.');
    } finally { if (mounted) setState(() => saving = false); }
  }

  Widget currencyField(String title, CurrencyCode value, ValueChanged<CurrencyCode> choose) =>
    DropdownButtonFormField<CurrencyCode>(value: value, isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: [for (final c in CurrencyCode.values) DropdownMenuItem(value: c, child: Text(c.label))],
      onChanged: (c) { if (c != null) setState(() => choose(c)); });

  @override
  Widget build(BuildContext context) => PopScope(canPop: !saving,
    child: Scaffold(appBar: AppBar(title: Text(widget.exchange ? 'صرف عملات' : 'سند جديد'),
      actions: [TextButton(onPressed: saving ? null : widget.openDrafts,
        child: const Text('المسودات', style: TextStyle(color: Colors.white)))]),
      body: AbsorbPointer(absorbing: saving, child: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<EntryDirection>(segments: [
          ButtonSegment(value: EntryDirection.debit, label: Text(widget.exchange ? 'بيع' : 'عليه')),
          ButtonSegment(value: EntryDirection.credit, label: Text(widget.exchange ? 'شراء' : 'له')),
        ], selected: {direction}, onSelectionChanged: (v) => setState(() => direction = v.single)),
        DropdownButtonFormField<String>(value: accountId, isExpanded: true,
          decoration: const InputDecoration(labelText: 'الحساب'),
          items: [for (final a in widget.controller.accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
          onChanged: (v) => setState(() {
            accountId = v;
            final c = widget.controller.accounts.where((a) => a.id == v).firstOrNull?.currency;
            if (!widget.exchange && c != null) currency = c;
          })),
        if (widget.exchange) currencyField('من عملة', fromCurrency, (c) => fromCurrency = c),
        currencyField(widget.exchange ? 'إلى عملة' : 'العملة', currency, (c) => currency = c),
        TextField(controller: amount, onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'المبلغ')),
        if (widget.exchange) ...[
          TextField(controller: rate, onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'سعر الصرف')),
          Builder(builder: (_) {
            final total = AccountingEngine.parseArabicNumber(amount.text) * AccountingEngine.parseArabicNumber(rate.text);
            return ListTile(title: const Text('المبلغ بعد الصرف'), trailing: Text(
              total.isFinite ? '${AccountingEngine.formatAmount(total)} ${currency.label}' : '—'));
          }),
        ],
        const SizedBox(height: 12),
        SegmentedButton<PaymentMethod>(segments: const [
          ButtonSegment(value: PaymentMethod.cash, label: Text('نقدي')),
          ButtonSegment(value: PaymentMethod.balance, label: Text('رصيد')),
        ], selected: {payment}, onSelectionChanged: (v) => setState(() => payment = v.single)),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'البيان')),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.save_outlined),
          label: Text(saving ? 'جارٍ الحفظ…' : 'حفظ')),
      ]))));
}
