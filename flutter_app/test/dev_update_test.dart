import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/screens/dev_update_action.dart';
import 'package:nasqo_pro_erp/services/dev_update_service.dart';
import 'package:sqlite3/sqlite3.dart';

final payload = List<int>.generate(2048, (index) => index % 256);
Map<String, dynamic> manifest() => {
  'enabled': true,
  'versionCode': 21,
  'versionName': '1.0',
  'apkUrl': 'https://erp.indexesstore.com/flutter-updates/nasqo-dev-21.apk',
  'sizeBytes': payload.length,
  'sha256': crypto.sha256.convert(payload).toString(),
};

class TestUpdates extends DevUpdateService {
  int checks = 0;
  int installs = 0;
  bool failInstall = false;
  @override
  bool get supported => true;
  @override
  Future<DevRelease?> check() async {
    checks++;
    return DevRelease.fromJson(manifest());
  }

  @override
  Future<void> downloadAndInstall(DevRelease release) async {
    installs++;
    if (failInstall) throw const FormatException('بصمة غير مطابقة');
  }
}

void main() {
  test(
    'manifest rejects untrusted download locations and invalid checksums',
    () {
      for (final change in [
        {'apkUrl': 'http://erp.indexesstore.com/flutter-updates/app.apk'},
        {'apkUrl': 'https://example.org/flutter-updates/app.apk'},
        {'apkUrl': 'https://erp.indexesstore.com:8443/flutter-updates/app.apk'},
        {'sha256': 'bad'},
        {'sizeBytes': 0},
      ]) {
        expect(
          () => DevRelease.fromJson({...manifest(), ...change}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'verified downloads and rejected or interrupted transfers preserve SQLite on reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('nasqo-update-');
      addTearDown(() => dir.delete(recursive: true));
      final cache = await Directory('${dir.path}/cache').create();
      final dbPath = '${dir.path}/nasqo_pro_erp.db';
      final db = sqlite3.open(dbPath);
      db.execute('CREATE TABLE stock (qty INTEGER)');
      db.execute('INSERT INTO stock VALUES (17)');
      db.dispose();
      final release = DevRelease.fromJson(manifest());
      final verified = await release.saveVerified(
        Stream.fromIterable([payload.sublist(0, 300), payload.sublist(300)]),
        cache,
      );
      for (final bytes in [
        Stream.value(payload.sublist(1)),
        Stream.value([...payload, 1]),
        Stream.value(List<int>.filled(payload.length, 0)),
        Stream<List<int>>.error(const SocketException('offline')),
      ]) {
        await expectLater(
          release.saveVerified(bytes, cache),
          throwsA(anyOf(isA<FormatException>(), isA<SocketException>())),
        );
        expect(await verified.readAsBytes(), payload);
      }
      final updates = Directory('${cache.path}/dev-updates');
      expect(updates.listSync().map((f) => f.path), [verified.path]);
      final reopened = sqlite3.open(dbPath);
      try {
        expect(reopened.select('SELECT qty FROM stock').single['qty'], 17);
      } finally {
        reopened.dispose();
      }
    },
  );

  testWidgets(
    'checks on open, waits for consent, and checks again from the toolbar',
    (tester) async {
      final updates = TestUpdates();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DevUpdateAction(updates: updates))),
      );
      await tester.pumpAndSettle();
      expect(updates.checks, 1);
      expect(updates.installs, 0);
      await tester.tap(find.text('لاحقًا'));
      await tester.pumpAndSettle();
      expect(updates.installs, 0);
      await tester.tap(find.byTooltip('التحقق من تحديثات التطبيق'));
      await tester.pumpAndSettle();
      expect(updates.checks, 2);
      await tester.tap(find.text('تنزيل وتحديث'));
      await tester.pumpAndSettle();
      expect(updates.installs, 1);
    },
  );

  testWidgets('a download accepted from the startup prompt reports failures', (
    tester,
  ) async {
    final updates = TestUpdates()..failInstall = true;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DevUpdateAction(updates: updates))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('تنزيل وتحديث'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('بصمة غير مطابقة'), findsOneWidget);
    expect(updates.installs, 1);
  });
}
