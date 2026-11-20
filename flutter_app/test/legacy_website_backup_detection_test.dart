import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/website_backup_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('legacy website SQLite is identified without restoring or changing source', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('nasqo-legacy-detection-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/legacy.back');
    final db = await databaseFactoryFfi.openDatabase(source.path);
    for (final name in ['customers', 'products', 'stores', 'cboxes', 'trans_details']) {
      await db.execute('CREATE TABLE $name(id INTEGER PRIMARY KEY)');
    }
    await db.close();
    final before = await source.readAsBytes();
    await expectLater(
      readWebsiteBackup(Uint8List.fromList(before), 1024 * 1024),
      throwsA(isA<FormatException>().having(
        (error) => error.message, 'message',
        contains('نسخة SQLite قديمة من الموقع'))),
    );
    expect(await source.readAsBytes(), before);
  });
}
