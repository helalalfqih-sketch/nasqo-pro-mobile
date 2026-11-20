import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../services/account_csv.dart';
import '../state/erp_controller.dart';

class AccountImportView extends StatefulWidget {
  const AccountImportView({super.key,required this.controller});
  final ErpController controller;
  @override
  State<AccountImportView> createState()=>_AccountImportState();
}
class _AccountImportState extends State<AccountImportView> {
  List<ImportedAccount> rows=[];
  String filename='',message='';
  bool busy=false;
  Future<void> choose() async {
    setState((){busy=true;message='';});
    try {
      final file=await openFile();
      if(file==null) return;
      final parsed=readAccountCsv(utf8.decode(await file.readAsBytes()));
      if(mounted) setState((){rows=parsed;filename=file.name;});
    } catch(error) {
      if(mounted) setState((){rows=[];filename='';message='تعذرت قراءة الملف: $error';});
    } finally {if(mounted) setState(()=>busy=false);}
  }
  Future<void> save() async {
    setState(()=>busy=true);
    try {
      final count=rows.length;
      await widget.controller.importAccountRows(rows);
      if(mounted) setState((){message='تم استيراد $count حساب';rows=[];filename='';});
    } catch(error) {if(mounted) setState(()=>message=error.toString());}
    finally {if(mounted) setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('اختر ملف CSV بصف عناوين، ثم اسم الحساب والهاتف والرصيد الافتتاحي بهذا الترتيب. تُضاف الحسابات إلى المشتريات برصيد افتتاحي دائن.'),
    OutlinedButton.icon(onPressed:busy?null:choose,icon:const Icon(Icons.file_open),label:const Text('اختيار ملف الحسابات')),
    if(rows.isNotEmpty)...[
      Text('$filename · ${rows.length} حساب'),
      for(final row in rows.take(10)) ListTile(title:Text(row.name),subtitle:Text(row.phone),trailing:Text('${row.opening}')),
      if(rows.length>10) const Text('تظهر أول عشرة حسابات للمعاينة.'),
      FilledButton(onPressed:busy?null:save,child:Text('استيراد ${rows.length} حساب'))
    ],
    if(busy) const LinearProgressIndicator(),
    if(message.isNotEmpty) Text(message)
  ]);
}

class AccountEditor extends StatefulWidget {
  const AccountEditor({super.key,required this.controller,this.account});
  final ErpController controller;
  final AccountRecord? account;
  @override
  State<AccountEditor> createState()=>_AccountEditorState();
}
class _AccountEditorState extends State<AccountEditor> {
  AccountRecord? get original=>widget.account;
  late String name=original?.name??'',phone=original?.phone??'',note=original?.note??'';
  late String opening='${original?.openingBalance??0}',limit='${original?.creditLimit??1000000}';
  late AccountCategory category=original?.category??AccountCategory.purchases;
  late CurrencyCode currency=original?.currency??widget.controller.defaultCurrency;
  late EntryDirection side=original?.openingDirection??EntryDirection.debit;
  late bool cash=original?.isCashAccount??false;
  bool busy=false;
  String error='';
  Future<void> save() async {
    setState((){busy=true;error='';});
    try {
      await widget.controller.saveAccountRows([(name:name,phone:phone,opening:parseAccountAmount(opening))],
        category:category,currency:currency,direction:side,creditLimit:parseAccountAmount(limit),
        note:note,cash:cash,editId:original?.id);
      if(mounted) Navigator.pop(context,true);
    } catch(e) {if(mounted) setState(()=>error=e.toString());}
    finally {if(mounted) setState(()=>busy=false);}
  }
  Widget field(String label,String value,ValueChanged<String> changed,{TextInputType? keyboard})=>
    TextFormField(initialValue:value,onChanged:changed,keyboardType:keyboard,decoration:InputDecoration(labelText:label));
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    field('اسم الحساب',name,(s)=>name=s),
    DropdownButtonFormField<AccountCategory>(value:category,decoration:const InputDecoration(labelText:'تصنيف الحساب'),
      items:[for(final c in AccountCategory.values) DropdownMenuItem(value:c,child:Text(c.label))],onChanged:(v)=>setState(()=>category=v!)),
    field('رقم الهاتف',phone,(s)=>phone=s,keyboard:TextInputType.phone),
    DropdownButtonFormField<CurrencyCode>(value:currency,decoration:const InputDecoration(labelText:'عملة الحساب'),
      items:[for(final c in CurrencyCode.values) DropdownMenuItem(value:c,child:Text(c.label))],onChanged:(v)=>setState(()=>currency=v!)),
    field('الرصيد الافتتاحي',opening,(s)=>opening=s,keyboard:TextInputType.number),
    DropdownButtonFormField<EntryDirection>(value:side,decoration:const InputDecoration(labelText:'جهة الرصيد الافتتاحي'),
      items:const [DropdownMenuItem(value:EntryDirection.debit,child:Text('مدين')),DropdownMenuItem(value:EntryDirection.credit,child:Text('دائن'))],
      onChanged:(v)=>setState(()=>side=v!)),
    field('سقف المديونية',limit,(s)=>limit=s,keyboard:TextInputType.number),
    field('ملاحظات',note,(s)=>note=s),
    SwitchListTile(title:const Text('حساب نقدي'),value:cash,onChanged:(v)=>setState(()=>cash=v)),
    if(error.isNotEmpty) Text(error),
    FilledButton(onPressed:busy?null:save,child:const Text('حفظ الحساب'))
  ]);
}

class MessageSettingsView extends StatefulWidget {
  const MessageSettingsView({super.key,required this.controller});
  final ErpController controller;
  @override
  State<MessageSettingsView> createState()=>_MessageSettingsState();
}
class _MessageSettingsState extends State<MessageSettingsView> {
  late String provider=widget.controller.messageProvider,phone=widget.controller.messagePhone;
  late bool instant=widget.controller.instantMessages;
  bool saving=false;
  String status='';
  Future<void> save() async {
    setState(()=>saving=true);
    try {
      await widget.controller.saveMessagePreferences(provider,phone,instant);
      if(mounted) setState(()=>status='تم حفظ إعدادات واتساب على الهاتف.');
    } catch(e){if(mounted) setState(()=>status=e.toString());}
    finally {if(mounted) setState(()=>saving=false);}
  }
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    Text(widget.controller.companyName,style:Theme.of(context).textTheme.titleLarge),
    const Text('إدارة إشعارات واتساب'),
    DropdownButtonFormField<String>(value:provider,decoration:const InputDecoration(labelText:'مزود خدمة واتساب'),
      items:const [DropdownMenuItem(value:'nasqo',child:Text('نسقو برو')),DropdownMenuItem(value:'external',child:Text('خدمة خارجية'))],
      onChanged:(v)=>setState(()=>provider=v!)),
    SwitchListTile(value:instant,onChanged:(v)=>setState(()=>instant=v),title:const Text('تفعيل نظام الرسائل الفورية عبر واتساب')),
    TextFormField(initialValue:phone,onChanged:(v)=>phone=v,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'رقم واتساب')),
    const Text('تُحفظ التفضيلات محليًا. إرسال الرسائل يتطلب اتصالًا وخدمة إرسال.'),
    FilledButton(onPressed:saving?null:save,child:const Text('حفظ الإعدادات')),
    if(status.isNotEmpty) Text(status)
  ]);
}
