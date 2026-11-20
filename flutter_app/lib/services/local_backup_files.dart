import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'local_backup_service.dart';

/// Metadata only. Paths and the envelope are never exposed to the UI.
class LocalBackupFile {
  const LocalBackupFile({
    required this.id,
    required this.bytes,
    required this.modifiedAt,
  });
  final String id;
  final int bytes;
  final DateTime modifiedAt;
}

class LocalBackupCheck {
  LocalBackupCheck({
    required this.checksum,
    required Map<String, int> tableCounts,
  }) : tableCounts = Map.unmodifiable(tableCounts);

  final String checksum;
  final Map<String, int> tableCounts;
}

/// Keeps recovery copies inside the app's private database directory. There is
/// no import, arbitrary path, share, deletion or overwrite API here.
class LocalBackupFiles {
  LocalBackupFiles({
    required LocalBackupService core,
    required Future<String> Function() privateDatabaseDirectory,
  })  : _core = core,
        _privateDatabaseDirectory = privateDatabaseDirectory;

  final LocalBackupService _core;
  final Future<String> Function() _privateDatabaseDirectory;
  static const maxBackupBytes = 16 * 1024 * 1024;
  static final _id = RegExp(r'^nasqo-[0-9]{13,18}-[0-9a-f]{24}\.json$');

  Future<Directory> _directory() async {
    final dir = Directory(
        p.join(await _privateDatabaseDirectory(), 'nasqo_local_backups'));
    var type = await FileSystemEntity.type(dir.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await dir.create(recursive: true);
      type = await FileSystemEntity.type(dir.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory) {
      throw StateError('دليل النسخ المحلية غير صالح.');
    }
    return dir;
  }

  Future<LocalBackupFile> _describe(File file) async {
    final info = await file.stat();
    return LocalBackupFile(
      id: p.basename(file.path),
      bytes: info.size,
      modifiedAt: info.modified,
    );
  }

  Future<List<LocalBackupFile>> loadBackups() async {
    final dir = await _directory();
    final out = <LocalBackupFile>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && _id.hasMatch(p.basename(entity.path))) {
        out.add(await _describe(entity));
      }
    }
    out.sort((a, b) {
      final byDate = b.modifiedAt.compareTo(a.modifiedAt);
      return byDate == 0 ? b.id.compareTo(a.id) : byDate;
    });
    return List.unmodifiable(out);
  }

  Future<LocalBackupFile> createBackup() async {
    final envelope = await _core.createBackup();
    final bytes = utf8.encode(envelope);
    if (bytes.length > maxBackupBytes) {
      throw StateError('النسخة أكبر من الحد المدعوم لهذا الاختبار.');
    }
    final random = Random.secure();
    final suffix = List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final dir = await _directory();
    final id = 'nasqo-${DateTime.now().millisecondsSinceEpoch}-$suffix.json';
    final target = File(p.join(dir.path, id));
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('تعذّر تسمية النسخة المحلية.');
    }
    // Only the temporary file created for this operation is cleaned up.
    final pending = File(p.join(dir.path, '.$id.pending'));
    var createdTemporary = false;
    try {
      await pending.create(exclusive: true);
      createdTemporary = true;
      await pending.writeAsBytes(bytes, flush: true);
      final saved = await pending.rename(target.path);
      return _describe(saved);
    } finally {
      if (createdTemporary && await pending.exists()) await pending.delete();
    }
  }

  Future<String> _read(String id) async {
    if (!_id.hasMatch(id)) throw ArgumentError('معرّف النسخة غير صالح.');
    final dir = await _directory();
    final file = File(p.join(dir.path, id));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('النسخة المحلية غير موجودة.');
    }
    final length = await file.length();
    if (length < 1 || length > maxBackupBytes) {
      throw StateError('حجم ملف النسخة غير صالح.');
    }
    // Enforce the bound again while streaming in case the file grew.
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maxBackupBytes) {
        throw StateError('النسخة أكبر من الحد المدعوم لهذا الاختبار.');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<LocalBackupCheck> verifyBackup(String id) async {
    final info = await _core.inspectBackup(await _read(id));
    return LocalBackupCheck(
        checksum: info.checksum, tableCounts: info.tableCounts);
  }

  Future<LocalBackupCheck> testRestore(String id) async {
    final info = await _core.verifyRestore(await _read(id));
    return LocalBackupCheck(
        checksum: info.checksum, tableCounts: info.tableCounts);
  }
}
