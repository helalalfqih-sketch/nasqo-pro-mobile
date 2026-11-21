import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/screens/local_backup_workspace_view.dart';
import 'package:nasqo_pro_erp/services/local_backup_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('InvoiceArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final latin = FontLoader('InvoiceLatin')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([font.load(), latin.load(), icons.load()]);
  });
  for (final brightness in Brightness.values) {
    testWidgets(
        'Arabic recovery at 320dp with larger type in ${brightness.name}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
              useMaterial3: true,
              brightness: brightness,
              fontFamily: 'InvoiceArabic',
              fontFamilyFallback: const ['InvoiceLatin']),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!),
          home: LocalBackupWorkspaceView(
              loadBackups: () async => [
                    LocalBackupFile(
                        id: 'nasqo-0123456789012-abcdef0123456789abcdef01.json',
                        bytes: 2048,
                        modifiedAt: DateTime(2026, 1, 1))
                  ],
              createBackup: () => throw UnimplementedError(),
              verifyBackup: (_) => throw UnimplementedError(),
              testRestore: (_) => throw UnimplementedError(),
              restoreWeb: (_) async {})));
      await tester.pumpAndSettle();
      final heading = find.text('معلومات النسخ الاحتياطية');
      expect(Directionality.of(tester.element(heading)), TextDirection.rtl);
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('goldens/backup-ar-${brightness.name}.png'));
    });
  }
}
