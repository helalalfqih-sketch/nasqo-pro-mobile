import 'package:flutter/material.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';
import 'web_auxiliary_views.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({
    super.key,
    required this.controller,
    this.openRecordedSalesTax,
  });
  final ErpController controller;
  final VoidCallback? openRecordedSalesTax;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final cur = widget.controller.defaultCurrency.label;
    final trial = AccountingEngine.computeTrialBalance(
      widget.controller.accounts,
      widget.controller.ledger,
    );
    final income = AccountingEngine.computeIncomeStatement(
      widget.controller.accounts,
      widget.controller.ledger,
    );
    final vat = AccountingEngine.computeVatSummary(
      widget.controller.accounts,
      widget.controller.ledger,
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('ميزان المراجعة')),
            ButtonSegment(value: 1, label: Text('الدخل')),
            ButtonSegment(value: 2, label: Text('VAT 15%')),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: 12),
        if (_tab == 0)
          ...trial.rows.map((r) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  title: Text('${r.codeNumber} · ${r.accountName}'),
                  subtitle: Text(r.category.label),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'مدين: ${AccountingEngine.formatAmount(r.closingDebit)}',
                        style: const TextStyle(
                            color: Color(0xFFD84949), fontSize: 12),
                      ),
                      Text(
                        'دائن: ${AccountingEngine.formatAmount(r.closingCredit)}',
                        style: const TextStyle(
                            color: Color(0xFF169B62), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )),
        if (_tab == 1) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _row('إجمالي المبيعات',
                      '${AccountingEngine.formatAmount(income.salesRevenue)} $cur'),
                  _row('مردودات المبيعات',
                      '${AccountingEngine.formatAmount(income.salesReturns)} $cur'),
                  _row('تكلفة المبيعات (COGS)',
                      '${AccountingEngine.formatAmount(income.cogs)} $cur'),
                  _row('مجمل الربح',
                      '${AccountingEngine.formatAmount(income.grossProfit)} $cur'),
                  _row('المصروفات التشغيلية',
                      '${AccountingEngine.formatAmount(income.totalOperatingExpenses)} $cur'),
                  const Divider(),
                  _row('صافي الربح',
                      '${AccountingEngine.formatAmount(income.netProfit)} $cur',
                      bold: true),
                ],
              ),
            ),
          ),
          ExpenseTrendsChartCard(
            accounts: widget.controller.accounts,
            ledger: widget.controller.ledger,
            currency: widget.controller.defaultCurrency,
          ),
          SupplierPerformanceChartCard(
            accounts: widget.controller.accounts,
            ledger: widget.controller.ledger,
            currency: widget.controller.defaultCurrency,
          ),
        ],
        if (_tab == 2 && widget.openRecordedSalesTax != null)
          OutlinedButton.icon(
            key: const ValueKey('finance-recorded-sales-tax'),
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: widget.openRecordedSalesTax,
            label: const Text('الضريبة الموثقة على المبيعات المحلية'),
          ),
        if (_tab == 2)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
                'الحساب أدناه تقديري بالطريقة القديمة؛ ليس إقرارًا أو مبلغًا معتمدًا للسداد.'),
          ),
        if (_tab == 2)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _row('المبيعات الخاضعة للضريبة',
                      '${AccountingEngine.formatAmount(vat.taxableSales)} $cur'),
                  _row('ضريبة المخرجات (15%)',
                      '${AccountingEngine.formatAmount(vat.outputVat)} $cur'),
                  _row('المشتريات الخاضعة للضريبة',
                      '${AccountingEngine.formatAmount(vat.taxablePurchases)} $cur'),
                  _row('ضريبة المدخلات (15%)',
                      '${AccountingEngine.formatAmount(vat.inputVat)} $cur'),
                  const Divider(),
                  _row('صافي الضريبة المستحقة',
                      '${AccountingEngine.formatAmount(vat.netVatPayable)} $cur',
                      bold: true),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String val, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          const SizedBox(width: 8),
          Flexible(
              child: Text(val,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.bold : FontWeight.w600))),
        ],
      ),
    );
  }
}
