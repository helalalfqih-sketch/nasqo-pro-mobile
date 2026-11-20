import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sale_facts.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

void _sqlite() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

class _GatedStore extends LocalDatabase {
  _GatedStore(String path)
      : super.withFactory(createDatabaseFactoryFfi(ffiInit: _sqlite), path);
  Completer<void>? gate;
  final entered = Completer<void>();
  bool failStartup = false;

  @override
  Future<bool> hasSeededData() async {
    if (failStartup) throw StateError('synthetic startup failure');
    return super.hasSeededData();
  }

  @override
  Future<void> saveSnapshot({
    required List<AccountRecord> accounts,
    required List<LedgerEntryRecord> ledger,
    required List<WarehouseRecord> warehouses,
    required List<InventoryItemRecord> inventory,
    required List<SavedSaleLine> saleLines,
    required String companyName,
    required bool isDarkMode,
    required int nextEntryNumber,
    SaleFacts? appendedSaleFacts,
  }) async {
    final waiting = gate;
    if (waiting != null && !entered.isCompleted) {
      entered.complete();
      await waiting.future;
    }
    await super.saveSnapshot(
      accounts: accounts,
      ledger: ledger,
      warehouses: warehouses,
      inventory: inventory,
      saleLines: saleLines,
      companyName: companyName,
      isDarkMode: isDarkMode,
      nextEntryNumber: nextEntryNumber,
      appendedSaleFacts: appendedSaleFacts,
    );
  }
}

Future<void> _sale(ErpController controller) {
  final item = controller.inventory.first;
  return controller.submitSalesInvoice(
    accountId: controller.accounts.first.id,
    customerName: 'Synthetic',
    warehouse:
        controller.warehouses.firstWhere((w) => w.id == item.warehouseId),
    payment: PaymentMethod.cash,
    includeVat: false,
    rows: [
      InvoiceItemRow(
        id: 'synthetic-row',
        itemId: item.id,
        productName: item.name,
        quantity: 1,
        unitPrice: 10,
      )
    ],
  );
}

void main() {
  test(
      'pending SQLite commit blocks another writer and changes neither stock nor ledger yet',
      () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-commit-gate-');
    final store = _GatedStore(p.join(dir.path, 'synthetic.db'));
    final c = ErpController(autoInitDb: false, localDatabase: store);
    addTearDown(() async {
      c.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });
    await c.initDatabase();
    expect(c.dbReady, isTrue);
    final before = await store.loadSnapshot();
    final inventoryBefore = c.inventory.first.quantity;
    store.gate = Completer<void>();
    final pending = _sale(c);
    await store.entered.future;
    try {
      expect(c.ledger, hasLength(before.ledger.length));
      expect(c.saleLines, isEmpty);
      expect(c.inventory.first.quantity, inventoryBefore);
      await expectLater(_sale(c), throwsA(isA<SaleValidationException>()));
      expect(() => c.addCustomer(name: 'Concurrent synthetic'),
          throwsA(isA<SaleValidationException>()));
      expect(
          (await store.loadSnapshot()).nextEntryNumber, before.nextEntryNumber);
    } finally {
      store.gate!.complete();
    }
    await pending;
    final after = await store.loadSnapshot();
    expect(after.nextEntryNumber, before.nextEntryNumber! + 1);
    expect(after.ledger, hasLength(before.ledger.length + 1));
    expect(after.saleLines, hasLength(1));
    expect(c.ledger, hasLength(after.ledger.length));
    expect(c.inventory.first.quantity, inventoryBefore - 1);
  });

  test('older queued snapshot cannot overwrite a later committed sale',
      () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-write-order-');
    final store = _GatedStore(p.join(dir.path, 'synthetic.db'));
    final c = ErpController(autoInitDb: false, localDatabase: store);
    addTearDown(() async {
      c.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });
    await c.initDatabase();
    final before = await store.loadSnapshot();
    store.gate = Completer<void>();
    c.toggleTheme();
    await store.entered.future;
    final pending = _sale(c);
    try {
      expect(c.ledger, hasLength(before.ledger.length));
      expect(
          (await store.loadSnapshot()).nextEntryNumber, before.nextEntryNumber);
    } finally {
      store.gate!.complete();
    }
    await pending;
    final after = await store.loadSnapshot();
    expect(after.isDarkMode, isTrue);
    expect(after.nextEntryNumber, before.nextEntryNumber! + 1);
    expect(after.saleLines, hasLength(1));
    expect(after.ledger, hasLength(before.ledger.length + 1));
  });

  test(
      'failed startup cannot post or initialize a synthetic sale behind the user',
      () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-startup-failure-');
    final path = p.join(dir.path, 'synthetic.db');
    final store = _GatedStore(path)..failStartup = true;
    final c = ErpController(autoInitDb: false, localDatabase: store);
    addTearDown(() async {
      c.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });
    final initialCount = c.ledger.length;
    final initialQty = c.inventory.first.quantity;
    await expectLater(_sale(c), throwsA(isA<SaleValidationException>()));
    expect(c.dbReady, isFalse);
    expect(c.ledger, hasLength(initialCount));
    expect(c.inventory.first.quantity, initialQty);
    expect(await File(path).exists(), isFalse);
  });
}
