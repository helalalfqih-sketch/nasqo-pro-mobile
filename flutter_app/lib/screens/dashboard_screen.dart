import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../services/customer_measurement_repository.dart';
import '../services/home_balance_groups.dart';
import '../state/erp_controller.dart';
import 'customer_measurement_views.dart';
import 'home_account_views.dart';
import 'invoice_workspace.dart';
import 'nasqo_brand_mark.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.onOpenModule,
    this.scrollController,
  });

  final ScrollController? scrollController;

  final ErpController controller;
  final ValueChanged<String> onOpenModule;

  void _openInvoice(BuildContext context) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => InvoiceWorkspace(controller: controller),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final quickActions = [
      _Tile('سند جديد', Icons.receipt_outlined,
          id: 'vouchers', action: () => onOpenModule('post-voucher')),
      _Tile('حوالة جديدة', Icons.send_outlined,
          id: 'cash-transfer-drafts',
          action: () => onOpenModule('post-transfer')),
      _Tile('فاتورة جديدة', Icons.receipt_long_outlined,
          id: 'invoice-new', action: () => _openInvoice(context)),
      _Tile('مردود جديد', Icons.keyboard_return,
          id: 'sales-return-drafts',
          action: () => onOpenModule('sales-return-drafts')),
      _Tile('قيد بسيط', Icons.category_outlined,
          id: 'simple-journal-drafts',
          action: () => onOpenModule('post-journal')),
      _Tile('عرض سعر', Icons.description_outlined,
          id: 'quote-new', action: () => onOpenModule('quote-new')),
      _Tile('صرف عملات', Icons.currency_exchange,
          id: 'fx-drafts', action: () => onOpenModule('post-exchange')),
      _Tile('طلبية جديدة', Icons.playlist_add,
          id: 'order-new', action: () => onOpenModule('order-new')),
      _Tile('البحث السريع', Icons.search,
          highlight: true, id: 'quick-search', action: () => onOpenModule('quick-search')),
      _Tile('الحركة اليومية', Icons.list_alt,
          id: 'daily-movement',
          highlight: true,
          action: () => onOpenModule('daily-movement')),
      _Tile('صناديق النقدية', Icons.account_balance_wallet_outlined,
          id: 'cashboxes',
          highlight: true,
          action: () => onOpenModule('cashboxes')),
      _Tile('كشف حساب', Icons.fact_check_outlined,
          highlight: true, id: 'account-statement',
          action: () => onOpenModule('account-statement')),
      _Tile('التقارير', Icons.assessment_outlined,
          id: 'reports', highlight: true, action: () => onOpenModule('reports')),
    ];

    // Additional administration and advanced tools (for mobile administration list)
    final administration = [
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
          id: 'trial-balance', action: () => onOpenModule('report-trial')),
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
          id: 'trial-balance', action: () => onOpenModule('report-trial')),
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
      color: Theme.of(context).brightness == Brightness.dark ? colors.surface : const Color(0xFFEEF2FF),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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
                    (controller.companyName.trim().isEmpty || controller.companyName == 'نسقو برو ERP')
                        ? 'نسقو برو'
                        : controller.companyName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
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
              key: const ValueKey('home-qr-scanner'),
              tooltip: 'مسح رمز QR',
              icon: const Icon(Icons.qr_code_2, color: Color(0xFF4338CA)),
              onPressed: () => onOpenModule('qr-scanner'),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(builder: (context, constraints) {
      final large = constraints.maxWidth >= 900;
      final balance = GroupBalancesPanel(controller: controller);

      return ListView(
        controller: scrollController,
        key: const PageStorageKey('nasqo-home-scroll'),
        padding: EdgeInsets.symmetric(horizontal: large ? 10 : 14, vertical: 14),
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
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: brandPlaque,
              ),
            ),
            const SizedBox(height: 10),
            balance,
            const SizedBox(height: 14),
            _QuickActionsGrid(tiles: quickActions, controller: controller),
            const SizedBox(height: 10),
            _QuickActionsGrid(tiles: administration, controller: controller),
            const SizedBox(height: 14),
            ExpansionTile(
              key: const PageStorageKey('nasqo-home-metrics'),
              title: const Text('المؤشرات والأرصدة'),
              children: [
                _MetricCardsGrid(controller: controller, onOpenModule: onOpenModule),
              ],
            ),
          ],
          const SizedBox(height: 16),
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
          color: Color(0xFF312E81),
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

/// Phone dashboard actions use the two-column layout of the React home screen.
class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({required this.tiles,required this.controller});
  final ErpController controller;
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final itemWidth = (constraints.maxWidth - 9) / 2;
      return Wrap(
        spacing: 9,
        runSpacing: 9,
        children: [
          for (final tile in tiles)
            SizedBox(
              width: itemWidth,
              height: 48,
              child: Tooltip(
                message: tile.action == null
                    ? '${tile.title} · غير متاح'
                    : tile.title,
                child: Material(
                  color: tile.highlight
                      ? Color(controller.secondaryTint)
                      : Color(controller.primaryTint),
                  borderRadius: BorderRadius.circular(controller.homeRadius),
                  child: InkWell(
                    key: tile.id == null ? null : ValueKey('home-${tile.id}'),
                    borderRadius: BorderRadius.circular(controller.homeRadius),
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
        route: 'group-sales',
        group: groupMap[AccountCategory.sales],
      ),
      _MetricCardData(
        title: 'المشتريات',
        category: AccountCategory.purchases,
        icon: Icons.local_shipping_outlined,
        route: 'group-purchases',
        group: groupMap[AccountCategory.purchases],
      ),
      _MetricCardData(
        title: 'العملاء',
        category: AccountCategory.clients,
        icon: Icons.people_alt_outlined,
        route: 'group-clients',
        group: groupMap[AccountCategory.clients],
      ),
      _MetricCardData(
        title: 'الموظفين',
        category: AccountCategory.employees,
        icon: Icons.badge_outlined,
        route: 'group-employees',
        group: groupMap[AccountCategory.employees],
      ),
      _MetricCardData(
        title: 'الحوالات',
        category: AccountCategory.transfers,
        icon: Icons.swap_horiz_outlined,
        route: 'group-transfers',
        group: groupMap[AccountCategory.transfers],
      ),
      _MetricCardData(
        title: 'المحل',
        category: AccountCategory.shop,
        icon: Icons.storefront_outlined,
        route: 'group-shop',
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
          border: Border.all(color: const Color(0xFF4338CA), width: 2),
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
                color: const Color(0xFF4338CA).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(data.icon, color: const Color(0xFF4338CA), size: 19),
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
                      color: Color(0xFF312E81),
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
                      ? const Color(0xFF4338CA).withValues(alpha: 0.85)
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
  final _groupCurrencies = <int, CurrencyCode>{};

  @override
  Widget build(BuildContext context) {
    final accounts = widget.controller.accounts;
    final ledger = widget.controller.ledger;
    final restored = widget.controller.restoredGroups;
    if (restored != null && restored.groups.isNotEmpty) {
      final fallback = widget.controller.defaultCurrency;
      final totals = restored.balances(accounts,ledger,_groupCurrencies,fallback);
      final counts = <int,int>{};
      for (final a in accounts) {
        final id = restored.membership[a.id];
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      void openGroup(int groupId) {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => HomeAccountsView.restoredGroup(
            controller: widget.controller,
            groupId: groupId,
            initialCurrency: _groupCurrencies[groupId] ?? fallback,
          ),
        ));
      }

      return _balanceTable(context, [
          for (final (index,g) in restored.groups.indexed)
            TableRow(decoration: _rowDecoration(context, index),
              children:[
                Center(child:Text('${g.number}')),
                TextButton(
                  onPressed: () => openGroup(g.id),
                  style: TextButton.styleFrom(alignment: AlignmentDirectional.centerStart),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${counts[g.id] ?? 0} حساب', style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => openGroup(g.id),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                  child: _signedBalance(context, totals[g.id] ?? 0),
                ),
                _currencyBox(context, DropdownButton<CurrencyCode>(isExpanded:true, isDense: true, iconSize: 16, style: Theme.of(context).textTheme.labelMedium, value:_groupCurrencies[g.id] ?? fallback,
                  items:[for(final c in CurrencyCode.values) DropdownMenuItem(value:c,child:Text(c.label, overflow: TextOverflow.ellipsis))],
                  onChanged:(c){if(c!=null) setState(()=>_groupCurrencies[g.id]=c);}))
              ])
        ]);
    }
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
    if (cats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('لا توجد حسابات محلية لعرض أرصدتها.'),
      );
    }
    return _balanceTable(context, [
      for (final (index, category) in cats.indexed)
        _groupRow(context, category, index, byCurrency, accounts, ledger),
    ]);
  }

  BoxDecoration _rowDecoration(BuildContext context, int index) {
    final theme = Theme.of(context);
    return BoxDecoration(color: index.isEven
        ? theme.colorScheme.surface
        : theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerHighest
            : const Color(0xFFDCE6F2));
  }

  Widget _balanceTable(BuildContext context, List<TableRow> rows) {
    final scheme = Theme.of(context).colorScheme;
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(47),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(),
        3: FixedColumnWidth(74),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder.all(color: scheme.outlineVariant),
      children: [
        TableRow(
          decoration: BoxDecoration(color: scheme.surfaceContainerLow),
          children: [
            for (final title in ['الرقم', 'الاسم', 'الرصيد', 'العملة'])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(title, textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        ...rows,
      ],
    );
  }

  TableRow _groupRow(
      BuildContext context,
      AccountCategory category,
      int index,
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

    return TableRow(decoration: _rowDecoration(context, index), children: [
      Center(child: Text('${_orderedCategories.indexOf(category) + 1}')),
      TextButton(
        key: ValueKey('balance-group-${category.name}'),
        style: TextButton.styleFrom(
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
        onPressed: showMembers,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_title(category), style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold)),
          Text('${members.length} حساب',
              style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
      InkWell(
        onTap: showMembers,
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (final c in selected)
                  _signedBalance(context, byCurrency[c]![category]!.netDebitMinusCredit,
                      currency: current == _all ? c : null),
              ],
            )),
      ),
      _currencyBox(context, DropdownButton<String>(
        isDense: true,
        iconSize: 16,
        style: Theme.of(context).textTheme.labelMedium,
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
      )),
    ]);
  }

  Widget _currencyBox(BuildContext context, Widget dropdown) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      constraints: const BoxConstraints(minHeight: 30),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(3),
      ),
      child: DropdownButtonHideUnderline(child: dropdown),
    );
  }

  Widget _signedBalance(BuildContext context, double net, {CurrencyCode? currency}) {
    final negative = net < 0 && net.abs() >= 0.005;
    final magnitude = AccountingEngine.formatAmount(net.abs() < 0.005 ? 0 : net.abs());
    final amount = negative ? '$magnitude-' : magnitude;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = net.abs() < 0.005
        ? theme.colorScheme.onSurface
        : negative
            ? (dark ? theme.colorScheme.error : const Color(0xFF9F1239))
            : (dark ? theme.colorScheme.primary : const Color(0xFF0B5CA8));
    return Text(
      currency == null ? amount : '$amount · ${currency.label}',
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
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

