import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/hybrid/react_workspace.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('React routes stay in React, item edits reuse the native row and workspace settings survive restart', () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-qa21-');
    final path = '${dir.path}/qa.db';
    var db = LocalDatabase.withFactory(databaseFactoryFfi, path);
    var controller = ErpController(autoInitDb:false, localDatabase:db, emptyOnFirstInstall:true);
    var recovered = 0;
    var bridge = ReactWorkspace(controller, allowWrites:true, onLegacyRecovery:() => recovered++);
    var sequence = 0;
    Future<dynamic> action(String name, Map<String,Object?> payload, [String? key]) async {
      final response = jsonDecode(await bridge.handle(jsonEncode({
        'kind':'request','protocolVersion':'1.0.0','requestId':'test_${++sequence}',
        'action':name,'payload':payload, if(key != null) 'idempotencyKey':key,
      })));
      expect(response['ok'], isTrue, reason: response.toString());
      return response['data'];
    }
    addTearDown(() async { controller.dispose(); await db.close(); await dir.delete(recursive:true); });
    expect((await action('getSnapshot',{}))['accounts'],isEmpty);
    for(final operation in ['openInvoice','openVoucher','openAccountStatement','navigate','goBack']) {
      await action(operation,{});
    }
    expect(recovered,0);
    await action('openLegacyRecovery',{});
    expect(recovered,1);
    final item=(await action('createInventoryItem',{'payload':{'name':'QA stock','unit':'kg','quantity':3,'avgCost':5}},'stock-create-qa21'))['item'];
    final changes={'itemId':item['id'],'updates':{'name':'QA updated','quantity':4,'avgCost':7}};
    await action('updateInventoryItem',changes,'stock-edit');
    expect((await action('updateInventoryItem',changes,'stock-edit'))['postingReceipt']['replayed'],true);
    expect(controller.inventory.single.quantity,4);
    final report=await action('getInventoryMovementsReport',{'options':{'itemId':item['id']}});
    expect(report['itemRows'].single['remainingValue'],28);
    expect((await action('getCashboxesReport',{}))['cashboxes'],isEmpty);
    await action('saveWorkspaceSettings',{'updates':{'companyName':'QA21 fixture','defaultCurrency':'usd',
      'whatsappProvider':'external','whatsappPhone':'QA','whatsappInstantEnabled':true}});
    controller.dispose(); await db.close();
    db=LocalDatabase.withFactory(databaseFactoryFfi,path);
    controller=ErpController(autoInitDb:false,localDatabase:db,emptyOnFirstInstall:true);
    bridge=ReactWorkspace(controller,allowWrites:true);
    final reopened=await action('getSnapshot',{});
    expect(reopened['inventory'].single['id'],item['id']);
    expect(reopened['inventory'].single['name'],'QA updated');
    expect(reopened['workspace']['companyName'],'QA21 fixture');
    expect(controller.defaultCurrency.name,'usd');
    expect(reopened['workspace']['whatsappPhone'],'QA');
  });
}
