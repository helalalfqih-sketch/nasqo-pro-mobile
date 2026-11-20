import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('stock, vouchers and exchanges survive closing and reopening SQLite', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('offline-posting');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/local.db';
    final store = LocalDatabase.withFactory(databaseFactoryFfi, path);
    final first = ErpController(autoInitDb: false, localDatabase: store);
    await first.initDatabase();
    final account = first.accounts.first;
    final item = first.inventory.first;
    final qty = item.quantity;
    await first.receiveStock(existingId: item.id, quantity: 2);
    final voucher = await first.postLocalEntry(accountId: account.id, kind: LedgerKind.voucher,
      direction: EntryDirection.debit, payment: PaymentMethod.balance,
      amount: 25, currency: account.currency);
    final exchange = await first.postLocalEntry(accountId: account.id, kind: LedgerKind.currency,
      direction: EntryDirection.credit, payment: PaymentMethod.cash, fromCurrency: CurrencyCode.usd,
      currency: CurrencyCode.sar, amount: 5, exchangeRate: 3.75);
    expect(exchange, voucher + 1);
    first.dispose();
    await store.close();

    final reopened = LocalDatabase.withFactory(databaseFactoryFfi, path);
    final second = ErpController(autoInitDb: false, localDatabase: reopened);
    addTearDown(() async { second.dispose(); await reopened.close(); });
    await second.initDatabase();
    expect(second.inventory.singleWhere((i) => i.id == item.id).quantity, qty + 2);
    expect(second.ledger.singleWhere((e) => e.entryNumber == voucher).amount, 25);
    expect(second.ledger.singleWhere((e) => e.entryNumber == exchange).amount, 18.75);
    expect(second.ledger.singleWhere((e) => e.entryNumber == exchange).currency, CurrencyCode.sar);
  });
}
