import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/hybrid/react_home.dart';
import 'package:nasqo_pro_erp/hybrid/react_workspace.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('React-first QA flags do not depend on Flutter debug mode', () {
    const requestedReact =
        bool.fromEnvironment('NASQO_QA_REACT_PRIMARY', defaultValue: false);
    const requestedWrites =
        bool.fromEnvironment('NASQO_QA_REACT_ALLOW_WRITES', defaultValue: false);
    expect(reactHomeEnabled, requestedReact);
    expect(reactHomeAllowWrites, requestedReact && requestedWrites);
  });

  test('React navigation notifications never open a native Flutter route or write SQLite',
      () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-react-ui-owner-');
    final store = LocalDatabase.withFactory(
        databaseFactoryFfi, '${dir.path}/qa.db');
    final controller = ErpController(
        autoInitDb: false, localDatabase: store, emptyOnFirstInstall: true);
    addTearDown(() async {
      controller.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });
    await controller.initDatabase();
    final app = ReactWorkspace(controller, allowWrites: true);
    var index = 0;
    Future<Map<String, dynamic>> request(String action, Map<String, dynamic> payload) async {
      final response = await app.handle(jsonEncode({
        'protocolVersion': '1.0.0',
        'kind': 'request',
        'requestId': 'qa_route_${++index}',
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
        'action': action,
        'payload': payload,
      }));
      return Map<String, dynamic>.from(jsonDecode(response) as Map);
    }

    for (final action in ['navigate', 'openInvoice', 'openVoucher',
                         'openAccountStatement', 'goBack']) {
      final payload = switch (action) {
        'navigate' => <String, dynamic>{'route': 'invoice'},
        'openInvoice' => <String, dynamic>{'intent': 'invoice'},
        'openVoucher' => <String, dynamic>{},
        'openAccountStatement' => <String, dynamic>{'accountId': 'missing'},
        _ => <String, dynamic>{'currentRoute': 'dashboard', 'stackDepth': 1},
      };
      final reply = await request(action, payload);
      expect(reply['ok'], true, reason: '$action: $reply');
      expect((reply['data'] as Map)['uiOwner'], 'react');
    }
    expect(controller.accounts, isEmpty);
    expect(controller.ledger, isEmpty);
  });

  test('unsupported React command is explicit rather than a native Flutter fallback',
      () async {
    final dir = await Directory.systemTemp.createTemp('nasqo-react-unsupported-');
    final store = LocalDatabase.withFactory(
        databaseFactoryFfi, '${dir.path}/qa.db');
    final controller = ErpController(
        autoInitDb: false, localDatabase: store, emptyOnFirstInstall: true);
    addTearDown(() async {
      controller.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });
    await controller.initDatabase();
    final app = ReactWorkspace(controller, allowWrites: true);
    final response = jsonDecode(await app.handle(jsonEncode({
      'protocolVersion': '1.0.0',
      'kind': 'request',
      'requestId': 'qa_unsupported',
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
      'action': 'pickFile',
      'payload': {'purpose': 'restore-backup', 'accept': ['.json']},
    }))) as Map;
    expect(response['ok'], false);
    expect((response['error'] as Map)['code'], 'SERVICE_UNAVAILABLE');
    expect(controller.ledger, isEmpty);
  });
}
