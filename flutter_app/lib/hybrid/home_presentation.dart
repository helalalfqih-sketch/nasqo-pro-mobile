import 'dart:convert';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../models/erp_models.dart';
import '../services/home_balance_groups.dart';
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
const _categories = [
  AccountCategory.sales,
  AccountCategory.purchases,
  AccountCategory.clients,
  AccountCategory.employees,
  AccountCategory.transfers,
  AccountCategory.shop
];

bool _hasKeys(Map map, Set<String> keys) =>
    map.length == keys.length && keys.every(map.containsKey);

bool _validLayout(Object? value) {
  if (value is! Map ||
      !_hasKeys(value, {'order', 'pinned', 'hidden', 'toneOverrides'})) {
    return false;
  }
  bool known(Object? id) =>
      id != 'qr-scanner' && homeDestinations.containsKey(id);
  for (final key in ['order', 'pinned', 'hidden']) {
    final ids = value[key];
    if (ids is! List ||
        ids.length > 24 ||
        ids.toSet().length != ids.length ||
        !ids.every(known)) {
      return false;
    }
  }
  final order = value['order'] as List;
  if (order.length != 24) return false;
  final hidden = value['hidden'] as List;
  if (hidden.contains('settings') ||
      (value['pinned'] as List).any(hidden.contains)) {
    return false;
  }
  final tones = value['toneOverrides'];
  return tones is Map &&
      tones.keys.every(known) &&
      tones.values.every((v) => v == 'blue' || v == 'amber');
}

class HomePresentation {
  HomePresentation(this.controller);
  final ErpController controller;
  static const preferenceKey = 'hybrid_home_ui_v1';
  final filters = <String, String>{};
  Map<String, dynamic>? layout;
  int scroll = 0;

  bool get restored => controller.restoredGroups?.groups.isNotEmpty == true;
  AccountCategory? categoryFor(int id) =>
      !restored && id < 0 && -id <= _categories.length
          ? _categories[-id - 1]
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
    final valid = switch (msg['action']) {
      'ready' || 'paint' => _hasKeys(msg, {'action'}),
      'tile' =>
        _hasKeys(msg, {'action', 'id'}) && homeDestinations.containsKey(id),
      'group' =>
        _hasKeys(msg, {'action', 'id'}) && id is int && containsGroup(id),
      'currency' => _hasKeys(msg, {'action', 'id', 'currency'}) &&
          id is int &&
          containsGroup(id) &&
          _currency(msg['currency']),
      'editing' => _hasKeys(msg, {'action', 'active'}) && msg['active'] is bool,
      'scroll' => _hasKeys(msg, {'action', 'y'}) &&
          msg['y'] is int &&
          (msg['y'] as int) >= 0 &&
          (msg['y'] as int) <= 1000000,
      'layout' =>
        _hasKeys(msg, {'action', 'value'}) && _validLayout(msg['value']),
      'haptic' => _hasKeys(msg, {'action', 'kind'}) &&
          const ['light', 'pin', 'success'].contains(msg['kind']),
      _ => false,
    };
    return valid ? msg : null;
  }

  Future<void> load() async {
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
      case 'layout':
        layout = msg['value'] as Map<String, dynamic>;
      case 'scroll':
        if (scroll == msg['y']) return;
        scroll = msg['y'] as int;
      default:
        throw ArgumentError('Expected a validated UI preference');
    }
    final payload =
        jsonEncode({'filters': filters, 'scroll': scroll, 'layout': layout});
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
      for (final (index, category) in _categories.indexed) {
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
      'defaultCurrency': controller.defaultCurrency.label,
      'currencies': [for (final c in CurrencyCode.values) c.label],
      'rows': rows,
      'layout': layout,
      'scroll': scroll
    };
  }
}
