import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'local_database.dart';

class LocalBackupQaResult {
  LocalBackupQaResult(
      {required this.scratchPath,
      required this.checksum,
      required Map<String, int> tableCounts})
      : tableCounts = Map.unmodifiable(tableCounts);
  final String scratchPath, checksum;
  final Map<String, int> tableCounts;
}

/// Offline QA only. A checksum detects corruption, not authorship/authenticity.
/// No SQL from a backup is executed. No destination argument or live replacement
/// exists. All restore writes go to a newly created, private sibling directory.
class LocalBackupService {
  LocalBackupService(this.source, {DatabaseFactory? factory})
      : _factory = factory ?? databaseFactory;
  final LocalDatabase source;
  final DatabaseFactory _factory;
  static const maxBytes = 16 * 1024 * 1024;
  static const maxRows = 100000;
  static const _format = 'nasqo-local-qa-json-v1';
  static const _tables = [
    'accounts',
    'ledger_entries',
    'warehouses',
    'inventory_items',
    'sale_lines',
    'erp_state',
    'nonposting_documents',
    'nonposting_lines',
    'sales_return_drafts',
    'sales_return_draft_lines',
    'sale_facts',
    'sale_line_cost_facts',
    'voucher_drafts',
    'cash_transfer_drafts',
    'simple_journal_drafts',
    'fx_drafts',
    'sqlite_sequence',
  ];
  static const _sequenceTables = {
    'nonposting_documents',
    'sales_return_drafts',
    'voucher_drafts',
    'cash_transfer_drafts',
    'simple_journal_drafts',
    'fx_drafts'
  };

  Future<Map<String, Object?>> _schema(DatabaseExecutor db) async {
    final names = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name <> 'android_metadata' ORDER BY name");
    final actual = names.map((r) => r['name']).toSet();
    if (actual.length != _tables.length || !_tables.every(actual.contains)) {
      throw StateError(
          'Unsupported database tables; QA backup requires exact v9 schema');
    }
    final objects = await db.rawQuery(
        "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE type IN ('trigger','view') OR (type = 'index' AND sql IS NOT NULL)");
    if (objects.isNotEmpty) {
      throw StateError('Custom triggers/views/indexes are not supported');
    }
    return {
      for (final table in _tables)
        table: {
          'columns': await db.rawQuery('PRAGMA table_info("$table")'),
          'sql': (await db.rawQuery(
                  "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                  [table]))
              .single['sql'],
        }
    };
  }

  Future<Map<String, Object?>> _payload(DatabaseExecutor db) async {
    // Fail closed before loading rows, including databases with large free pages.
    final pages =
        (await db.rawQuery('PRAGMA page_count')).single.values.single as int;
    final pageSize =
        (await db.rawQuery('PRAGMA page_size')).single.values.single as int;
    if (pages * pageSize > maxBytes) {
      throw StateError('Database exceeds QA size limit');
    }
    final version =
        (await db.rawQuery('PRAGMA user_version')).single.values.single;
    if (version != 9 || LocalDatabase.dbVersion != 9) {
      throw StateError('Only schema v9 is supported');
    }
    final schema = await _schema(db);
    var count = 0;
    var encodedBytes = 0;
    final data = <String, Object?>{};
    for (final table in _tables) {
      // Bounded reads: refuse instead of silently truncating a large database.
      final rows = await db.query(table, limit: maxRows + 1 - count);
      count += rows.length;
      if (count > maxRows) {
        throw StateError('Backup row limit exceeded');
      }
      encodedBytes += utf8.encode(_canonical(rows)).length;
      if (encodedBytes > maxBytes) {
        throw StateError('Backup size limit exceeded');
      }
      data[table] = rows;
    }
    return {
      'schemaVersion': 9,
      'schema': schema,
      'schemaFingerprint': _sha(_canonical(schema)),
      'data': _sortData(data)
    };
  }

  Future<String> createBackup() async {
    final db = await source.database;
    final payload = await db.transaction((txn) => _payload(txn));
    final encoded = _canonical({
      'format': _format,
      'payload': payload,
      'checksum': _sha(_canonical(payload))
    });
    if (utf8.encode(encoded).length > maxBytes) {
      throw StateError('Backup size limit exceeded');
    }
    return encoded;
  }

  Future<LocalBackupQaResult> verifyRestore(String envelope) async {
    final payload = _validateEnvelope(envelope);
    final schema = payload['schema'] as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    final expectedChecksum = _sha(_canonical(payload));
    final live = await source.database;
    final livePath = live.path;
    if (livePath == inMemoryDatabasePath || !p.isAbsolute(livePath)) {
      throw StateError('A file-backed source is required');
    }
    final sibling = Directory(p.join(p.dirname(livePath), 'nasqo_qa_backups'));
    // Refuse symlink redirection, including an existing QA directory.
    if (await FileSystemEntity.type(sibling.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('QA directory must not be a symlink');
    }
    await sibling.create();
    final scratchDir = await sibling.createTemp('qa-');
    final path = p.join(scratchDir.path, 'qa.db');
    final scratch = LocalDatabase.withFactory(_factory, path);
    try {
      final db = await scratch.database;
      final actualSchema = await _schema(db);
      if (_canonical(actualSchema) != _canonical(schema)) {
        throw const FormatException('Schema differs from installed v9');
      }
      await db.transaction((txn) async {
        for (final table in _tables) {
          if ((await txn.query(table, limit: 1)).isNotEmpty) {
            throw StateError('Scratch database was not empty');
          }
        }
        for (final table in _tables.where((t) => t != 'sqlite_sequence')) {
          for (final raw in data[table] as List) {
            await txn.insert(table, Map<String, Object?>.from(raw as Map));
          }
        }
        // Restore exact AUTOINCREMENT state, including sequences above max ID.
        await txn.delete('sqlite_sequence');
        for (final raw in data['sqlite_sequence'] as List) {
          await txn.insert(
              'sqlite_sequence', Map<String, Object?>.from(raw as Map));
        }
      });
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 ||
          integrity.single.values.single != 'ok' ||
          (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw StateError('QA integrity verification failed');
      }
      final restored = await db.transaction((txn) => _payload(txn));
      if (_sha(_canonical(restored)) != expectedChecksum) {
        throw StateError('QA roundtrip checksum mismatch');
      }
      return LocalBackupQaResult(
          scratchPath: path,
          checksum: expectedChecksum,
          tableCounts: {
            for (final table in _tables) table: (data[table] as List).length
          });
    } finally {
      await scratch.close();
      await scratchDir.delete(recursive: true);
    }
  }

  Map<String, dynamic> _validateEnvelope(String envelope) {
    // Validate all bytes/structure before even making a scratch directory.
    if (envelope.length > maxBytes || utf8.encode(envelope).length > maxBytes) {
      throw const FormatException('Backup size limit exceeded');
    }
    final root = jsonDecode(envelope);
    if (root is! Map<String, dynamic> ||
        !_keys(root, {'format', 'payload', 'checksum'}) ||
        root['format'] != _format ||
        root['payload'] is! Map<String, dynamic>) {
      throw const FormatException('Unsupported backup envelope');
    }
    final payload = root['payload'] as Map<String, dynamic>;
    if (!_keys(payload,
            {'schemaVersion', 'schema', 'schemaFingerprint', 'data'}) ||
        payload['schemaVersion'] != 9 ||
        root['checksum'] != _sha(_canonical(payload)) ||
        payload['schema'] is! Map<String, dynamic> ||
        payload['schemaFingerprint'] != _sha(_canonical(payload['schema'])) ||
        payload['data'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid schema/checksum');
    }
    final schema = payload['schema'] as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    if (!_keys(schema, _tables.toSet()) || !_keys(data, _tables.toSet())) {
      throw const FormatException('Unexpected tables');
    }
    var rowCount = 0;
    for (final table in _tables) {
      if (data[table] is! List ||
          schema[table] is! Map<String, dynamic> ||
          !_keys(schema[table] as Map, {'columns', 'sql'}) ||
          (schema[table] as Map)['columns'] is! List) {
        throw const FormatException('Invalid table contents');
      }
      final columns = <String>{};
      for (final column in (schema[table] as Map)['columns'] as List) {
        if (column is! Map ||
            column['name'] is! String ||
            !columns.add(column['name'] as String)) {
          throw const FormatException('Invalid columns');
        }
      }
      for (final row in data[table] as List) {
        rowCount++;
        if (rowCount > maxRows ||
            row is! Map<String, dynamic> ||
            !_keys(row, columns) ||
            row.values.any((v) =>
                v != null && v is! String && v is! int && v is! double) ||
            row.values.any((v) => v is double && !v.isFinite)) {
          throw const FormatException('Invalid data row');
        }
        if (table == 'sqlite_sequence' &&
            (!_sequenceTables.contains(row['name']) ||
                row['seq'] is! int ||
                row['seq'] < 0)) {
          throw const FormatException('Invalid sequence');
        }
      }
    }
    return payload;
  }

  /// Read-only inspection, including comparison with the current schema.
  Future<LocalBackupQaResult> inspectBackup(String envelope) async {
    final payload = _validateEnvelope(envelope);
    final db = await source.database;
    final schema = await db.transaction((txn) => _schema(txn));
    if (_canonical(schema) != _canonical(payload['schema'])) {
      throw const FormatException('Schema differs from installed v9');
    }
    final data = payload['data'] as Map;
    return LocalBackupQaResult(
        scratchPath: '',
        checksum: _sha(_canonical(payload)),
        tableCounts: {
          for (final table in _tables) table: (data[table] as List).length
        });
  }

  static bool _keys(Map value, Set<String> expected) =>
      value.length == expected.length && expected.every(value.containsKey);
  static Map<String, Object?> _sortData(Map<String, Object?> data) => {
        for (final entry in data.entries)
          entry.key: (List<Object?>.from(entry.value as List)
            ..sort((a, b) => _canonical(a).compareTo(_canonical(b))))
      };
  static String _canonical(Object? value) {
    Object? ordered(Object? v) {
      if (v is Map) {
        final keys = v.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: ordered(v[key])};
      }
      if (v is List) {
        return v.map(ordered).toList();
      }
      return v;
    }

    return jsonEncode(ordered(value));
  }

  // Dependency-free SHA-256 (UTF-8), solely an integrity checksum, not a MAC.
  static String _sha(String input) {
    const k = [
      0x428a2f98,
      0x71374491,
      0xb5c0fbcf,
      0xe9b5dba5,
      0x3956c25b,
      0x59f111f1,
      0x923f82a4,
      0xab1c5ed5,
      0xd807aa98,
      0x12835b01,
      0x243185be,
      0x550c7dc3,
      0x72be5d74,
      0x80deb1fe,
      0x9bdc06a7,
      0xc19bf174,
      0xe49b69c1,
      0xefbe4786,
      0x0fc19dc6,
      0x240ca1cc,
      0x2de92c6f,
      0x4a7484aa,
      0x5cb0a9dc,
      0x76f988da,
      0x983e5152,
      0xa831c66d,
      0xb00327c8,
      0xbf597fc7,
      0xc6e00bf3,
      0xd5a79147,
      0x06ca6351,
      0x14292967,
      0x27b70a85,
      0x2e1b2138,
      0x4d2c6dfc,
      0x53380d13,
      0x650a7354,
      0x766a0abb,
      0x81c2c92e,
      0x92722c85,
      0xa2bfe8a1,
      0xa81a664b,
      0xc24b8b70,
      0xc76c51a3,
      0xd192e819,
      0xd6990624,
      0xf40e3585,
      0x106aa070,
      0x19a4c116,
      0x1e376c08,
      0x2748774c,
      0x34b0bcb5,
      0x391c0cb3,
      0x4ed8aa4a,
      0x5b9cca4f,
      0x682e6ff3,
      0x748f82ee,
      0x78a5636f,
      0x84c87814,
      0x8cc70208,
      0x90befffa,
      0xa4506ceb,
      0xbef9a3f7,
      0xc67178f2
    ];
    final bytes = utf8.encode(input).toList();
    final bits = bytes.length * 8;
    bytes.add(128);
    while (bytes.length % 64 != 56) {
      bytes.add(0);
    }
    for (var i = 7; i >= 0; i--) {
      bytes.add((bits >> (8 * i)) & 255);
    }
    final h = [
      0x6a09e667,
      0xbb67ae85,
      0x3c6ef372,
      0xa54ff53a,
      0x510e527f,
      0x9b05688c,
      0x1f83d9ab,
      0x5be0cd19
    ];
    int r(int v, int n) => ((v >> n) | (v << (32 - n))) & 0xffffffff;
    for (var off = 0; off < bytes.length; off += 64) {
      final w = List<int>.filled(64, 0);
      for (var i = 0; i < 16; i++) {
        final j = off + 4 * i;
        w[i] = (bytes[j] << 24) |
            (bytes[j + 1] << 16) |
            (bytes[j + 2] << 8) |
            bytes[j + 3];
      }
      for (var i = 16; i < 64; i++) {
        final x = w[i - 15], y = w[i - 2];
        w[i] = (w[i - 16] +
                (r(x, 7) ^ r(x, 18) ^ (x >> 3)) +
                w[i - 7] +
                (r(y, 17) ^ r(y, 19) ^ (y >> 10))) &
            0xffffffff;
      }
      var a = h[0],
          b = h[1],
          c = h[2],
          d = h[3],
          e = h[4],
          f = h[5],
          g = h[6],
          hh = h[7];
      for (var i = 0; i < 64; i++) {
        final t1 = (hh +
                (r(e, 6) ^ r(e, 11) ^ r(e, 25)) +
                ((e & f) ^ ((~e) & g)) +
                k[i] +
                w[i]) &
            0xffffffff;
        final t2 =
            ((r(a, 2) ^ r(a, 13) ^ r(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) &
                0xffffffff;
        hh = g;
        g = f;
        f = e;
        e = (d + t1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & 0xffffffff;
      }
      final v = [a, b, c, d, e, f, g, hh];
      for (var i = 0; i < 8; i++) {
        h[i] = (h[i] + v[i]) & 0xffffffff;
      }
    }
    return h.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
  }
}
