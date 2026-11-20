import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/local_backup_files.dart';
import 'package:nasqo_pro_erp/screens/local_backup_workspace_view.dart';

final backup = LocalBackupFile(
    id: 'local-synthetic.json', bytes: 123, modifiedAt: DateTime(2026, 11, 19));
final check = LocalBackupCheck(
    checksum: 'synthetic-checksum', tableCounts: {'accounts': 2});
Widget app(
        {Future<List<LocalBackupFile>> Function()? load,
        Future<LocalBackupFile> Function()? create,
        Future<LocalBackupCheck> Function(String)? verify,
        Future<LocalBackupCheck> Function(String)? restore}) =>
    MaterialApp(
        home: LocalBackupWorkspaceView(
            loadBackups: load ?? () async => [backup],
            createBackup: create ?? () async => backup,
            verifyBackup: verify ?? (_) async => check,
            testRestore: restore ?? (_) async => check));
Future<void> tap(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets(
      'read only on open, distinct explicit verify and isolated restore',
      (tester) async {
    var creates = 0;
    var verifies = 0;
    var restores = 0;
    await tester.pumpWidget(app(create: () async {
      creates++;
      return backup;
    }, verify: (id) async {
      expect(id, backup.id);
      verifies++;
      return check;
    }, restore: (id) async {
      expect(id, backup.id);
      restores++;
      return check;
    }));
    await tester.pumpAndSettle();
    expect(creates + verifies + restores, 0);
    await tap(tester, 'التحقق من السلامة');
    await tester.pumpAndSettle();
    expect(verifies, 1);
    expect(restores, 0);
    expect(find.textContaining('هذا ليس اختبار استعادة'), findsOneWidget);
    await tap(tester, 'اختبار استعادة معزولة');
    await tester.pumpAndSettle();
    expect(restores, 1);
    expect(creates, 0);
    expect(
        find.textContaining('نجح اختبار الاستعادة المعزولة'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('await create prevents duplicate actions and Back',
      (tester) async {
    final pending = Completer<LocalBackupFile>();
    var creates = 0;
    await tester.pumpWidget(app(
        load: () async => [],
        create: () {
          creates++;
          return pending.future;
        }));
    await tester.pumpAndSettle();
    await tap(tester, 'إنشاء نسخة محلية');
    await tester.tap(find.text('إنشاء نسخة محلية'));
    await tester.pump();
    expect(creates, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, false);
    expect(
        find.textContaining('تم إنشاء نسخة محلية داخل التطبيق'), findsNothing);
    pending.complete(backup);
    await tester.pumpAndSettle();
    expect(find.text(backup.id), findsOneWidget);
    expect(find.textContaining('لم تُختبر استعادتها بعد'), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, true);
  });
  testWidgets('list failure can retry without creation', (tester) async {
    var loads = 0;
    var creates = 0;
    await tester.pumpWidget(app(load: () async {
      if (++loads == 1) {
        throw StateError('synthetic');
      }
      return [backup];
    }, create: () async {
      creates++;
      return backup;
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذر إكمال العملية'), findsOneWidget);
    await tap(tester, 'تحديث القائمة');
    await tester.pumpAndSettle();
    expect(find.text(backup.id), findsOneWidget);
    expect(creates, 0);
  });
  testWidgets('failed isolated test keeps file, permits retry and narrow RTL',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    await tester.pumpWidget(app(restore: (_) async {
      if (++attempts == 1) {
        throw StateError('synthetic');
      }
      return check;
    }));
    await tester.pumpAndSettle();
    await tap(tester, 'اختبار استعادة معزولة');
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذر إكمال العملية'), findsOneWidget);
    expect(find.text(backup.id), findsOneWidget);
    await tap(tester, 'اختبار استعادة معزولة');
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
        find.textContaining('نجح اختبار الاستعادة المعزولة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(Directionality.of(tester.element(find.text(backup.id))),
        TextDirection.rtl);
  });
}
