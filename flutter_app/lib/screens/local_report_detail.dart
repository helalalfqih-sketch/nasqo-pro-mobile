import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';
import '../services/invoice_movement_report.dart';

enum LocalReport {
  profit('أرباح الفواتير'),
  movement('حركة الأصناف والأرباح'),
  closing('تقرير الحسابات الختامية'),
  category('تقرير إجمالي حسب التصنيف'),
  stock('المخزون المتبقي'),
  expiry('تقرير المخزون المتبقي وتاريخ الانتهاء'),
  services('تقارير الخدمات');
  const LocalReport(this.title);
  final String title;
}

class LocalReportDetail extends StatefulWidget {
  const LocalReportDetail({super.key,required this.controller,required this.report});
  final ErpController controller;
  final LocalReport report;
  @override
  State<LocalReportDetail> createState() => _LocalReportDetailState();
}

class _LocalReportDetailState extends State<LocalReportDetail> {
  late CurrencyCode currency = widget.controller.defaultCurrency;
  String warehouse = '';
  int limit = 100;
  DateTimeRange? period;
  CostBasis basis = CostBasis.average;
  String day(DateTime? d) => d?.toIso8601String().split('T').first ?? '';

  Future<void> choosePeriod() async {
    final picked = await showDateRangePicker(context:context,firstDate:DateTime(1900),
      lastDate:DateTime(2200),initialDateRange:period);
    if(mounted && picked!=null) setState(() {period=picked;limit=100;});
  }

  Widget invoiceReport() {
    final c=widget.controller, movement=widget.report==LocalReport.movement;
    final rows=invoiceMovementReport(inventory:c.inventory,ledger:c.ledger,lines:c.saleLines,
      metadata:c.restoredGroups,currency:currency,warehouse:warehouse,
      from:day(period?.start),through:day(period?.end),basis:basis);
    final visible=rows.where((r)=>movement || r.sold.abs()>0.0001 || r.sales.abs()>0.0001 || r.profit.abs()>0.0001);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(movement) DropdownButtonFormField<CostBasis>(value:basis,decoration:const InputDecoration(labelText:'أساس الربح'),
        items:const [DropdownMenuItem(value:CostBasis.average,child:Text('متوسط الشراء')),
          DropdownMenuItem(value:CostBasis.catalog,child:Text('تكلفة الصنف')),
          DropdownMenuItem(value:CostBasis.lastPurchase,child:Text('آخر سعر شراء'))],
        onChanged:(v)=>setState((){if(v!=null) basis=v;})),
      Wrap(children:[TextButton.icon(onPressed:choosePeriod,icon:const Icon(Icons.date_range),
        label:Text(period==null?'كل الفترات':'${day(period!.start)} — ${day(period!.end)}')),
        if(period!=null) TextButton(onPressed:()=>setState((){period=null;limit=100;}),child:const Text('إزالة الفترة'))]),
      table(['اسم الصنف',if(movement)...['صافي كمية الشراء','إجمالي الشراء'],'كمية البيع','إجمالي البيع','الربح'],
        [for(final r in visible) [r.item.name,if(movement)...[format(r.bought),format(r.purchases)],
          format(r.sold),format(r.sales),format(r.profit)]],
        'لا توجد حركات فواتير أصناف في النطاق المحدد.'),
      Text('إجمالي المبيعات: ${format(rows.fold<double>(0,(s,r)=>s+r.sales))}'),
      Text('إجمالي الأرباح: ${format(rows.fold<double>(0,(s,r)=>s+r.profit))}')
    ]);
  }
  final format = AccountingEngine.formatAmount;

  Widget table(List<String> headers,List<List<String>> rows,String empty) {
    if (rows.isEmpty) return Padding(padding:const EdgeInsets.all(20),child:Text(empty));
    return Column(children:[
      SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(
        columnSpacing:20, horizontalMargin:10,
        headingRowColor:WidgetStatePropertyAll(Theme.of(context).colorScheme.surfaceContainerHighest),
        columns:[for(final h in headers) DataColumn(label:Text(h))],
        rows:[for(final row in rows.take(limit)) DataRow(cells:[for(final value in row) DataCell(Text(value))])])),
      if(rows.length > limit) TextButton(onPressed:()=>setState(()=>limit+=100),
        child:Text('عرض المزيد (المعروض $limit من ${rows.length})'))
    ]);
  }

  Widget categoryReport() {
    final c = widget.controller;
    final accounts = {for(final a in c.accounts) a.id:a};
    final debit = <AccountCategory,double>{}, credit = <AccountCategory,double>{};
    final counts = <AccountCategory,int>{};
    void add(AccountCategory group,bool isDebit,double value) {
      final totals = isDebit ? debit : credit;
      totals[group] = (totals[group] ?? 0) + value;
    }
    for(final a in c.accounts) {
      counts[a.category] = (counts[a.category] ?? 0)+1;
      if(a.currency == currency && a.openingBalance > 0) {
        add(a.category,a.openingDirection == EntryDirection.debit,a.openingBalance);
      }
    }
    for(final e in c.ledger) {
      if(e.currency != currency || e.deleted || e.kind == LedgerKind.quote || e.kind == LedgerKind.order) continue;
      final a = accounts[e.accountId];
      final isDebit = e.direction == EntryDirection.debit;
      if(a != null) {
        final metadata = c.restoredGroups;
        final wash = (metadata?.settledEntries.contains(e.id) ?? false) ||
            (metadata?.sides[e.id] == null && a.isCashAccount && e.payment == PaymentMethod.cash);
        add(a.category,isDebit,e.amount);
        if(wash) add(a.category,!isDebit,e.amount);
      }
      final other = accounts[c.restoredGroups?.counterparts[e.id]];
      if(other != null) add(other.category,!isDebit,e.amount);
    }
    final rows = <List<String>>[];
    for(final group in AccountCategory.values) {
      final d = debit[group] ?? 0.0, cr = credit[group] ?? 0.0;
      final net = cr-d;
      rows.add([group.label,'${counts[group] ?? 0}',format(d),format(cr),
        '${format(net.abs())} ${net<0 ? "عليه" : net>0 ? "له" : ""}'.trim()]);
    }
    return table(['التصنيف','الحسابات','عليه','له','الرصيد'],rows,'');
  }

  Widget closingReport() {
    final c = widget.controller;
    final balances = <String,double>{
      for(final a in c.accounts) a.id:
        a.currency == currency && a.openingBalance>0
          ? a.openingBalance*(a.openingDirection == EntryDirection.debit ? 1 : -1) : 0
    };
    var cash = 0.0, sales = 0.0, purchases = 0.0;
    for(final e in c.ledger) {
      if(e.deleted || e.currency!=currency || e.kind==LedgerKind.quote || e.kind==LedgerKind.order) continue;
      final debit = e.direction==EntryDirection.debit;
      final side = c.restoredGroups?.sides[e.id];
      final settled = c.restoredGroups?.settledEntries.contains(e.id) ?? false;
      if(!settled) {
        final change = (side?.debit ?? (debit ? e.amount : 0.0)) -
            (side?.credit ?? (debit ? 0.0 : e.amount));
        balances[e.accountId] = (balances[e.accountId] ?? 0) + change;
      }
      if(e.payment==PaymentMethod.cash || settled) {
        final type = c.restoredGroups?.documentTypes[e.id];
        final cashDocument = [LedgerKind.voucher,LedgerKind.transfer,LedgerKind.simpleEntry].contains(e.kind);
        final inflow = cashDocument ? !debit : type==null ? debit : [2,7,5].contains(type);
        cash += inflow ? e.amount : -e.amount;
      }
      if(e.kind==LedgerKind.invoice) {
        if(e.typeLabel.contains('بيع') || debit) {sales += e.amount;} else {purchases += e.amount;}
      } else if(e.kind==LedgerKind.returnEntry) {
        if(e.typeLabel.contains('مبيعات') || !debit) {sales -= e.amount;} else {purchases -= e.amount;}
      }
    }
    final debit = balances.values.where((v)=>v>0.005).fold<double>(0,(s,v)=>s+v);
    final credit = balances.values.where((v)=>v < -0.005).fold<double>(0,(s,v)=>s-v);
    final inventory = c.inventory.where((i)=>i.avgCost>0).fold<double>(0,(s,i)=>s+i.quantity*i.avgCost);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      for(final (title,values) in [
        ('الأرصدة',[('إجمالي المدين (عليهم)',debit),('إجمالي الدائن (لهم)',credit),
          ('إجمالي النقدية',cash<0 ? 0.0 : cash),('صافي الرصيد',debit-credit)]),
        ('نتيجة النشاط',[('المبيعات',sales),('المشتريات',purchases),('قيمة المخزون',inventory),
          ('صافي الربح',sales+inventory-purchases)])
      ]) ...[
        Text(title,style:Theme.of(context).textTheme.titleMedium),
        for(final (label,value) in values) ListTile(title:Text(label),trailing:Text(format(value)))
      ]
    ]);
  }

  Widget stockReport() {
    final c = widget.controller;
    final expiry = widget.report == LocalReport.expiry;
    final dates = c.restoredGroups?.expiryDates ?? <String,String>{};
    final items = c.inventory.where((i)=>(warehouse.isEmpty || i.warehouseId==warehouse) &&
        i.quantity.abs()>0.0001 && (!expiry || dates.containsKey(i.id))).toList();
    items.sort((a,b)=>expiry ? dates[a.id]!.compareTo(dates[b.id]!) : a.name.compareTo(b.name));
    if(expiry) {
      final now = DateTime.now(), rows = <List<String>>[];
      final today = DateTime.utc(now.year,now.month,now.day);
      for(final item in items) {
        final date = dates[item.id]!;
        final end = DateTime.tryParse('${date}T00:00:00Z');
        final days = end?.difference(today).inDays;
        rows.add([item.name,'${format(item.quantity)} ${item.unit}',date,
          days==null ? '—' : days<0 ? 'منتهي منذ ${days.abs()} يوم' : days==0 ? 'ينتهي اليوم' : 'متبقي $days يوم']);
      }
      return table(['اسم الصنف','الكمية','تاريخ الانتهاء','الحالة'],rows,'لا توجد أصناف بتاريخ انتهاء مسجل في بطاقات الأصناف.');
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      table(['الرقم','اسم الصنف','الوحدة','الكمية','القيمة'],[
        for(final (index,item) in items.indexed)
          ['${c.restoredGroups?.itemNumbers[item.id] ?? index+1}',item.name,item.unit,
            format(item.quantity),format(item.quantity*item.avgCost)]
      ],'لا توجد أصناف بكميات متبقية.'),
      Text('إجمالي الكمية: ${format(items.fold<double>(0,(s,i)=>s+i.quantity))}'),
      Text('إجمالي القيمة: ${format(items.fold<double>(0,(s,i)=>s+i.quantity*i.avgCost))}')
    ]);
  }

  Widget servicesReport() {
    final c = widget.controller;
    final invoices = c.ledger.where((e)=>!e.deleted && e.kind==LedgerKind.invoice &&
        e.currency==currency && (c.restoredGroups?.serviceInvoices.contains(e.id) ?? false)).toList()
      ..sort((a,b){final date=b.entryDate.compareTo(a.entryDate);
        return date==0 ? b.entryNumber.compareTo(a.entryNumber) : date;});
    double total(EntryDirection side) => invoices.where((e)=>e.direction==side).fold<double>(0,(sum,e)=>sum+e.amount);
    final sales=total(EntryDirection.debit), purchases=total(EntryDirection.credit);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      table(['الرقم','التاريخ','الحساب','النوع','المبلغ'],[
        for(final e in invoices) ['${e.entryNumber}',e.entryDate,e.accountName,e.typeLabel,'${format(e.amount)} ${currency.label}']
      ],'لا توجد فواتير خدمات (فواتير حرة بدون أصناف).'),
      Text('إيرادات الخدمات (مبيعات): ${format(sales)}'),
      Text('مصروفات الخدمات (مشتريات): ${format(purchases)}'),
      Text('صافي الخدمات: ${format(sales-purchases)}')
    ]);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable:widget.controller,builder:(context,_) {
    final stock = widget.report==LocalReport.stock || widget.report==LocalReport.expiry;
    final invoices = widget.report==LocalReport.movement || widget.report==LocalReport.profit;
    return ListView(padding:const EdgeInsets.all(12),children:[
      if(stock || invoices) DropdownButtonFormField<String>(value:warehouse,decoration:const InputDecoration(labelText:'مخزن التقرير'),
        items:[const DropdownMenuItem(value:'',child:Text('كل المخازن')),
          for(final w in widget.controller.warehouses) DropdownMenuItem(value:w.id,child:Text(w.name))],
        onChanged:(v)=>setState((){warehouse=v ?? '';limit=100;})),
      if(!stock) DropdownButtonFormField<CurrencyCode>(value:currency,decoration:const InputDecoration(labelText:'عملة التقرير'),
        items:[for(final v in CurrencyCode.values) DropdownMenuItem(value:v,child:Text(v.label))],
        onChanged:(v)=>setState((){if(v!=null) currency=v;limit=100;})),
      const SizedBox(height:12),
      if(invoices) invoiceReport() else if(stock) stockReport() else if(widget.report==LocalReport.closing) closingReport() else if(widget.report==LocalReport.category) categoryReport() else servicesReport()
    ]);
  });
}
