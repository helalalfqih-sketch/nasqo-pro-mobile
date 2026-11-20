import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/main.dart';
import 'package:nasqo_pro_erp/screens/local_backup_workspace_view.dart';
import 'package:nasqo_pro_erp/services/local_backup_files.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

class _Workspace extends ErpController {
  _Workspace() : super(autoInitDb: false);
  int reads = 0;
  @override
  Future<List<LocalBackupFile>> loadLocalBackups() async {
    reads++;
    return [];
  }
}

void main() {
  testWidgets('options opens backup workspace in read-only list state',
      (tester) async {
    final c = _Workspace();
    addTearDown(c.dispose);
    final original = List.of(c.ledger);
    await tester.pumpWidget(NasqoProErpApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('خيارات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('النسخ المحلية واختبار الاستعادة'));
    await tester.pumpAndSettle();
    expect(find.byType(LocalBackupWorkspaceView), findsOneWidget);
    expect(c.reads, 1);
    expect(c.ledger, original);
    expect(tester.takeException(), isNull);
  });
}
