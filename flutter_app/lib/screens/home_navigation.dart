import 'package:flutter/material.dart';

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
        ('cash-transfer-drafts', 'حوالة جديدة', Icons.send_outlined),
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
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    for (final (route, title, icon) in const [
      ('finance', 'ميزان المراجعة', Icons.balance),
      ('accounts', 'تقرير إجمالي حسب التصنيف', Icons.account_tree_outlined),
      ('cashboxes', 'صناديق النقدية', Icons.account_balance_wallet_outlined),
      ('inventory', 'المخزون المتبقي', Icons.inventory_2_outlined),
      ('stock-movement', 'حركة المخزون', Icons.swap_horiz),
      ('sales-register', 'سجل فواتير المبيعات', Icons.receipt_long_outlined),
      ('recorded-sales-tax', 'التقارير الضريبية', Icons.percent),
    ])
      Card(child: ListTile(title: Text(title), leading: Icon(icon),
        trailing: const Icon(Icons.chevron_left), onTap: () => onOpenModule(route))),
  ]);
}
