import 'package:sqflite/sqflite.dart';
import '../models/erp_models.dart';
import '../models/cash_transfer_draft.dart';
import 'local_database.dart';

/// Writes only cash_transfer_drafts. No cash balance, fees, FX or posting.
class CashTransferDraftRepository {
  CashTransferDraftRepository(this.database);
  final LocalDatabase database;
  static Future<void> createSchema(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS cash_transfer_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT, revision INTEGER NOT NULL CHECK(revision > 0),
      date TEXT NOT NULL, sourceCashId TEXT NOT NULL, destinationCashId TEXT NOT NULL,
      currency TEXT NOT NULL, amount REAL NOT NULL CHECK(amount > 0), note TEXT NOT NULL,
      CHECK(sourceCashId <> destinationCashId)
    )
  ''');
  static Future<void> clearDrafts(DatabaseExecutor db) async {
    await db.delete('cash_transfer_drafts');
  }

  Future<CashTransferDraft> save(CashTransferDraft draft) async {
    draft.validate();
    final db = await database.database;
    return db.transaction((txn) async {
      for (final id in [draft.sourceCashId, draft.destinationCashId]) {
        final account =
            await txn.query('accounts', where: 'id = ?', whereArgs: [id]);
        // Account schema has no separate active flag: require current persisted
        // existence, cash designation and matching denomination at each save.
        if (account.length != 1 ||
            account.single['isCashAccount'] != 1 ||
            account.single['currency'] != draft.currency.name) {
          throw StateError('يلزم صندوقان موجودان بالعملة نفسها');
        }
      }
      final values = <String, Object?>{
        'revision': draft.revision + 1,
        'date': draft.date,
        'sourceCashId': draft.sourceCashId,
        'destinationCashId': draft.destinationCashId,
        'currency': draft.currency.name,
        'amount': draft.amount,
        'note': draft.note
      };
      final int id;
      if (draft.id == null) {
        id = await txn.insert('cash_transfer_drafts', values);
      } else {
        id = draft.id!;
        final changed = await txn.update('cash_transfer_drafts', values,
            where: 'id = ? AND revision = ?', whereArgs: [id, draft.revision]);
        if (changed != 1) {
          throw StateError('المسودة تغيرت أو غير موجودة؛ أعد تحميلها');
        }
      }
      return CashTransferDraft(
          id: id,
          revision: draft.revision + 1,
          date: draft.date,
          sourceCashId: draft.sourceCashId,
          destinationCashId: draft.destinationCashId,
          currency: draft.currency,
          amount: draft.amount,
          note: draft.note);
    });
  }

  CashTransferDraft _read(Map<String, Object?> row) => CashTransferDraft(
      id: row['id'] as int,
      revision: row['revision'] as int,
      date: row['date'] as String,
      sourceCashId: row['sourceCashId'] as String,
      destinationCashId: row['destinationCashId'] as String,
      currency: CurrencyCode.values.byName(row['currency'] as String),
      amount: (row['amount'] as num).toDouble(),
      note: row['note'] as String);
  Future<CashTransferDraft?> get(int id) async {
    final db = await database.database;
    final rows = await db
        .query('cash_transfer_drafts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _read(rows.single);
  }

  Future<List<CashTransferDraft>> list() async {
    final db = await database.database;
    return List.unmodifiable(
        (await db.query('cash_transfer_drafts', orderBy: 'date DESC,id DESC'))
            .map(_read));
  }
}
