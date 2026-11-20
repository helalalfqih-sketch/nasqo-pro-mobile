import 'package:flutter/material.dart';
import 'invoice_actions.dart';
import '../models/erp_models.dart';
import '../services/account_csv.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';

class PurchaseInvoiceView extends StatefulWidget {
  const PurchaseInvoiceView({super.key,required this.controller,this.onSaving});
  final ValueChanged<bool>? onSaving;
  final ErpController controller;
  @override
  State<PurchaseInvoiceView> createState()=>_PurchaseInvoiceState();
}
class _PurchaseInvoiceState extends State<PurchaseInvoiceView> {
  String? account,item,warehouse;
  PaymentMethod payment=PaymentMethod.credit;
  final rows=<InvoiceItemRow>[];
  final price=TextEditingController(),quantity=TextEditingController(text:'1');
  String reference='',error='',rate='1';
  bool saving=false,free=false;
  DateTime date=DateTime.now();
  String? cashbox;
  final discount=TextEditingController(), freeTotal=TextEditingController();
  @override
  void dispose(){discount.dispose();freeTotal.dispose();price.dispose();quantity.dispose();super.dispose();}
  void add() {
    try {
      final product=widget.controller.inventory.where((v)=>v.id==item).firstOrNull;
      final qty=parseAccountAmount(quantity.text), cost=parseAccountAmount(price.text);
      if(product==null || qty<=0 || price.text.trim().isEmpty) throw const FormatException('اختر صنفًا وأدخل الكمية وسعر الشراء.');
      final reduction=discount.text.trim().isEmpty?0.0:parseAccountAmount(discount.text);
      if(reduction<0 || cost<0) throw const FormatException('تحقق من السعر والخصم.');
      setState((){rows.add(InvoiceItemRow(id:'row_${DateTime.now().microsecondsSinceEpoch}',itemId:product.id,
        productName:product.name,quantity:qty,unitPrice:cost,discount:reduction));discount.clear();error='';});
    } catch(e){setState(()=>error=e.toString());}
  }
  Future<void> save({bool printAfter=false}) async {
    if(saving) return;
    setState(()=>saving=true);
    widget.onSaving?.call(true);
    try {
      if(payment==PaymentMethod.cash && cashbox==null) throw const FormatException('اختر صندوق النقدية.');
      final number=await widget.controller.postPurchaseInvoice(accountId:account??'',warehouseId:warehouse??'',
        payment:payment,rows:free?[]:rows,reference:reference,invoiceDate:date,cashboxAccountId:payment==PaymentMethod.cash?cashbox:null,
        freeAmount:free?parseAccountAmount(freeTotal.text):null,exchangeRate:parseAccountAmount(rate));
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تم ترحيل فاتورة الشراء رقم $number')));
      if(printAfter) {
        final entry=widget.controller.ledger.singleWhere((e)=>e.entryNumber==number && e.kind==LedgerKind.invoice);
        showCommittedInvoice(context,widget.controller,entry.id);
      } else { Navigator.pop(context); }
    } catch(e){if(mounted) setState(()=>error=e.toString());}
    finally{if(mounted) {widget.onSaving?.call(false);setState(()=>saving=false);}}
  }
  @override
  Widget build(BuildContext context){
    final c=widget.controller;
    final suppliers=c.accounts.where((a)=>a.category==AccountCategory.purchases);
    final cur=suppliers.where((a)=>a.id==account).firstOrNull?.currency??c.defaultCurrency;
    final boxes=c.accounts.where((a)=>a.isCashAccount && a.currency==cur);
    return PopScope(canPop:!saving,child:AbsorbPointer(absorbing:saving,child:ListView(padding:const EdgeInsets.all(16),children:[
      DropdownButtonFormField<String>(value:account,isExpanded:true,decoration:const InputDecoration(labelText:'المورد'),
        items:[for(final a in suppliers) DropdownMenuItem(value:a.id,child:Text(a.name))],onChanged:rows.isNotEmpty?null:(v)=>setState((){account=v;cashbox=null;rate='1';price.clear();item=null;})),
      if(suppliers.isEmpty) const Text('أضف حساب مورد من دليل الحسابات.'),
      if(cur!=c.defaultCurrency) TextFormField(key:ValueKey(account),initialValue:rate,keyboardType:TextInputType.number,
        onChanged:(v)=>rate=v,decoration:InputDecoration(labelText:'سعر الصرف: ${c.defaultCurrency.label} لكل ${cur.label}')),
      DropdownButtonFormField<String>(value:warehouse,decoration:const InputDecoration(labelText:'المستودع'),
        items:[for(final w in c.warehouses) DropdownMenuItem(value:w.id,child:Text(w.name))],
        onChanged:rows.isNotEmpty?null:(v)=>setState((){warehouse=v;item=null;price.clear();})),
      DropdownButtonFormField<PaymentMethod>(value:payment,decoration:const InputDecoration(labelText:'طريقة الدفع'),
        items:[for(final v in [PaymentMethod.cash,PaymentMethod.credit]) DropdownMenuItem(value:v,child:Text(v.label))],
        onChanged:(v)=>setState(()=>payment=v!)),
      if(payment==PaymentMethod.cash) DropdownButtonFormField<String>(value:cashbox,
        decoration:const InputDecoration(labelText:'صندوق النقدية'),
        items:[for(final b in boxes) DropdownMenuItem(value:b.id,child:Text(b.name))],
        onChanged:(v)=>setState(()=>cashbox=v)),
      InvoiceDateField(value:date,onChanged:(v)=>setState(()=>date=v)),
      TextField(decoration:const InputDecoration(labelText:'رقم فاتورة المورد'),onChanged:(s)=>reference=s),
      SegmentedButton<bool>(segments:const [
        ButtonSegment(value:false,label:Text('أصناف')), ButtonSegment(value:true,label:Text('حرة')),
      ],selected:{free},onSelectionChanged:(v)=>setState(()=>free=v.single)),
      if(free) TextField(controller:freeTotal,keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:const InputDecoration(labelText:'إجمالي مبلغ الفاتورة'),onChanged:(_)=>setState((){}))
      else ...[
      DropdownButtonFormField<String>(key:ValueKey(warehouse),value:item,isExpanded:true,decoration:const InputDecoration(labelText:'الصنف'),
        items:[for(final i in c.inventory.where((v)=>v.warehouseId==warehouse)) DropdownMenuItem(value:i.id,child:Text(i.name))],
        onChanged:(v)=>setState((){item=v;price.text=cur==c.defaultCurrency?c.inventory.firstWhere((i)=>i.id==v).avgCost.toString():'';})),
      TextField(controller:quantity,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية')),
      TextField(controller:price,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'سعر الشراء')),
      TextField(controller:discount,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'خصم السطر')),
      OutlinedButton(onPressed:saving?null:add,child:const Text('إضافة بند')),
      for(final row in rows) ListTile(title:Text(row.productName),subtitle:Text('${row.quantity} × ${row.unitPrice} · الخصم ${row.discount} · الصافي ${row.lineTotal}'),
        trailing:IconButton(tooltip:'إزالة البند',onPressed:saving?null:()=>setState(()=>rows.remove(row)),icon:const Icon(Icons.close))),
      ],
      Text('إجمالي الفاتورة: ${AccountingEngine.formatAmount(free?AccountingEngine.parseArabicNumber(freeTotal.text):rows.fold<double>(0,(s,r)=>s+r.lineTotal))} ${cur.label}'),
      if(error.isNotEmpty) Text(error),
      OutlinedButton.icon(onPressed:saving || (!free && rows.isEmpty)?null:()=>save(printAfter:true),
        icon:const Icon(Icons.print_outlined),label:const Text('حفظ وطباعة')),
      FilledButton(onPressed:saving || (!free && rows.isEmpty)?null:save,child:const Text('حفظ وترحيل المشتريات'))
    ])));
  }
}

class CatalogItemEditor extends StatefulWidget {
  const CatalogItemEditor({super.key,required this.controller,required this.item});
  final ErpController controller;
  final InventoryItemRecord item;
  @override
  State<CatalogItemEditor> createState()=>_CatalogItemEditorState();
}
class _CatalogItemEditorState extends State<CatalogItemEditor> {
  late String name=widget.item.name,sku=widget.item.sku,unit=widget.item.unit,threshold=widget.item.minThreshold.toString();
  String error='';
  bool saving=false;
  Future<void> save() async {
    setState(()=>saving=true);
    try {
      await widget.controller.updateCatalogItem(widget.item.id,name:name,sku:sku,unit:unit,threshold:parseAccountAmount(threshold));
      if(mounted) Navigator.pop(context);
    } catch(e){if(mounted) setState(()=>error=e.toString());}
    finally{if(mounted) setState(()=>saving=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('تعديل الصنف')),body:ListView(
    padding:const EdgeInsets.all(16),children:[
      TextFormField(initialValue:name,onChanged:(s)=>name=s,decoration:const InputDecoration(labelText:'اسم الصنف')),
      TextFormField(initialValue:sku,onChanged:(s)=>sku=s,decoration:const InputDecoration(labelText:'رمز الصنف')),
      TextFormField(initialValue:unit,onChanged:(s)=>unit=s,decoration:const InputDecoration(labelText:'الوحدة')),
      TextFormField(initialValue:threshold,onChanged:(s)=>threshold=s,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'حد التنبيه')),
      if(error.isNotEmpty) Text(error),
      FilledButton(onPressed:saving?null:save,child:const Text('حفظ التعديل'))
    ]));
}

class PurchasesRegister extends StatefulWidget {
  const PurchasesRegister({super.key,required this.controller,required this.openNew});
  final ErpController controller;
  final VoidCallback openNew;
  @override
  State<PurchasesRegister> createState()=>_PurchasesRegisterState();
}
class _PurchasesRegisterState extends State<PurchasesRegister> {
  String query='';
  PaymentMethod? payment;
  CurrencyCode? currency;
  @override
  Widget build(BuildContext context) {
    final c=widget.controller;
    final filtered=c.ledger.where((e)=>!e.deleted && e.kind==LedgerKind.invoice &&
      e.direction==EntryDirection.credit && (payment==null || e.payment==payment) &&
      (currency==null || e.currency==currency) &&
      '${e.accountName} ${e.documentNumber} ${e.entryNumber}'.toLowerCase().contains(query.trim().toLowerCase())).toList()
      ..sort((a,b){final date=b.entryDate.compareTo(a.entryDate);return date==0?b.entryNumber.compareTo(a.entryNumber):date;});
    return ListView(padding:const EdgeInsets.all(16),children:[
      FilledButton.icon(onPressed:widget.openNew,icon:const Icon(Icons.add),label:const Text('فاتورة مشتريات جديدة')),
      TextField(decoration:const InputDecoration(labelText:'بحث بالمورد أو رقم الفاتورة'),onChanged:(v)=>setState(()=>query=v)),
      DropdownButtonFormField<PaymentMethod?>(value:payment,decoration:const InputDecoration(labelText:'طريقة الدفع'),
        items:[const DropdownMenuItem(value:null,child:Text('كل طرق الدفع')),
          for(final v in PaymentMethod.values) DropdownMenuItem(value:v,child:Text(v.label))],
        onChanged:(v)=>setState(()=>payment=v)),
      DropdownButtonFormField<CurrencyCode?>(value:currency,decoration:const InputDecoration(labelText:'العملة'),
        items:[const DropdownMenuItem(value:null,child:Text('كل العملات')),
          for(final v in CurrencyCode.values) DropdownMenuItem(value:v,child:Text(v.label))],onChanged:(v)=>setState(()=>currency=v)),
      if(filtered.isEmpty) const ListTile(title:Text('لا توجد فواتير مشتريات تطابق البحث.')),
      for(final e in filtered) ListTile(title:Text('${e.entryNumber} · ${e.accountName}'),
        subtitle:Text('${e.entryDate} · ${e.payment.label}'),
        trailing:Text('${AccountingEngine.formatAmount(e.amount)} ${e.currency.label}'),
        onTap:()=>showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(ctx){
          final lines=c.saleLines.where((line)=>line.entryId==e.id);
          return SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(16),children:[
            Text('فاتورة مشتريات ${e.documentNumber}',style:Theme.of(ctx).textTheme.titleLarge),
            Text('${e.accountName} · ${e.warehouseName} · ${e.entryDate}'),
            if(e.details.isNotEmpty) Text(e.details),
            if(lines.isEmpty) const ListTile(title:Text('لا تتوفر بنود محفوظة لهذه الفاتورة.')),
            for(final line in lines) ListTile(title:Text(line.itemName),
              subtitle:Text('${line.quantity} ${line.unit} × ${line.unitPrice}'),
              trailing:Text(AccountingEngine.formatAmount(line.quantity*line.unitPrice))),
            Text('الإجمالي: ${AccountingEngine.formatAmount(e.amount)} ${e.currency.label}')
          ]));
        }))
    ]);
  }
}
