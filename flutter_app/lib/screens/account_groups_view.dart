import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../state/erp_controller.dart';

class AccountGroupsView extends StatefulWidget {
  const AccountGroupsView({super.key,required this.controller});
  final ErpController controller;
  @override
  State<AccountGroupsView> createState()=>_GroupsState();
}
class _GroupsState extends State<AccountGroupsView> {
  String query='';
  Future<void> edit([int? id]) async {
    final c=widget.controller,archive=c.restoredGroups;
    final group=archive?.groups.where((g)=>g.id==id).firstOrNull;
    final fallback=id!=null && (archive==null || archive.groups.isEmpty) ? AccountCategory.values[id-1] : null;
    final category=AccountCategory.values.where((v)=>v.name==archive?.groupCategories[id]).firstOrNull ?? fallback ?? AccountCategory.shop;
    final rawCurrency=archive?.groupCurrencies[id];
    final currency=CurrencyCode.values.where((v)=>v.name==rawCurrency || v.label==rawCurrency).firstOrNull ?? c.defaultCurrency;
    final members={for(final a in c.accounts)
      if(id!=null && (fallback==null ? archive?.membership[a.id]==id : a.category==fallback)) a.id};
    await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>_GroupEditor(controller:c,
      groupId:id,name:group?.name??fallback?.label??'',category:category,currency:currency,members:members)));
  }
  @override
  Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.controller,builder:(ctx,_){
    final c=widget.controller, archive=c.restoredGroups;
    final groups=archive?.groups;
    final rows=<({int id,int number,String name,int count})>[];
    if(groups!=null && groups.isNotEmpty) {
      final counts=<int,int>{};
      for(final a in c.accounts) {
        final id=archive!.membership[a.id];
        if(id!=null) counts[id]=(counts[id]??0)+1;
      }
      for(final g in groups) {rows.add((id:g.id,number:g.number,name:g.name,count:counts[g.id]??0));}
    } else {
      for(final cat in AccountCategory.values) {
        rows.add((id:cat.index+1,number:cat.index+1,name:cat.label,count:c.accounts.where((a)=>a.category==cat).length));
      }
    }
    final visible=rows.where((g)=>'${g.number} ${g.name}'.contains(query.trim())).toList();
    return ListView(padding:const EdgeInsets.all(12),children:[
      FilledButton.icon(onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('إضافة مجموعة')),
      TextField(decoration:const InputDecoration(labelText:'بحث باسم المجموعة أو رقمها'),onChanged:(v)=>setState(()=>query=v)),
      if(visible.isEmpty) const Text('لا توجد مجموعات مطابقة.'),
      for(final g in visible) ListTile(leading:Text('${g.number}'),title:Text(g.name),subtitle:Text('${g.count} حساب'),
        trailing:const Icon(Icons.edit_outlined),onTap:()=>edit(g.id))
    ]);
  });
}
class _GroupEditor extends StatefulWidget {
  const _GroupEditor({required this.controller,required this.groupId,required this.name,
    required this.category,required this.currency,required this.members});
  final ErpController controller;
  final int? groupId;
  final String name;
  final AccountCategory category;
  final CurrencyCode currency;
  final Set<String> members;
  @override
  State<_GroupEditor> createState()=>_GroupEditorState();
}
class _GroupEditorState extends State<_GroupEditor> {
  late String name=widget.name;
  late AccountCategory category=widget.category;
  late CurrencyCode currency=widget.currency;
  late Set<String> selected=Set.of(widget.members);
  String query='',error='';
  bool busy=false;
  Future<void> save() async {
    setState(()=>busy=true);
    try{
      await widget.controller.saveGroup(id:widget.groupId,name:name,category:category,currency:currency,members:selected);
      if(mounted) Navigator.pop(context);
    }catch(e){if(mounted) setState(()=>error=e.toString());}
    finally{if(mounted) setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context){
    final accounts=widget.controller.accounts.where((a)=>'${a.codeNumber} ${a.name}'.contains(query.trim())).toList();
    return Scaffold(appBar:AppBar(title:Text(widget.groupId==null?'إضافة مجموعة':'تعديل المجموعة')),
      body:Column(children:[Expanded(child:ListView.builder(padding:const EdgeInsets.all(12),itemCount:accounts.length+1,
        itemBuilder:(ctx,index){
          if(index==0) return Column(children:[
            TextFormField(initialValue:name,onChanged:(v)=>name=v,decoration:const InputDecoration(labelText:'اسم المجموعة')),
            DropdownButtonFormField<AccountCategory>(value:category,decoration:const InputDecoration(labelText:'التصنيف'),
              items:[for(final v in AccountCategory.values) DropdownMenuItem(value:v,child:Text(v.label))],onChanged:(v)=>setState(()=>category=v!)),
            DropdownButtonFormField<CurrencyCode>(value:currency,decoration:const InputDecoration(labelText:'عملة المجموعة'),
              items:[for(final v in CurrencyCode.values) DropdownMenuItem(value:v,child:Text(v.label))],onChanged:(v)=>setState(()=>currency=v!)),
            TextField(onChanged:(v)=>setState(()=>query=v),decoration:const InputDecoration(labelText:'بحث في حسابات المجموعة')),
          ]);
          final a=accounts[index-1];
          return CheckboxListTile(title:Text(a.name),subtitle:Text('${a.codeNumber}'),value:selected.contains(a.id),
            onChanged:(v)=>setState((){if(v==true){selected.add(a.id);}else{selected.remove(a.id);}}));
        })),
        if(error.isNotEmpty) Text(error),
        SafeArea(child:FilledButton(onPressed:busy?null:save,child:Text('حفظ المجموعة (${selected.length} حساب)')))
      ]));
  }
}
