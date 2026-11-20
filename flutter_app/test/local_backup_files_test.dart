import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/local_backup_files.dart';
import 'package:nasqo_pro_erp/services/local_backup_service.dart';
import 'package:nasqo_pro_erp/services/local_database.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

void _ffi() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }
}

void main() {
  test(
      'app-private file roundtrip, invalid path rejection and source unchanged',
      () async {
    final root = await Directory.systemTemp.createTemp('nasqo-backup-files-');
    final factory = createDatabaseFactoryFfi(ffiInit: _ffi);
    final store =
        LocalDatabase.withFactory(factory, p.join(root.path, 'synthetic.db'));
    final c = ErpController(autoInitDb: false, localDatabase: store);
    addTearDown(() async {
      c.dispose();
      await store.close();
      await root.delete(recursive: true);
    });
    await c.initDatabase();
    expect(c.dbReady, isTrue);
    final files = LocalBackupFiles(
      core: LocalBackupService(store, factory: factory),
      privateDatabaseDirectory: () async => root.path,
    );
    final before = await store.loadSnapshot();
    expect(await files.loadBackups(), isEmpty);
    await expectLater(
        files.verifyBackup('../synthetic.db'), throwsA(isA<ArgumentError>()));
    final file = await files.createBackup();
    expect(file.bytes, greaterThan(0));
    expect((await files.loadBackups()).single.id, file.id);
    final checked = await files.verifyBackup(file.id);
    final restored = await files.testRestore(file.id);
    expect(restored.checksum, checked.checksum);
    expect(restored.tableCounts, checked.tableCounts);
    expect(restored.tableCounts['ledger_entries'], before.ledger.length);
    if (Platform.isLinux) {
      const forged = 'nasqo-1234567890123-000000000000000000000000.json';
      final link = Link(p.join(root.path, 'nasqo_local_backups', forged));
      await link.create(p.join(root.path, 'synthetic.db'));
      await expectLater(files.verifyBackup(forged), throwsStateError);
      expect((await files.loadBackups()).single.id, file.id);
    }
    final after = await store.loadSnapshot();
    expect(after.inventory.map((i) => [i.id, i.quantity]),
        before.inventory.map((i) => [i.id, i.quantity]));
    expect(after.ledger.map((l) => l.id), before.ledger.map((l) => l.id));
    expect(after.nextEntryNumber, before.nextEntryNumber);
  });
}
