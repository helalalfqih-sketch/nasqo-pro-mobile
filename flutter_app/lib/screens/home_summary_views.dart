import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../state/erp_controller.dart';

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
                  'العملات المعرفة في التطبيق المحلي. عرض فقط؛ لا يتضمن أسعار صرف أو تحويل أرصدة.'),
              const SizedBox(height: 12),
              for (final currency in CurrencyCode.values)
                Card(
                    child: ListTile(
                  title: Text(currency.label),
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
