import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/invoice_actions.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/services/posting_receipt.dart';
import 'package:nasqo_pro_erp/services/account_amounts.dart';
import 'package:nasqo_pro_erp/services/cash_statement.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  testWidgets('invoice calendar day remains a single LTR run in Arabic',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Directionality(
                textDirection: TextDirection.rtl,
                child: InvoiceDateField(
                    value: DateTime(2026, 1, 9), onChanged: (_) {})))));
    expect(tester.widget<Text>(find.text('2026-01-09')).textDirection,
        TextDirection.ltr);
  });
  test(
      'sale, purchase and voucher receipts survive SQLite reopen and reject changed retries',
      () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-seven-synthetic-');
    final factory = createDatabaseFactoryFfi(ffiInit: () {
      sqfliteFfiInit();
      if (Platform.isLinux) {
        open.overrideFor(OperatingSystem.linux,
            () => DynamicLibrary.open('libsqlite3.so.0'));
      }
    });
    final store = LocalDatabase.withFactory(factory, '${dir.path}/audit.db');
    var c = ErpController(autoInitDb: false, localDatabase: store);
    addTearDown(() async {
      c.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });
    c.accounts
      ..clear()
      ..addAll(const [
        AccountRecord(
            id: 'a', name: 'مبيعات الاختبار', category: AccountCategory.sales),
        AccountRecord(
            id: 's', name: 'مورد تجريبي', category: AccountCategory.purchases),
        AccountRecord(
            id: 'b',
            name: 'صندوق الاختبار',
            category: AccountCategory.transfers,
            isCashAccount: true),
        AccountRecord(
            id: 'u',
            name: 'صندوق الدولار',
            category: AccountCategory.transfers,
            isCashAccount: true,
            currency: CurrencyCode.usd),
      ]);
    c.warehouses
      ..clear()
      ..add(const WarehouseRecord(id: 'w', name: 'مستودع اختباري'));
    c.inventory
      ..clear()
      ..add(const InventoryItemRecord(
          id: 'i',
          name: 'صنف اختباري',
          unit: 'حبة',
          warehouseId: 'w',
          quantity: 10,
          avgCost: 2));
    c.ledger.clear();
    c.saleLines.clear();
    await c.initDatabase();
    final date = DateTime(2026, 11, 21),
        rows = [
          InvoiceItemRow(
              id: 'tmp',
              itemId: 'i',
              productName: 'صنف اختباري',
              quantity: 2,
              unitPrice: 4)
        ];
    final saleKey = PostingReceipt.newRequest(),
        purchaseKey = PostingReceipt.newRequest(),
        voucherKey = PostingReceipt.newRequest();
    String? saleId;
    Future<void> sale({bool tax = false}) => c.submitSalesInvoice(
        requestId: saleKey,
        accountId: 'a',
        customerName: 'مبيعات الاختبار',
        warehouse: c.warehouses.single,
        payment: PaymentMethod.cash,
        cashboxAccountId: 'b',
        includeVat: tax,
        rows: rows,
        invoiceDate: date,
        onCommitted: (id) => saleId = id);
    Future<int> purchase() => c.postPurchaseInvoice(
        requestId: purchaseKey,
        accountId: 's',
        warehouseId: 'w',
        payment: PaymentMethod.credit,
        rows: rows,
        invoiceDate: date);
    Future<int> voucher(
            {String box = 'b', double amount = 3.25, String? key}) =>
        c.postLocalEntry(
            requestId: key ?? voucherKey,
            accountId: 'a',
            kind: LedgerKind.voucher,
            direction: EntryDirection.credit,
            payment: PaymentMethod.cash,
            currency: CurrencyCode.sar,
            cashboxAccountId: box,
            amount: amount);
    await sale();
    final original = saleId;
    final purchaseNumber = await purchase(), voucherNumber = await voucher();
    expect(c.inventory.single.quantity, 10);
    expect(c.saleLines.length, 2);
    final postings =
        c.ledger.where((e) => e.entryNumber == voucherNumber).toList();
    expect(postings.length, 2);
    expect(postings.singleWhere((e) => e.accountId == 'a').direction,
        EntryDirection.credit);
    expect(postings.singleWhere((e) => e.accountId == 'b').direction,
        EntryDirection.debit);
    final before = {
      for (final e in c.ledger)
        e.id: [e.entryNumber, e.amount, e.direction.name, e.currency.name]
    };
    final cost = c.inventory.single.avgCost;
    c.dispose();
    await store.close();
    c = ErpController(autoInitDb: false, localDatabase: store);
    await c.initDatabase();
    await sale();
    expect(saleId, original);
    expect(await purchase(), purchaseNumber);
    expect(await voucher(), voucherNumber);
    await expectLater(sale(tax: true), throwsA(isA<SaleValidationException>()));
    await expectLater(
        voucher(amount: 4), throwsA(isA<SaleValidationException>()));
    await expectLater(voucher(box: 'u', key: 'different-token'),
        throwsA(isA<SaleValidationException>()));
    expect({
      for (final e in c.ledger)
        e.id: [e.entryNumber, e.amount, e.direction.name, e.currency.name]
    }, before);
    expect(c.inventory.single.quantity, 10);
    expect(c.inventory.single.avgCost, cost);
    expect(c.saleLines.length, 2);
    final cash = c.accounts.singleWhere((a)=>a.id=='b');
    final stmt = CashStatement.read(c,cash,currency:'ريال',period:'الكل',previous:true);
    expect(stmt.issue,isNull);
    expect(stmt.totals[CurrencyCode.sar]!.debit,11.25);
    expect(stmt.totals[CurrencyCode.sar]!.credit,0);
    expect(stmt.rows.first.running,-11.25);
    expect(accountAmountsByCurrency(c,[cash])[('b',CurrencyCode.sar)]!.debit,11.25);
    final customer=c.accounts.singleWhere((a)=>a.id=='a');
    expect(CashStatement.read(c,customer,currency:'ريال',period:'الكل',previous:true).totals[CurrencyCode.sar]!.closing,3.25);
    final db = await store.database;
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok');
  });
}
