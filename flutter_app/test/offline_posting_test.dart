import 'package:nasqo_pro_erp/services/account_csv.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/customer_measurement_repository.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('catalog, imported accounts, message settings and purchases survive a cold reopen', () async {
    sqfliteFfiInit(); databaseFactory=databaseFactoryFfi;
    final dir=await Directory.systemTemp.createTemp('nasqo-account-import');
    final store=LocalDatabase.withFactory(databaseFactoryFfi,'${dir.path}/data.db');
    final c=ErpController(autoInitDb:false,localDatabase:store);
    addTearDown(() async {c.dispose();await store.close();await dir.delete(recursive:true);});
    await c.initDatabase();
    final input=readAccountCsv('\uFEFFالاسم,الهاتف,الرصيد\r\n"مورد, اختباري",0123,١٢٫٥');
    await c.importAccountRows(input);
    final supplier=c.accounts.singleWhere((a)=>a.name=='مورد, اختباري');
    expect(supplier.openingBalance,12.5);
    expect(supplier.phone,'0123');
    final item=c.inventory.first;
    await c.updateCatalogItem(item.id,name:'صنف محرر',sku:item.sku,unit:item.unit,threshold:8);
    final before=c.ledger.length;
    InvoiceItemRow line(double qty)=>InvoiceItemRow(id:'l',itemId:item.id,productName:'صنف محرر',quantity:qty,unitPrice:12);
    await expectLater(c.postPurchaseInvoice(accountId:supplier.id,warehouseId:item.warehouseId,payment:PaymentMethod.credit,
      rows:[line(3),line(-1)]),throwsFormatException);
    expect(c.ledger.length,before);
    expect(c.inventory.first.quantity,item.quantity);
    final number=await c.postPurchaseInvoice(accountId:supplier.id,warehouseId:item.warehouseId,payment:PaymentMethod.credit,rows:[line(3)]);
    await c.saveCurrencyDetails(CurrencyCode.usd, 'USD', 'سنت', 3.7, 3.8);
    await expectLater(c.saveCurrencyDetails(CurrencyCode.usd, 'USD', '', 0, 1), throwsA(isA<Exception>()));
    await c.saveMessagePreferences('external','770000000',true);
    await c.saveGroup(name:'موردون محليون',category:AccountCategory.purchases,currency:supplier.currency,members:{supplier.id});
    await c.updateAlerts(['stock_test']);
    await c.updateAlerts(['limit_test'],dismiss:true);
    await store.close();
    final reopened=ErpController(autoInitDb:false,localDatabase:store);
    addTearDown(reopened.dispose);
    await reopened.initDatabase();
    final purchase=reopened.ledger.singleWhere((e)=>e.entryNumber==number);
    expect(purchase.amount,36);
    expect(purchase.accountId,supplier.id);
    expect(purchase.direction,EntryDirection.credit);
    expect(reopened.saleLines.singleWhere((l)=>l.entryId==purchase.id).quantity,3);
    final stock=reopened.inventory.singleWhere((i)=>i.id==item.id);
    expect(stock.quantity,item.quantity+3);
    expect(stock.name,'صنف محرر');
    expect(stock.avgCost,(item.quantity*item.avgCost+36)/(item.quantity+3));
    final group=reopened.restoredGroups!.groups.singleWhere((g)=>g.name=='موردون محليون');
    expect(reopened.restoredGroups!.membership[supplier.id],group.id);
    expect(reopened.restoredGroups!.groupCurrencies[group.id],supplier.currency.name);
    expect(reopened.currencyDetails(CurrencyCode.usd)['subunit'], 'سنت');
    expect(reopened.exchangeQuote(CurrencyCode.usd, CurrencyCode.sar, EntryDirection.credit), 3.7);
    expect(reopened.exchangeQuote(CurrencyCode.sar, CurrencyCode.usd, EntryDirection.credit), 1 / 3.8);
    expect(reopened.exchangeQuote(CurrencyCode.usd, CurrencyCode.eur, EntryDirection.debit), isNull);
    expect(reopened.messageProvider,'external');
    expect(reopened.messagePhone,'770000000');
    expect(reopened.readAlerts,containsAll(['stock_test','limit_test']));
    expect(reopened.dismissedAlerts,{'limit_test'});
    expect(reopened.instantMessages,isTrue);
    final db=await store.database;
    await db.update('ledger_entries',{'deleted':1},where:'id = ?',whereArgs:[purchase.id]);
    final restored=await store.resolveDeletedEntry(purchase.id,purge:false);
    expect(restored!.deleted,isFalse);
    await expectLater(store.resolveDeletedEntry(purchase.id,purge:true),throwsStateError);
    await db.update('ledger_entries',{'deleted':1},where:'id = ?',whereArgs:[purchase.id]);
    await store.resolveDeletedEntry(purchase.id,purge:true);
    final afterPurge=await store.loadSnapshot();
    expect(afterPurge.ledger.where((e)=>e.id==purchase.id),isEmpty);
    expect(afterPurge.saleLines.where((l)=>l.entryId==purchase.id),isEmpty);
    final foreign=ErpController(autoInitDb:false,localDatabase:store);
    addTearDown(foreign.dispose);await foreign.initDatabase();
    await foreign.saveAccountRows([(name:'مورد دولار',phone:'',opening:0.0)],category:AccountCategory.purchases,
      currency:CurrencyCode.usd,direction:EntryDirection.credit);
    final beforeForeign=foreign.inventory.singleWhere((v)=>v.id==item.id);
    final fx=await foreign.postPurchaseInvoice(accountId:foreign.accounts.last.id,warehouseId:item.warehouseId,
      payment:PaymentMethod.credit,rows:[line(2)],exchangeRate:3.75);
    final foreignEntry=foreign.ledger.singleWhere((e)=>e.entryNumber==fx);
    expect(foreignEntry.currency,CurrencyCode.usd);
    expect(foreignEntry.exchangeRate,3.75);
    expect(foreignEntry.amount,24);
    expect(foreign.inventory.singleWhere((v)=>v.id==item.id).avgCost,
      (beforeForeign.quantity*beforeForeign.avgCost+90)/(beforeForeign.quantity+2));
  });
  test('stock, vouchers and exchanges survive closing and reopening SQLite', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
    first.addEmployee(name: 'موظف اختبار', roleTitle: 'محاسب', department: 'المالية',
      basicSalary: 1000, allowances: 200, deductions: 50);
    await first.renameCompany('شركة محلية');
    await first.saveWarehouse(name: 'فرع محلي', details: 'مخزن', isDefault: true);
    await CustomerMeasurementRepository(store).count();
    final backup = await first.createLocalBackup();
    final voucher = await first.postLocalEntry(accountId: account.id, kind: LedgerKind.voucher,
      direction: EntryDirection.debit, payment: PaymentMethod.balance,
      amount: 25, currency: account.currency);
    final exchange = await first.postLocalEntry(accountId: account.id, kind: LedgerKind.currency,
      direction: EntryDirection.credit, payment: PaymentMethod.cash, fromCurrency: CurrencyCode.usd,
      currency: CurrencyCode.sar, amount: 5, exchangeRate: 3.75);
    expect(exchange, voucher + 1);
    final counterpart = first.accounts.firstWhere((a) => a.id != account.id);
    final journal = await first.postLocalEntry(accountId: account.id, counterpartId: counterpart.id,
      kind: LedgerKind.simpleEntry, direction: EntryDirection.credit, payment: PaymentMethod.balance,
      amount: 10, currency: account.currency);
    expect(first.ledger.where((e) => e.entryNumber == journal).map((e) => e.direction).toSet(),
      {EntryDirection.debit, EntryDirection.credit});
    first.dispose();
    await store.close();

    final reopened = LocalDatabase.withFactory(databaseFactoryFfi, path);
    final second = ErpController(autoInitDb: false, localDatabase: reopened);
    addTearDown(() async { second.dispose(); await reopened.close(); });
    await second.initDatabase();
    expect(second.companyName, 'شركة محلية');
    expect(second.warehouses.singleWhere((w) => w.isDefault).name, 'فرع محلي');
    expect(second.employees.singleWhere((e) => e.name == 'موظف اختبار').allowances, 200);
    expect(second.inventory.singleWhere((i) => i.id == item.id).quantity, qty + 2);
    expect(second.ledger.singleWhere((e) => e.entryNumber == voucher).amount, 25);
    expect(second.ledger.singleWhere((e) => e.entryNumber == exchange).amount, 18.75);
    expect(second.ledger.singleWhere((e) => e.entryNumber == exchange).currency, CurrencyCode.sar);
    final bytes = await (await second.database.database).rawQuery('PRAGMA integrity_check');
    expect(bytes.single.values.single, 'ok');
    await second.restoreLocalBackup(backup.id);
    expect(second.ledger.where((e) => e.entryNumber == voucher), isEmpty);
    expect(second.employees.singleWhere((e) => e.name == 'موظف اختبار').allowances, 200);
  });
}
