import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/hybrid/home_presentation.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('bridge accepts only local view events and existing destinations', () {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    c.accounts
      ..clear()
      ..add(const AccountRecord(
          id: 'qa', name: 'مثال', category: AccountCategory.clients));
    c.ledger.clear();
    final home = HomePresentation(c);
    c.primaryTint = 0xff047857;
    c.secondaryTint = 0xff0f766e;
    c.homeRadius = 9;
    expect(home.snapshot(false)['appearance'],
        {'primary': '#047857', 'secondary': '#0f766e', 'radius': 9.0});
    final row = (home.snapshot(false)['rows'] as List).single;
    expect(row['name'], 'العملاء');
    expect(home.categoryFor(row['id']), AccountCategory.clients);
    final open = jsonEncode({'action': 'group', 'id': row['id']});
    expect(home.parse(open)?['action'], 'group');
    for (final bad in [
      '[]',
      '{',
      '{"action":"ready","extra":1}',
      '{"action":"sql"}',
      '{"action":"tile","id":"https://erp.indexesstore.com/"}',
      '{"action":"group","id":9999}',
      '{"action":"layout","value":{"order":["settings"]}}',
      '{"action":"scroll","y":-5}',
      '{"action":"currency","id":-3,"currency":"?"}',
      '{"action":"post","amount":5}',
      jsonEncode({'action': 'ready', 'padding': 'x' * 4096})
    ]) {
      expect(home.parse(bad), isNull,
          reason: bad.substring(0, bad.length.clamp(0, 80)));
    }
    expect(home.parse('{"action":"tile","id":"new-invoice"}')?['id'],
        'new-invoice');
  });
  test(
      'restored balances and UI preferences survive cold SQLite reopen without business writes',
      () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('nasqo-home-test-');
    addTearDown(() => dir.delete(recursive: true));
    final source =
        File('../qa/groups_lab/assets/fixture.json').readAsStringSync();
    final doc = jsonDecode(source) as Map<String, dynamic>;
    final accounts = [
      for (final a in doc['accounts'])
        AccountRecord(
            id: a['id'],
            name: a['name'],
            category: AccountCategory.values.byName(a['category']),
            openingBalance: (a['openingBalance'] as num).toDouble(),
            openingDirection:
                EntryDirection.values.byName(a['openingDirection']),
            currency: CurrencyCode.values
                .singleWhere((c) => c.label == a['currency']))
    ];
    final path = '${dir.path}/test.db';
    final first = LocalDatabase.withFactory(databaseFactoryFfi, path);
    await first.saveSnapshot(
        accounts: accounts,
        ledger: [],
        warehouses: [],
        inventory: [],
        saleLines: [],
        companyName: 'مختبر المطابقة',
        isDarkMode: false,
        nextEntryNumber: 1,
        restoredWebExport: source);
    await first.close();
    List<Object?>? baseline;
    for (final boot in [0, 1]) {
      final db = LocalDatabase.withFactory(databaseFactoryFfi, path);
      final controller = ErpController(autoInitDb: false, localDatabase: db);
      try {
        await controller.initDatabase();
        final view = HomePresentation(controller);
        await view.load();
        final conn = await db.database;
        Future<List<Object?>> books() async {
          final names = await conn.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
          return [
            for (final e in names)
              await conn.query(e['name'] as String,
                  orderBy: 'rowid',
                  where: e['name'] == 'erp_state' ? 'stateKey <> ?' : null,
                  whereArgs: e['name'] == 'erp_state'
                      ? [HomePresentation.preferenceKey]
                      : null)
          ];
        }

        final before = await books();
        if (boot == 0) {
          baseline = before;
          final snapshot = view.snapshot(false);
          final rows = snapshot['rows'] as List;
          expect(rows.first['netDebitMinusCredit'], -1250.5);
          expect(rows.last['netDebitMinusCredit'], 80);
          if (const bool.fromEnvironment('HYBRID_CAPTURE')) {
            File('../qa/hybrid_home/fixture_snapshot.json').writeAsStringSync(
                '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n');
          }
          final ids =
              homeDestinations.keys.where((s) => s != 'qr-scanner').toList();
          final layout = {
            'order': ids.reversed.toList(),
            'pinned': ['new-voucher'],
            'hidden': ['trash'],
            'toneOverrides': {'accounts': 'amber'}
          };
          for (final m in [
            {'action': 'layout', 'value': layout},
            {'action': 'scroll', 'y': 253},
            {'action': 'currency', 'id': 41, 'currency': 'الكل'}
          ]) {
            await view.savePreference(view.parse(jsonEncode(m))!);
          }
        } else {
          expect(before, baseline);
          expect(view.scroll, 253);
          expect(view.layout?['pinned'], ['new-voucher']);
          final rows = view.snapshot(true)['rows'] as List;
          expect(rows.first['netDebitMinusCredit'], isNull);
          expect(
              rows.first['amounts'],
              containsAll([
                {'currency': 'ريال', 'value': -1250.5},
                {'currency': 'دولار', 'value': 25.0}
              ]));
          expect(rows.last['currency'], 'ريال');
        }
        expect(await conn.rawQuery('PRAGMA integrity_check'), [
          {'integrity_check': 'ok'}
        ]);
        expect(await conn.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(await books(), baseline);
      } finally {
        controller.dispose();
        await db.close();
      }
    }
  });
}
