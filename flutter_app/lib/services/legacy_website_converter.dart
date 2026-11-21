import 'dart:convert';
import 'dart:collection';
import 'backup_decimal.dart';
import 'package:sqflite/sqflite.dart';
import '../models/erp_models.dart';

const legacyMappedColumns = <String, Set<String>>{
  'workspaces': {
    'id',
    'company_name',
    'whatsapp_phone',
    'whatsapp_provider',
    'whatsapp_instant_enabled'
  },
  'store_trans': {
    'id',
    'store_id1',
    'store_id2',
    'date',
    'ndate',
    'year',
    'month',
    'day',
    'details',
    'type',
    'user_id'
  },
  'trans_details': {
    'id',
    'bill_id',
    'prod_id',
    'amount',
    'unit',
    'unitnum',
    'details',
    'exdate'
  },
  'cboxes': {'id', 'name', 'account_id', 'cur'},
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
    'bstate',
    'ndate',
    'date',
    'cboxid'
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
  for (final t in legacyMappedColumns.keys
      .where((t) => !{'store_trans', 'trans_details', 'cboxes'}.contains(t))) {
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
    if (extra.isNotEmpty) {
      fail('حقول تحتاج إلى مطابقة في $table: ${extra.join("، ")}');
    }
    const identifiers = {
      'id',
      'account_id',
      'type',
      'cur',
      'per_id',
      'bill_type',
      'year',
      'month',
      'day',
      'bstate',
      'cboxid',
      'bill_id',
      'prod_id',
      'store_id',
      'store_id1',
      'store_id2',
      'user_id',
      'unitnum',
      'is_default',
      'whatsapp_instant_enabled'
    };
    const numeric = {
      'amount',
      'amount2',
      'lim',
      'opening_balance',
      'quantity',
      'price2',
      'min_threshold',
      'dain',
      'madin',
      'curprice',
      'price',
      'total',
      'discount'
    };
    for (final col in schema) {
      final key = col['name'] as String,
          type = col['type'].toString().toUpperCase();
      if (identifiers.contains(key) && !type.contains('INT') ||
          numeric.contains(key) &&
              !RegExp('INT|NUM|DEC|REAL|FLOA|DOUB').hasMatch(type)) {
        fail('نوع عمود غير متوافق: $table.$key ($type).');
      }
    }
    final mapped = <int, Map<String, Object?>>{};
    for (final row in await db.query(table)) {
      final id = row['id'];
      if (id is! int || id <= 0 || mapped.containsKey(id)) {
        fail('معرف غير صالح أو مكرر في $table.');
      }
      mapped[id] = row;
    }
    data[table] = mapped;
  }
  Iterable<Map<String, Object?>> rows(String table) =>
      data[table]?.values ?? [];
  String field(Map row, String key) {
    final v = row[key];
    if (v is! String || v.trim().isEmpty) {
      fail('حقل مطلوب $key في السجل ${row["id"]}.');
    }
    return v;
  }

  num number(Map row, String key) {
    final v = row[key];
    if (v is! num || !v.isFinite || v.abs() > 9007199254740991) {
      fail('قيمة $key غير مؤكدة في السجل ${row["id"]}.');
    }
    return v;
  }

  Map<String, Object?> ref(Map row, String key, String table) =>
      data[table]?[row[key]] ??
      fail('مرجع $key غير معرّف في $table للسجل ${row["id"]}.');
  String currency(Map r) {
    final name = field(ref(r, 'cur', 'currencies'), 'name');
    return CurrencyCode.values
            .where((c) => c.name == name || c.label == name)
            .firstOrNull
            ?.name ??
        fail('عملة غير مدعومة: $name');
  }

  String sourceDate(Map r) {
    final candidates = <String>{};
    void check(int y, int m, int d) {
      final date = DateTime.utc(y, m, d);
      if (y < 1 ||
          y > 9999 ||
          date.year != y ||
          date.month != m ||
          date.day != d) {
        fail('تاريخ غير صالح في السجل ${r["id"]}.');
      }
      candidates.add(date.toIso8601String().split('T').first);
    }

    if (r['year'] != null || r['month'] != null || r['day'] != null) {
      if (r['year'] is! int || r['month'] is! int || r['day'] is! int) {
        fail('تاريخ غير مكتمل.');
      }
      check(r['year'], r['month'], r['day']);
    }
    for (final key in ['date', 'ndate']) {
      if (r[key] == null || r[key] == '') continue;
      final value = r[key].toString();
      if (!RegExp(r'^(?:[0-9]{8}|[0-9]{4}-[0-9]{2}-[0-9]{2})$').hasMatch(value)) {
        fail('صيغة تاريخ غير مؤكدة.');
      }
      final compact = value.replaceAll('-', '');
      check(int.parse(compact.substring(0, 4)),
          int.parse(compact.substring(4, 6)), int.parse(compact.substring(6)));
    }
    if (candidates.length != 1) fail('تاريخ مفقود أو متعارض.');
    return candidates.single;
  }

  final moneyCodes = <String>{};
  final currencies = [
    for (final r in rows('currencies'))
      (() {
        final code = currency({'cur': r['id']});
        if (!moneyCodes.add(code) ||
            number(r, 'amount') <= 0 ||
            number(r, 'amount2') <= 0) {
          fail('تعريف العملة أو سعرها غير صالح.');
        }
        return {
          'legacyId': r['id'],
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
  // Mobile cashboxes are accounts. An explicit source link is required.
  final cashAccounts = <int>{};
  final cashboxes = [
    for (final r in rows('cboxes'))
      (() {
        final account = ref(r, 'account_id', 'customers'),
            group = ref(account, 'type', 'boxes');
        if (currency(r) != currency(group) ||
            !cashAccounts.add(account['id'] as int)) {
          fail('ربط الصندوق بالحساب أو العملة غير متطابق.');
        }
        return {
          'id': r['id'],
          'name': field(r, 'name'),
          'currencyCode': currency(r),
          'accountId': 'sp_acc_${account["id"]}'
        };
      })()
  ];
  final accounts = [
    for (final r in rows('customers'))
      (() {
        final group = ref(r, 'type', 'boxes');
        if (!{'credit', 'debit'}.contains(r['opening_direction']) ||
            number(r, 'opening_balance') < 0) {
          fail('الرصيد الافتتاحي غير مؤكد للحساب ${r["id"]}.');
        }
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
          'isCashAccount': cashAccounts.contains(r['id'])
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
        store['id'] != item['store_id']) {
      fail('لم يتطابق بند الفاتورة ${r["id"]} مع الصنف أو المبلغ.');
    }
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
            r['bstate'] != 1) {
          fail('نوع الدفع أو جانبا الحركة غير محسومين: ${r["id"]}.');
        }
        if (r['cboxid'] != null && r['cboxid'] != 0) {
          ref(r, 'cboxid', 'cboxes');
          fail(
              'الحركة النقدية تحتاج مطابقة طرف الصندوق مع القيد قبل الاستعادة.');
        }
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
                    BackupDecimal.from(amount).toString()) {
          fail('لم يتطابق إجمالي المستند ${r["id"]} مع بنوده.');
        }
        final entryDate = sourceDate(r);
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
          'entryDate': entryDate,
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
  final transfers = [
    for (final r in rows('store_trans'))
      (() {
        final from = ref(r, 'store_id1', 'stores'),
            to = ref(r, 'store_id2', 'stores');
        if (from['id'] == to['id']) fail('مخزنا التحويل متطابقان.');
        return {
          'id': r['id'],
          'fromWarehouseId': 'sp_wh_${from["id"]}',
          'toWarehouseId': 'sp_wh_${to["id"]}',
          'transferDate': sourceDate(r),
          'details': r['details'],
          'transferType': r['type'],
          'userLegacyId': r['user_id']
        };
      })()
  ];
  final transferLines = [
    for (final r in rows('trans_details'))
      (() {
        final header = ref(r, 'bill_id', 'store_trans'),
            item = ref(r, 'prod_id', 'products');
        if (number(r, 'amount') <= 0 ||
            r['unit'] != item['unit'] ||
            r['unitnum'] != 1) {
          fail('كمية أو وحدة تحويل مخزني غير مؤكدة.');
        }
        return {
          'id': r['id'],
          'transferId': header['id'],
          'inventoryItemId': 'sp_inv_${item["id"]}',
          'quantity': r['amount'],
          'unit': r['unit'],
          'unitNum': r['unitnum'],
          'details': r['details'],
          'expiryDate': r['exdate']
        };
      })()
  ];
  final transferIds = transferLines.map((l) => l['transferId']).toSet();
  if (transfers.any((h) => !transferIds.contains(h['id']))) {
    fail('تحويل مخزني بلا بنود.');
  }
  if (rows('workspaces').length != 1) fail('تعذّر تحديد المنشأة.');
  // Independent totals from source rows. Do not derive the baseline from
  // the converted ledger: an incorrect direction or warehouse must be caught.
  final balances = SplayTreeMap<String, BackupDecimal>();
  final sourceInvoices = SplayTreeMap<String, Object?>(),
      sourceStock = SplayTreeMap<String, Object?>();
  void post(Object? account, String code, num amount) {
    final key = jsonEncode(['sp_acc_$account', code]);
    balances[key] =
        (balances[key] ?? BackupDecimal.from(0)) + BackupDecimal.from(amount);
  }

  for (final row in rows('customers')) {
    final opening = number(row, 'opening_balance');
    post(row['id'], currency(ref(row, 'type', 'boxes')),
        row['opening_direction'] == 'debit' ? opening : -opening);
  }
  for (final row in rows('input_move')) {
    final debit = number(row, 'dain'),
        credit = number(row, 'madin'),
        code = currency(row);
    post(row['per_id'], code, debit);
    post(row['per_id'], code, -credit);
    if (row['bill_type'] != 1) {
      sourceInvoices['sp_ent_${row["id"]}'] = {
        'currency': code,
        'amount':
            (BackupDecimal.from(debit) + BackupDecimal.from(credit)).toString()
      };
    }
  }
  for (final row in rows('products')) {
    sourceStock[
            jsonEncode(['sp_inv_${row["id"]}', 'sp_wh_${row["store_id"]}'])] =
        BackupDecimal.from(number(row, 'quantity')).toString();
  }
  final workspace = rows('workspaces').single;
  if (workspace['whatsapp_instant_enabled'] != null &&
      !{0, 1}.contains(workspace['whatsapp_instant_enabled'])) {
    fail('إعداد منشأة غير صالح.');
  }
  return jsonEncode({
    'stockTransfers': transfers,
    'stockTransferLines': transferLines,
    'cashboxes': cashboxes,
    'format': 'nasqo-unified-sqlite-export-v2',
    'legacySourceTotals': {
      'accountCurrencyBalances':
          balances.map((k, v) => MapEntry(k, v.toString())),
      'invoiceAmounts': sourceInvoices,
      'stockByItemAndWarehouse': sourceStock
    },
    'version': 2,
    'workspace': {
      'companyName': field(workspace, 'company_name'),
      'legacyId': workspace['id'],
      'whatsappProvider': workspace['whatsapp_provider'],
      'whatsappPhone': workspace['whatsapp_phone'],
      'whatsappInstantEnabled': workspace['whatsapp_instant_enabled'] == 1
    },
    'currencies': currencies,
    'accountGroups': groups,
    'accounts': accounts,
    'warehouses': warehouses,
    'inventory': inventory,
    'ledger': ledger
  });
}
