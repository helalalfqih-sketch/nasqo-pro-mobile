import 'package:nasqo_pro_erp/services/posting_receipt.dart';
import 'dart:async';
import 'dart:convert';
import 'package:nasqo_pro_erp/models/sales_return_draft.dart';
import 'package:nasqo_pro_erp/screens/home_account_views.dart';
import 'package:nasqo_pro_erp/services/accounting_engine.dart';
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
    BridgeResult? bridgeResult,
    String? restoredWebExport,
    Map<String, Object?>? erpData,
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
      bridgeResult: bridgeResult,
      restoredWebExport: restoredWebExport,
      erpData: erpData,
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
  for (final payment in [PaymentMethod.cash, PaymentMethod.credit]) {
    test('partial ${payment.name} returns reverse the account, stock and tax once and reject surplus', () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-return-');
    final store = _GatedStore(p.join(dir.path, 'return.db'));
    final c = ErpController(autoInitDb: false, localDatabase: store);
    addTearDown(() async { c.dispose(); await store.close(); await dir.delete(recursive:true); });
    await c.initDatabase();
    final item = c.inventory.first;
    final customer = c.accounts.firstWhere((a) => a.category == AccountCategory.clients);
    final box = c.accounts.firstWhere((a) => a.isCashAccount);
    final cash = payment == PaymentMethod.cash;
    final account = cash ? box : customer;
    final other = cash ? customer : box;
    double balance(AccountRecord a) => LocalAccountStatement(a, c.ledger, a.currency).closing;
    final before = balance(account), otherBefore = balance(other);
    final originalIncome = AccountingEngine.computeIncomeStatement(c.accounts, c.ledger);
    await c.submitSalesInvoice(accountId:customer.id, customerName:customer.name,
      cashboxAccountId:cash ? box.id : null,
      warehouse:c.warehouses.firstWhere((w) => w.id == item.warehouseId),
      payment:payment, includeVat:true,
      rows:[InvoiceItemRow(id:'row',itemId:item.id,productName:item.name,quantity:2,unitPrice:10)]);
    expect(balance(account), before + 23);
    final source = c.saleLines.single;
    Future<SalesReturnDraft> draft(double qty) => c.saveSalesReturnDraft(
        sourceEntryId:source.entryId,date:'2026-11-20',reason:'اختبار',
        selections:[SalesReturnSelection(position:source.position,quantity:qty)]);
    final one = await draft(1);
    final surplus = await draft(2);
    final number = await c.postSalesReturn(one.id,one.revision);
    final entry = c.ledger.singleWhere((e) => e.entryNumber == number && e.kind == LedgerKind.returnEntry);
    expect(entry.amount,11.5);
    expect(entry.payment, payment);
    expect(entry.accountId, customer.id);
    expect(c.ledger.where((e) => e.entryNumber == number && e.kind == LedgerKind.voucher), hasLength(cash ? 2 : 0));
    expect(balance(account), before + 11.5);
    expect(balance(other), otherBefore);
    expect(entry.direction,EntryDirection.credit);
    await expectLater(c.postSalesReturn(one.id,one.revision),throwsStateError);
    await expectLater(c.postSalesReturn(surplus.id,surplus.revision),throwsStateError);
    await store.close();
    final snap = await store.loadSnapshot();
    expect(snap.inventory.singleWhere((i) => i.id == item.id).quantity,item.quantity-1);
    expect(snap.ledger.where((e) => e.id == entry.id),hasLength(1));
    final register = await store.loadSaleTaxRegister();
    final reversal = register.rows.singleWhere((r) => r.entryId == entry.id);
    expect(reversal.taxAmount, -1.5);
    expect(reversal.finalTotal, -11.5);
    final sql = await store.database;
    final tax = await sql.query('erp_state',where:'stateKey = ?',whereArgs:['return_detail/${entry.id}']);
    expect(jsonDecode(tax.single['payloadJson'] as String)['tax'],1.5);
    final remaining = await draft(1);
    final failWhen = cash ? "NEW.id LIKE '%/settlement'" : "NEW.kind = 'returnEntry'";
    await sql.execute("CREATE TRIGGER reject_return BEFORE INSERT ON ledger_entries "
        "WHEN $failWhen BEGIN SELECT RAISE(ABORT,'synthetic'); END");
    await expectLater(c.postSalesReturn(remaining.id, remaining.revision),throwsA(anything));
    final rolledBack = await store.loadSnapshot();
    expect(rolledBack.inventory.singleWhere((i) => i.id == item.id).quantity,item.quantity-1);
    expect(LocalAccountStatement(account, rolledBack.ledger, account.currency).closing, before + 11.5);
    expect(LocalAccountStatement(other, rolledBack.ledger, other.currency).closing, otherBefore);
    expect(await store.getSalesReturnDraft(remaining.id),isNotNull);
    await sql.execute('DROP TRIGGER reject_return');
    await c.postSalesReturn(remaining.id, remaining.revision);
    expect(c.inventory.singleWhere((i) => i.id == item.id).quantity,item.quantity);
    expect(balance(account), before);
    expect(balance(other), otherBefore);
    final finalIncome = AccountingEngine.computeIncomeStatement(c.accounts, c.ledger);
    expect(finalIncome.netSales, originalIncome.netSales);
    expect(finalIncome.totalOperatingExpenses, originalIncome.totalOperatingExpenses);
    final settled = await store.loadSaleTaxRegister();
    expect(settled.rows.where((r) => r.documentNumber == entry.documentNumber)
        .fold<double>(0,(sum,row) => sum + row.finalTotal),0);

    });
  }

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
