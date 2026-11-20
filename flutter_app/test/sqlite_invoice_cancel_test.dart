import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/screens/invoice_form_sheet.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

const _tables = [
  'accounts',
  'ledger_entries',
  'warehouses',
  'inventory_items',
  'sale_lines',
  'erp_state'
];

void _sqliteForHost() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    // The runtime library has a stable SONAME even without libsqlite3-dev.
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

Future<Map<String, Object?>> _readAll(Database db) async => {
      for (final table in _tables)
        table: await db.query(table,
            orderBy: table == 'erp_state'
                ? 'stateKey'
                : (table == 'sale_lines' ? 'entryId, position' : 'id')),
    };

Future<int> _nextNumber(Database db) async {
  final settings = (await db
          .query('erp_state', where: 'stateKey = ?', whereArgs: ['settings']))
      .single;
  return (jsonDecode(settings['payloadJson']! as String)
      as Map<String, dynamic>)['nextEntryNumber'] as int;
}

void main() {
  test('SQLite v1 migrates additively without inventing legacy sale lines',
      () async {
    final directory = await Directory.systemTemp.createTemp('nasqo-sqlite-v1-');
    final path = p.join(directory.path, 'legacy-synthetic.db');
    final factory = createDatabaseFactoryFfi(ffiInit: _sqliteForHost);
    final store = LocalDatabase.withFactory(factory, path);
    final controller = ErpController(autoInitDb: false, localDatabase: store);
    addTearDown(() async {
      controller.dispose();
      await store.close();
      await directory.delete(recursive: true);
    });
    await controller.initDatabase();
    final db = await store.database;
    final before = await _readAll(db);
    final number = await _nextNumber(db);
    // Recreate the v1 schema by removing only the later additive tables.
    // The database is synthetic and unique to this test.
    await db.execute('DROP TABLE fx_drafts');
    await db.execute('DROP TABLE simple_journal_drafts');
    await db.execute('DROP TABLE cash_transfer_drafts');
    await db.execute('DROP TABLE voucher_drafts');
    await db.execute('DROP TABLE sale_line_cost_facts');
    await db.execute('DROP TABLE sale_facts');
    await db.execute('DROP TABLE sales_return_draft_lines');
    await db.execute('DROP TABLE sales_return_drafts');
    await db.execute('DROP TABLE nonposting_lines');
    await db.execute('DROP TABLE nonposting_documents');
    await db.execute('DROP TABLE sale_lines');
    await db.setVersion(1);
    await store.close();
    final upgraded = await store.database;
    expect(await upgraded.getVersion(), 9);
    expect(await _readAll(upgraded), before);
    expect(await _nextNumber(upgraded), number);
    expect((await store.loadSnapshot()).saleLines, isEmpty);
  });

  testWidgets('draft cancel and platform back perform zero SQLite writes',
      (tester) async {
    final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('nasqo-sqlite-test-')))!;
    final path = p.join(directory.path, 'synthetic.db');
    final factory = createDatabaseFactoryFfi(ffiInit: _sqliteForHost);
    final store = LocalDatabase.withFactory(factory, path);
    final controller = ErpController(autoInitDb: false, localDatabase: store);
    addTearDown(() async {
      controller.dispose();
      await store.close();
      await directory.delete(recursive: true);
    });

    // Surface driver or schema errors instead of relying on the controller's
    // production fallback, which deliberately keeps the UI running.
    final db = (await tester.runAsync(() => store.database))!;
    await tester.runAsync(controller.initDatabase);
    expect(controller.dbReady, isTrue);
    final before = (await tester.runAsync(() => _readAll(db)))!;
    final documentNumber = (await tester.runAsync(() => _nextNumber(db)))!;
    final item = controller.inventory.first;
    final changes = (await tester
            .runAsync(() => db.rawQuery('SELECT total_changes() AS changes')))!
        .single;
    expect(before['ledger_entries'], isNotEmpty);
    expect(before['inventory_items'], isNotEmpty);

    await tester.pumpWidget(NasqoProErpApp(controller: controller));
    await tester.pumpAndSettle();
    Future<void> openInvoice() async {
      final action = find.byKey(const ValueKey('home-invoice-new'));
      await tester.scrollUntilVisible(action, 200,
          scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(action);
    }

    for (final systemBack in [false, true]) {
      await openInvoice();
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceFormSheet), findsOneWidget);
      final price = find.widgetWithText(TextFormField, 'السعر');
      await tester.ensureVisible(price);
      await tester.enterText(price, '123.45');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        final cancel = find.byKey(const Key('invoice-cancel'));
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
      }
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceFormSheet), findsNothing);
    }
    await tester.runAsync(() async {
      expect(await _readAll(db), equals(before));
      expect((await db.rawQuery('SELECT total_changes() AS changes')).single,
          equals(changes));
      await store.close();
      expect(await _readAll(await store.database), equals(before));
    });

    // Overselling through the UI keeps the draft open and changes no table.
    await openInvoice();
    await tester.pumpAndSettle();
    final quantity = find.widgetWithText(TextFormField, 'الكمية');
    await tester.ensureVisible(quantity);
    await tester.enterText(quantity, '٩٩٩٩٩');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final rejectedSave = find.byKey(const Key('invoice-save'));
    await tester.ensureVisible(rejectedSave);
    await tester.tap(rejectedSave);
    await tester.pumpAndSettle();
    expect(find.byType(InvoiceFormSheet), findsOneWidget);
    expect(find.textContaining('الكمية غير كافية'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(await _readAll(await store.database), equals(before));
    });

    // Positive control: the same route writes once when explicitly saved.
    await openInvoice();
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('invoice-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    final beforeCount = (before['ledger_entries']! as List).length;
    for (var attempt = 0; attempt < 125; attempt++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (controller.ledger.length > beforeCount) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(controller.ledger, hasLength(beforeCount + 1));
    await tester.pumpAndSettle();
    expect(find.byType(InvoiceFormSheet), findsNothing);
    await tester.runAsync(() async {
      final persisted = await store.database;
      expect(await _nextNumber(persisted), documentNumber + 1);
      final rows = await _readAll(persisted);
      expect(rows['accounts'], equals(before['accounts']));
      expect(rows['warehouses'], equals(before['warehouses']));
      expect(rows['ledger_entries'],
          hasLength((before['ledger_entries']! as List).length + 1));
      final savedItem = (await persisted
              .query('inventory_items', where: 'id = ?', whereArgs: [item.id]))
          .single;
      expect(savedItem['quantity'], item.quantity - 1);
      final saved = (await persisted.query('sale_lines')).single;
      expect(saved['itemId'], item.id);
      expect(saved['quantity'], 1);
      expect(
          await persisted.query('ledger_entries',
              where: 'id = ?', whereArgs: [saved['entryId']]),
          hasLength(1));
      await store.close();
      expect((await store.loadSnapshot()).saleLines.single.itemId, item.id);
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
