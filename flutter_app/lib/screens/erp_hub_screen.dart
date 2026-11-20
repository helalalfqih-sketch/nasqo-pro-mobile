import 'package:flutter/material.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';

class ErpHubScreen extends StatelessWidget {
  const ErpHubScreen({
    super.key,
    required this.controller,
    required this.onOpenModule,
  });

  final ErpController controller;
  final ValueChanged<String> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final income = AccountingEngine.computeIncomeStatement(
      controller.accounts,
      controller.ledger,
    );
    final invTotal =
        AccountingEngine.computeInventoryValue(controller.inventory);
    final payroll =
        AccountingEngine.computeTotalNetPayroll(controller.employees);
    final vat = AccountingEngine.computeVatSummary(
      controller.accounts,
      controller.ledger,
    );
    final cur = controller.defaultCurrency.label;

    final modules = [
      (
        'finance',
        'القوائم المالية والأستاذ العام',
        'ميزان المراجعة · الدخل · VAT',
        Icons.bar_chart,
        const Color(0xFF0B5CA8)
      ),
      (
        'crm',
        'المبيعات ونقطة البيع (POS / CRM)',
        'نقطة بيع · صفقات · فواتير',
        Icons.point_of_sale,
        const Color(0xFF169B62)
      ),
      (
        'procurement',
        'المشتريات وسلسلة التوريد',
        'أوامر الشراء · الاستلام المخزني',
        Icons.local_shipping_outlined,
        const Color(0xFFF39A16)
      ),
      (
        'hr',
        'الموارد البشرية والرواتب',
        'الموظفون · الإجازات · الرواتب',
        Icons.people_alt_outlined,
        Colors.purple
      ),
      (
        'manufacturing',
        'التصنيع (BOM) ومراكز التكلفة',
        'قوائم المواد · أوامر الإنتاج',
        Icons.precision_manufacturing_outlined,
        Colors.teal
      ),
    ];

    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF07365D), Color(0xFF0B5CA8)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'مركز قيادة ${controller.companyName}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'كل عملية في المبيعات أو المشتريات أو الرواتب أو التصنيع تحدّث المخزون والأستاذ العام لحظياً.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 40 + MediaQuery.textScalerOf(context).scale(68),
          ),
          children: [
            _kpiTile(
                context,
                'صافي الربح التشغيلي',
                '${AccountingEngine.formatAmount(income.netProfit)} $cur',
                income.netProfit >= 0),
            _kpiTile(context, 'قيمة المخزون الحالية',
                '${AccountingEngine.formatAmount(invTotal)} $cur', true),
            _kpiTile(context, 'مسير الرواتب الشهري',
                '${AccountingEngine.formatAmount(payroll)} $cur', true),
            _kpiTile(
                context,
                'صافي ضريبة VAT 15%',
                '${AccountingEngine.formatAmount(vat.netVatPayable)} $cur',
                vat.netVatPayable <= 0),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'وحدات النظام المتكاملة',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...modules.map((m) {
          final (id, title, subtitle, icon, color) = m;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () => onOpenModule(id),
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                foregroundColor: color,
                child: Icon(icon),
              ),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        }),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.storage_rounded,
                        color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'قاعدة البيانات المحلية (SQLite)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      controller.dbReady ? 'متصلة' : 'جاري التهيئة',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: controller.dbReady
                            ? const Color(0xFF169B62)
                            : colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'الحسابات: ${controller.accounts.length} · القيود: ${controller.ledger.length} · الأصناف: ${controller.inventory.length}',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpiTile(
      BuildContext context, String title, String value, bool positive) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color:
                  positive ? const Color(0xFF169B62) : const Color(0xFFD84949),
            ),
          ),
        ],
      ),
    );
  }
}
