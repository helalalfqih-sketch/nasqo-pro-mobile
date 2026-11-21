import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/screens/dashboard_screen.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nasqo_groups_lab/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final fixture=File('assets/fixture.json').readAsStringSync();
  test('offline reopen, filter and drill intents preserve every stored row',() async{
    final dir=await Directory.systemTemp.createTemp('nasqo-parity-');
    addTearDown(()=>dir.delete(recursive:true));
    final file='${dir.path}/qa.db';
    List<Object?>? previous;
    for(var boot=0;boot<2;boot++){
      final db=LocalDatabase.withFactory(databaseFactoryFfi,file);
      final controller=await loadLab(db,fixture);
      final conn=await db.database;
      final names=await conn.rawQuery("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
      Future<List<Object?>> snapshot()async=>[
        for(final row in names) await conn.query(row['name'] as String,orderBy:'rowid')
      ];
      final before=await snapshot();
      if(previous!=null)expect(before,previous);
      final s=TableSession(controller);
      double net(int index)=>(((s.presentation(false)['rows'] as List)[index]['netDebitMinusCredit']) as num).toDouble();
      expect(net(0),-1250.5);expect(net(1),80);
      expect(s.receive('{"action":"currency","id":41,"currency":"دولار"}')?.action,'currency');
      expect(net(0),25);expect(net(1),80);
      expect(s.receive('{"action":"currency","id":41,"currency":"الكل"}')?.action,'currency');
      final row=(s.presentation(false)['rows'] as List).first;
      expect(row['netDebitMinusCredit'],isNull);
      expect(row['amounts'],containsAll([{'currency':'ريال','value':-1250.5},{'currency':'دولار','value':25}]));
      for(final bad in ['not JSON','[]','{"action":"open","id":404}',
        '{"action":"currency","id":41,"currency":"unknown"}','{"action":"save","id":41}',
        '{"action":"open","id":41,"sql":"extra"}']){expect(s.receive(bad),isNull);}
      expect(s.receive('{"action":"open","id":41}')?.id,41);
      expect(await conn.rawQuery('pragma integrity_check'),[{'integrity_check':'ok'}]);
      expect(await snapshot(),before);
      previous=before;controller.dispose();await db.close();
    }
  });
  for(final dark in [false,true]){
    for (final restored in [true,false]){
    testWidgets('native source, currencies and capture dark=$dark restored=$restored',(tester)async{
      tester.view.devicePixelRatio=1;
      tester.view.physicalSize=const Size(427,952);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir=Directory.systemTemp.createTempSync('nasqo-golden-');
      final db=LocalDatabase.withFactory(databaseFactoryFfi,'${dir.path}/qa.db');
      final c=await tester.runAsync(()=>loadLab(db,fixture));
      addTearDown(()async{c!.dispose();await db.close();await dir.delete(recursive:true);});
      final loader=FontLoader('LabArabic')..addFont(rootBundle.load('assets/NotoSansArabic-Regular.ttf'));
      await tester.runAsync(loader.load);
      final archive=c!.restoredGroups!;
      if(!restored)c.restoredGroups=null;
      Future<List<Object?>> sqlRows() async{
        final conn=await db.database;
        return [for(final table in ['accounts','ledger_entries','erp_state'])
          await conn.query(table,orderBy:'rowid')];
      }
      final before=await tester.runAsync(sqlRows);
      const key=ValueKey('capture');
      await tester.pumpWidget(MaterialApp(
        locale:const Locale('ar'),supportedLocales:const [Locale('ar')],
        localizationsDelegates:GlobalMaterialLocalizations.delegates,
        theme:ThemeData(brightness:dark?Brightness.dark:Brightness.light,fontFamily:'LabArabic'),
        home:Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:RepaintBoundary(key:key,
          child:GroupBalancesPanel(controller:c))))));
      await tester.pumpAndSettle();
      final debit=tester.widget<Text>(find.text('80'));
      expect(debit.style!.color,dark?const Color(0xff60a5fa):const Color(0xff0b5ca8));
      final credit=tester.widget<Text>(find.text('1,250.5-'));
      expect(credit.style!.color,dark?const Color(0xfffb7185):const Color(0xff9f1239));
      final image=await tester.runAsync(()async{
        final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        final image=await boundary.toImage(pixelRatio:1);
        try{return (await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();}
        finally{image.dispose();}
      });
      if(restored && const bool.fromEnvironment('CAPTURE')){
        final file=File('../screenshots/native-${dark?'dark':'light'}.png');
        file.parent.createSync(recursive:true);file.writeAsBytesSync(image!);
      }
      final filter=find.byKey(ValueKey(restored?'balance-restored-41':'balance-currency-clients'));
      await tester.tap(filter);await tester.pumpAndSettle();
      await tester.tap(find.text('الكل').last);await tester.pumpAndSettle();
      expect(find.text('1,250.5- · ريال'),findsOneWidget);
      expect(find.text('25 · دولار'),findsOneWidget);
      expect(find.text('1,225.5-'),findsNothing);
      expect(tester.takeException(),isNull);
      expect(await tester.runAsync(sqlRows),before);
      c.restoredGroups=archive;
    });
    }
  }
}
