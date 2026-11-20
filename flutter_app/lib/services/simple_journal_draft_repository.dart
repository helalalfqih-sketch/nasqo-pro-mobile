import 'package:sqflite/sqflite.dart';
import '../models/erp_models.dart';
import '../models/simple_journal_draft.dart';
import 'local_database.dart';

/// Writes only simple_journal_drafts. No balance, stock, cash movement, FX or posting.
class SimpleJournalDraftRepository {
  SimpleJournalDraftRepository(this.database);
  final LocalDatabase database;
  static Future<void> createSchema(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS simple_journal_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT, revision INTEGER NOT NULL CHECK(revision > 0),
      date TEXT NOT NULL, debitAccountId TEXT NOT NULL, creditAccountId TEXT NOT NULL,
      currency TEXT NOT NULL, amount REAL NOT NULL CHECK(amount > 0), note TEXT NOT NULL,
      CHECK(debitAccountId <> creditAccountId)
    )
  ''');
  static Future<void> clearDrafts(DatabaseExecutor db) async {
    await db.delete('simple_journal_drafts');
  }

  Future<SimpleJournalDraft> save(SimpleJournalDraft draft) async {
    draft.validate();
    final db = await database.database;
    return db.transaction((txn) async {
      for (final id in [draft.debitAccountId, draft.creditAccountId]) {
        final account =
            await txn.query('accounts', where: 'id = ?', whereArgs: [id]);
        // Account schema has no separate active flag: require current persisted
        // existence, matching denomination at each save (any account category).
        if (account.length != 1 ||
            account.single['currency'] != draft.currency.name) {
          throw StateError('يلزم حسابان موجودان بالعملة نفسها');
        }
      }
      final values = <String, Object?>{
        'revision': draft.revision + 1,
        'date': draft.date,
        'debitAccountId': draft.debitAccountId,
        'creditAccountId': draft.creditAccountId,
        'currency': draft.currency.name,
        'amount': draft.amount,
        'note': draft.note
      };
      final int id;
      if (draft.id == null) {
        id = await txn.insert('simple_journal_drafts', values);
      } else {
        id = draft.id!;
        final changed = await txn.update('simple_journal_drafts', values,
            where: 'id = ? AND revision = ?', whereArgs: [id, draft.revision]);
        if (changed != 1) {
          throw StateError('المسودة تغيرت أو غير موجودة؛ أعد تحميلها');
        }
      }
      return SimpleJournalDraft(
          id: id,
          revision: draft.revision + 1,
          date: draft.date,
          debitAccountId: draft.debitAccountId,
          creditAccountId: draft.creditAccountId,
          currency: draft.currency,
          amount: draft.amount,
          note: draft.note);
    });
  }

  SimpleJournalDraft _read(Map<String, Object?> row) => SimpleJournalDraft(
      id: row['id'] as int,
      revision: row['revision'] as int,
      date: row['date'] as String,
      debitAccountId: row['debitAccountId'] as String,
      creditAccountId: row['creditAccountId'] as String,
      currency: CurrencyCode.values.byName(row['currency'] as String),
      amount: (row['amount'] as num).toDouble(),
      note: row['note'] as String);
  Future<SimpleJournalDraft?> get(int id) async {
    final db = await database.database;
    final rows = await db
        .query('simple_journal_drafts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _read(rows.single);
  }

  Future<List<SimpleJournalDraft>> list() async {
    final db = await database.database;
    return List.unmodifiable(
        (await db.query('simple_journal_drafts', orderBy: 'date DESC,id DESC'))
            .map(_read));
  }
}
