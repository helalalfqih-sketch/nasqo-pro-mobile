import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/erp_models.dart';
import 'local_database.dart';
import 'backup_decimal.dart';
import 'dart:collection';
import 'web_backup.dart';

Map<String, dynamic> websitePreferences(WebBackup backup) {
  final ws = jsonDecode(backup.original)['workspace'];
  return {
    'provider': ws['whatsappProvider'],
    'phone': ws['whatsappPhone'],
    'instant': ws['whatsappInstantEnabled']
  };
}

Future<void> writeWebsiteSnapshot(
    LocalDatabase database, WebBackup backup, bool dark) async {
  _validateWebsiteRelations(backup);
  await database.saveSnapshot(
      accounts: backup.accounts,
      ledger: backup.ledger,
      warehouses: backup.warehouses,
      inventory: backup.inventory,
      saleLines: backup.lines,
      companyName: backup.company,
      isDarkMode: dark,
      nextEntryNumber: backup.lastNumber,
      restoredWebExport: backup.original,
      erpData: {
        ...backup.modules.toJson(),
        'messagePreferences': websitePreferences(backup),
        'currencyDetails': backup.currencyDetails
      });
}

/// Compare rows by their stable logical keys, including every posted amount and
/// quantity, before producing per-document results. Avoid SQL floating sums.
Map<String, String> _rows(LocalDbSnapshot s) {
  final out = <String, String>{};
  void put(String key, List<Object?> fields) {
    if (out.containsKey(key))
      throw const FormatException('معرّف مكرر أثناء مطابقة الاستعادة.');
    out[key] = jsonEncode(fields);
  }

  for (final a in s.accounts) {
    put('a/${a.id}', [
      a.name,
      a.codeNumber,
      a.category.name,
      a.currency.name,
      a.openingDirection.name,
      a.openingBalance,
      a.creditLimit,
      a.isCashAccount,
      a.phone,
      a.note
    ]);
  }
  for (final e in s.ledger) {
    put('e/${e.id}', [
      e.accountId,
      e.accountName,
      e.kind.name,
      e.direction.name,
      e.payment.name,
      e.currency.name,
      e.amount,
      e.exchangeRate,
      e.entryNumber,
      e.entryDate,
      e.deleted,
      e.documentNumber,
      e.warehouseId,
      e.warehouseName,
      e.typeLabel,
      e.details,
      e.expenseCategory
    ]);
  }
  for (final i in s.inventory) {
    put('i/${i.id}', [
      i.warehouseId,
      i.name,
      i.sku,
      i.unit,
      i.quantity,
      i.avgCost,
      i.minThreshold
    ]);
  }
  for (final w in s.warehouses) {
    put('w/${w.id}', [w.name, w.details, w.isDefault]);
  }
  for (final l in s.saleLines) {
    put('l/${l.entryId}/${l.position}',
        [l.itemId, l.itemName, l.unit, l.quantity, l.unitPrice]);
  }
  return out;
}

Map<String, Object?> _financialReport(
    LocalDbSnapshot data, RestoredGroups groups) {
  final balances = SplayTreeMap<String, BackupDecimal>();
  final invoices = SplayTreeMap<String, Object?>(),
      quantities = SplayTreeMap<String, Object?>();
  void post(String account, String currency, num amount) {
    final key = jsonEncode([account, currency]);
    balances[key] =
        (balances[key] ?? BackupDecimal.from(0)) + BackupDecimal.from(amount);
  }

  for (final a in data.accounts) {
    post(
        a.id,
        a.currency.name,
        a.openingDirection == EntryDirection.debit
            ? a.openingBalance
            : -a.openingBalance);
  }
  for (final e in data.ledger) {
    if (e.deleted || e.kind == LedgerKind.quote || e.kind == LedgerKind.order)
      continue;
    if (e.kind == LedgerKind.invoice || e.kind == LedgerKind.returnEntry) {
      invoices[e.id] = {
        'currency': e.currency.name,
        'amount': BackupDecimal.from(e.amount).toString()
      };
    }
    final sides = groups.sides[e.id];
    if (sides?.settled == true) continue;
    post(e.accountId, e.currency.name,
        sides?.debit ?? (e.direction == EntryDirection.debit ? e.amount : 0));
    post(
        e.accountId,
        e.currency.name,
        -(sides?.credit ??
            (e.direction == EntryDirection.credit ? e.amount : 0)));
  }
  for (final i in data.inventory) {
    quantities[jsonEncode([i.id, i.warehouseId])] =
        BackupDecimal.from(i.quantity).toString();
  }
  return {
    'accountCurrencyBalances':
        balances.map((k, v) => MapEntry(k, v.toString())),
    'invoiceAmounts': invoices,
    'stockByItemAndWarehouse': quantities
  };
}

void _validateWebsiteRelations(WebBackup backup) {
  final data = jsonDecode(backup.original) as Map<String, dynamic>;
  final groups = backup.groupData.groups.map((g) => g.id).toSet();
  if (groups.length != backup.groupData.groups.length ||
      backup.groupData.membership.values.any((id) => !groups.contains(id))) {
    throw const FormatException('مجموعة حسابات مكررة أو مفقودة.');
  }
  final stores = backup.warehouses.map((i) => i.id).toSet(),
      items = backup.inventory.map((i) => i.id).toSet();
  final cash = {
    for (final a in backup.accounts)
      if (a.isCashAccount) a.id: a.currency
  };
  for (final box in data['cashboxes'] ?? []) {
    final currency = cash[box['accountId']], code = box['currencyCode'];
    if (currency == null ||
        !{currency.name, currency.name.toUpperCase(), currency.label}
            .contains(code)) {
      throw const FormatException(
          'تعذّر مطابقة الصندوق مع حساب نقدي وعملة محددة.');
    }
  }
  if ((data['priceOffers'] as List?)?.isNotEmpty == true) {
    throw const FormatException(
        'تتضمن النسخة عروض أسعار لم تُطابَق مع مستندات الهاتف.');
  }
  final transferHeaders = data['stockTransfers'] as List? ?? [];
  if (transferHeaders.map((h) => h['id']).toSet().length !=
      transferHeaders.length) {
    throw const FormatException('معرّف تحويل مخزني مكرر.');
  }
  for (final movement in backup.groupData.transfers) {
    if (!stores.contains(movement.source) ||
        !stores.contains(movement.destination) ||
        movement.source == movement.destination ||
        !items.contains(movement.item) ||
        !movement.quantity.isFinite ||
        movement.quantity <= 0 ||
        movement.unit < 1) {
      throw const FormatException(
          'تعذّر مطابقة مستودعات التحويل أو الصنف أو الكمية.');
    }
  }
  for (final entry in data['ledger'] as List) {
    final date = entry['entryDate'];
    final parsed = date is String ? DateTime.tryParse(date) : null;
    if (parsed == null ||
        parsed.toIso8601String().split('T').first != date ||
        entry['exchangeRate'] <= 0) {
      throw const FormatException('تاريخ الحركة أو سعر صرفها غير صالح.');
    }
    bool set(Object? v) => v != null && v != '' && v != 0;
    if (set(entry['warehouseId']) && !stores.contains(entry['warehouseId'])) {
      throw const FormatException('مخزن الحركة مفقود.');
    }
    for (final key in ['taxAmount', 'discount', 'bonus', 'cashboxId']) {
      if (set(entry[key]))
        throw FormatException(
            'لم تتم مطابقة الحقل المالي $key في الحركة ${entry["id"]}.');
    }
    for (final line in entry['lines'] ?? []) {
      if ((line['lineKind'] != 'free' &&
              !items.contains(line['inventoryItemId'])) ||
          (set(line['warehouseId']) && !stores.contains(line['warehouseId']))) {
        throw const FormatException(
            'بند فاتورة يشير إلى صنف أو مخزن غير معرّف.');
      }
      if (set(line['discount']) || set(line['bonus']))
        throw const FormatException(
            'تحتاج خصومات أو إضافات بنود الفاتورة إلى مطابقة.');
    }
  }
}

Future<Map<String, Object?>> testWebsiteRestore(WebBackup backup) async {
  final dir = await Directory.systemTemp.createTemp('nasqo-restore-trial-');
  final stage =
      LocalDatabase.withFactory(databaseFactory, '${dir.path}/trial.sqlite');
  try {
    await writeWebsiteSnapshot(stage, backup, false);
    await stage.close();
    final db = await stage.database;
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.length != 1 ||
        integrity.single.values.single != 'ok' ||
        (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('لم تجتز قاعدة الاختبار فحص السلامة.');
    }
    final after = await stage.loadSnapshot();
    final before = LocalDbSnapshot(
        accounts: backup.accounts,
        ledger: backup.ledger,
        inventory: backup.inventory,
        warehouses: backup.warehouses,
        saleLines: backup.lines);
    final archived = await stage.readOriginalWebExport();
    if (!mapEquals(_rows(before), _rows(after)) ||
        after.companyName != backup.company ||
        after.nextEntryNumber != backup.lastNumber ||
        jsonEncode(archived) != jsonEncode(jsonDecode(backup.original))) {
      throw const FormatException(
          'اختلفت السجلات بعد التحويل وإعادة فتح قاعدة الاختبار.');
    }
    Map<String, int> counts(LocalDbSnapshot snap) => {
          'accounts': snap.accounts.length,
          'movements': snap.ledger.length,
          'invoices':
              snap.ledger.where((e) => e.kind == LedgerKind.invoice).length,
          'invoiceLines': snap.saleLines.length,
          'warehouses': snap.warehouses.length,
          'items': snap.inventory.length
        };
    final expectedTotals = _financialReport(before, backup.groupData);
    final actualTotals =
        _financialReport(after, RestoredGroups.fromJson(archived!));
    final sourceTotals = archived['legacySourceTotals'];
    if ((sourceTotals != null &&
            jsonEncode(sourceTotals) != jsonEncode(actualTotals)) ||
        jsonEncode(expectedTotals) != jsonEncode(actualTotals)) {
      throw const FormatException(
          'لم تتطابق الأرصدة أو الفواتير أو كميات المخزون.');
    }
    return {
      'financialBefore': sourceTotals ?? expectedTotals,
      'financialAfter': actualTotals,
      'coldReopen': true,
      'before': counts(before),
      'after': counts(after),
      'matchedRecords': _rows(after).length,
      'integrity': 'ok'
    };
  } finally {
    try {
      await stage.close();
    } finally {
      await dir.delete(recursive: true);
    }
  }
}


/// Verify the actual committed phone database, not merely the scratch trial.
/// Failure must trigger the caller's preserved local-backup rollback.
Future<void> verifyCommittedWebsiteRestore(
    LocalDatabase live, WebBackup backup) async {
  final db = await live.database;
  final integrity = await db.rawQuery('PRAGMA integrity_check');
  if (integrity.length != 1 || integrity.single.values.single != 'ok' ||
      (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
    throw const FormatException('فشلت سلامة قاعدة البيانات بعد الحفظ.');
  }
  final actual = await live.loadSnapshot();
  final expected = LocalDbSnapshot(
    accounts: backup.accounts,
    ledger: backup.ledger,
    warehouses: backup.warehouses,
    inventory: backup.inventory,
    saleLines: backup.lines,
  );
  final exported = await live.readOriginalWebExport();
  if (!mapEquals(_rows(actual), _rows(expected)) ||
      actual.companyName != backup.company ||
      actual.nextEntryNumber != backup.lastNumber ||
      exported == null ||
      jsonEncode(exported) != jsonEncode(jsonDecode(backup.original))) {
    throw const FormatException('اختلاف في السجلات بعد حفظ نسخة الويب.');
  }
  final before = _financialReport(expected, backup.groupData);
  final after = _financialReport(actual, RestoredGroups.fromJson(exported));
  if (jsonEncode(before) != jsonEncode(after)) {
    throw const FormatException('اختلاف في الأرصدة أو العملات أو كميات الأصناف.');
  }
}
