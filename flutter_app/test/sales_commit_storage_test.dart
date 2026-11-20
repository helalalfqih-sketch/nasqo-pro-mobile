import 'dart:convert';
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

Future<Map<String, Object?>> _disk(Database db) async => {
      for (final table in [
        'accounts',
        'ledger_entries',
        'warehouses',
        'inventory_items',
        'sale_lines',
        'sale_facts',
        'sale_line_cost_facts',
        'erp_state',
        'nonposting_documents',
        'nonposting_lines',
        'sqlite_sequence'
      ])
        table: await db.query(table,
            orderBy: switch (table) {
              'sale_lines' || 'sale_line_cost_facts' => 'entryId, position',
              'sale_facts' => 'entryId',
              'nonposting_lines' => 'documentId, position',
              'erp_state' => 'stateKey',
              'sqlite_sequence' => 'name',
              _ => 'id',
            }),
    };
Map<String, Object?> _memory(ErpController c) => {
      'inventory': c.inventory
          .map((i) => [i.id, i.quantity, i.avgCost, i.warehouseId])
          .toList(),
      'ledger': c.ledger
          .map((e) => [
                e.id,
                e.entryNumber,
                e.accountId,
                e.amount,
                e.documentNumber,
                e.deleted
              ])
          .toList(),
      'lines': c.saleLines
          .map(
              (l) => [l.entryId, l.position, l.itemId, l.quantity, l.unitPrice])
          .toList(),
    };
Future<int> _number(Database db) async {
  final settings = (await db
          .query('erp_state', where: 'stateKey = ?', whereArgs: ['settings']))
      .single;
  return (jsonDecode(settings['payloadJson'] as String)
      as Map<String, dynamic>)['nextEntryNumber'] as int;
}

void main() {
  for (final failingTable in [
    'sale_lines',
    'ledger_entries',
    'sale_line_cost_facts'
  ]) {
    test(
        'sales commit rolls back $failingTable failure, retry once survives reopen',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('nasqo-sale-commit-synthetic-');
      final path = '${dir.path}/isolated.db';
      final factory = createDatabaseFactoryFfi(ffiInit: _ffi);
      final store = LocalDatabase.withFactory(factory, path);
      final c = ErpController(autoInitDb: false, localDatabase: store);
      addTearDown(() async {
        c.dispose();
        await store.close();
        await dir.delete(recursive: true);
      });
      c.accounts
        ..clear()
        ..add(const AccountRecord(
            id: 'synthetic-client',
            name: 'عميل اختبار',
            category: AccountCategory.clients));
      c.warehouses
        ..clear()
        ..add(const WarehouseRecord(id: 'synthetic-wh', name: 'مخزن اختبار'));
      c.inventory
        ..clear()
        ..add(const InventoryItemRecord(
            id: 'synthetic-item',
            name: 'صنف اختبار',
            unit: 'حبة',
            quantity: 10,
            avgCost: 2,
            warehouseId: 'synthetic-wh'));
      c.ledger.clear();
      c.saleLines.clear();
      await c.initDatabase();
      expect(c.dbReady, true);
      final db = await store.database;
      final beforeDisk = await _disk(db);
      final beforeMemory = _memory(c);
      final beforeNumber = await _number(db);
      var notices = 0;
      c.addListener(() => notices++);
      Future<void> submit(
              {String ref = 'QA-502', String memo = 'بيان اصطناعي'}) =>
          c.submitSalesInvoice(
              documentNumber: ref,
              memo: memo,
              accountId: 'synthetic-client',
              customerName: 'عميل اختبار',
              warehouse: c.warehouses.single,
              payment: PaymentMethod.credit,
              includeVat: false,
              rows: [
                InvoiceItemRow(
                    id: 'draft-only',
                    itemId: 'synthetic-item',
                    productName: 'صنف اختبار',
                    quantity: 2,
                    unitPrice: 5)
              ]);
      await db.execute(
          "CREATE TRIGGER reject_synthetic_sale BEFORE INSERT ON $failingTable BEGIN SELECT RAISE(ABORT, 'synthetic commit failure'); END");
      await expectLater(submit(), throwsA(anything));
      expect(await _disk(db), equals(beforeDisk));
      expect(_memory(c), equals(beforeMemory));
      expect(await _number(db), beforeNumber);
      // Notifications may describe failure/busy state; no test assumes they
      // indicate committed financial data. The state assertions above do.
      await db.execute('DROP TRIGGER reject_synthetic_sale');
      await submit();
      expect(c.ledger.length, 1);
      expect(c.saleLines.length, 1);
      expect(c.inventory.single.quantity, 8);
      expect(c.ledger.single.amount, 10);
      expect(c.ledger.single.documentNumber, 'QA-502');
      expect(
          c.ledger.single.details, startsWith('بيان الفاتورة: بيان اصطناعي\n'));
      final committedForRejects = await _disk(db);
      await expectLater(
          submit(ref: 'qa-٥٠٢'), throwsA(isA<SaleValidationException>()));
      await expectLater(
          submit(ref: 'INV-900'), throwsA(isA<SaleValidationException>()));
      await expectLater(submit(ref: 'QA-503', memo: 'أ\nب'),
          throwsA(isA<SaleValidationException>()));
      expect(await _disk(db), equals(committedForRejects));
      expect(c.ledger.single.entryNumber, beforeNumber + 1);
      expect(c.saleLines.single.entryId, c.ledger.single.id);
      final facts = (await c.loadOriginalSaleFacts(c.ledger.single.id))!;
      expect(facts.preTaxTotal, 10);
      expect(facts.taxEnabled, isFalse);
      expect(facts.taxAmount, 0);
      expect(facts.finalTotal, 10);
      expect(facts.lineCosts.single.stockAverageCost, 2);
      expect(await _number(db), beforeNumber + 1);
      expect(notices, greaterThan(0));
      final committedMemory = _memory(c);
      final committedDisk = await _disk(db);
      // CSV must see committed rows rather than the controller's mutable list.
      final savedHeaders = List.of(c.ledger);
      c.ledger.clear();
      final exportHeaders = await c.loadCommittedSalesForExport();
      expect(exportHeaders.map((row) => [row.id, row.amount]),
          savedHeaders.map((row) => [row.id, row.amount]));
      expect(await _disk(db), equals(committedDisk));
      expect(c.ledger, isEmpty);
      final printSnapshot = await c.loadInvoiceForPrint(savedHeaders.single.id);
      expect(printSnapshot.entry.amount, 10);
      expect(printSnapshot.lines.single.quantity, 2);
      expect(printSnapshot.facts?.taxAmount, 0);
      expect(await _disk(db), equals(committedDisk));
      expect(c.ledger, isEmpty);
      c.ledger.addAll(savedHeaders);
      await store.close();
      final reopened = LocalDatabase.withFactory(factory, path);
      final loaded = ErpController(autoInitDb: false, localDatabase: reopened);
      try {
        await loaded.initDatabase();
        expect(loaded.dbReady, true);
        expect(_memory(loaded), equals(committedMemory));
        expect(await _disk(await reopened.database), equals(committedDisk));
      } finally {
        loaded.dispose();
        await reopened.close();
      }
    });
  }
}
