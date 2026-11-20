import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../state/erp_controller.dart';
import 'cash_supplier_statement_view.dart';

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
      this.cashOnly = false, this.onOpenModule});
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final currency =
              _selectedCurrency ?? widget.controller.defaultCurrency;
          final accounts = widget.controller.accounts
              .where((a) =>
                  (widget.cashOnly
                      ? a.isCashAccount
                      : widget.category == null ||
                          a.category == widget.category) &&
                  '${a.name} ${a.codeNumber} ${a.phone}'
                      .toLowerCase()
                      .contains(_query.toLowerCase()))
              .toList();
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                  title: Text(widget.cashOnly
                      ? 'الصناديق المحلية'
                      : widget.category?.label ?? 'الحسابات')),
              body: ListView(padding: const EdgeInsets.all(16), children: [
                Text(widget.cashOnly
                    ? 'حسابات مميزة كنقدية في الدفتر المحلي، وليست سجلات صناديق مستقلة. للقراءة فقط.'
                    : 'أرصدة الدفتر المحلي للقراءة فقط، دون تحويل بين العملات.'),
                _currencyPicker(currency,
                    (value) => setState(() => _selectedCurrency = value)),
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
                    title: Text(account.name),
                    subtitle:
                        Text('رقم ${account.codeNumber} • ${currency.label}'),
                    trailing: Text(_money(
                        LocalAccountStatement(
                                account, widget.controller.ledger, currency)
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
          return Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                appBar: AppBar(
                    title: Text(account == null
                        ? 'كشف الحساب'
                        : 'كشف حساب ${account.name}')),
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
                    const Divider(),
                    if (statement.entries.isEmpty)
                      const Text('لا توجد حركات مرحّلة بهذه العملة.'),
                    for (final entry in statement.entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${entry.entryDate} • ${entry.typeLabel} #${entry.entryNumber}'),
                        subtitle: Text(
                            '${entry.details}\n${entry.direction == EntryDirection.debit ? "مدين" : "دائن"}: ${_money(entry.amount, currency)}\nالرصيد: ${_money(running += entry.direction == EntryDirection.debit ? entry.amount : -entry.amount, currency)}'),
                        isThreeLine: true,
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
