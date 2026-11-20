import 'package:flutter/material.dart';

import 'nasqo_brand_mark.dart';

/// Native navigation ordered like the published NASQO sidebar.
///
/// Only existing native routes are actionable. The parent owns navigation
/// (including closing the drawer); unavailable web features never redirect to
/// a different native feature.
class NasqoWebDrawer extends StatelessWidget {
  const NasqoWebDrawer({
    super.key,
    required this.companyName,
    required this.onOpen,
  });

  final String companyName;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Drawer(
        semanticLabel: 'قائمة تنقل نسقو برو',
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(15, 12, 15, 11),
                color: colors.surfaceContainerLow,
                child: Column(
                  children: [
                    const NasqoBrandMark(size: 59),
                    const SizedBox(height: 8),
                    Text('نسقو برو',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      companyName.trim().isEmpty
                          ? 'إدارة الحسابات والمبيعات'
                          : companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  key: const Key('nasqo-web-drawer-list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _item('الرئيسية', Icons.home_outlined, route: 'home'),
                    _item('ملخص المبيعات المحلي', Icons.dashboard_outlined,
                        route: 'sales-overview'),
                    _item('سجل فواتير المبيعات', Icons.receipt_long_outlined,
                        route: 'sales-register'),
                    _item('سجل فواتير المشتريات', Icons.shopping_basket_outlined, route:'purchase-register'),
                    _item('الحركة اليومية', Icons.today_outlined,
                        route: 'daily-movement'),
                    _item('الرسائل الفورية واتساب', Icons.chat_outlined, route:'message-settings'),
                    _item(
                      'حركة المخزون',
                      Icons.swap_horiz,
                      route: 'stock-movement',
                    ),
                    _item('عروض الأسعار', Icons.request_quote_outlined,
                        route: 'quotes'),
                    _item('الطلبيات', Icons.shopping_bag_outlined,
                        route: 'orders'),
                    _item('سلة المحذوفات', Icons.delete_outline,
                        route: 'trash'),
                    _item('الإعدادات', Icons.settings_outlined,
                        route: 'settings'),
                    _section(context, 'المخازن والأصناف'),
                    _item('المخازن', Icons.warehouse_outlined,
                        route: 'warehouses'),
                    _item('الأصناف', Icons.inventory_2_outlined,
                        route: 'inventory'),
                    _item('إضافة صنف', Icons.add_box_outlined, route:'item-new'),
                    _section(context, 'الحسابات'),
                    _item('حسابات المحل', Icons.store_outlined, route:'group-shop'),
                    _item('حسابات الموردين', Icons.local_shipping_outlined, route:'group-purchases'),
                    _item('حسابات العملاء', Icons.people_outline, route:'group-clients'),
                    _item('دليل الحسابات', Icons.account_tree_outlined,
                        route: 'chart-accounts'),
                    _item('إدارة مجموعات الحسابات',Icons.workspaces_outlined,route:'group-directory'),
                    _item('جميع الحسابات', Icons.groups_outlined,
                        route: 'accounts'),
                    _item('دليل العملات المحلي', Icons.currency_exchange,
                        route: 'currencies'),
                    _item('مسودات صرف العملات',
                        Icons.swap_horizontal_circle_outlined,
                        route: 'fx-drafts'),
                    _item('إضافة حساب', Icons.person_add_outlined, route:'account-new'),
                    _item('استيراد الحسابات', Icons.file_upload_outlined, route:'account-import'),
                    _section(context, 'نظام ERP'),
                    _item('مركز ERP', Icons.apps_outlined, route: 'hub'),
                    _item(
                      'القوائم المالية والأستاذ العام',
                      Icons.bar_chart,
                      route: 'finance',
                    ),
                    _item(
                      'المبيعات ونقطة البيع (POS / CRM)',
                      Icons.point_of_sale,
                      route: 'crm',
                    ),
                    _item(
                      'المشتريات وسلسلة التوريد',
                      Icons.local_shipping_outlined,
                      route: 'procurement',
                    ),
                    _item(
                      'الموارد البشرية والرواتب',
                      Icons.people_alt_outlined,
                      route: 'hr',
                    ),
                    _item(
                      'التصنيع ومراكز التكلفة',
                      Icons.precision_manufacturing_outlined,
                      route: 'manufacturing',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(String title, IconData icon, {String? route}) {
    final available = route != null;
    return ListTile(
      key: route == null ? null : ValueKey('nasqo-drawer-$route'),
      enabled: available,
      leading: Icon(icon),
      title: Text(title),
      subtitle: available ? null : const Text('غير متاح في هذه النسخة'),
      trailing: available
          ? const Icon(Icons.chevron_left, size: 20)
          : const Icon(Icons.lock_outline, size: 16),
      // A null handler gives both pointer and accessibility users a genuinely
      // disabled item, not a tappable placeholder with a misleading toast.
      onTap: route == null ? null : () => onOpen(route),
    );
  }
}
