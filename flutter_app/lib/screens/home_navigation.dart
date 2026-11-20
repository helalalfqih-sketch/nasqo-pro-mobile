import 'package:flutter/material.dart';
import '../state/erp_controller.dart';
import '../models/erp_models.dart';
import 'home_account_views.dart';

class HomeNavigation extends StatelessWidget {
  const HomeNavigation({super.key, required this.onHome, required this.onServices,
    required this.onQuickActions, required this.onReports, required this.onProfile});
  final VoidCallback onHome, onServices, onQuickActions, onReports, onProfile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(String label, IconData icon, VoidCallback tap, {bool selected = false}) =>
      Expanded(child: Semantics(selected: selected, button: true,
        child: InkWell(onTap: tap, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 23, color: selected ? scheme.primary : scheme.onSurfaceVariant),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
        ]))));
    return SafeArea(top: false, child: Material(
      elevation: 8, color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SizedBox(height: 68, child: Row(children: [
        tab('الرئيسية', Icons.home_rounded, onHome, selected: true),
        tab('الخدمات', Icons.work_rounded, onServices),
        SizedBox(width: 70, child: Center(child: IconButton.filled(
          tooltip: 'الإجراءات السريعة', onPressed: onQuickActions,
          style: IconButton.styleFrom(fixedSize: const Size.square(54)),
          icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 32)))),
        tab('التقارير', Icons.format_list_bulleted_rounded, onReports),
        tab('الملف', Icons.person_rounded, onProfile),
      ]))));
  }
}

Future<String?> showHomeQuickActions(BuildContext context) => showModalBottomSheet<String>(
  context: context, useSafeArea: true, showDragHandle: true,
  builder: (context) => Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
    child: Row(children: [
      for (final (route, title, icon) in const [
        ('post-transfer', 'حوالة جديدة', Icons.send_outlined),
        ('qr-scanner', 'مسح باركود', Icons.qr_code_scanner),
        ('invoice', 'فاتورة جديدة', Icons.receipt_long_outlined),
        ('post-voucher', 'سند جديد', Icons.note_add_outlined),
      ])
        Expanded(child: InkWell(onTap: () => Navigator.pop(context, route),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6), Text(title, textAlign: TextAlign.center),
            ])))),
    ])));

class HomeReportsView extends StatelessWidget {
  const HomeReportsView({super.key, required this.onOpenModule});
  final ValueChanged<String> onOpenModule;

  @override
  Widget build(BuildContext context) {
    const groups = [
      ('التقارير المالية', [
        ('cashboxes','حركة الصندوق'),('report-closing','تقرير الحسابات الختامية'),('report-category','تقرير إجمالي حسب التصنيف'),
        ('finance','ميزان المراجعة')
      ]),
      ('التقارير المخزنية', [
        ('report-movement','حركة الأصناف والأرباح'),('stock-movement','حركة المخزون'),('report-expiry','تقرير المخزون المتبقي وتاريخ الانتهاء'),
        ('report-stock','المخزون المتبقي'),('report-profit','أرباح الفواتير'),('report-services','تقارير الخدمات'),
        ('recorded-sales-tax','التقارير الضريبية'),('sales-register','سجل فواتير المبيعات')
      ])
    ];
    return ListView(padding:const EdgeInsets.all(12),children:[
      for(final (section,links) in groups) ...[
        Padding(padding:const EdgeInsets.symmetric(vertical:8),
          child:Text(section,style:Theme.of(context).textTheme.titleMedium)),
        Wrap(spacing:8,runSpacing:8,children:[
          for(final (index,link) in links.indexed)
            FilledButton(onPressed:()=>onOpenModule(link.$1),
              style:FilledButton.styleFrom(backgroundColor:index.isEven ? const Color(0xFF945100) : const Color(0xFF3730A3)),
              child:Text(link.$2))
        ]),
      ]
    ]);
  }
}

typedef LocalAlert = ({String id,String title,String detail,String target,String? account,IconData icon});

List<LocalAlert> workspaceAlerts(ErpController c) {
  final result=<LocalAlert>[];
  final now=DateTime.now();
  final today=DateTime.utc(now.year,now.month,now.day);
  final balances=<String,double>{for(final a in c.accounts) a.id:
    a.openingBalance*(a.openingDirection==EntryDirection.debit?1:-1)};
  final accounts={for(final a in c.accounts)a.id:a};
  for(final e in c.ledger) {
    if(e.deleted || e.kind==LedgerKind.quote || e.kind==LedgerKind.order) continue;
    if(accounts[e.accountId]?.currency==e.currency) {
      balances[e.accountId]=(balances[e.accountId]??0)+(e.direction==EntryDirection.debit?e.amount:-e.amount);
    }
    if(e.kind!=LedgerKind.invoice || e.payment!=PaymentMethod.credit) continue;
    final raw=c.restoredGroups?.dueDates[e.id];
    final base=DateTime.tryParse(raw??e.entryDate);
    if(base==null) continue;
    final date=DateTime.utc(base.year,base.month,base.day).add(Duration(days:raw==null?30:0));
    final days=date.difference(today).inDays;
    if(days<=10) result.add((id:'due_${e.id}',title:days<0?'فاتورة آجلة متأخرة السداد (#${e.entryNumber})':'موعد استحقاق فاتورة قريب (#${e.entryNumber})',
      detail:'${e.accountName} · ${e.amount} ${e.currency.label} · ${date.toIso8601String().substring(0,10)}',
      target:'account',account:e.accountId,icon:Icons.event_outlined));
  }
  for(final a in c.accounts) {
    final balance=balances[a.id]??0;
    if(a.creditLimit>0 && balance>a.creditLimit) result.add((id:'limit_${a.id}',title:'تجاوز سقف المديونية: ${a.name}',
      detail:'الرصيد $balance ${a.currency.label} · السقف ${a.creditLimit}',target:'account',account:a.id,icon:Icons.account_balance_wallet_outlined));
  }
  for(final i in c.inventory.where((i)=>i.minThreshold>0 && i.quantity<i.minThreshold)) {
    result.add((id:'stock_${i.id}',title:'انخفاض مخزون: ${i.name}',detail:'المتوفر ${i.quantity} ${i.unit} · الحد الأدنى ${i.minThreshold}',
      target:'inventory',account:null,icon:Icons.inventory_2_outlined));
  }
  return result.where((a)=>!c.dismissedAlerts.contains(a.id)).toList();
}

class LocalAlertsView extends StatelessWidget {
  const LocalAlertsView({super.key,required this.controller,required this.open});
  final ErpController controller;
  final ValueChanged<String> open;
  Future<bool> mark(BuildContext context,Iterable<String> ids,{bool dismiss=false}) async {
    try {await controller.updateAlerts(ids,dismiss:dismiss);return true;}
    catch(e){if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));return false;}
  }
  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:controller,builder:(context,_) {
    final alerts=workspaceAlerts(controller);
    final unread=alerts.where((a)=>!controller.readAlerts.contains(a.id)).map((a)=>a.id).toList();
    return ListView.builder(padding:const EdgeInsets.all(12),itemCount:alerts.length+1,itemBuilder:(ctx,index){
      if(index==0) return alerts.isEmpty?const ListTile(title:Text('لا توجد تنبيهات.')):
        TextButton(onPressed:unread.isEmpty?null:()=>mark(context,unread),child:Text('تعليم الكل كمقروء (${unread.length})'));
      final a=alerts[index-1];
      return Card(child:ListTile(leading:Icon(a.icon),title:Text(a.title,style:TextStyle(
        fontWeight:controller.readAlerts.contains(a.id)?FontWeight.normal:FontWeight.bold)),subtitle:Text(a.detail),
        trailing:IconButton(tooltip:'إخفاء التنبيه',icon:const Icon(Icons.close),onPressed:()=>mark(context,[a.id],dismiss:true)),
        onTap:() async {
          if(!await mark(context,[a.id]) || !context.mounted) return;
          if(a.account!=null) {
            Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>HomeAccountStatementView(controller:controller,accountId:a.account!)));
          } else {open(a.target);}
        }));
    });
  });
}
