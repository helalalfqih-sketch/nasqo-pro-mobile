import 'dart:convert';
import 'backup_decimal.dart';
import 'package:sqflite/sqflite.dart';
import '../models/erp_models.dart';

const legacyMappedColumns = <String, Set<String>>{
  'workspaces': {'id', 'company_name'},
  'currencies': {'id', 'name', 'amount', 'amount2', 'sympol', 'name2'},
  'boxes': {'id', 'name', 'cur'},
  'customers': {
    'id',
    'name',
    'type',
    'phone',
    'lim',
    'opening_balance',
    'opening_direction'
  },
  'stores': {'id', 'name', 'details', 'is_default'},
  'products': {
    'id',
    'name',
    'barcode',
    'unit',
    'store_id',
    'quantity',
    'price2',
    'min_threshold'
  },
  'input_move': {
    'id',
    'bill',
    'per_id',
    'bill_type',
    'year',
    'month',
    'day',
    'dain',
    'madin',
    'cur',
    'curprice',
    'details',
    'bstate'
  },
  'bill_details': {
    'id',
    'bill_id',
    'prod_id',
    'store_id',
    'unit',
    'amount',
    'price',
    'total',
    'discount'
  },
};

/// Strict SmartPro item-invoice profile. Source balances and per-store stock
/// must be explicit. Never infer stock from historical bill lines.
Future<String> convertLegacyWebsite(Database db, Set<Object?> tables) async {
  Never fail(String detail) =>
      throw FormatException('نسخة SQLite قديمة من الموقع. $detail');
  for (final t in legacyMappedColumns.keys) {
    if (!tables.contains(t)) fail('جدول مطلوب مفقود: $t');
  }
  final data = <String, Map<int, Map<String, Object?>>>{};
  for (final table in tables.whereType<String>()) {
    if (table.startsWith('sqlite_') || table == 'android_metadata') continue;
    final name = '"${table.replaceAll('"', '""')}"';
    final n = (await db.rawQuery('SELECT COUNT(*) FROM $name'))
        .single
        .values
        .single as int;
    if (n == 0) {
      data[table] = {};
      continue;
    }
    final supported = legacyMappedColumns[table];
    if (supported == null) fail('لم يُطابق جدول $table وفيه $n سجل.');
    final schema = await db.rawQuery('PRAGMA table_info($name)');
    final extra =
        schema.map((r) => r['name']).where((c) => !supported.contains(c));
    if (extra.isNotEmpty)
      fail('حقول تحتاج إلى مطابقة في $table: ${extra.join("، ")}');
    final mapped = <int, Map<String, Object?>>{};
    for (final row in await db.query(table)) {
      final id = row['id'];
      if (id is! int || id <= 0 || mapped.containsKey(id))
        fail('معرف غير صالح أو مكرر في $table.');
      mapped[id] = row;
    }
    data[table] = mapped;
  }
  Iterable<Map<String, Object?>> rows(String table) => data[table]!.values;
  String field(Map row, String key) {
    final v = row[key];
    if (v is! String || v.trim().isEmpty)
      fail('حقل مطلوب $key في السجل ${row["id"]}.');
    return v;
  }

  num number(Map row, String key) {
    final v = row[key];
    if (v is! num || !v.isFinite || v.abs() > 9007199254740991)
      fail('قيمة $key غير مؤكدة في السجل ${row["id"]}.');
    return v;
  }

  Map<String, Object?> ref(Map row, String key, String table) =>
      data[table]![row[key]] ??
      fail('مرجع $key غير معرّف في $table للسجل ${row["id"]}.');
  String currency(Map r) {
    final name = field(ref(r, 'cur', 'currencies'), 'name');
    return CurrencyCode.values
            .where((c) => c.name == name || c.label == name)
            .firstOrNull
            ?.name ??
        fail('عملة غير مدعومة: $name');
  }

  final moneyCodes = <String>{};
  final currencies = [
    for (final r in rows('currencies'))
      (() {
        final code = currency({'cur': r['id']});
        if (!moneyCodes.add(code) ||
            number(r, 'amount') <= 0 ||
            number(r, 'amount2') <= 0) fail('تعريف العملة أو سعرها غير صالح.');
        return {
          'code': code,
          'ratePrimary': r['amount'],
          'rateSecondary': r['amount2'],
          'symbol': r['sympol'],
          'nameSecondary': r['name2']
        };
      })()
  ];
  const categories = {
    'العملاء': 'clients',
    'المبيعات': 'sales',
    'المشتريات': 'purchases',
    'الموردين': 'purchases',
    'الموظفين': 'employees',
    'المحل': 'shop',
    'الحوالات': 'transfers'
  };
  final groups = [
    for (final r in rows('boxes'))
      {
        'id': r['id'],
        'name': field(r, 'name'),
        'category': categories[r['name']] ??
            fail('تصنيف مجموعة غير محسوم: ${r["name"]}'),
        'currencyCode': currency(r)
      }
  ];
  final accounts = [
    for (final r in rows('customers'))
      (() {
        final group = ref(r, 'type', 'boxes');
        if (!{'credit', 'debit'}.contains(r['opening_direction']) ||
            number(r, 'opening_balance') < 0)
          fail('الرصيد الافتتاحي غير مؤكد للحساب ${r["id"]}.');
        return {
          'id': 'sp_acc_${r["id"]}',
          'codeNumber': r['id'],
          'groupId': group['id'],
          'category': categories[group['name']],
          'currency': currency(group),
          'name': field(r, 'name'),
          'phone': r['phone'],
          'openingDirection': r['opening_direction'],
          'openingBalance': r['opening_balance'],
          'creditLimit': number(r, 'lim'),
          'isCashAccount': false
        };
      })()
  ];
  final warehouses = [
    for (final r in rows('stores'))
      {
        'id': 'sp_wh_${r["id"]}',
        'name': field(r, 'name'),
        'details': r['details'],
        'isDefault': switch (r['is_default']) {
          1 => true,
          0 => false,
          _ => fail('صفة المخزن الافتراضي غير محددة.')
        }
      }
  ];
  final inventory = [
    for (final r in rows('products'))
      {
        'id': 'sp_inv_${r["id"]}',
        'legacyId': r['id'],
        'name': field(r, 'name'),
        'unit': field(r, 'unit'),
        'sku': r['barcode'],
        'warehouseId': 'sp_wh_${ref(r, "store_id", "stores")["id"]}',
        'quantity': number(r, 'quantity'),
        'avgCost': number(r, 'price2'),
        'minThreshold': number(r, 'min_threshold')
      }
  ];
  final lines = <int, List<Map<String, Object?>>>{};
  for (final r in rows('bill_details')) {
    final bill = ref(r, 'bill_id', 'input_move'),
        item = ref(r, 'prod_id', 'products'),
        store = ref(r, 'store_id', 'stores');
    final qty = number(r, 'amount'),
        price = number(r, 'price'),
        total = number(r, 'total');
    if (qty <= 0 ||
        price < 0 ||
        number(r, 'discount') != 0 ||
        (BackupDecimal.from(qty) * BackupDecimal.from(price)).toString() !=
            BackupDecimal.from(total).toString() ||
        r['unit'] != item['unit'] ||
        store['id'] != item['store_id'])
      fail('لم يتطابق بند الفاتورة ${r["id"]} مع الصنف أو المبلغ.');
    (lines[bill['id'] as int] ??= []).add({
      'legacyId': r['id'],
      'inventoryItemId': 'sp_inv_${item["id"]}',
      'warehouseId': 'sp_wh_${store["id"]}',
      'itemName': item['name'],
      'unit': item['unit'],
      'price': price,
      'quantity': qty,
      'total': total,
      'discount': r['discount']
    });
  }
  final ledger = [
    for (final r in rows('input_move'))
      (() {
        final account = ref(r, 'per_id', 'customers'), code = currency(r);
        final debit = number(r, 'dain'),
            credit = number(r, 'madin'),
            rate = number(r, 'curprice');
        if (debit < 0 ||
            credit < 0 ||
            (debit > 0) == (credit > 0) ||
            rate <= 0 ||
            r['bstate'] != 1)
          fail('نوع الدفع أو جانبا الحركة غير محسومين: ${r["id"]}.');
        final kind = r['bill_type'];
        if (!{1, 2, 3, 4, 5}.contains(kind)) fail('نوع مستند غير مدعوم: $kind');
        final items = lines[r['id']] ?? [], amount = debit + credit;
        if (kind == 1
            ? items.isNotEmpty
            : items.isEmpty ||
                items
                        .fold<BackupDecimal>(BackupDecimal.from(0),
                            (s, i) => s + BackupDecimal.from(i['total'] as num))
                        .toString() !=
                    BackupDecimal.from(amount).toString())
          fail('لم يتطابق إجمالي المستند ${r["id"]} مع بنوده.');
        final y = r['year'], m = r['month'], d = r['day'];
        if (y is! int || m is! int || d is! int || y < 1 || y > 9999)
          fail('تاريخ غير مكتمل.');
        final date = DateTime.utc(y, m, d);
        if (date.year != y || date.month != m || date.day != d)
          fail('تاريخ غير صالح في الحركة ${r["id"]}.');
        final stores = items.map((i) => i['warehouseId']).toSet();
        if (stores.length > 1) fail('فاتورة متعددة المخازن تتطلب مطابقة.');
        return {
          'id': 'sp_ent_${r["id"]}',
          'entryNumber': r['id'],
          'accountId': 'sp_acc_${account["id"]}',
          'accountName': account['name'],
          'currency': code,
          'exchangeRate': rate,
          'rawDain': debit,
          'rawMadin': credit,
          'direction': debit > 0 ? 'debit' : 'credit',
          'amount': amount,
          'entryDate': date.toIso8601String().split('T').first,
          'payment': 'credit',
          'docType': kind,
          'kind': kind == 1
              ? 'voucher'
              : kind == 4 || kind == 5
                  ? 'return'
                  : 'invoice',
          'typeLabel': {
            1: 'سند تاريخي',
            2: 'فاتورة بيع آجل',
            3: 'فاتورة شراء آجلة',
            4: 'مردود مبيعات',
            5: 'مردود مشتريات'
          }[kind],
          'details': r['details'],
          'documentNumber': r['bill'],
          'deleted': false,
          'lines': items,
          if (stores.isNotEmpty) 'warehouseId': stores.single,
          if (stores.isNotEmpty)
            'warehouseName':
                warehouses.singleWhere((w) => w['id'] == stores.single)['name']
        };
      })()
  ];
  if (rows('workspaces').length != 1) fail('تعذّر تحديد المنشأة.');
  return jsonEncode({
    'format': 'nasqo-unified-sqlite-export-v2',
    'version': 2,
    'workspace': {
      'companyName': field(rows('workspaces').single, 'company_name')
    },
    'currencies': currencies,
    'accountGroups': groups,
    'accounts': accounts,
    'warehouses': warehouses,
    'inventory': inventory,
    'ledger': ledger
  });
}
