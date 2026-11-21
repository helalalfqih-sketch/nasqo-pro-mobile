import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/cash_statement.dart';
import 'package:nasqo_pro_erp/services/web_backup.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  test('currency buckets, real document number, previous balance and restored counterpart',(){
    final c=ErpController(autoInitDb:false);addTearDown(c.dispose);
    const a=AccountRecord(id:'cash',name:'اختبار ريال',category:AccountCategory.clients,
      openingBalance:10,openingDirection:EntryDirection.credit);
    const b=AccountRecord(id:'counter',name:'اختبار نظير',category:AccountCategory.sales);
    c.accounts..clear()..addAll([a,b]);c.ledger.clear();c.saleLines.clear();
    LedgerEntryRecord entry(String id,String day,int n,CurrencyCode cur,double amount,String account,EntryDirection side)=>
      LedgerEntryRecord(id:id,accountId:account,accountName:account=='cash'?a.name:b.name,
        kind:LedgerKind.voucher,typeLabel:'سند اختبار',payment:PaymentMethod.credit,
        direction:side,amount:amount,currency:cur,entryDate:day,entryNumber:n,documentNumber:'DOC-$n');
    c.ledger.addAll([entry('old','2026-01-01',1,CurrencyCode.sar,4,'cash',EntryDirection.debit),
      entry('usd','2026-02-02',2,CurrencyCode.usd,5,'cash',EntryDirection.credit),
      entry('sar','2026-02-03',3,CurrencyCode.sar,2.25,'counter',EntryDirection.debit)]);
    c.restoredGroups=RestoredGroups([],{}, {})..counterparts['sar']='cash';
    CashStatement report(String currency,{String q='',String field='الكل'})=>CashStatement.read(c,a,
      currency:currency,period:'شهري',previous:true,today:DateTime(2026,2,20),query:q,criterion:field);
    final all=report('جميع العملات بدون مصارفة');
    expect(all.totals[CurrencyCode.sar]!.closing,8.25);expect(all.totals[CurrencyCode.usd]!.closing,5);
    expect(all.rows.map((r)=>r.running),[8.25,5]);expect(report('دولار').totals.keys,[CurrencyCode.usd]);
    expect(report('ريال',q:'DOC-3',field:'رقم المستند').rows.single.entry.id,'sar');
    expect(report('ريال',q:'sar',field:'رقم المستند').rows,isEmpty);
    expect(report('مصارفة الكل بعملة ريال').issue,isNotNull);
  });
}
