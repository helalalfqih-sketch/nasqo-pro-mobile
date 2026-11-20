import 'dart:convert';
import '../models/erp_workspace_snapshot.dart';
import '../models/erp_models.dart';

/// The original export is retained alongside the records supported by mobile.
class WebBackup {
  WebBackup._(this.original, this.company, this.modules, this.groupData);
  final RestoredGroups groupData;
  final ErpWorkspaceSnapshot modules;
  final String original, company;
  final accounts = <AccountRecord>[];
  final warehouses = <WarehouseRecord>[];
  final inventory = <InventoryItemRecord>[];
  final ledger = <LedgerEntryRecord>[];
  final lines = <SavedSaleLine>[];
  int lastNumber = 0;

  static WebBackup parse(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        !const {'nasqo-pro-erp-backup', 'nasqo-unified-sqlite-export-v1',
          'nasqo-unified-sqlite-export-v2'}.contains(data['format']) ||
        !const {1, 2}.contains(data['version'])) {
      throw const FormatException('صيغة النسخة أو إصدارها غير مدعوم.');
    }
    final result = WebBackup._(source, _required(data['workspace']['companyName']),
      ErpWorkspaceSnapshot.fromJson((data['erpData'] ?? <String, dynamic>{}) as Map<String, dynamic>), RestoredGroups.fromJson(data));
    List<Map<String, dynamic>> rows(String key) {
      final list = (data[key] as List).cast<Map<String, dynamic>>();
      final ids = <String>{};
      for (final row in list) {
        if (!ids.add(_required(row['id']))) {
          throw FormatException('معرّف مكرر في $key');
        }
      }
      return list;
    }
    for (final r in rows('accounts')) {
      result.accounts.add(AccountRecord(id: r['id'], name: _required(r['name']),
        category: AccountCategory.values.byName(r['category']),
        phone: r['phone'] ?? '', creditLimit: _number(r['creditLimit']),
        currency: _currency(r['currency']), isCashAccount: r['isCashAccount'],
        note: r['note'] ?? '', openingBalance: _number(r['openingBalance']),
        openingDirection: EntryDirection.values.byName(r['openingDirection']),
        codeNumber: r['codeNumber']));
    }
    for (final r in rows('warehouses')) {
      result.warehouses.add(WarehouseRecord(id: r['id'], name: _required(r['name']),
        details: r['details'] ?? '', isDefault: r['isDefault']));
    }
    final warehouseIds = result.warehouses.map((w) => w.id).toSet();
    for (final r in rows('inventory')) {
      if (!warehouseIds.contains(r['warehouseId']) || r['quantityUnverified'] == true) {
        throw const FormatException('تحقق من مستودع الصنف وكميته في الموقع.');
      }
      result.inventory.add(InventoryItemRecord(id: r['id'], name: _required(r['name']),
        unit: _required(r['unit']), quantity: _number(r['computedQuantity'] ?? r['quantity']),
        avgCost: _number(r['avgCost']), warehouseId: r['warehouseId'],
        minThreshold: _number(r['minThreshold'] ?? 0), sku: r['sku'] ?? ''));
    }
    final accountIds = result.accounts.map((a) => a.id).toSet();
    for (final r in rows('ledger')) {
      if (!accountIds.contains(r['accountId'])) {
        throw const FormatException('يوجد قيد يشير إلى حساب مفقود.');
      }
      final kind = {'return': 'returnEntry', 'simple-entry': 'simpleEntry'}[r['kind']] ?? r['kind'];
      final entry = LedgerEntryRecord(id: r['id'], accountId: r['accountId'],
        accountName: r['accountName'], kind: LedgerKind.values.byName(kind),
        typeLabel: r['typeLabel'], payment: PaymentMethod.values.byName(r['payment']),
        direction: EntryDirection.values.byName(r['direction']), amount: _number(r['amount']),
        currency: _currency(r['currency']), exchangeRate: _number(r['exchangeRate']),
        details: r['details'] ?? '', documentNumber: r['documentNumber'] ?? '',
        warehouseId: r['warehouseId'] ?? '', warehouseName: r['warehouseName'] ?? '',
        expenseCategory: r['expenseCategory'] ?? '', entryNumber: r['entryNumber'],
        deleted: r['deleted'], entryDate: _required(r['entryDate']));
      result.ledger.add(entry);
      if (entry.entryNumber > result.lastNumber) result.lastNumber = entry.entryNumber;
      final items = (r['lines'] ?? []) as List;
      for (var i = 0; i < items.length; i++) {
        final line = items[i];
        result.lines.add(SavedSaleLine(entryId: entry.id, position: i,
          itemId: line['inventoryItemId'] ?? '', itemName: line['itemName'],
          unit: line['unit'] ?? '', quantity: _number(line['quantity']),
          unitPrice: _number(line['price'])));
      }
    }
    if (result.accounts.isEmpty && result.warehouses.isEmpty &&
        result.ledger.isEmpty && result.inventory.isEmpty) {
      throw const FormatException('النسخة لا تتضمن سجلات محاسبية أو مخزنية للاستعادة.');
    }
    return result;
  }

  static String _required(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value;
    throw const FormatException('نص مطلوب مفقود من النسخة.');
  }

  static double _number(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    throw const FormatException('قيمة عددية غير صالحة في النسخة.');
  }

  static CurrencyCode _currency(dynamic value) => CurrencyCode.values.firstWhere(
    (currency) => currency.name.toUpperCase() == value || currency.label == value || currency.name == value,
    orElse: () => throw FormatException('عملة غير مدعومة: $value'));
}

class RestoredGroups {
  RestoredGroups(this.groups, this.membership, this.sides);
  final List<({int id, int number, int order, String name})> groups;
  final Map<String, int> membership;
  final Map<String, ({num? debit, num? credit, bool settled})> sides;

  factory RestoredGroups.fromJson(Map<String, dynamic> data) {
    final groups = [for (final g in data['accountGroups'] ?? [])
      (id: g['id'] as int, number: (g['legacyId'] ?? g['id']) as int,
       order: (g['legacyId'] ?? g['sortOrder'] ?? g['id']) as int, name: g['name'] as String)];
    groups.sort((a,b) => a.order.compareTo(b.order));
    return RestoredGroups(groups, {
      for (final a in data['accounts'] ?? [])
        if (a['groupId'] is int) a['id'] as String: a['groupId'] as int
    }, {
      for (final e in data['ledger'] ?? [])
        if (e['rawDain'] is num || e['rawMadin'] is num)
          e['id'] as String: (debit:e['rawDain'] as num?, credit:e['rawMadin'] as num?,
            settled:e['settledOnReceipt'] == true)
    });
  }

  Map<int, double> balances(List<AccountRecord> accounts, List<LedgerEntryRecord> ledger,
      Map<int, CurrencyCode> filters, CurrencyCode fallback) {
    final result = <int,double>{};
    for (final a in accounts) {
      final id = membership[a.id];
      if (id == null || a.currency != (filters[id] ?? fallback) || a.openingBalance <= 0) continue;
      final sign = a.openingDirection == EntryDirection.debit ? 1 : -1;
      result[id] = (result[id] ?? 0) + sign * a.openingBalance;
    }
    for (final e in ledger) {
      final id = membership[e.accountId];
      if (id == null || e.currency != (filters[id] ?? fallback) || e.deleted ||
          e.kind == LedgerKind.quote || e.kind == LedgerKind.order) continue;
      final side = sides[e.id];
      if (side?.settled == true) continue;
      final debit = side?.debit ?? (e.direction == EntryDirection.debit ? e.amount : 0);
      final credit = side?.credit ?? (e.direction == EntryDirection.credit ? e.amount : 0);
      result[id] = (result[id] ?? 0) + debit - credit;
    }
    return result;
  }
}
