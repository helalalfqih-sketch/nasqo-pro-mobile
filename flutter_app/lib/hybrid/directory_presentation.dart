import '../models/erp_models.dart';
import '../state/erp_controller.dart';
import '../services/account_amounts.dart';
import '../services/trial_balance_summary.dart';

const homeCategories = [
  AccountCategory.sales,
  AccountCategory.purchases,
  AccountCategory.clients,
  AccountCategory.employees,
  AccountCategory.transfers,
  AccountCategory.shop
];

/// Read-only projections from the controller's active SQLite workspace.
/// Ledger rows and native editing capabilities stay outside the WebView.
class DirectoryPresentation {
  DirectoryPresentation(this.controller);
  final ErpController controller;
  String screen = 'home', period = 'الكل';
  String currency = '', from = '', through = '';
  int? group;
  AccountCategory? category;

  void open(String target,
      {int? groupId,
      AccountCategory? accountCategory,
      String? initialCurrency}) {
    screen = target;
    group = groupId;
    category = accountCategory;
    period = 'الكل';
    from = through = '';
    currency = initialCurrency ?? controller.defaultCurrency.label;
  }

  bool includes(AccountRecord account) {
    if (screen == 'picker' || screen == 'chart') return true;
    if (screen != 'suppliers') return false;
    return group == null
        ? account.category == category
        : controller.restoredGroups?.membership[account.id] == group;
  }

  AccountRecord? account(Object? id) =>
      controller.accounts.where((a) => a.id == id && includes(a)).firstOrNull;

  List<List<String>> exportRows(bool onlyCurrency) {
    final accounts = controller.accounts.where(includes).toList();
    final values =
        accountAmountsByCurrency(controller, accounts, period: period);
    return [
      [
        'الرقم',
        'اسم الحساب',
        'العملة',
        'مدين',
        'دائن',
        'الرصيد (مدين ناقص دائن)'
      ],
      for (final a in accounts)
        for (final c in CurrencyCode.values)
          if ((currency == 'الكل' &&
                  (a.currency == c || values.containsKey((a.id, c)))) ||
              (currency == c.label &&
                  (!onlyCurrency ||
                      a.currency == c ||
                      values.containsKey((a.id, c)))))
            [
              a.codeNumber.toString(),
              a.name,
              c.label,
              (values[(a.id, c)]?.debit ?? 0).toStringAsFixed(2),
              (values[(a.id, c)]?.credit ?? 0).toStringAsFixed(2),
              ((values[(a.id, c)]?.debit ?? 0) -
                      (values[(a.id, c)]?.credit ?? 0))
                  .toStringAsFixed(2),
            ],
    ];
  }

  Map<String, Object?> snapshot() {
    if (screen == 'trial') {
      return {
        'screen': screen,
        'currency': currency,
        'from': from,
        'through': through,
        'reports': [
          for (final c in CurrencyCode.values)
            if (currency == 'الكل' || currency == c.label)
              trialBalanceSummary(controller, c, from: from, through: through)
                  .toJson()
        ]
      };
    }
    if (screen == 'warehouses') {
      return {
        'screen': screen,
        'warehouses': [
          for (final w in controller.warehouses)
            {
              'id': w.id,
              'name': w.name,
              'isDefault': w.isDefault,
              'codeNumber': controller.restoredGroups?.warehouseNumbers[w.id]
            }
        ]
      };
    }
    final accounts = controller.accounts.where(includes).toList();
    final amountsByKey = screen == 'picker'
        ? <(String, CurrencyCode), AccountAmounts>{}
        : accountAmountsByCurrency(controller, accounts, period: period);
    final archive = controller.restoredGroups;
    return {
      'screen': screen,
      'group': group,
      'category': category?.name,
      'currency': currency,
      'period': period,
      'accounts': [
        for (final a in accounts)
          {
            'id': a.id,
            'name': a.name,
            'codeNumber': a.codeNumber,
            'category': a.category.name,
            'groupId': archive?.membership[a.id] ??
                -(homeCategories.indexOf(a.category) + 1),
            'currency': a.currency.label,
            'phone': a.phone,
            'note': a.note,
            'creditLimit': a.creditLimit,
            'openingBalance': a.openingBalance,
            'isCashAccount': a.isCashAccount,
            if (screen != 'picker')
              'amounts': {
                for (final c in CurrencyCode.values)
                  if (c == a.currency || amountsByKey.containsKey((a.id, c)))
                    c.label:
                        (amountsByKey[(a.id, c)] ?? AccountAmounts()).toJson()
              },
          },
      ],
    };
  }
}
