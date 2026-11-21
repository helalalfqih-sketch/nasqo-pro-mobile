import '../models/erp_models.dart';
import '../state/erp_controller.dart';
import 'account_posting.dart';
import 'accounting_engine.dart';

class StatementTotals {
  double debit=0, credit=0, previous=0;
  double get closing => previous+credit-debit;
}
typedef StatementLine=({LedgerEntryRecord entry,CurrencyCode currency,double amount,double running,bool debit});

class CashStatement {
  CashStatement._(this.from,this.through);
  final String from,through;
  final totals=<CurrencyCode,StatementTotals>{};
  final rows=<StatementLine>[];
  String? issue;

  static CashStatement read(ErpController controller,AccountRecord account,{
    required String currency, required String period, required bool previous,
    String query='',String criterion='الكل',DateTime? today,
  }) {
    final day=(today??DateTime.now()).toIso8601String().substring(0,10);
    final from=switch(period){'شهري'=>'${day.substring(0,7)}-01','سنوي'=>'${day.substring(0,4)}-01-01',_=>''};
    final result=CashStatement._(from,from.isEmpty?'':day);
    final converted=currency=='مصارفة الكل بعملة ريال';
    final selected=CurrencyCode.values.where((c)=>c.label==currency).firstOrNull;
    final posting=AccountPosting(controller.ledger,controller.restoredGroups);
    StatementTotals bucket(CurrencyCode code)=>result.totals.putIfAbsent(code,StatementTotals.new);
    CashStatement unavailable(String message){
      result.issue=message;result.rows.clear();result.totals.clear();return result;
    }
    if(converted && controller.defaultCurrency!=CurrencyCode.sar){
      return unavailable('تعذّر التحويل إلى الريال لأن العملة الأساسية المسجلة مختلفة.');
    }
    if(previous && account.openingBalance!=0 && (selected==null || selected==account.currency)){
      if(converted && account.currency!=CurrencyCode.sar){
        return unavailable('سعر الرصيد الافتتاحي التاريخي غير متاح. اعرض العملات دون مصارفة.');
      }
      bucket(converted?CurrencyCode.sar:account.currency).previous=
          account.openingDirection==EntryDirection.credit?account.openingBalance:-account.openingBalance;
    }
    final entries=controller.ledger.where((e)=>!e.deleted && e.kind!=LedgerKind.quote && e.kind!=LedgerKind.order &&
        (selected==null || e.currency==selected) && (result.through.isEmpty || e.entryDate.compareTo(result.through)<=0))
      .toList()..sort((a,b){
        final d=a.entryDate.compareTo(b.entryDate);if(d!=0)return d;
        final n=a.entryNumber.compareTo(b.entryNumber);return n!=0?n:a.id.compareTo(b.id);
      });
    final needle=query.trim().toLowerCase();
    String searchText(LedgerEntryRecord e,double debit,double credit){
      final counter=controller.restoredGroups?.counterparts[e.id];
      final sender=controller.accounts.where((a)=>a.id==counter).firstOrNull?.name??'';
      final description=[e.details,...controller.saleLines.where((line)=>line.entryId==e.id).map((l)=>l.itemName)].join(' ');
      final fields={'الرقم':e.entryNumber.toString(),'البيان':description,'رقم المستند':e.documentNumber,
        'اسم المرسل':sender,'اسم المستلم':e.accountName,'اسم الشركة':e.warehouseName,
        'المبلغ عليه':debit==0?'':'$debit ${AccountingEngine.formatAmount(debit)}',
        'المبلغ له':credit==0?'':'$credit ${AccountingEngine.formatAmount(credit)}'};
      return criterion=='الكل'?[...fields.values,e.typeLabel,e.entryDate,e.currency.label].join(' '):fields[criterion]??'';
    }
    for(final entry in entries) {
      final side=posting.forAccount(account,entry);
      if(side==null)continue;
      final earlier=from.isNotEmpty && entry.entryDate.compareTo(from)<0;
      if(earlier&&!previous)continue;
      if(!earlier && needle.isNotEmpty && !searchText(entry,side.debit,side.credit).toLowerCase().contains(needle))continue;
      final code=converted?CurrencyCode.sar:entry.currency;
      var rate=1.0;
      if(converted && entry.currency!=CurrencyCode.sar) {
        rate=entry.exchangeRate;
        // Local voucher/exchange amounts are already denominated in the entry
        // currency. A generic default or a source/target FX rate is not a SAR quote.
        final documented=controller.restoredGroups?.rateToBase.contains(entry.id)??false;
        if(!rate.isFinite || rate<=0 || (!documented &&
            (entry.kind==LedgerKind.currency || rate==1))) {
          return unavailable('لا يوجد سعر تاريخي موثّق لهذا القيد. اعرض العملات دون مصارفة.');
        }
      }
      final balance=bucket(code), debit=side.debit*rate,credit=side.credit*rate;
      if(earlier){balance.previous+=credit-debit;continue;}
      balance.debit+=debit;balance.credit+=credit;
      result.rows.add((entry:entry,currency:code,amount:entry.amount*rate,running:balance.closing,debit:debit>credit));
    }
    if(result.totals.isEmpty)bucket(selected??(converted?CurrencyCode.sar:account.currency));
    final newest=result.rows.reversed.toList();result.rows..clear()..addAll(newest);
    return result;
  }
}
