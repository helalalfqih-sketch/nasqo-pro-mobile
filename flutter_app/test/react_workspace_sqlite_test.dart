import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/hybrid/react_workspace.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test(
      'native postings survive closing SQLite and replay only once after reopening',
      () async {
    final tmp = await Directory.systemTemp.createTemp('nasqo-react-');
    final path = '${tmp.path}/app.db';
    late LocalDatabase store;
    late ErpController controller;
    late ReactWorkspace app;
    Future<void> open() async {
      store = LocalDatabase.withFactory(databaseFactoryFfi, path);
      controller = ErpController(
          autoInitDb: false, localDatabase: store, emptyOnFirstInstall: true);
      await controller.initDatabase();
      expect(controller.dbReady, isTrue);
      app = ReactWorkspace(controller, allowWrites: true);
    }

    Future<void> close() async {
      controller.dispose();
      await store.close();
    }

    await open();
    addTearDown(() async {
      await close();
      await tmp.delete(recursive: true);
    });
    int sequence = 0;
    Future<Map> request(String action, Map payload, [String? key]) async =>
        jsonDecode(await app.handle(jsonEncode({
          'action': action,
          'payload': payload,
          'protocolVersion': '1.0.0',
          'kind': 'request',
          'requestId': 'req_${++sequence}',
          if (key != null) 'idempotencyKey': key
        }))) as Map;
    Future<Map> save(String action, Map data, String key) async {
      final r = await request(
          action, {'workspaceId': 'local-erp-workspace', 'payload': data}, key);
      expect(r['ok'], true, reason: r.toString());
      return r['data'] as Map;
    }

    expect((await app.snapshot())['accountGroups'], isEmpty);
    expect(controller.accounts, isEmpty);
    expect(controller.ledger, isEmpty);
    final acc = (await save(
        'saveAccount',
        {'name': 'مورد اختبار', 'category': 'purchases'},
        'account-001'))['account'];
    final groups = (await app.snapshot())['accountGroups'] as List;
    expect(groups.single['id'], acc['groupId']);
    final item = (await save(
        'createInventoryItem',
        {
          'name': 'صنف الاختبار',
          'unit': 'حبة',
          'warehouseId': 'wh_1',
          'quantity': 10,
          'avgCost': 2
        },
        'inventory-001'))['item'];
    final invoice = {
      'accountId': acc['id'],
      'kind': 'invoice',
      'direction': 'credit',
      'payment': 'credit',
      'currency': 'ريال',
      'amount': 15,
      'lines': [
        {'inventoryItemId': item['id'], 'quantity': 3, 'price': 5}
      ],
      'warehouseId': 'wh_1',
      'documentNumber': 'QA-1'
    };
    final voucher = {
      'accountId': acc['id'],
      'kind': 'voucher',
      'direction': 'debit',
      'payment': 'cash',
      'amount': 4,
      'currency': 'ريال'
    };
    final results = await Future.wait([
      save('createLedgerEntry', invoice, 'invoice-001'),
      save('createLedgerEntry', invoice, 'invoice-001')
    ]);
    expect(results[1]['postingReceipt']['replayed'], true);
    await save('createLedgerEntry', voucher, 'voucher-001');
    expect(controller.saleLines.single.quantity, 3);
    expect(controller.inventory.single.quantity, 13);
    await close();
    await open();
    expect(
        (await save(
                'createLedgerEntry', invoice, 'invoice-001'))['postingReceipt']
            ['replayed'],
        true);
    expect(
        (await save(
                'createLedgerEntry', voucher, 'voucher-001'))['postingReceipt']
            ['replayed'],
        true);
    expect(
        (await request(
            'createLedgerEntry',
            {
              'workspaceId': 'local-erp-workspace',
              'payload': {...voucher, 'amount': 8}
            },
            'voucher-001'))['ok'],
        false);
    final db = await store.database;
    expect(await db.rawQuery('SELECT COUNT(*) AS n FROM ledger_entries'), [
      {'n': 2}
    ]);
    expect(await db.rawQuery('SELECT quantity FROM inventory_items'), [
      {'quantity': 13.0}
    ]);
    expect(await db.rawQuery('SELECT quantity,unitPrice FROM sale_lines'), [
      {'quantity': 3.0, 'unitPrice': 5.0}
    ]);
    expect((await app.snapshot())['accounts'], hasLength(1));
    app = ReactWorkspace(controller, allowWrites: false);
    expect(
        (await request(
            'saveAccount',
            {
              'payload': {'name': 'رفض'}
            },
            'unauthorized'))['error']['code'],
        'UNAUTHORIZED_ACTION');
  });
}
