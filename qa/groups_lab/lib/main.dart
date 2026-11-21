import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nasqo_pro_erp/screens/dashboard_screen.dart';
import 'package:nasqo_pro_erp/screens/home_account_views.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db=LocalDatabase.withFactory(databaseFactory,p.join(await getDatabasesPath(),'qa_parity_groups_v1.db'));
  final c=await loadLab(db,await rootBundle.loadString('assets/fixture.json'));
  runApp(MaterialApp(locale:const Locale('ar'),supportedLocales:const [Locale('ar')],
    localizationsDelegates:GlobalMaterialLocalizations.delegates,
    theme:ThemeData(fontFamily:'LabArabic'),darkTheme:ThemeData.dark().copyWith(textTheme:ThemeData.dark().textTheme.apply(fontFamily:'LabArabic')),
    home:LabHome(controller:c)));
}

class LabHome extends StatelessWidget {
  const LabHome({super.key,required this.controller});
  final ErpController controller;
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('مختبر مجموعات الحسابات')),
    body:Column(children:[
      for(final native in [true,false]) FilledButton(
        onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Scaffold(
          appBar:AppBar(title:Text(native?'Flutter':'React')),
          body:native?SingleChildScrollView(child:GroupBalancesPanel(controller:controller)):HybridTable(controller:controller)))),
        child:Text(native?'Flutter':'React')),
    ]));
}

class HybridTable extends StatefulWidget {
  const HybridTable({super.key,required this.controller});
  final ErpController controller;
  @override
  State<HybridTable> createState()=>_HybridState();
}
class _HybridState extends State<HybridTable> {
  late final table=TableSession(widget.controller);
  late final web=WebViewController();
  bool ready=false,drilling=false,dark=false;
  String? failure;
  @override
  void initState(){super.initState();_load();}
  Future<void> _load() async {
    try {
      await web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await web.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest:(_)=>NavigationDecision.prevent));
      await web.addJavaScriptChannel('Groups',onMessageReceived:(m) async {
        if(!mounted)return;
        final intent=table.receive(m.message);
        if(intent==null)return;
        if(intent.action=='open'){
          if(drilling)return;
          drilling=true;
          try{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>HomeAccountsView.restoredGroup(
            controller:widget.controller,groupId:intent.id!,initialCurrency:table.currencyFor(intent.id!))));}
          finally{drilling=false;}
        }else{
          ready=true;await _present();
        }
      });
      await web.loadHtmlString(await rootBundle.loadString('assets/table.html'));
    }catch(_){if(mounted)setState(()=>failure='تعذّر فتح جدول الاختبار المحلي');}
  }
  Future<void> _present() async{
    if(!ready||!mounted)return;
    await web.runJavaScript('window.present('+jsonEncode(table.presentation(dark))+')');
  }
  @override
  void didChangeDependencies(){
    super.didChangeDependencies();
    dark=Theme.of(context).brightness==Brightness.dark;
    _present();
  }
  @override
  Widget build(BuildContext context)=>failure==null?WebViewWidget(controller:web):Text(failure!);
}
