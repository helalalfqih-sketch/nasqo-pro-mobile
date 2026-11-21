import 'package:flutter/material.dart';
import 'account_tools.dart';
import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';

class LocalEntryView extends StatefulWidget {
  const LocalEntryView({super.key, required this.controller, required this.kind, required this.openDrafts});
  final ErpController controller;
  final LedgerKind kind;
  bool get exchange => kind == LedgerKind.currency;
  bool get transfer => kind == LedgerKind.transfer;
  bool get journal => kind == LedgerKind.simpleEntry;
  final VoidCallback openDrafts;
  @override
  State<LocalEntryView> createState() => _LocalEntryState();
}

class _LocalEntryState extends State<LocalEntryView> {
  String? accountId, counterpart, error;
  String expenseCategory = '';
  String? categoryNotice;
  final document = TextEditingController(), sender = TextEditingController(), recipient = TextEditingController(), company = TextEditingController();
  late CurrencyCode currency, fromCurrency;
  EntryDirection direction = EntryDirection.debit;
  PaymentMethod payment = PaymentMethod.cash;
  final amount = TextEditingController(), rate = TextEditingController(text: '1'), note = TextEditingController();
  bool saving = false;
  final accountSearch = TextEditingController();

  double _accountBalance(String? id) {
    if (id == null) return 0;
    final acc = widget.controller.accounts.where((a) => a.id == id).firstOrNull;
    if (acc == null) return 0;
    var total = acc.currency == currency
        ? acc.openingBalance * (acc.openingDirection == EntryDirection.debit ? 1 : -1)
        : 0.0;
    for (final e in widget.controller.ledger) {
      if (e.deleted || e.accountId != id || e.currency != currency ||
          e.kind == LedgerKind.quote || e.kind == LedgerKind.order) {
        continue;
      }
      total += e.direction == EntryDirection.debit ? e.amount : -e.amount;
    }
    return total;
  }

  Widget _balanceStrip(String? id) {
    final acc = widget.controller.accounts.where((a) => a.id == id).firstOrNull;
    if (acc == null) return const SizedBox.shrink();
    final bal = _accountBalance(id);
    final side = bal > 0 ? 'عليه' : bal < 0 ? 'له' : 'متزن';
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('رصيد ${acc.name}:', style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
          Text(
            '${AccountingEngine.formatAmount(bal.abs())} ${currency.label} ($side)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFC2410C)),
          ),
        ],
      ),
    );
  }

  void _swapAccounts() {
    if (accountId == null && counterpart == null) return;
    setState(() {
      final tmp = accountId;
      accountId = counterpart;
      counterpart = tmp;
    });
  }

  void _suggestExpenseCategory() {
    final acc = widget.controller.accounts.where((a) => a.id == accountId).firstOrNull;
    if (note.text.trim().isEmpty && acc == null) {
      setState(() => categoryNotice = 'أدخل البيان أو اختر الحساب أولًا لاقتراح التصنيف.');
      return;
    }
    final suggested = ErpController.inferExpenseCategory(
      note.text,
      acc?.name ?? '',
      acc?.category,
    );
    setState(() {
      expenseCategory = suggested;
      categoryNotice = 'اقتراح التصنيف الذكي: $suggested';
    });
  }

  List<AccountRecord> get matchingAccounts {
    String normalize(String value) => value.trim().toLowerCase().replaceAllMapped(
      RegExp('[٠-٩۰-۹]'), (m) => '0123456789'[m[0]!.codeUnitAt(0) & 15]);
    final query = normalize(accountSearch.text);
    final matches = widget.controller.accounts.where((a) =>
      normalize('${a.name} ${a.codeNumber} ${a.phone}').contains(query));
    bool exact(AccountRecord a) => query.isNotEmpty &&
      [a.codeNumber.toString(), normalize(a.name), normalize(a.phone)].contains(query);
    return [...matches.where(exact), ...matches.where((a) => !exact(a))];
  }

  Future<void> addExchangeAccount() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) =>
      Scaffold(appBar: AppBar(title: const Text('إضافة حساب للصرف')),
        body: AccountEditor(controller: widget.controller))));
    if (mounted && saved == true) {
      setState(() { accountSearch.clear(); accountId = widget.controller.accounts.last.id; });
    }
  }

  @override
  void initState() {
    super.initState();
    final first = widget.controller.accounts.firstOrNull;
    accountId = first?.id;
    if (widget.journal || widget.exchange) { payment = PaymentMethod.balance; direction = EntryDirection.credit; }
    fromCurrency = first?.currency ?? widget.controller.defaultCurrency;
    currency = widget.exchange ? widget.controller.defaultCurrency : fromCurrency;
    if (widget.exchange) {
      fromCurrency = CurrencyCode.values.firstWhere((c) => c != currency);
      applyExchangeQuote();
    }
  }

  void applyExchangeQuote() {
    final quote = widget.controller.exchangeQuote(fromCurrency, currency, direction);
    rate.text = quote == null ? '' : quote.toString();
  }

  @override
  void dispose() { accountSearch.dispose(); document.dispose(); sender.dispose(); recipient.dispose(); company.dispose(); amount.dispose(); rate.dispose(); note.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (saving) return;
    setState(() { saving = true; error = null; });
    try {
      if (widget.exchange && accountSearch.text.trim().isNotEmpty) {
        throw const SaleValidationException('اختر حسابًا من نتائج البحث.');
      }
      final number = await widget.controller.postLocalEntry(accountId: accountId ?? '',
        kind: widget.kind, direction: direction, counterpartId: counterpart, documentNumber: document.text,
        payment: payment, amount: AccountingEngine.parseArabicNumber(amount.text), currency: currency,
        fromCurrency: widget.exchange ? fromCurrency : null, exchangeRate: widget.exchange
          ? AccountingEngine.parseArabicNumber(rate.text) : 1,
        expenseCategory: expenseCategory,
        note: [
            if (sender.text.trim().isNotEmpty) 'المرسل: ${sender.text.trim()}',
            if (recipient.text.trim().isNotEmpty) 'المستلم: ${recipient.text.trim()}',
            if (company.text.trim().isNotEmpty) 'شركة التحويل: ${company.text.trim()}',
            if (note.text.trim().isNotEmpty) note.text.trim(),
          ].join(' · '));
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
    child: Scaffold(appBar: AppBar(title: Text(switch (widget.kind) {LedgerKind.currency => 'صرف عملات', LedgerKind.simpleEntry => 'قيد بسيط', LedgerKind.transfer => 'حوالة جديدة', _ => 'سند جديد'}),
      actions: [TextButton(onPressed: saving ? null : widget.openDrafts,
        child: const Text('المسودات', style: TextStyle(color: Colors.white)))]),
      body: AbsorbPointer(absorbing: saving, child: ListView(padding: const EdgeInsets.all(16), children: [
        if (!widget.journal) SegmentedButton<EntryDirection>(segments: [
          ButtonSegment(value: EntryDirection.debit, label: Text(widget.exchange ? 'بيع' : widget.transfer ? 'صادرة' : 'عليه')),
          ButtonSegment(value: EntryDirection.credit, label: Text(widget.exchange ? 'شراء' : widget.transfer ? 'واردة' : 'له')),
        ], selected: {direction}, onSelectionChanged: (v) => setState(() {
          direction = v.single;
          if (widget.exchange) applyExchangeQuote();
        })),
        if (widget.exchange) Row(children: [
          Expanded(child: TextField(controller: accountSearch,
            decoration: InputDecoration(labelText: 'ابحث عن الاسم هنا',
              suffixIcon: IconButton(tooltip: 'مسح البحث', icon: const Icon(Icons.clear),
                onPressed: () => setState(accountSearch.clear))),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              final match = matchingAccounts.firstOrNull;
              if (match != null) setState(() { accountId = match.id; accountSearch.clear(); });
            })),
          IconButton(tooltip: 'إضافة حساب للصرف', icon: const Icon(Icons.person_add_alt),
            onPressed: addExchangeAccount),
        ]),
        DropdownButtonFormField<String>(
          value: widget.exchange && accountSearch.text.trim().isNotEmpty ? null : accountId,
          hint: Text(widget.exchange && matchingAccounts.isEmpty ? 'لا توجد حسابات مطابقة' : 'اختر الحساب'),
          isExpanded: true,
          decoration: InputDecoration(labelText: widget.journal ? 'إلى حساب (دائن)' : 'الحساب'),
          items: [for (final a in (widget.exchange ? matchingAccounts : widget.controller.accounts)) DropdownMenuItem(value: a.id, child: Text(a.name))],
          onChanged: (v) => setState(() {
            accountId = v;
            if (widget.exchange) accountSearch.clear();
            if (counterpart == v) counterpart = null;
            final c = widget.controller.accounts.where((a) => a.id == v).firstOrNull?.currency;
            if (!widget.exchange && c != null) currency = c;
          })),
        if (widget.journal || widget.transfer) ...[
          _balanceStrip(accountId),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('local-entry-swap-accounts'),
              onPressed: _swapAccounts,
              icon: const Icon(Icons.swap_vert, size: 18),
              label: const Text('تبديل الحسابين'),
            ),
          ),
          DropdownButtonFormField<String>(value: counterpart, isExpanded: true,
            decoration: InputDecoration(labelText: widget.journal ? 'من حساب (مدين)' : 'الحساب المقابل'),
            items: [for (final a in widget.controller.accounts.where((a) => a.id != accountId))
              DropdownMenuItem(value: a.id, child: Text(a.name))],
            onChanged: (v) => setState(() => counterpart = v)),
          _balanceStrip(counterpart),
          TextField(controller: document, decoration: InputDecoration(labelText: widget.transfer ? 'رقم الحوالة' : 'رقم المستند')),
        ],
        if (widget.transfer) ...[
          TextField(controller: sender, decoration: const InputDecoration(labelText: 'المرسل')),
          TextField(controller: recipient, decoration: const InputDecoration(labelText: 'المستلم')),
          TextField(controller: company, decoration: const InputDecoration(labelText: 'شركة التحويل')),
        ],
        if (widget.exchange) currencyField('من عملة', fromCurrency, (c) { fromCurrency = c; applyExchangeQuote(); }),
        currencyField(widget.exchange ? 'إلى عملة' : 'العملة', currency, (c) { currency = c; if (widget.exchange) applyExchangeQuote(); }),
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
        if (!widget.journal && !widget.transfer) SegmentedButton<PaymentMethod>(segments: const [
          ButtonSegment(value: PaymentMethod.cash, label: Text('نقدي')),
          ButtonSegment(value: PaymentMethod.balance, label: Text('رصيد')),
        ], selected: {payment}, onSelectionChanged: (v) => setState(() => payment = v.single)),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'البيان')),
        if (widget.kind == LedgerKind.voucher) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: expenseCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'التصنيف المحاسبي'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('تلقائي حسب البيان')),
                    for (final cat in ErpController.expenseCategories)
                      DropdownMenuItem(value: cat, child: Text(cat)),
                  ],
                  onChanged: (v) => setState(() {
                    expenseCategory = v ?? '';
                    categoryNotice = null;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('local-entry-smart-category'),
                onPressed: _suggestExpenseCategory,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('تصنيف ذكي'),
              ),
            ],
          ),
          if (categoryNotice != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                categoryNotice!,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ],
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.save_outlined),
          label: Text(saving ? 'جارٍ الحفظ…' : 'حفظ')),
      ]))));
}
