import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../services/customer_measurement_repository.dart';
import '../services/home_balance_groups.dart';
import '../state/erp_controller.dart';
import 'customer_measurement_views.dart';
import 'invoice_form_sheet.dart';
import 'nasqo_brand_mark.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.onOpenModule,
  });

  final ErpController controller;
  final ValueChanged<String> onOpenModule;

  void _openInvoice(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (_) => InvoiceFormSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 9 Compact Quick Actions according to mobile reference specification
    final quickActions = [
      _Tile('سند جديد', Icons.receipt_outlined,
          id: 'vouchers', action: () => onOpenModule('vouchers')),
      _Tile('حوالة جديدة', Icons.send_outlined,
          id: 'cash-transfer-drafts',
          action: () => onOpenModule('cash-transfer-drafts')),
      _Tile('كشف حساب', Icons.fact_check_outlined,
          id: 'account-statement',
          action: () => onOpenModule('account-statement')),
      _Tile('قيد بسيط', Icons.category_outlined,
          id: 'simple-journal-drafts',
          highlight: true,
          action: () => onOpenModule('simple-journal-drafts')),
      _Tile('الحركة اليومية', Icons.list_alt,
          id: 'daily-movement',
          highlight: true,
          action: () => onOpenModule('daily-movement')),
      _Tile('صناديق النقدية', Icons.account_balance_wallet_outlined,
          id: 'cashboxes',
          highlight: true,
          action: () => onOpenModule('cashboxes')),
      _Tile('فاتورة جديدة', Icons.receipt_long_outlined,
          id: 'invoice-new', action: () => _openInvoice(context)),
      _Tile('صرف عملات', Icons.currency_exchange,
          id: 'fx-drafts', action: () => onOpenModule('fx-drafts')),
      _Tile('البحث السريع', Icons.search,
          id: 'quick-search', action: () => onOpenModule('quick-search')),
    ];

    // Additional administration and advanced tools (for mobile administration list)
    final administration = [
      _Tile('عرض سعر', Icons.description_outlined,
          id: 'quote-new', action: () => onOpenModule('quote-new')),
      _Tile('طلبية جديدة', Icons.playlist_add,
          id: 'order-new', action: () => onOpenModule('order-new')),
      _Tile('مسودة مرتجع بيع', Icons.keyboard_return,
          id: 'sales-return-drafts',
          action: () => onOpenModule('sales-return-drafts')),
      _Tile('العملات', Icons.payments_outlined,
          id: 'currencies', action: () => onOpenModule('currencies')),
      _Tile('دليل الحسابات', Icons.account_tree_outlined,
          id: 'chart-accounts', action: () => onOpenModule('chart-accounts')),
      _Tile('الحسابات', Icons.groups_outlined,
          id: 'accounts', action: () => onOpenModule('accounts')),
      _Tile('المخازن', Icons.warehouse_outlined,
          id: 'warehouses', action: () => onOpenModule('warehouses')),
      _Tile('لوحة المبيعات', Icons.bar_chart_outlined,
          id: 'sales-overview', action: () => onOpenModule('sales-overview')),
      _Tile('سلة المحذوفات', Icons.delete_outline,
          id: 'trash', action: () => onOpenModule('trash')),
      _Tile('ميزان المراجعة', Icons.balance,
          id: 'trial-balance', action: () => onOpenModule('finance')),
      _Tile('الأصناف', Icons.inventory_2_outlined,
          id: 'inventory',
          action: () => onOpenModule('inventory'),
          highlight: true),
      _Tile('حركة المخزون', Icons.swap_horiz,
          id: 'stock-movement',
          action: () => onOpenModule('stock-movement'),
          highlight: true),
      _Tile('الإدارة المتقدمة', Icons.hub_outlined,
          id: 'erp', action: () => onOpenModule('hub'), highlight: true),
      _Tile('الإعدادات', Icons.settings_outlined,
          id: 'settings',
          action: () => onOpenModule('settings'),
          highlight: true),
    ];

    // Wide/desktop test tiles: exactly 12 ops + 11 admin = 23 FilledButtons
    final opsLarge = [
      _Tile('مسودة سند', Icons.receipt_outlined,
          id: 'vouchers', action: () => onOpenModule('vouchers')),
      _Tile('مسودة تحويل داخلي', Icons.send_outlined,
          id: 'cash-transfer-drafts',
          action: () => onOpenModule('cash-transfer-drafts')),
      _Tile('فاتورة جديدة', Icons.receipt_long_outlined,
          id: 'invoice-new', action: () => _openInvoice(context)),
      _Tile('مسودة مرتجع بيع', Icons.keyboard_return,
          id: 'sales-return-drafts',
          action: () => onOpenModule('sales-return-drafts')),
      _Tile('مسودة قيد بسيط', Icons.category_outlined,
          id: 'simple-journal-drafts',
          action: () => onOpenModule('simple-journal-drafts')),
      _Tile('عرض سعر', Icons.description_outlined,
          id: 'quote-new', action: () => onOpenModule('quote-new')),
      _Tile('مسودة صرف عملات', Icons.currency_exchange,
          id: 'fx-drafts', action: () => onOpenModule('fx-drafts')),
      _Tile('طلبية جديدة', Icons.playlist_add,
          id: 'order-new', action: () => onOpenModule('order-new')),
      _Tile('البحث السريع', Icons.search,
          highlight: true,
          id: 'quick-search',
          action: () => onOpenModule('quick-search')),
      _Tile('الحركة اليومية', Icons.list_alt,
          highlight: true,
          id: 'daily-movement',
          action: () => onOpenModule('daily-movement')),
      _Tile('صناديق النقدية', Icons.account_balance_wallet_outlined,
          highlight: true,
          id: 'cashboxes',
          action: () => onOpenModule('cashboxes')),
      _Tile('كشف حساب', Icons.fact_check_outlined,
          highlight: true,
          id: 'account-statement',
          action: () => onOpenModule('account-statement')),
    ];

    final adminLarge = [
      _Tile('العملات', Icons.payments_outlined,
          id: 'currencies', action: () => onOpenModule('currencies')),
      _Tile('دليل الحسابات', Icons.account_tree_outlined,
          id: 'chart-accounts', action: () => onOpenModule('chart-accounts')),
      _Tile('الحسابات', Icons.groups_outlined,
          id: 'accounts', action: () => onOpenModule('accounts')),
      _Tile('المخازن', Icons.warehouse_outlined,
          id: 'warehouses', action: () => onOpenModule('warehouses')),
      _Tile('لوحة المبيعات', Icons.bar_chart_outlined,
          id: 'sales-overview', action: () => onOpenModule('sales-overview')),
      _Tile('سلة المحذوفات', Icons.delete_outline,
          id: 'trash', action: () => onOpenModule('trash')),
      _Tile('ميزان المراجعة', Icons.balance,
          id: 'trial-balance', action: () => onOpenModule('finance')),
      _Tile('الأصناف', Icons.inventory_2_outlined,
          id: 'inventory',
          action: () => onOpenModule('inventory'),
          highlight: true),
      _Tile('حركة المخزون', Icons.swap_horiz,
          id: 'stock-movement',
          action: () => onOpenModule('stock-movement'),
          highlight: true),
      _Tile('الإدارة المتقدمة', Icons.hub_outlined,
          id: 'erp', action: () => onOpenModule('hub'), highlight: true),
      _Tile('الإعدادات', Icons.settings_outlined,
          id: 'settings',
          action: () => onOpenModule('settings'),
          highlight: true),
    ];

    final colors = Theme.of(context).colorScheme;

    // Mobile Reference Brand Plaque
    final brandPlaque = Card(
      color: colors.surface,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const NasqoBrandMark(size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.companyName.trim().isEmpty
                        ? 'نسقو برو'
                        : controller.companyName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0B5CA8),
                        ),
                  ),
                  const Text(
                    'إدارة الحسابات والمبيعات والمخزون',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'البحث السريع',
              icon: const Icon(Icons.qr_code_2, color: Color(0xFF0B5CA8)),
              onPressed: () => onOpenModule('quick-search'),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(builder: (context, constraints) {
      final large = constraints.maxWidth >= 900;
      final balance = GroupBalancesPanel(controller: controller);

      return ListView(
        key: const PageStorageKey('nasqo-home-scroll'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        children: [
          if (large)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 270,
                  child: Column(children: [
                    const _SectionHeader(title: 'العمليات السريعة'),
                    const SizedBox(height: 6),
                    _AdministrationGrid(tiles: opsLarge),
                  ])),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    brandPlaque,
                    const SizedBox(height: 12),
                    _MetricCardsGrid(
                      controller: controller,
                      onOpenModule: onOpenModule,
                    ),
                    const SizedBox(height: 14),
                    balance,
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 270,
                child: Column(children: [
                  const _SectionHeader(title: 'لوحة التحكم والإدارة'),
                  const SizedBox(height: 6),
                  _AdministrationGrid(tiles: adminLarge),
                ]),
              ),
            ])
          else ...[
            brandPlaque,
            const SizedBox(height: 12),

            // 9 Compact Quick Actions (3 columns x 3 rows)
            _QuickActionsGrid(tiles: quickActions),
            const SizedBox(height: 14),

            // 8 Metric Cards Grid (2 columns) with 2px solid blue border
            const _SectionHeader(title: 'المؤشرات والأرصدة'),
            const SizedBox(height: 6),
            _MetricCardsGrid(
              controller: controller,
              onOpenModule: onOpenModule,
            ),
            const SizedBox(height: 14),

            // Live Group Balances Audit Table
            balance,
            const SizedBox(height: 14),

            // Administration & Advanced Tools Grid
            const _SectionHeader(title: 'لوحة التحكم والعمليات المتقدمة'),
            const SizedBox(height: 6),
            _AdministrationGrid(tiles: administration),
          ],
          const SizedBox(height: 16),
          _DashboardFooter(onOpenModule: onOpenModule),
          const SizedBox(height: 8),
        ],
      );
    });
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF073B68),
        ),
      ),
    );
  }
}

class _Tile {
  const _Tile(this.title, this.icon,
      {this.id, this.action, this.highlight = false});
  final String title;
  final IconData icon;
  final String? id;
  final VoidCallback? action;
  final bool highlight;
}

/// 9 Compact Quick Actions: 3 columns x 3 rows
class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final itemWidth = (constraints.maxWidth - 12) / 3;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tile in tiles)
            SizedBox(
              width: itemWidth,
              height: 38,
              child: Tooltip(
                message: tile.action == null
                    ? '${tile.title} · غير متاح'
                    : tile.title,
                child: Material(
                  color: tile.highlight
                      ? const Color(0xFFF39A16)
                      : const Color(0xFF0B5CA8),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    key: tile.id == null ? null : ValueKey('home-${tile.id}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: tile.action,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            tile.action == null
                                ? Icons.lock_outline
                                : tile.icon,
                            size: 15,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              tile.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// 8 Metric Cards: 2 columns, 2px solid #0B5CA8 border, red/green balance without metadata
class _MetricCardsGrid extends StatefulWidget {
  const _MetricCardsGrid({
    required this.controller,
    required this.onOpenModule,
  });

  final ErpController controller;
  final ValueChanged<String> onOpenModule;

  @override
  State<_MetricCardsGrid> createState() => _MetricCardsGridState();
}

class _MetricCardsGridState extends State<_MetricCardsGrid> {
  int _measurementCount = 0;

  @override
  void initState() {
    super.initState();
    _loadMeasurementsCount();
  }

  Future<void> _loadMeasurementsCount() async {
    try {
      final repo = CustomerMeasurementRepository(widget.controller.database);
      final count = await repo.count();
      if (mounted) setState(() => _measurementCount = count);
    } catch (_) {}
  }

  void _openMeasurementForm() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerMeasurementFormSheet(
        repository: CustomerMeasurementRepository(widget.controller.database),
        onSaved: _loadMeasurementsCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.controller.accounts;
    final ledger = widget.controller.ledger;
    final defaultCurrency = widget.controller.defaultCurrency;

    final balanceGroups = computeHomeBalanceGroups(
      accounts,
      ledger,
      currency: defaultCurrency,
    );

    final groupMap = {for (final g in balanceGroups) g.category: g};

    // Card definitions preserving the exact reference order:
    // (sales/purchases, clients/employees, transfers/shop, measurements/new measurement)
    final cards = [
      _MetricCardData(
        title: 'المبيعات',
        category: AccountCategory.sales,
        icon: Icons.shopping_cart_outlined,
        route: 'sales-overview',
        group: groupMap[AccountCategory.sales],
      ),
      _MetricCardData(
        title: 'المشتريات',
        category: AccountCategory.purchases,
        icon: Icons.local_shipping_outlined,
        route: 'accounts',
        group: groupMap[AccountCategory.purchases],
      ),
      _MetricCardData(
        title: 'العملاء',
        category: AccountCategory.clients,
        icon: Icons.people_alt_outlined,
        route: 'accounts',
        group: groupMap[AccountCategory.clients],
      ),
      _MetricCardData(
        title: 'الموظفين',
        category: AccountCategory.employees,
        icon: Icons.badge_outlined,
        route: 'hr',
        group: groupMap[AccountCategory.employees],
      ),
      _MetricCardData(
        title: 'الحوالات',
        category: AccountCategory.transfers,
        icon: Icons.swap_horiz_outlined,
        route: 'cash-transfer-drafts',
        group: groupMap[AccountCategory.transfers],
      ),
      _MetricCardData(
        title: 'المحل',
        category: AccountCategory.shop,
        icon: Icons.storefront_outlined,
        route: 'accounts',
        group: groupMap[AccountCategory.shop],
      ),
      _MetricCardData(
        title: 'تمييز ومقاسات',
        icon: Icons.straighten_outlined,
        route: 'measurements',
        fixedAmount: _measurementCount.toDouble(),
      ),
      _MetricCardData(
        title: 'مقاس جديد',
        icon: Icons.square_foot_outlined,
        route: 'measurement-new',
        fixedAmount: 0.0,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth = (constraints.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final card in cards)
            SizedBox(
              width: cardWidth,
              child: _MetricCardItem(
                data: card,
                currencyLabel: defaultCurrency.label,
                onTap: () {
                  if (card.route == 'measurement-new') {
                    _openMeasurementForm();
                  } else {
                    widget.onOpenModule(card.route);
                  }
                },
              ),
            ),
        ],
      );
    });
  }
}

class _MetricCardData {
  const _MetricCardData({
    required this.title,
    required this.icon,
    required this.route,
    this.category,
    this.group,
    this.fixedAmount,
  });

  final String title;
  final IconData icon;
  final String route;
  final AccountCategory? category;
  final HomeBalanceGroup? group;
  final double? fixedAmount;
}

class _MetricCardItem extends StatelessWidget {
  const _MetricCardItem({
    required this.data,
    required this.currencyLabel,
    required this.onTap,
  });

  final _MetricCardData data;
  final String currencyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final netAmount = data.fixedAmount ?? (data.group?.netDebitMinusCredit ?? 0.0);
    final isNeg = netAmount < -0.005;
    final isPos = netAmount > 0.005;

    // Pure red/green balances without metadata
    final amountColor = isNeg
        ? const Color(0xFFDC2626) // Red
        : (isPos
            ? const Color(0xFF16A34A) // Green
            : const Color(0xFF334155)); // Neutral ink

    final formattedAmount = AccountingEngine.formatAmount(netAmount.abs());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          border: Border.all(color: const Color(0xFF0B5CA8), width: 2),
          borderRadius: BorderRadius.circular(11),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F0B5CA8),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0B5CA8).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(data.icon, color: const Color(0xFF0B5CA8), size: 19),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF073B68),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formattedAmount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Administration Grid for secondary tools
class _AdministrationGrid extends StatelessWidget {
  const _AdministrationGrid({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, size) {
      final half = (size.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final tile in tiles)
          SizedBox(
            width: half,
            child: Tooltip(
              message:
                  tile.action == null ? '${tile.title} · غير متاح' : tile.title,
              child: FilledButton(
                key: tile.id == null ? null : ValueKey('home-${tile.id}'),
                onPressed: tile.action,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  backgroundColor: tile.highlight
                      ? const Color(0xFF0B5CA8).withValues(alpha: 0.85)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: tile.highlight
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(tile.action == null ? Icons.lock_outline : tile.icon,
                      size: 15),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      tile.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}

const _orderedCategories = [
  AccountCategory.sales,
  AccountCategory.purchases,
  AccountCategory.clients,
  AccountCategory.employees,
  AccountCategory.transfers,
  AccountCategory.shop,
];

String _title(AccountCategory category) => switch (category) {
      AccountCategory.purchases => 'المشتريات',
      AccountCategory.employees => 'الموظفون',
      AccountCategory.shop => 'المحل',
      _ => category.label,
    };

class GroupBalancesPanel extends StatefulWidget {
  const GroupBalancesPanel({super.key, required this.controller});
  final ErpController controller;

  @override
  State<GroupBalancesPanel> createState() => _GroupBalancesPanelState();
}

class _GroupBalancesPanelState extends State<GroupBalancesPanel> {
  final _filters = <AccountCategory, String>{};
  static const _all = 'all';

  @override
  Widget build(BuildContext context) {
    final accounts = widget.controller.accounts;
    final ledger = widget.controller.ledger;
    final cats = _orderedCategories
        .where((c) => accounts.any((a) => a.category == c))
        .toList();
    final byCurrency = {
      for (final currency in CurrencyCode.values)
        currency: {
          for (final group
              in computeHomeBalanceGroups(accounts, ledger, currency: currency))
            group.category: group
        },
    };
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surface,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('مجموعات الحسابات والأرصدة',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF073B68),
                  )),
          const SizedBox(height: 3),
          const Text(
            'الأرصدة حسب فئات الحسابات المحلية، من دون تحويل العملات.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 7),
          if (cats.isEmpty)
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text('لا توجد حسابات محلية لعرض أرصدتها.'))
          else ...[
            _line(
              context,
              const [
                Text('الرقم', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('الاسم', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('الرصيد', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('العملة', style: TextStyle(fontWeight: FontWeight.bold))
              ],
              header: true,
            ),
            for (var index = 0; index < cats.length; index++)
              _groupRow(
                  context,
                  cats[index],
                  _orderedCategories.indexOf(cats[index]) + 1,
                  byCurrency,
                  accounts,
                  ledger),
          ],
        ]),
      ),
    );
  }

  Widget _line(BuildContext context, List<Widget> fields,
      {bool header = false}) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: header ? scheme.surfaceContainerHighest : null,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 40, child: Center(child: fields[0])),
        Expanded(flex: 3, child: fields[1]),
        Expanded(
            flex: 3,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: fields[2])),
        SizedBox(width: 76, child: fields[3]),
      ]),
    );
  }

  Widget _groupRow(
      BuildContext context,
      AccountCategory category,
      int number,
      Map<CurrencyCode, Map<AccountCategory, HomeBalanceGroup>> byCurrency,
      List<AccountRecord> accounts,
      List<LedgerEntryRecord> ledger) {
    final members = accounts.where((a) => a.category == category).toList();
    final currencies = CurrencyCode.values.where((c) {
      final result = byCurrency[c]![category]!;
      return members.any((a) => a.currency == c) ||
          result.debitTotal != 0 ||
          result.creditTotal != 0;
    }).toList();
    final current = _filters[category] ??
        (currencies.contains(widget.controller.defaultCurrency)
            ? widget.controller.defaultCurrency.name
            : currencies.first.name);
    final selected = current == _all
        ? currencies
        : [
            currencies.firstWhere((c) => c.name == current,
                orElse: () => currencies.first)
          ];
    final resolvedValue = current == _all ? _all : selected.single.name;

    void showMembers() => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => SafeArea(
              child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .62,
            child: Column(children: [
              ListTile(
                title: Text('حسابات ${_title(category)}'),
                trailing: IconButton(
                  tooltip: 'إغلاق حسابات المجموعة',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                  child: ListView(children: [
                for (final account in members)
                  ListTile(
                    leading: Text('${account.codeNumber}'),
                    title: Text(account.name),
                    subtitle: Wrap(spacing: 12, children: [
                      for (final c in selected)
                        _amount(
                            context,
                            computeHomeBalanceGroups([account], ledger,
                                    currency: c)
                                .firstWhere((g) => g.category == category),
                            withCurrency: current == _all),
                    ]),
                  ),
              ])),
            ]),
          )),
        );

    return _line(context, [
      Text('$number'),
      TextButton(
        key: ValueKey('balance-group-${category.name}'),
        style: TextButton.styleFrom(
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
        onPressed: showMembers,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_title(category)),
          Text('${members.length} حساب',
              style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
      InkWell(
        onTap: showMembers,
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in selected)
                  _amount(context, byCurrency[c]![category]!,
                      withCurrency: current == _all),
              ],
            )),
      ),
      DropdownButton<String>(
        key: ValueKey('balance-currency-${category.name}'),
        isExpanded: true,
        value: resolvedValue,
        onChanged: (s) {
          if (s != null) setState(() => _filters[category] = s);
        },
        items: [
          for (final c in currencies)
            DropdownMenuItem(
                value: c.name,
                child: Text(c.label, overflow: TextOverflow.ellipsis)),
          const DropdownMenuItem(value: _all, child: Text('الكل')),
        ],
      ),
    ]);
  }

  Widget _amount(BuildContext context, HomeBalanceGroup g,
      {required bool withCurrency}) {
    final value = AccountingEngine.formatAmount(g.magnitude);
    final red = Theme.of(context).colorScheme.error;
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '$value ${g.currency.label} ${g.balanceLabel}',
      excludeSemantics: true,
      child: Text(
          '$value ${g.balanceLabel}${withCurrency ? ' · ${g.currency.label}' : ''}',
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: g.netDebitMinusCredit < 0 ? red : primary)),
    );
  }
}

/// Small version and link footer matching reference prototype
class _DashboardFooter extends StatelessWidget {
  const _DashboardFooter({required this.onOpenModule});
  final ValueChanged<String> onOpenModule;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 24, thickness: 0.5),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const NasqoBrandMark(size: 20),
            const SizedBox(width: 6),
            Text(
              'نسقو برو ERP · الإصدار 1.0.17+18',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            _FooterLink(
              label: 'الموقع الرسمي',
              icon: Icons.language,
              onTap: () => onOpenModule('settings'),
            ),
            _FooterLink(
              label: 'واتساب الدعم',
              icon: Icons.chat_bubble_outline,
              onTap: () => onOpenModule('settings'),
            ),
            _FooterLink(
              label: 'قناة تيليجرام',
              icon: Icons.send_outlined,
              onTap: () => onOpenModule('settings'),
            ),
            _FooterLink(
              label: 'شروحات الفيديو',
              icon: Icons.play_circle_outline,
              onTap: () => onOpenModule('settings'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF0B5CA8)),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF0B5CA8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
