import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../services/account_csv.dart';
import '../state/erp_controller.dart';
import 'web_auxiliary_views.dart';

/// Conservative classification: only explicit sale labels produced by the local
/// controller. Unknown/imported headers are not guessed to be sales.
class LocalSalesSummary {
  LocalSalesSummary(Iterable<LedgerEntryRecord> ledger, CurrencyCode currency)
      : entries = List.unmodifiable(ledger.where((e) =>
            !e.deleted &&
            e.kind == LedgerKind.invoice &&
            e.currency == currency &&
            const {
              'ف.مبيعات آجل',
              'ف.مبيعات نقدية',
              'فاتورة مبيعات (CRM)',
            }.contains(e.typeLabel)));

  final List<LedgerEntryRecord> entries;
  int get count => entries.length;
  double get total => entries.fold(0.0, (sum, e) => sum + e.amount);
  int get cashCount =>
      entries.where((e) => e.payment == PaymentMethod.cash || e.typeLabel == 'ف.مبيعات نقدية').length;
  int get creditCount => count - cashCount;
}

class HomeCurrencyDirectoryView extends StatelessWidget {
  const HomeCurrencyDirectoryView({super.key, required this.controller});
  final ErpController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: const Text('دليل العملات')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'اختر العملة لتعديل رمزها ووحدتها الصغرى وأسعارها المحلية.'),
              const SizedBox(height: 12),
              for (final currency in CurrencyCode.values)
                Card(
                    child: ListTile(
                  title: Text(currency.label),
                  onTap: () => showDialog<void>(context: context, builder: (_) =>
                    _CurrencyDetailsEditor(controller: controller, currency: currency)),
                  subtitle: Text(
                      'عدد الحسابات: ${controller.accounts.where((a) => a.currency == currency).length}'),
                  trailing: controller.defaultCurrency == currency
                      ? const Chip(label: Text('الافتراضية'))
                      : null,
                )),
            ]),
          ),
        ),
      );
}

class _CurrencyDetailsEditor extends StatefulWidget {
  const _CurrencyDetailsEditor({required this.controller, required this.currency});
  final ErpController controller;
  final CurrencyCode currency;
  @override
  State<_CurrencyDetailsEditor> createState() => _CurrencyDetailsEditorState();
}

class _CurrencyDetailsEditorState extends State<_CurrencyDetailsEditor> {
  late final details = widget.controller.currencyDetails(widget.currency);
  late String symbol = details['symbol'] ?? '', subunit = details['subunit'] ?? '';
  String initialRate(String side) => widget.currency == widget.controller.defaultCurrency
      ? '1' : '${details[side] ?? 1}';
  late String buy = initialRate('buy'), sell = initialRate('sell');
  bool saving = false;
  String error = '';

  Future<void> save() async {
    setState(() { saving = true; error = ''; });
    try {
      await widget.controller.saveCurrencyDetails(widget.currency, symbol, subunit,
        parseAccountAmount(buy), parseAccountAmount(sell));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر حفظ بيانات العملة. تحقق من الأسعار وأعد المحاولة.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.controller.defaultCurrency;
    return AlertDialog(
      scrollable: true,
      title: Text('بيانات العملة · ${widget.currency.label}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(initialValue: symbol, onChanged: (v) => symbol = v,
          decoration: const InputDecoration(labelText: 'رمز العملة')),
        TextFormField(initialValue: subunit, onChanged: (v) => subunit = v,
          decoration: const InputDecoration(labelText: 'الوحدة الصغرى')),
        Text('القيمة بعملة ${base.label} لكل وحدة من ${widget.currency.label}'),
        TextFormField(initialValue: buy, enabled: widget.currency != base,
          onChanged: (v) => buy = v, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'سعر الشراء')),
        TextFormField(initialValue: sell, enabled: widget.currency != base,
          onChanged: (v) => sell = v, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'سعر البيع')),
        if (error.isNotEmpty) Text(error),
      ]),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: saving ? null : save, child: const Text('حفظ العملة')),
      ],
    );
  }
}

class HomeSalesOverviewView extends StatelessWidget {
  const HomeSalesOverviewView({super.key, required this.controller});
  final ErpController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: const Text('ملخص المبيعات')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'ملخص محلي محدود لكل التواريخ، وليس تقرير الموقع الحي. إجمالي رؤوس فواتير المبيعات المعروفة غير المحذوفة فقط، وليس صافي الربح أو التحصيل.'),
              const SizedBox(height: 8),
              const Text(
                  'يستبعد المشتريات والمرتجعات والعروض والطلبات والأنواع غير المعروفة. لا تُجمع العملات ولا تُحوّل؛ لا يُخصم المرتجع من الإجمالي.'),
              const SizedBox(height: 12),
              for (final currency in CurrencyCode.values)
                _SalesCurrencyCard(
                    summary: LocalSalesSummary(controller.ledger, currency),
                    currency: currency),
              const SizedBox(height: 8),
              SalesTrendChartCard(
                ledger: controller.ledger,
                currency: controller.defaultCurrency,
              ),
              SupplierPerformanceChartCard(
                accounts: controller.accounts,
                ledger: controller.ledger,
                currency: controller.defaultCurrency,
              ),
            ]),
          ),
        ),
      );
}

class _SalesCurrencyCard extends StatelessWidget {
  const _SalesCurrencyCard({required this.summary, required this.currency});
  final LocalSalesSummary summary;
  final CurrencyCode currency;
  @override
  Widget build(BuildContext context) => Card(
          child: ListTile(
        title: Text('${summary.total.toStringAsFixed(2)} ${currency.label}'),
        subtitle: Text(summary.count == 0
            ? 'لا توجد فواتير مبيعات معروفة بهذه العملة'
            : 'عدد الفواتير: ${summary.count}'),
      ));
}
