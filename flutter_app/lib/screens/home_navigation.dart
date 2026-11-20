import 'package:flutter/material.dart';
import '../state/erp_controller.dart';
import '../models/erp_models.dart';
import 'home_account_views.dart';

class HomeNavigation extends StatelessWidget {
  const HomeNavigation({super.key, required this.onHome, required this.onServices,
    required this.onQuickActions, required this.onReports, required this.onProfile});
  final VoidCallback onHome, onServices, onQuickActions, onReports, onProfile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(String label, IconData icon, VoidCallback tap, {bool selected = false}) =>
      Expanded(child: Semantics(selected: selected, button: true,
        child: InkWell(onTap: tap, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 23, color: selected ? scheme.primary : scheme.onSurfaceVariant),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
        ]))));
    return SafeArea(top: false, child: Material(
      elevation: 8, color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SizedBox(height: 68, child: Row(children: [
        tab('الرئيسية', Icons.home_rounded, onHome, selected: true),
        tab('الخدمات', Icons.work_rounded, onServices),
        SizedBox(width: 70, child: Center(child: IconButton.filled(
          tooltip: 'الإجراءات السريعة', onPressed: onQuickActions,
          style: IconButton.styleFrom(fixedSize: const Size.square(54)),
          icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 32)))),
        tab('التقارير', Icons.format_list_bulleted_rounded, onReports),
        tab('الملف', Icons.person_rounded, onProfile),
      ]))));
  }
}

Future<String?> showHomeQuickActions(BuildContext context) => showModalBottomSheet<String>(
  context: context, useSafeArea: true, showDragHandle: true,
  builder: (context) => Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
    child: Row(children: [
      for (final (route, title, icon) in const [
        ('post-transfer', 'حوالة جديدة', Icons.send_outlined),
        ('qr-scanner', 'مسح باركود', Icons.qr_code_scanner),
        ('invoice', 'فاتورة جديدة', Icons.receipt_long_outlined),
        ('post-voucher', 'سند جديد', Icons.note_add_outlined),
      ])
        Expanded(child: InkWell(onTap: () => Navigator.pop(context, route),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6), Text(title, textAlign: TextAlign.center),
            ])))),
    ])));

class HomeReportsView extends StatelessWidget {
  const HomeReportsView({super.key, required this.onOpenModule});
  final ValueChanged<String> onOpenModule;

  @override
  Widget build(BuildContext context) {
    const groups = [
      ('التقارير المالية', [
        ('cashboxes','حركة الصندوق'),('report-closing','تقرير الحسابات الختامية'),('report-category','تقرير إجمالي حسب التصنيف'),
        ('finance','ميزان المراجعة')
      ]),
      ('التقارير المخزنية', [
        ('report-movement','حركة الأصناف والأرباح'),('stock-movement','حركة المخزون'),('report-expiry','تقرير المخزون المتبقي وتاريخ الانتهاء'),
        ('report-stock','المخزون المتبقي'),('report-profit','أرباح الفواتير'),('report-services','تقارير الخدمات'),
        ('recorded-sales-tax','التقارير الضريبية'),('sales-register','سجل فواتير المبيعات')
      ])
    ];
    return ListView(padding:const EdgeInsets.all(12),children:[
      for(final (section,links) in groups) ...[
        Padding(padding:const EdgeInsets.symmetric(vertical:8),
          child:Text(section,style:Theme.of(context).textTheme.titleMedium)),
        Wrap(spacing:8,runSpacing:8,children:[
          for(final (index,link) in links.indexed)
            FilledButton(onPressed:()=>onOpenModule(link.$1),
              style:FilledButton.styleFrom(backgroundColor:index.isEven ? const Color(0xFF945100) : const Color(0xFF3730A3)),
              child:Text(link.$2))
        ]),
      ]
    ]);
  }
}

class LocalAlertsView extends StatelessWidget {
  const LocalAlertsView({super.key, required this.controller, required this.open});
  final ErpController controller;
  final ValueChanged<String> open;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: controller, builder: (context, _) {
    final low = controller.inventory.where((i) => i.minThreshold > 0 && i.quantity < i.minThreshold);
    final debts = <(AccountRecord, double)>[];
    for (final a in controller.accounts.where((a) => a.creditLimit > 0)) {
      final balance = LocalAccountStatement(a, controller.ledger, a.currency).closing;
      if (balance > a.creditLimit) debts.add((a, balance));
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (low.isEmpty && debts.isEmpty) const ListTile(title: Text('لا توجد تنبيهات للمخزون أو سقف المديونية.')),
      for (final item in low)
        Card(child: ListTile(leading: const Icon(Icons.inventory_2_outlined),
          title: Text('انخفاض مخزون: ${item.name}'),
          subtitle: Text('المتوفر ${item.quantity} ${item.unit} · الحد الأدنى ${item.minThreshold}'),
          onTap: () => open('inventory'))),
      for (final (account, balance) in debts)
        Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text('تجاوز سقف المديونية: ${account.name}'),
          subtitle: Text('الرصيد $balance ${account.currency.label} · السقف ${account.creditLimit}'),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
            HomeAccountStatementView(controller: controller, accountId: account.id, initialCurrency: account.currency))))),
    ]);
  });
}
