import 'dart:convert';
import 'directory_presentation.dart';
import '../services/account_amounts.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../models/erp_models.dart';
import '../services/home_balance_groups.dart';
import '../services/customer_measurement_repository.dart';
import '../screens/home_navigation.dart' show workspaceAlerts;
import '../state/erp_controller.dart';

/// Values are native route names. The WebView can request these destinations;
/// the actual forms, validation, confirmation and posting belong to Flutter.
const homeDestinations = <String, String>{
  'new-voucher': 'post-voucher',
  'new-transfer': 'post-transfer',
  'new-invoice': 'invoice',
  'new-return': 'sales-return-drafts',
  'simple-entry': 'post-journal',
  'quote': 'quote-new',
  'currency-exchange': 'post-exchange',
  'new-order': 'order-new',
  'quick-search': 'quick-search',
  'daily-journal': 'daily-movement',
  'cashboxes': 'cashboxes',
  'statement': 'account-statement',
  'reports': 'reports',
  'currencies': 'currencies',
  'account-groups': 'group-directory',
  'accounts': 'accounts',
  'warehouses': 'warehouses',
  'sales-dashboard': 'sales-overview',
  'trash': 'trash',
  'trial-balance': 'report-trial',
  'items': 'inventory',
  'stock-movement': 'stock-movement',
  'erp-hub': 'hub',
  'settings': 'settings',
  'qr-scanner': 'qr-scanner',
};
const homeNavigationRoutes = {
  'app-update',
  'about-modal',
  'activation-modal',
  'home-mode',
  'theme',
  'local-backups',
  'account-import',
  'message-settings',
  'notifications',
  'account-new',
  'chart-accounts',
  'item-new',
  'group-sales',
  'group-purchases',
  'group-clients',
  'group-employees',
  'group-transfers',
  'group-shop',
  'measurements',
  'measurement-new',
  'quotes',
  'orders',
  'finance',
  'hr',
  'crm',
  'procurement',
  'manufacturing',
  'report-closing',
  'report-category',
  'report-expiry',
  'report-stock',
  'report-profit',
  'report-services',
  'report-movement',
  'recorded-sales-tax',
};

bool _hasKeys(Map map, Set<String> keys) =>
    map.length == keys.length && keys.every(map.containsKey);

const homeMetricIds = {
  'sales',
  'purchases',
  'clients',
  'employees',
  'transfers',
  'shop',
  'measurements',
  'measurement-new',
};

bool _validLayout(Object? value, {bool metrics = false}) {
  if (value is! Map ||
      !_hasKeys(value, {'order', 'pinned', 'hidden', 'toneOverrides'})) {
    return false;
  }
  bool known(Object? id) => metrics
      ? homeMetricIds.contains(id)
      : id != 'qr-scanner' && homeDestinations.containsKey(id);
  final size = metrics ? homeMetricIds.length : homeDestinations.length - 1;
  for (final key in ['order', 'pinned', 'hidden']) {
    final ids = value[key];
    if (ids is! List ||
        ids.length > size ||
        ids.toSet().length != ids.length ||
        !ids.every(known)) {
      return false;
    }
  }
  final order = value['order'] as List;
  if (order.length != size) return false;
  final hidden = value['hidden'] as List;
  if (hidden.contains('settings') ||
      (metrics && hidden.length > size - 2) ||
      (value['pinned'] as List).any(hidden.contains)) {
    return false;
  }
  final tones = value['toneOverrides'];
  return tones is Map &&
      tones.keys.every(known) &&
      tones.values.every((v) => v == 'blue' || v == 'amber');
}

class HomePresentation {
  late final directory = DirectoryPresentation(controller);
  HomePresentation(this.controller);
  final ErpController controller;
  static const preferenceKey = 'hybrid_home_ui_v1';
  final filters = <String, String>{};
  Map<String, dynamic>? layout;
  Map<String, dynamic>? metricLayout;
  int scroll = 0;
  int measurementCount = 0;

  Future<void> loadMeasurementCount() async {
    measurementCount =
        await CustomerMeasurementRepository(controller.database).count();
  }

  bool get restored => controller.restoredGroups?.groups.isNotEmpty == true;
  AccountCategory? categoryFor(int id) =>
      !restored && id < 0 && -id <= homeCategories.length
          ? homeCategories[-id - 1]
          : null;
  String _key(int id) =>
      restored ? 'group-$id' : 'category-${categoryFor(id)?.name}';
  bool containsGroup(int id) {
    if (restored) {
      return controller.restoredGroups!.groups.any((g) => g.id == id);
    }
    final category = categoryFor(id);
    return category != null &&
        controller.accounts.any((account) => account.category == category);
  }

  static bool _validDay(Object? input) {
    if (input == '') return true;
    if (input is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input))
      return false;
    return DateTime.tryParse(input)?.toIso8601String().split('T').first ==
        input;
  }

  static bool _currency(Object? value) =>
      value == 'الكل' || CurrencyCode.values.any((c) => c.label == value);
  String selection(int id) =>
      filters[_key(id)] ?? controller.defaultCurrency.label;
  CurrencyCode currencyFor(int id) =>
      CurrencyCode.values.where((c) => c.label == selection(id)).firstOrNull ??
      controller.defaultCurrency;

  /// The sole database write this bridge can cause is the fixed UI preference
  /// row below. Incoming objects are never interpreted as commands or SQL.
  Map<String, dynamic>? parse(String raw) {
    if (raw.length > 4096) return null;
    Object? msg;
    try {
      msg = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (msg is! Map<String, dynamic>) return null;
    final id = msg['id'];
    final category = msg['category'];
    final valid = switch (msg['action']) {
      'trialFilter' => directory.screen == 'trial' &&
          _hasKeys(msg, {'action', 'currency', 'from', 'through'}) &&
          _currency(msg['currency']) &&
          _validDay(msg['from']) &&
          _validDay(msg['through']) &&
          (msg['from'] == '' ||
              msg['through'] == '' ||
              (msg['from'] as String).compareTo(msg['through']) <= 0),
      'browse' => _hasKeys(msg, {'action', 'screen'}) &&
          const {'home', 'warehouses', 'picker', 'chart', 'trial'}
              .contains(msg['screen']),
      'members' => _hasKeys(msg, {'action', 'category'}) &&
          homeCategories.any((c) => c.name == category),
      'filter' => _hasKeys(msg, {'action', 'period', 'currency'}) &&
          directory.screen == 'suppliers' &&
          const {'يومي', 'شهري', 'سنوي', 'الكل'}.contains(msg['period']) &&
          _currency(msg['currency']),
      'account' => _hasKeys(msg, {'action', 'id', 'op'}) &&
          directory.account(id) != null &&
          const {
            'statement',
            'edit',
            'invoice',
            'return',
            'voucher',
            'transfer',
            'journal',
            'exchange',
            'quote',
            'order',
            'contact',
            'message',
            'whatsapp'
          }.contains(msg['op']),
      'directoryExport' => directory.screen == 'suppliers' &&
          _hasKeys(msg, {'action', 'format', 'onlyCurrency'}) &&
          msg['onlyCurrency'] is bool &&
          const {'pdf-print', 'excel', 'pdf-share'}.contains(msg['format']),
      'warehouse' => directory.screen == 'warehouses' &&
          ((_hasKeys(msg, {'action', 'op'}) && msg['op'] == 'create') ||
              (_hasKeys(msg, {'action', 'op', 'id'}) &&
                  const {'edit', 'items', 'movement'}.contains(msg['op']) &&
                  controller.warehouses.any((w) => w.id == id))),
      'ready' || 'paint' => _hasKeys(msg, {'action'}),
      'tile' =>
        _hasKeys(msg, {'action', 'id'}) && homeDestinations.containsKey(id),
      'navigate' =>
        _hasKeys(msg, {'action', 'id'}) && homeNavigationRoutes.contains(id),
      'group' =>
        _hasKeys(msg, {'action', 'id'}) && id is int && containsGroup(id),
      'currency' => _hasKeys(msg, {'action', 'id', 'currency'}) &&
          id is int &&
          containsGroup(id) &&
          _currency(msg['currency']),
      'editing' ||
      'overlay' =>
        _hasKeys(msg, {'action', 'active'}) && msg['active'] is bool,
      'scroll' => _hasKeys(msg, {'action', 'y'}) &&
          msg['y'] is int &&
          (msg['y'] as int) >= 0 &&
          (msg['y'] as int) <= 1000000,
      'metricLayout' => _hasKeys(msg, {'action', 'value'}) &&
          _validLayout(msg['value'], metrics: true),
      'layout' =>
        _hasKeys(msg, {'action', 'value'}) && _validLayout(msg['value']),
      'haptic' => _hasKeys(msg, {'action', 'kind'}) &&
          const ['light', 'pin', 'success', 'warning'].contains(msg['kind']),
      _ => false,
    };
    return valid ? msg : null;
  }

  Future<void> load() async {
    await loadMeasurementCount();
    final db = await controller.database.database;
    final found = await db.query('erp_state',
        columns: ['payloadJson'],
        where: 'stateKey = ?',
        whereArgs: [preferenceKey]);
    if (found.isEmpty) return;
    Object? prefs;
    try {
      prefs = jsonDecode(found.single['payloadJson'] as String);
    } on FormatException {
      return;
    }
    if (prefs is! Map) return;
    if (_validLayout(prefs['layout'])) {
      layout = Map<String, dynamic>.from(prefs['layout'] as Map);
    }
    if (_validLayout(prefs['metricLayout'], metrics: true)) {
      metricLayout = Map<String, dynamic>.from(prefs['metricLayout'] as Map);
    }
    final y = prefs['scroll'];
    if (y is int && y >= 0 && y <= 1000000) scroll = y;
    final stored = prefs['filters'];
    if (stored is Map) {
      for (final entry in stored.entries) {
        if (entry.key is String && _currency(entry.value)) {
          filters[entry.key as String] = entry.value as String;
        }
      }
    }
  }

  Future<void> savePreference(Map<String, dynamic> msg) async {
    switch (msg['action']) {
      case 'currency':
        filters[_key(msg['id'] as int)] = msg['currency'] as String;
      case 'metricLayout':
        metricLayout = msg['value'] as Map<String, dynamic>;
      case 'layout':
        layout = msg['value'] as Map<String, dynamic>;
      case 'scroll':
        if (scroll == msg['y']) return;
        scroll = msg['y'] as int;
      default:
        throw ArgumentError('Expected a validated UI preference');
    }
    final payload = jsonEncode({
      'filters': filters,
      'scroll': scroll,
      'layout': layout,
      if (metricLayout != null) 'metricLayout': metricLayout
    });
    final db = await controller.database.database;
    await db.insert(
        'erp_state',
        {
          'stateKey': preferenceKey,
          'payloadJson': payload,
          'updatedAt': DateTime.now().toUtc().toIso8601String()
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, double> _categoryMetrics() {
    final result = {for (final c in homeCategories) c.name: 0.0};
    final amounts = accountAmountsByCurrency(controller, controller.accounts);
    for (final a in controller.accounts) {
      final b = amounts[(a.id, controller.defaultCurrency)];
      if (b != null) {
        result[a.category.name] = result[a.category.name]! + b.credit - b.debit;
      }
    }
    return result;
  }

  Map<String, dynamic> snapshot(bool dark) {
    final rows = <Map<String, Object?>>[];
    void add(int id, int number, String name, int count, String? category,
        Map<CurrencyCode, double> amounts) {
      final choice = selection(id);
      rows.add({
        'id': id,
        'legacyId': number,
        'name': name,
        'accountCount': count,
        'category': category,
        'currency': choice,
        'netDebitMinusCredit':
            choice == 'الكل' ? null : amounts[currencyFor(id)],
        if (choice == 'الكل')
          'amounts': [
            for (final e in amounts.entries)
              {'currency': e.key.label, 'value': e.value}
          ]
      });
    }

    final archive = controller.restoredGroups;
    if (restored && archive != null) {
      final counts = <int, int>{};
      for (final a in controller.accounts) {
        final id = archive.membership[a.id];
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      final totals =
          archive.balancesByCurrency(controller.accounts, controller.ledger);
      for (final g in archive.groups) {
        add(
            g.id,
            g.number,
            g.name,
            counts[g.id] ?? 0,
            archive.groupCategories[g.id],
            {for (final c in CurrencyCode.values) c: totals[c]![g.id] ?? 0});
      }
    } else {
      final totals = {
        for (final c in CurrencyCode.values)
          c: {
            for (final g in computeHomeBalanceGroups(
                controller.accounts, controller.ledger,
                currency: c))
              g.category: g
          }
      };
      for (final (index, category) in homeCategories.indexed) {
        final group = totals[controller.defaultCurrency]![category]!;
        if (group.accountCount == 0) continue;
        final name = switch (category) {
          AccountCategory.purchases => 'المشتريات',
          AccountCategory.shop => 'المحل',
          AccountCategory.transfers => 'الحوالات',
          _ => category.label
        };
        add(-index - 1, index + 1, name, group.accountCount, category.name, {
          for (final c in CurrencyCode.values)
            c: totals[c]![category]!.netDebitMinusCredit
        });
      }
    }
    String rgb(int argb) =>
        '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return {
      'dark': dark,
      'appearance': {
        'primary': rgb(controller.primaryTint),
        'secondary': rgb(controller.secondaryTint),
        // 24 is the existing native default. The React pill default is 26.
        if (controller.homeRadius != 24) 'radius': controller.homeRadius,
      },
      'company': controller.companyName,
      if (directory.screen != 'home') 'directory': directory.snapshot(),
      'metrics': _categoryMetrics(),
      'measurementCount': measurementCount,
      'unread': workspaceAlerts(controller)
          .where((alert) => !controller.readAlerts.contains(alert.id))
          .length,
      'defaultCurrency': controller.defaultCurrency.label,
      'currencies': [for (final c in CurrencyCode.values) c.label],
      'rows': rows,
      'layout': layout,
      if (metricLayout != null) 'metricLayout': metricLayout,
      'scroll': scroll
    };
  }
}
