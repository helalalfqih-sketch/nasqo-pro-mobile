import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/sales_return_draft.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  late LocalDatabase store;
  late ErpController c;
  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('nasqo-invoice-modes');
    store = LocalDatabase.withFactory(databaseFactoryFfi, '${dir.path}/workspace.db');
    c = ErpController(autoInitDb:false, localDatabase:store);
    await c.initDatabase();
  });
  tearDown(() async {c.dispose(); await store.close(); await dir.delete(recursive:true);});

  test('item invoice rounds each net line like the website, including lines without a discount', () async {
    final item=c.inventory.first;
    InvoiceItemRow row(String id,double price,double discount)=>InvoiceItemRow(id:id,itemId:item.id,
        productName:item.name,quantity:1,unitPrice:price,discount:discount,roundLineTotal:true);
    await c.submitSalesInvoice(accountId:c.accounts.first.id,customerName:'اختبار',
        warehouse:c.warehouses.firstWhere((w)=>w.id==item.warehouseId),payment:PaymentMethod.credit,
        includeVat:false,rows:[row('a',1.119,0),row('b',4.025,1)]);
    expect(c.ledger.first.amount,closeTo(4.15,1e-8));
    final saved=c.saleLines.where((l)=>l.entryId==c.ledger.first.id);
    expect(saved.map((l)=>l.unitPrice),[1.12,3.03]);
  });
  test('free sale and refund record tax without touching inventory; discounted sale refunds net value', () async {
    final wh=c.warehouses.first, item=c.inventory.first;
    final customer=c.accounts.firstWhere((a)=>a.category==AccountCategory.clients);
    Future<void> sale(List<InvoiceItemRow> rows,{double? free}) => c.submitSalesInvoice(
        accountId:customer.id, customerName:customer.name, warehouse:wh, payment:PaymentMethod.credit,
        includeVat:true, rows:rows, freeAmount:free, invoiceDate:DateTime(2026,5,8));
    Future<void> refund(String id,double qty) async {
      final draft=await c.saveSalesReturnDraft(sourceEntryId:id,date:'2026-11-21',reason:'اختبار',
          selections:[SalesReturnSelection(position:0,quantity:qty)]);
      await c.postSalesReturn(draft.id,draft.revision);
    }
    await sale([],free:100);
    final service=c.ledger.first;
    expect(service.entryDate,'2026-05-08');
    expect(service.amount,115);
    expect(c.inventory.first.quantity,item.quantity);
    await refund(service.id,1);
    expect(c.ledger.first.amount,115);
    expect(c.inventory.first.quantity,item.quantity);
    await sale([InvoiceItemRow(id:'line', itemId:item.id, productName:item.name,
        quantity:2,unitPrice:50,discount:20)]);
    final discounted=c.ledger.first;
    expect(discounted.amount,92);
    await refund(discounted.id,1);
    expect(c.ledger.first.amount,46);
    final register=await c.loadSaleTaxRegister();
    expect(register.rows.where((r)=>r.entryId==discounted.id).single.taxAmount,12);
    await store.close();
    final snapshot=await store.loadSnapshot();
    expect(snapshot.inventory.firstWhere((i)=>i.id==item.id).quantity,item.quantity-1);
    expect(snapshot.saleLines.singleWhere((l)=>l.entryId==discounted.id).unitPrice,40);
  });

  test('split returns allocate the original net and VAT down to the last cent', () async {
    final item=c.inventory.first, customer=c.accounts.first;
    await c.submitSalesInvoice(accountId:customer.id,customerName:customer.name,
        warehouse:c.warehouses.firstWhere((w)=>w.id==item.warehouseId),payment:PaymentMethod.credit,
        includeVat:true,rows:[InvoiceItemRow(id:'l',itemId:item.id,productName:item.name,
          quantity:3,unitPrice:10,discount:10)]);
    final source=c.ledger.first;
    final refunds=<double>[];
    for(var i=0;i<3;i++) {
      final d=await c.saveSalesReturnDraft(sourceEntryId:source.id,date:'2026-11-21',reason:'اختبار',
          selections:[SalesReturnSelection(position:0,quantity:1)]);
      await c.postSalesReturn(d.id,d.revision);
      refunds.add(c.ledger.first.amount);
    }
    expect(refunds.map((n)=>(n*100).round()), [767,766,767]);
    expect(refunds.reduce((a,b)=>a+b),closeTo(source.amount,1e-8));
    expect(c.inventory.first.quantity,item.quantity);
  });

  for(final payment in [PaymentMethod.cash,PaymentMethod.credit]) {
    test('partial ${payment.name} purchase return uses discounted cost and rejects duplicate and excess after reopen', () async {
      final supplier=c.accounts.firstWhere((a)=>a.category==AccountCategory.purchases);
      final box=c.accounts.firstWhere((a)=>a.isCashAccount), item=c.inventory.first;
      final number=await c.postPurchaseInvoice(accountId:supplier.id,warehouseId:item.warehouseId,
        payment:payment,cashboxAccountId:payment==PaymentMethod.cash?box.id:null,
        rows:[InvoiceItemRow(id:'a',itemId:item.id,productName:item.name,quantity:4,unitPrice:10,discount:8)]);
      final source=c.ledger.singleWhere((e)=>e.entryNumber==number && e.kind==LedgerKind.invoice);
      expect(source.amount,32);
      final printable = await c.loadInvoiceForPrint(source.id);
      expect(printable.entry.accountId,supplier.id);
      expect(printable.lines.single.unitPrice,8);
      Future<int> refund(String key,double qty)=>c.postPurchaseReturn(sourceId:source.id,requestId:key,quantities:{0:qty});
      final ret=await refund('one',2);
      final returned=c.ledger.singleWhere((e)=>e.entryNumber==ret && e.kind==LedgerKind.returnEntry);
      expect(returned.direction,EntryDirection.debit);
      expect(returned.amount,16);
      if(payment==PaymentMethod.cash) {
        expect(c.ledger.singleWhere((e)=>e.id=='${source.id}/cashbox').direction,EntryDirection.credit);
        expect(c.ledger.singleWhere((e)=>e.id=='${returned.id}/cashbox').direction,EntryDirection.debit);
      }
      final count=c.ledger.length;
      c.dispose();await store.close();
      c=ErpController(autoInitDb:false,localDatabase:store);await c.initDatabase();
      await expectLater(refund('one',1),throwsStateError);
      await expectLater(refund('two',3),throwsFormatException);
      expect(c.ledger.length,count);
      expect(c.remainingPurchaseQuantities(source.id)[0],2);
      expect(c.inventory.singleWhere((i)=>i.id==item.id).quantity,item.quantity+2);
      await refund('two',2);
      expect(c.inventory.singleWhere((i)=>i.id==item.id).quantity,item.quantity);
      final serviceNumber=await c.postPurchaseInvoice(accountId:supplier.id,warehouseId:item.warehouseId,
          payment:PaymentMethod.credit,rows:[],freeAmount:60);
      final service=c.ledger.singleWhere((e)=>e.entryNumber==serviceNumber);
      await c.postPurchaseReturn(sourceId:service.id,requestId:'service',quantities:{0:1});
      expect(c.ledger.first.amount,60);
      expect(c.inventory.singleWhere((i)=>i.id==item.id).quantity,item.quantity);
    });
  }
}
