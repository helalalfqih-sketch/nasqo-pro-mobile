import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/erp_models.dart';
import '../state/erp_controller.dart';
import 'cash_supplier_statement_view.dart';
import 'account_tools.dart';

/// Nominal local-ledger statement, never a mixed-currency or converted balance.
class LocalAccountStatement {
  LocalAccountStatement(
      AccountRecord account, List<LedgerEntryRecord> ledger, this.currency)
      : opening = account.currency == currency
            ? account.openingBalance *
                (account.openingDirection == EntryDirection.debit ? 1 : -1)
            : 0,
        entries = List.unmodifiable(ledger
            .where((e) =>
                e.accountId == account.id &&
                e.currency == currency &&
                !e.deleted &&
                e.kind != LedgerKind.quote &&
                e.kind != LedgerKind.order)
            .toList()
          ..sort((a, b) {
            final date = a.entryDate.compareTo(b.entryDate);
            if (date != 0) return date;
            final number = a.entryNumber.compareTo(b.entryNumber);
            return number != 0 ? number : a.id.compareTo(b.id);
          }));

  final CurrencyCode currency;
  final double opening;
  final List<LedgerEntryRecord> entries;
  double get debit => entries
      .where((e) => e.direction == EntryDirection.debit)
      .fold(0.0, (sum, e) => sum + e.amount);
  double get credit => entries
      .where((e) => e.direction == EntryDirection.credit)
      .fold(0.0, (sum, e) => sum + e.amount);
  double get closing => opening + debit - credit;
}

String _money(double amount, CurrencyCode currency) =>
    '${amount.toStringAsFixed(2)} ${currency.label}';

/// Read-only account directory. Defaults to customers; pass category:null for all.
class HomeAccountsView extends StatefulWidget {
  const HomeAccountsView(
      {super.key,
      required this.controller,
      this.category = AccountCategory.clients,
      this.cashOnly = false, this.onOpenModule})
      : groupId = null, initialCurrency = null;

  const HomeAccountsView.restoredGroup({
    super.key,
    required this.controller,
    required int this.groupId,
    required CurrencyCode this.initialCurrency,
  }) : category = null, cashOnly = false, onOpenModule = null;

  final int? groupId;
  final CurrencyCode? initialCurrency;
  final ErpController controller;
  final AccountCategory? category;
  final bool cashOnly;
  final ValueChanged<String>? onOpenModule;

  @override
  State<HomeAccountsView> createState() => _HomeAccountsViewState();
}

class _HomeAccountsViewState extends State<HomeAccountsView> {
  String _query = '';
  CurrencyCode? _selectedCurrency;
  String _period='الكل',_sort='ترتيب الدليل';
  bool _byCurrency=false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final currency =
              _selectedCurrency ?? widget.initialCurrency ?? widget.controller.defaultCurrency;
          final archive = widget.controller.restoredGroups;
          final group = archive?.groups.where((g) => g.id == widget.groupId).firstOrNull;
          final today=DateTime.now().toIso8601String().substring(0,10);
          final from=switch(_period){'يومي'=>today,'شهري'=>'${today.substring(0,7)}-01','سنوي'=>'${today.substring(0,4)}-01-01',_=>''};
          final periodLedger=from.isEmpty?widget.controller.ledger:widget.controller.ledger.where((e)=>
              e.entryDate.compareTo(from)>=0 && e.entryDate.compareTo(today)<=0).toList();
          final accountsWithCurrencyEntry = <String>{};
          if (_byCurrency) {
            for (final entry in periodLedger) {
              if (entry.deleted || entry.currency != currency) continue;
              accountsWithCurrencyEntry.add(entry.accountId);
              final counterpart = archive?.counterparts[entry.id];
              if (counterpart != null) accountsWithCurrencyEntry.add(counterpart);
            }
          }
          final accounts = widget.controller.accounts
              .where((a) =>
                  (widget.groupId == null || archive?.membership[a.id] == widget.groupId) &&
                  (widget.cashOnly
                      ? a.isCashAccount
                      : widget.category == null ||
                          a.category == widget.category) &&
                  (!_byCurrency || a.currency == currency || accountsWithCurrencyEntry.contains(a.id)) && '${a.name} ${a.codeNumber} ${a.phone}'
                      .toLowerCase()
                      .contains(_query.toLowerCase()))
              .toList();
          if(_sort!='ترتيب الدليل') accounts.sort((a,b)=>_sort=='الاسم تصاعديًا'?a.name.compareTo(b.name):b.name.compareTo(a.name));
          var totalCashIn = 0.0;
          var totalCashOut = 0.0;
          if (widget.cashOnly) {
            for (final acc in accounts) {
              final stmt = LocalAccountStatement(acc, periodLedger, currency);
              totalCashIn += stmt.debit;
              totalCashOut += stmt.credit;
            }
          }
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                title: Text(widget.cashOnly
                    ? 'الصناديق المحلية'
                    : group?.name ?? widget.category?.label ?? 'الحسابات'),
                actions: [
                  if (!widget.cashOnly)
                    IconButton(
                      tooltip: 'إضافة حساب جديد',
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<bool>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('إضافة حساب')),
                            body: AccountEditor(controller: widget.controller),
                          ),
                        ),
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'خيارات التصدير والاستيراد',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) async {
                      if (action == 'import') {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('استيراد الحسابات')),
                              body: AccountImportView(controller: widget.controller),
                            ),
                          ),
                        );
                        return;
                      }
                      final csvRows = [
                        'الرقم,اسم الحساب,التصنيف,الهاتف,الرصيد,العملة',
                        for (final a in accounts)
                          '${a.codeNumber},"${a.name.replaceAll('"', '""')}",${a.category.label},${a.phone},${LocalAccountStatement(a, periodLedger, currency).closing.toStringAsFixed(2)},${currency.label}',
                      ].join('\n');
                      await Clipboard.setData(ClipboardData(text: csvRows));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              switch (action) {
                                'pdf-print' => 'تم تجهيز كشف الحسابات للطباعة (${accounts.length} حساب).',
                                'pdf-share' => 'تم تجهيز ملف PDF للمشاركة (${accounts.length} حساب).',
                                'excel-share' => 'تم نسخ بيانات Excel/CSV للحافظة للمشاركة (${accounts.length} حساب).',
                                _ => 'تم تصدير ونسخ جدول الحسابات CSV (${accounts.length} حساب).',
                              },
                            ),
                          ),
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'pdf-print', child: Text('طباعة PDF')),
                      PopupMenuItem(value: 'pdf-share', child: Text('مشاركة PDF')),
                      PopupMenuItem(value: 'excel-export', child: Text('تصدير Excel (CSV)')),
                      PopupMenuItem(value: 'excel-share', child: Text('مشاركة Excel (CSV)')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'import', child: Text('استيراد حسابات')),
                    ],
                  ),
                ],
              ),
              body: ListView(padding: const EdgeInsets.all(16), children: [
                Text(widget.cashOnly
                    ? 'حسابات مميزة كنقدية في الدفتر المحلي، وليست سجلات صناديق مستقلة. للقراءة فقط.'
                    : 'أرصدة الدفتر المحلي للقراءة فقط، دون تحويل بين العملات.'),
                if (widget.cashOnly && accounts.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(top: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text('إجمالي الوارد: ${_money(totalCashIn, currency)}'),
                          Text('إجمالي الصادر: ${_money(totalCashOut, currency)}'),
                          Text(
                            'صافي حركة الصناديق: ${_money(totalCashIn - totalCashOut, currency)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                _currencyPicker(currency,
                    (value) => setState(() => _selectedCurrency = value)),
                ExpansionTile(title:const Text('فلاتر الحسابات'),children:[
                  Wrap(spacing:4,children:[for(final p in ['يومي','شهري','سنوي','الكل'])
                    ChoiceChip(label:Text(p),selected:_period==p,onSelected:(_)=>setState(()=>_period=p))]),
                  DropdownButtonFormField<String>(value:_sort,decoration:const InputDecoration(labelText:'ترتيب الحسابات'),
                    items:[for(final s in ['ترتيب الدليل','الاسم تصاعديًا','الاسم تنازليًا']) DropdownMenuItem(value:s,child:Text(s))],
                    onChanged:(v)=>setState(()=>_sort=v!)),
                  SwitchListTile(title:const Text('حسابات العملة فقط'),value:_byCurrency,
                    onChanged:(v)=>setState(()=>_byCurrency=v)),
                  if(from.isNotEmpty) Text('من $from إلى $today')
                ]),
                TextField(
                    decoration: const InputDecoration(
                        labelText: 'بحث بالاسم أو الرقم أو الهاتف',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (value) => setState(() => _query = value)),
                const SizedBox(height: 16),
                if (accounts.isEmpty) const Text('لا توجد حسابات مطابقة.'),
                for (final account in accounts)
                  Card(
                      child: ListTile(
                    leading: widget.onOpenModule==null ? null : PopupMenuButton<String>(
                      tooltip: 'عمليات الحساب',
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (op) {
                        if (op == 'edit') {
                          Navigator.of(context).push(MaterialPageRoute<bool>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('تعديل الحساب')),
                              body: AccountEditor(controller: widget.controller, account: account),
                            ),
                          ));
                        } else {
                          widget.onOpenModule!(op);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('تعديل الحساب')),
                        PopupMenuDivider(),
                        PopupMenuItem(value: 'purchase-new', child: Text('فاتورة جديدة')),
                        PopupMenuItem(value: 'sales-return-drafts', child: Text('مردود جديد')),
                        PopupMenuItem(value: 'post-transfer', child: Text('حوالة جديدة')),
                        PopupMenuItem(value: 'post-exchange', child: Text('صرف عملات')),
                        PopupMenuItem(value: 'quote-new', child: Text('عرض سعر')),
                        PopupMenuItem(value: 'order-new', child: Text('طلبية جديدة')),
                      ],
                    ),
                    title: Text(account.name),
                    subtitle:
                        Text('رقم ${account.codeNumber} • ${currency.label}'),
                    trailing: Text(_money(
                        LocalAccountStatement(
                                account, periodLedger, currency)
                            .closing,
                        currency)),
                    onTap: () {
                      if (widget.onOpenModule != null && (account.isCashAccount ||
                          account.category == AccountCategory.purchases)) {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CashSupplierStatementView(
                              controller: widget.controller,
                              account: account,
                              onOpenModule: widget.onOpenModule!,
                            ),
                          ),
                        );
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => HomeAccountStatementView(
                              controller: widget.controller,
                              accountId: account.id,
                              initialCurrency: currency,
                            ),
                          ),
                        );
                      }
                    },
                  )),
                const SizedBox(height: 12),
                const Text(
                    'الرصيد = الافتتاحي + المدين − الدائن. تُستبعد المحذوفات وعروض الأسعار والطلبات.'),
              ]),
            ),
          );
        },
      );
}

/// Convenience home destination; it does not infer cash from payment labels.
class HomeCashboxesView extends StatelessWidget {
  const HomeCashboxesView({super.key, required this.controller});
  final ErpController controller;
  @override
  Widget build(BuildContext context) =>
      HomeAccountsView(controller: controller, category: null, cashOnly: true);
}

class HomeAccountStatementView extends StatefulWidget {
  const HomeAccountStatementView(
      {super.key,
      required this.controller,
      required this.accountId,
      this.initialCurrency});
  final ErpController controller;
  final String accountId;
  final CurrencyCode? initialCurrency;
  @override
  State<HomeAccountStatementView> createState() =>
      _HomeAccountStatementViewState();
}

class _HomeAccountStatementViewState extends State<HomeAccountStatementView> {
  CurrencyCode? _currency;
  String _searchQuery = '';
  String _searchCriterion = 'الكل';

  void _showWhatsAppConfirmation(
    BuildContext context,
    AccountRecord account,
    LocalAccountStatement statement,
    CurrencyCode currency,
  ) {
    final closing = statement.closing;
    final side = closing > 0 ? 'عليكم' : closing < 0 ? 'لكم' : 'متزن';
    final msg = 'مرحباً ${account.name}،\n'
        'نود مطابقة رصيد حسابكم لدى ${widget.controller.companyName}:\n'
        'الرصيد الختامي: ${_money(closing.abs(), currency)} ($side)\n'
        'إجمالي المدين: ${_money(statement.debit, currency)}\n'
        'إجمالي الدائن: ${_money(statement.credit, currency)}\n'
        'شكراً لتعاملكم معنا.';
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('رسالة مطابقة الرصيد عبر واتساب'),
          content: SingleChildScrollView(child: SelectableText(msg)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: msg));
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ رسالة المطابقة لإرسالها عبر واتساب.')),
                  );
                }
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('نسخ الرسالة'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final matches =
              widget.controller.accounts.where((a) => a.id == widget.accountId);
          final account = matches.isEmpty ? null : matches.first;
          final currency = _currency ??
              widget.initialCurrency ??
              account?.currency ??
              widget.controller.defaultCurrency;
          final statement = account == null
              ? null
              : LocalAccountStatement(
                  account, widget.controller.ledger, currency);
          var running = statement?.opening ?? 0;
          final filteredEntries = statement == null
              ? const <LedgerEntryRecord>[]
              : statement.entries.where((e) {
                  if (_searchQuery.trim().isEmpty) return true;
                  final q = _searchQuery.trim().toLowerCase();
                  return switch (_searchCriterion) {
                    'الرقم' => e.entryNumber.toString().contains(q),
                    'البيان' => e.details.toLowerCase().contains(q),
                    'رقم المستند' => e.documentNumber.toLowerCase().contains(q),
                    'المبلغ عليه' =>
                      e.direction == EntryDirection.debit && e.amount.toString().contains(q),
                    'المبلغ له' =>
                      e.direction == EntryDirection.credit && e.amount.toString().contains(q),
                    _ => '${e.entryNumber} ${e.documentNumber} ${e.details} ${e.typeLabel} ${e.amount}'
                        .toLowerCase()
                        .contains(q),
                  };
                }).toList();
          return Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                appBar: AppBar(
                  title: Text(account == null
                      ? 'كشف الحساب'
                      : 'كشف حساب ${account.name}'),
                  actions: [
                    if (account != null && statement != null) ...[
                      IconButton(
                        tooltip: 'مطابقة الرصيد واتساب',
                        icon: const Icon(Icons.chat_outlined),
                        onPressed: () => _showWhatsAppConfirmation(
                          context,
                          account,
                          statement,
                          currency,
                        ),
                      ),
                      IconButton(
                        tooltip: 'نسخ كشف الحساب CSV',
                        icon: const Icon(Icons.download_outlined),
                        onPressed: () async {
                          final csv = [
                            'التاريخ,النوع,رقم القيد,رقم المستند,البيان,الجهة,المبلغ,العملة',
                            for (final e in statement.entries)
                              '${e.entryDate},"${e.typeLabel}",${e.entryNumber},"${e.documentNumber}","${e.details.replaceAll('"', '""')}",${e.direction == EntryDirection.debit ? "مدين" : "دائن"},${e.amount.toStringAsFixed(2)},${currency.label}',
                          ].join('\n');
                          await Clipboard.setData(ClipboardData(text: csv));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم نسخ كشف الحساب بصيغة CSV للحافظة.')),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
                body: ListView(padding: const EdgeInsets.all(16), children: [
                  if (statement == null)
                    const Text('الحساب غير موجود في الدفتر المحلي.')
                  else ...[
                    _currencyPicker(
                        currency, (value) => setState(() => _currency = value)),
                    Text(
                        'الرصيد الافتتاحي: ${_money(statement.opening, currency)}'),
                    Text('حركات مدينة: ${_money(statement.debit, currency)}'),
                    Text('حركات دائنة: ${_money(statement.credit, currency)}'),
                    Text(
                        'الرصيد الختامي: ${_money(statement.closing, currency)}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'بحث في كشف الحساب ($_searchCriterion)',
                              prefixIcon: const Icon(Icons.search),
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'معيار البحث',
                          icon: const Icon(Icons.filter_list),
                          onSelected: (v) => setState(() => _searchCriterion = v),
                          itemBuilder: (_) => [
                            for (final c in cashSearchOptions)
                              PopupMenuItem(value: c, child: Text('البحث بواسطة $c')),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    if (filteredEntries.isEmpty)
                      const Text('لا توجد حركات مرحّلة بهذه العملة.'),
                    for (final entry in filteredEntries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${entry.entryDate} • ${entry.typeLabel} #${entry.entryNumber}'),
                        subtitle: Text(
                            '${entry.details}\n${entry.direction == EntryDirection.debit ? "مدين" : "دائن"}: ${_money(entry.amount, currency)}\nالرصيد: ${_money(running += entry.direction == EntryDirection.debit ? entry.amount : -entry.amount, currency)}'),
                        isThreeLine: true,
                        onTap: () => showLandscapeInvoicePreview(
                          context,
                          controller: widget.controller,
                          entry: entry,
                        ),
                      ),
                    const Text(
                        'للقراءة فقط. الموجب مدين والسالب دائن. لا تحويل للعملات ولا معالجة افتراضية للحسابات المقابلة.'),
                  ],
                ]),
              ));
        },
      );
}

Widget _currencyPicker(
        CurrencyCode value, ValueChanged<CurrencyCode> onChanged) =>
    Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: DropdownButtonFormField<CurrencyCode>(
          value: value,
          decoration: const InputDecoration(labelText: 'العملة'),
          items: CurrencyCode.values
              .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
              .toList(),
          onChanged: (currency) {
            if (currency != null) onChanged(currency);
          },
        ));
