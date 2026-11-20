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

  test('free sale and refund record tax without touching inventory; discounted sale refunds net value', () async {
    final wh=c.warehouses.first, item=c.inventory.first;
    final customer=c.accounts.firstWhere((a)=>a.category==AccountCategory.clients);
    Future<void> sale(List<InvoiceItemRow> rows,{double? free}) => c.submitSalesInvoice(
        accountId:customer.id, customerName:customer.name, warehouse:wh, payment:PaymentMethod.credit,
        includeVat:true, rows:rows, freeAmount:free);
    Future<void> refund(String id,double qty) async {
      final draft=await c.saveSalesReturnDraft(sourceEntryId:id,date:'2026-11-21',reason:'اختبار',
          selections:[SalesReturnSelection(position:0,quantity:qty)]);
      await c.postSalesReturn(draft.id,draft.revision);
    }
    await sale([],free:100);
    final service=c.ledger.first;
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

  for(final payment in [PaymentMethod.cash,PaymentMethod.credit]) {
    test('partial ${payment.name} purchase return uses discounted cost and rejects duplicate and excess after reopen', () async {
      final supplier=c.accounts.firstWhere((a)=>a.category==AccountCategory.purchases);
      final box=c.accounts.firstWhere((a)=>a.isCashAccount), item=c.inventory.first;
      final number=await c.postPurchaseInvoice(accountId:supplier.id,warehouseId:item.warehouseId,
        payment:payment,cashboxAccountId:payment==PaymentMethod.cash?box.id:null,
        rows:[InvoiceItemRow(id:'a',itemId:item.id,productName:item.name,quantity:4,unitPrice:10,discount:8)]);
      final source=c.ledger.singleWhere((e)=>e.entryNumber==number && e.kind==LedgerKind.invoice);
      expect(source.amount,32);
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
