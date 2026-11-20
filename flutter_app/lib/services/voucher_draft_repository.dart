import 'package:sqflite/sqflite.dart';
import '../models/erp_models.dart';
import '../models/voucher_draft.dart';
import 'local_database.dart';

/// Writes ONLY voucher_drafts. No ledger, stock, financial sequence or FX.
/// Schema lifecycle is owned by LocalDatabase migration/reset, not this class.
class VoucherDraftRepository {
  VoucherDraftRepository(this.database);
  final LocalDatabase database;

  static Future<void> createSchema(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS voucher_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      revision INTEGER NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('receipt','payment')),
      date TEXT NOT NULL, partyAccountId TEXT NOT NULL,
      cashAccountId TEXT NOT NULL, currency TEXT NOT NULL,
      amount REAL NOT NULL CHECK(amount > 0), note TEXT NOT NULL
    )
  ''');

  static Future<void> clearDrafts(DatabaseExecutor db) async {
    await db.delete('voucher_drafts');
  }

  Future<VoucherDraft> save(VoucherDraft draft) async {
    draft.validate();
    final db = await database.database;
    return db.transaction((txn) async {
      // Current schema has no active/deleted flag on accounts. Existence in the
      // authoritative accounts table is the only supported availability check.
      final party = await txn.query('accounts',
          where: 'id = ?', whereArgs: [draft.partyAccountId]);
      final cash = await txn
          .query('accounts', where: 'id = ?', whereArgs: [draft.cashAccountId]);
      if (party.length != 1 ||
          cash.length != 1 ||
          cash.single['isCashAccount'] != 1 ||
          party.single['isCashAccount'] != 0 ||
          party.single['currency'] != draft.currency.name ||
          cash.single['currency'] != draft.currency.name) {
        throw StateError(
            'اختر حسابين موجودين بالعملة نفسها، وحساب صندوق نقدي صالح');
      }
      final values = <String, Object?>{
        'revision': draft.revision + 1,
        'type': draft.type.name,
        'date': draft.date,
        'partyAccountId': draft.partyAccountId,
        'cashAccountId': draft.cashAccountId,
        'currency': draft.currency.name,
        'amount': draft.amount,
        'note': draft.note
      };
      final int id;
      if (draft.id == null) {
        id = await txn.insert('voucher_drafts', values);
      } else {
        id = draft.id!;
        final changed = await txn.update('voucher_drafts', values,
            where: 'id = ? AND revision = ? AND type = ?',
            whereArgs: [id, draft.revision, draft.type.name]);
        if (changed != 1) {
          throw StateError('المسودة تغيرت أو نوعها غير مطابق؛ أعد تحميلها');
        }
      }
      return VoucherDraft(
          id: id,
          revision: draft.revision + 1,
          type: draft.type,
          date: draft.date,
          partyAccountId: draft.partyAccountId,
          cashAccountId: draft.cashAccountId,
          currency: draft.currency,
          amount: draft.amount,
          note: draft.note);
    });
  }

  VoucherDraft _read(Map<String, Object?> row) => VoucherDraft(
      id: row['id'] as int,
      revision: row['revision'] as int,
      type: VoucherDraftType.values.byName(row['type'] as String),
      date: row['date'] as String,
      partyAccountId: row['partyAccountId'] as String,
      cashAccountId: row['cashAccountId'] as String,
      currency: CurrencyCode.values.byName(row['currency'] as String),
      amount: (row['amount'] as num).toDouble(),
      note: row['note'] as String);

  Future<VoucherDraft?> get(int id) async {
    final db = await database.database;
    final rows =
        await db.query('voucher_drafts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _read(rows.single);
  }

  Future<List<VoucherDraft>> list({VoucherDraftType? type}) async {
    final db = await database.database;
    final rows = await db.query('voucher_drafts',
        where: type == null ? null : 'type = ?',
        whereArgs: type == null ? null : [type.name],
        orderBy: 'date DESC, id DESC');
    return List.unmodifiable(rows.map(_read));
  }
}
