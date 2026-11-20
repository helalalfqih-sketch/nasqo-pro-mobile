import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/screens/local_db_startup_view.dart';

Widget app(String? code, Future<void> Function() retry) =>
    MaterialApp(home: LocalDbStartupView(diagnosticCode: code, retry: retry));
void main() {
  testWidgets('null diagnostic is loading and never retries automatically',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(null, () async {
      calls++;
    }));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('إعادة المحاولة بأمان'), findsNothing);
    expect(calls, 0);
  });
  testWidgets('retry awaits and blocks repeats before returning failure state',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(app('DB-LOCKED', () {
      calls++;
      return pending.future;
    }));
    await tester.tap(find.text('إعادة المحاولة بأمان'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('إعادة المحاولة بأمان'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, false);
    pending.completeError(StateError('secret raw error'));
    await tester.pumpAndSettle();
    expect(find.text('إعادة المحاولة بأمان'), findsOneWidget);
    expect(find.textContaining('secret raw error'), findsNothing);
  });
  testWidgets(
      'unknown errors sanitized and known codes described in RTL narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final code in [
      'DB-DRIVER',
      'DB-SETTINGS',
      'DB-SCHEMA',
      'DB-LOCKED',
      'DB-SPACE',
      'DB-DAMAGED',
      'DB-OPEN',
      'private/path raw'
    ]) {
      await tester.pumpWidget(app(code, () async {}));
      await tester.pump();
      final expected = code == 'private/path raw' ? 'DB-OPEN' : code;
      expect(find.text('رمز التشخيص: $expected'), findsOneWidget);
      expect(find.textContaining('private/path raw'), findsNothing);
      expect(
          Directionality.of(
              tester.element(find.text('رمز التشخيص: $expected'))),
          TextDirection.rtl);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('parent transitions from failure to loading after retry',
      (tester) async {
    await tester.pumpWidget(app('DB-OPEN', () async {}));
    await tester.tap(find.text('إعادة المحاولة بأمان'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(null, () async {}));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('إعادة المحاولة بأمان'), findsNothing);
  });
}
