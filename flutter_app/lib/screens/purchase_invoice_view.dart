import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../services/account_csv.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';

class PurchaseInvoiceView extends StatefulWidget {
  const PurchaseInvoiceView({super.key,required this.controller});
  final ErpController controller;
  @override
  State<PurchaseInvoiceView> createState()=>_PurchaseInvoiceState();
}
class _PurchaseInvoiceState extends State<PurchaseInvoiceView> {
  String? account,item,warehouse;
  PaymentMethod payment=PaymentMethod.credit;
  final rows=<InvoiceItemRow>[];
  final price=TextEditingController(),quantity=TextEditingController(text:'1');
  String reference='',error='';
  bool saving=false;
  @override
  void dispose(){price.dispose();quantity.dispose();super.dispose();}
  void add() {
    try {
      final product=widget.controller.inventory.where((v)=>v.id==item).firstOrNull;
      final qty=parseAccountAmount(quantity.text), cost=parseAccountAmount(price.text);
      if(product==null || qty<=0 || price.text.trim().isEmpty) throw const FormatException('اختر صنفًا وأدخل الكمية وسعر الشراء.');
      setState((){rows.add(InvoiceItemRow(id:'row_${DateTime.now().microsecondsSinceEpoch}',itemId:product.id,
        productName:product.name,quantity:qty,unitPrice:cost));error='';});
    } catch(e){setState(()=>error=e.toString());}
  }
  Future<void> save() async {
    if(saving) return;
    setState(()=>saving=true);
    try {
      final number=await widget.controller.postPurchaseInvoice(accountId:account??'',warehouseId:warehouse??'',
        payment:payment,rows:rows,reference:reference);
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تم ترحيل فاتورة الشراء رقم $number')));
      Navigator.pop(context);
    } catch(e){if(mounted) setState(()=>error=e.toString());}
    finally{if(mounted) setState(()=>saving=false);}
  }
  @override
  Widget build(BuildContext context){
    final c=widget.controller;
    final suppliers=c.accounts.where((a)=>a.category==AccountCategory.purchases && a.currency==c.defaultCurrency);
    return ListView(padding:const EdgeInsets.all(16),children:[
      DropdownButtonFormField<String>(value:account,isExpanded:true,decoration:const InputDecoration(labelText:'المورد'),
        items:[for(final a in suppliers) DropdownMenuItem(value:a.id,child:Text(a.name))],onChanged:(v)=>setState(()=>account=v)),
      if(suppliers.isEmpty) Text('أضف حساب مورد بعملة ${c.defaultCurrency.label} من دليل الحسابات.'),
      DropdownButtonFormField<String>(value:warehouse,decoration:const InputDecoration(labelText:'المستودع'),
        items:[for(final w in c.warehouses) DropdownMenuItem(value:w.id,child:Text(w.name))],
        onChanged:rows.isNotEmpty?null:(v)=>setState((){warehouse=v;item=null;price.clear();})),
      DropdownButtonFormField<PaymentMethod>(value:payment,decoration:const InputDecoration(labelText:'طريقة الدفع'),
        items:[for(final v in [PaymentMethod.cash,PaymentMethod.credit]) DropdownMenuItem(value:v,child:Text(v.label))],
        onChanged:(v)=>setState(()=>payment=v!)),
      TextField(decoration:const InputDecoration(labelText:'رقم فاتورة المورد'),onChanged:(s)=>reference=s),
      DropdownButtonFormField<String>(key:ValueKey(warehouse),value:item,isExpanded:true,decoration:const InputDecoration(labelText:'الصنف'),
        items:[for(final i in c.inventory.where((v)=>v.warehouseId==warehouse)) DropdownMenuItem(value:i.id,child:Text(i.name))],
        onChanged:(v)=>setState((){item=v;price.text=c.inventory.firstWhere((i)=>i.id==v).avgCost.toString();})),
      TextField(controller:quantity,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية')),
      TextField(controller:price,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'سعر الشراء')),
      OutlinedButton(onPressed:saving?null:add,child:const Text('إضافة بند')),
      for(final row in rows) ListTile(title:Text(row.productName),subtitle:Text('${row.quantity} × ${row.unitPrice}'),
        trailing:IconButton(tooltip:'إزالة البند',onPressed:saving?null:()=>setState(()=>rows.remove(row)),icon:const Icon(Icons.close))),
      Text('إجمالي الفاتورة: ${AccountingEngine.formatAmount(rows.fold<double>(0,(s,r)=>s+r.lineTotal))} ${c.defaultCurrency.label}'),
      if(error.isNotEmpty) Text(error),
      FilledButton(onPressed:saving || rows.isEmpty?null:save,child:const Text('حفظ وترحيل المشتريات'))
    ]);
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
