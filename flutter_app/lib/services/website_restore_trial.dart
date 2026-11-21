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
        LocalDatabase database, WebBackup backup, bool dark) =>
    database.saveSnapshot(
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
    if (jsonEncode(expectedTotals) != jsonEncode(actualTotals)) {
      throw const FormatException(
          'لم تتطابق الأرصدة أو الفواتير أو كميات المخزون.');
    }
    return {
      'financialBefore': expectedTotals,
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
