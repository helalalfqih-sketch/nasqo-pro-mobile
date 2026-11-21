import 'dart:convert';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

// Only the standalone lab calls this. Its caller supplies its own SQLite path.
Future<ErpController> loadLab(LocalDatabase db, String syntheticJson) async {
  if (!await db.hasSeededData()) {
    final doc = jsonDecode(syntheticJson) as Map<String,dynamic>;
    final accounts = [
      for (final a in doc['accounts'])
        AccountRecord(id:a['id'],name:a['name'],
          category:AccountCategory.values.byName(a['category']),
          currency:CurrencyCode.values.singleWhere((c)=>c.label==a['currency']),
          openingBalance:(a['openingBalance'] as num).toDouble(),
          openingDirection:EntryDirection.values.byName(a['openingDirection'])),
    ];
    await db.saveSnapshot(accounts:accounts,ledger:[],warehouses:[],inventory:[],
      saleLines:[],companyName:'مختبر المطابقة',isDarkMode:false,nextEntryNumber:1,
      restoredWebExport:syntheticJson);
  }
  final c = ErpController(autoInitDb:false,localDatabase:db);
  await c.initDatabase();
  if(c.restoredGroups==null || !c.dbReady) {c.dispose();throw StateError('تعذرت قراءة قاعدة الاختبار');}
  return c;
}

class TableSession {
  TableSession(this.controller);
  final ErpController controller;
  final filters=<int,String>{};
  final currencies=[for(final c in CurrencyCode.values)c.label];
  bool accepts(int id)=>controller.restoredGroups!.groups.any((g)=>g.id==id);

  // Incoming messages express UI intent only. Navigation is handled in Flutter.
  ({String action,int? id})? receive(String message) {
    if(message.length>256)return null;
    Object? m;
    try {m=jsonDecode(message);}on FormatException{return null;}
    if(m is! Map<String,dynamic>)return null;
    final action=m['action'];
    if(action=='ready' && m.length==1)return (action:'ready',id:null);
    final id=m['id'];
    if(id is! int || !accepts(id))return null;
    if(action=='open' && m.length==2)return (action:'open',id:id);
    final value=m['currency'];
    if(action=='currency' && m.length==3 && value is String && (value=='الكل'||currencies.contains(value))){
      filters[id]=value;
      return (action:'currency',id:id);
    }
    return null;
  }

  CurrencyCode currencyFor(int id) => CurrencyCode.values.where((c)=>c.label==filters[id]).firstOrNull ?? controller.defaultCurrency;

  Map<String,Object?> presentation(bool dark) {
    final archive=controller.restoredGroups!;
    final count=<int,int>{};
    for(final a in controller.accounts){
      final id=archive.membership[a.id];
      if(id!=null)count[id]=(count[id]??0)+1;
    }
    final totals=archive.balancesByCurrency(controller.accounts,controller.ledger);
    return {'dark':dark,'currencies':currencies,'rows':[
      for(final g in archive.groups){
        'id':g.id,'legacyId':g.number,'name':g.name,'category':archive.groupCategories[g.id],
        'accountCount':count[g.id]??0,'netDebitMinusCredit':filters[g.id]=='الكل'?null:totals[currencyFor(g.id)]![g.id]??0,
        if(filters[g.id]=='الكل') 'amounts':[for(final c in CurrencyCode.values)
          {'currency':c.label,'value':totals[c]![g.id]??0}],
        'currency':filters[g.id]??controller.defaultCurrency.label,
      },
    ]};
  }
}
