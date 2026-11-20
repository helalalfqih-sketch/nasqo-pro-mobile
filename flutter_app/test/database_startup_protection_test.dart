import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

Future<Map<String, Object?>> snapshot(Database db) async {
  final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
  return {
    for (final row in tables)
      row['name'] as String: await db.query(row['name'] as String)
  };
}

void main() {
  late Directory dir;
  late LocalDatabase store;
  late Database db;
  late ErpController controller;
  setUp(() async {
    dir =
        await Directory.systemTemp.createTemp('startup-protection-synthetic-');
    store = LocalDatabase.withFactory(
        createDatabaseFactoryFfi(ffiInit: _ffi), '${dir.path}/test.db');
    db = await store.database;
    controller = ErpController(autoInitDb: false, localDatabase: store);
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  for (final kind in ['ledger', 'inventory', 'settings', 'draft']) {
    test('empty accounts with existing $kind must not seed or overwrite',
        () async {
      if (kind == 'ledger') {
        await db.insert('ledger_entries', {
          'id': 'existing-ledger',
          'accountId': 'missing-old-account',
          'accountName': 'synthetic',
          'kind': 'voucher',
          'typeLabel': 'سند',
          'payment': 'credit',
          'direction': 'debit',
          'amount': 12.34,
          'currency': 'usd',
          'exchangeRate': 1,
          'details': 'must survive',
          'documentNumber': 'existing',
          'warehouseId': 'w',
          'warehouseName': 'synthetic',
          'expenseCategory': '',
          'entryNumber': 551,
          'deleted': 0,
          'entryDate': '2026-01-01'
        });
      } else if (kind == 'inventory') {
        await db.insert('inventory_items', {
          'id': 'existing-item',
          'name': 'synthetic',
          'unit': 'حبة',
          'quantity': 7.125,
          'avgCost': 2.5,
          'warehouseId': 'missing-old-wh',
          'minThreshold': 1,
          'sku': 'existing'
        });
      } else if (kind == 'settings') {
        await db.insert('erp_state', {
          'stateKey': 'settings',
          'payloadJson':
              '{"companyName":"existing-synthetic","isDarkMode":true,"nextEntryNumber":9988}',
          'updatedAt': 'existing-marker'
        });
      } else {
        await db.insert('nonposting_documents', {
          'type': 'quote',
          'revision': 1,
          'date': '2026-01-01',
          'currency': 'usd',
          'customerName': 'existing-synthetic',
          'accountId': 'a',
          'notes': 'must survive'
        });
      }
      final before = await snapshot(db);
      await controller.initDatabase();
      expect(await snapshot(db), equals(before),
          reason: 'startup cannot seed because accounts is empty');
      expect(controller.accounts, isEmpty,
          reason: 'demo accounts must not masquerade as existing data');
      await controller.initDatabase();
      expect(await snapshot(db), equals(before));
    });
  }
  test('malformed settings fails closed without overwriting existing rows',
      () async {
    await db.insert('erp_state', {
      'stateKey': 'settings',
      'payloadJson': '{not-json',
      'updatedAt': 'must-survive'
    });
    final before = await snapshot(db);
    await controller.initDatabase();
    expect(controller.dbReady, false);
    expect(await snapshot(db), equals(before));
    await controller.initDatabase();
    expect(await snapshot(db), equals(before));
  });
  test('database read failure cannot trigger destructive fallback or reseed',
      () async {
    await db.insert('erp_state', {
      'stateKey': 'sentinel',
      'payloadJson': '{}',
      'updatedAt': 'must-survive'
    });
    // Deliberately broken synthetic schema, never a real user database.
    await db.execute('ALTER TABLE accounts RENAME TO accounts_unavailable');
    final before = await snapshot(db);
    await controller.initDatabase();
    expect(controller.dbReady, false);
    expect(await snapshot(db), equals(before));
  });
  test('v6 to v9 additive migration preserves existing rows exactly', () async {
    await store.saveSnapshot(
        accounts: [
          const AccountRecord(
              id: 'existing-account',
              name: 'synthetic',
              category: AccountCategory.clients,
              openingBalance: 123.456)
        ],
        ledger: [],
        warehouses: [],
        inventory: [],
        saleLines: [],
        companyName: 'existing-synthetic',
        isDarkMode: true,
        nextEntryNumber: 33221);
    for (final table in [
      'cash_transfer_drafts',
      'simple_journal_drafts',
      'fx_drafts'
    ]) {
      await db.execute('DROP TABLE $table');
    }
    await db.setVersion(6);
    final before = await snapshot(db);
    await store.close();
    await controller.initDatabase();
    final upgraded = await store.database;
    expect(await upgraded.getVersion(), 9);
    final after = await snapshot(upgraded);
    for (final entry in before.entries) {
      expect(after[entry.key], equals(entry.value), reason: entry.key);
    }
    expect(controller.dbReady, true);
    expect(controller.accounts.single.id, 'existing-account');
    expect(controller.accounts.single.openingBalance, 123.456);
    for (final table in [
      'cash_transfer_drafts',
      'simple_journal_drafts',
      'fx_drafts'
    ]) {
      expect(after[table], isEmpty);
    }
  });
}
