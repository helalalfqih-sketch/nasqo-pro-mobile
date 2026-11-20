import 'package:sqflite/sqflite.dart';
import '../models/erp_models.dart';
import '../models/fx_draft.dart';
import 'local_database.dart';

/// Writes only fx_drafts, never balances, financial entries or inventory.
class FxDraftRepository {
  FxDraftRepository(this.database);
  final LocalDatabase database;
  static Future<void> createSchema(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS fx_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT, revision INTEGER NOT NULL CHECK(revision > 0),
      date TEXT NOT NULL, sourceCashId TEXT NOT NULL, destinationCashId TEXT NOT NULL,
      sourceCurrency TEXT NOT NULL, destinationCurrency TEXT NOT NULL,
      sourceAmount REAL NOT NULL CHECK(sourceAmount > 0),
      destinationAmount REAL NOT NULL CHECK(destinationAmount > 0), note TEXT NOT NULL,
      CHECK(sourceCashId <> destinationCashId), CHECK(sourceCurrency <> destinationCurrency)
    )
  ''');
  static Future<void> clearDrafts(DatabaseExecutor db) async {
    await db.delete('fx_drafts');
  }

  Future<FxDraft> save(FxDraft draft) async {
    draft.validate();
    final db = await database.database;
    return db.transaction((txn) async {
      for (final side in [
        (draft.sourceCashId, draft.sourceCurrency),
        (draft.destinationCashId, draft.destinationCurrency)
      ]) {
        final rows =
            await txn.query('accounts', where: 'id = ?', whereArgs: [side.$1]);
        // The account model has no separate active flag; require current
        // persisted existence, cash designation and matching currency.
        if (rows.length != 1 ||
            rows.single['isCashAccount'] != 1 ||
            rows.single['currency'] != side.$2.name) {
          throw StateError('اختر صندوقين موجودين بعملتين مختلفتين مطابقتين');
        }
      }
      final values = <String, Object?>{
        'revision': draft.revision + 1,
        'date': draft.date,
        'sourceCashId': draft.sourceCashId,
        'destinationCashId': draft.destinationCashId,
        'sourceCurrency': draft.sourceCurrency.name,
        'destinationCurrency': draft.destinationCurrency.name,
        'sourceAmount': draft.sourceAmount,
        'destinationAmount': draft.destinationAmount,
        'note': draft.note
      };
      final int id;
      if (draft.id == null) {
        id = await txn.insert('fx_drafts', values);
      } else {
        id = draft.id!;
        if (await txn.update('fx_drafts', values,
                where: 'id = ? AND revision = ?',
                whereArgs: [id, draft.revision]) !=
            1) {
          throw StateError('المسودة تغيرت أو غير موجودة؛ أعد تحميلها');
        }
      }
      return FxDraft(
          id: id,
          revision: draft.revision + 1,
          date: draft.date,
          sourceCashId: draft.sourceCashId,
          destinationCashId: draft.destinationCashId,
          sourceCurrency: draft.sourceCurrency,
          destinationCurrency: draft.destinationCurrency,
          sourceAmount: draft.sourceAmount,
          destinationAmount: draft.destinationAmount,
          note: draft.note);
    });
  }

  FxDraft _read(Map<String, Object?> r) => FxDraft(
      id: r['id'] as int,
      revision: r['revision'] as int,
      date: r['date'] as String,
      sourceCashId: r['sourceCashId'] as String,
      destinationCashId: r['destinationCashId'] as String,
      sourceCurrency: CurrencyCode.values.byName(r['sourceCurrency'] as String),
      destinationCurrency:
          CurrencyCode.values.byName(r['destinationCurrency'] as String),
      sourceAmount: (r['sourceAmount'] as num).toDouble(),
      destinationAmount: (r['destinationAmount'] as num).toDouble(),
      note: r['note'] as String);
  Future<FxDraft?> get(int id) async {
    final db = await database.database;
    final rows = await db.query('fx_drafts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _read(rows.single);
  }

  Future<List<FxDraft>> list() async {
    final db = await database.database;
    return List.unmodifiable(
        (await db.query('fx_drafts', orderBy: 'date DESC,id DESC')).map(_read));
  }
}
