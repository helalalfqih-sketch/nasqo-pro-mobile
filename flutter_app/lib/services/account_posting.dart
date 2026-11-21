import '../models/erp_models.dart';
import 'cash_sale_settlement.dart';
import 'web_backup.dart';

/// Native cash postings already contain both explicit ledger legs. Applying
/// legacy implicit settlement to one of these rows would erase its cash effect.
class AccountPosting {
  AccountPosting(Iterable<LedgerEntryRecord> entries, this.archive) {
    final byId = {for (final e in entries) e.id:e};
    for (final leg in entries) {
      String? primary;
      if (isCashSaleSettlement(leg)) {
        primary = leg.id.substring(0,leg.id.lastIndexOf('/'));
      } else if (leg.id.startsWith('local_') && leg.id.endsWith('_counter')) {
        primary = leg.id.substring(0,leg.id.length-'_counter'.length);
      }
      final source = byId[primary];
      if (source != null && source.entryNumber == leg.entryNumber &&
          source.currency == leg.currency && source.amount == leg.amount) {
        _explicit.add(source.id);
        _explicit.add(leg.id);
      }
    }
  }
  final RestoredGroups? archive;
  final _explicit = <String>{};

  ({double debit,double credit})? forAccount(AccountRecord account, LedgerEntryRecord entry) {
    if (entry.deleted) return null;
    final primary = account.id == entry.accountId;
    if (!primary && archive?.counterparts[entry.id] != account.id) return null;
    if (entry.kind == LedgerKind.quote || entry.kind == LedgerKind.order) {
      return (debit:0.0,credit:0.0);
    }
    if (primary && !_explicit.contains(entry.id) &&
        ((archive?.settledEntries.contains(entry.id) ?? false) ||
         (archive?.sides[entry.id] == null && account.isCashAccount && entry.payment == PaymentMethod.cash))) {
      return (debit:entry.amount,credit:entry.amount);
    }
    final credit = (entry.direction == EntryDirection.credit) == primary;
    return (debit:credit?0.0:entry.amount,credit:credit?entry.amount:0.0);
  }
}
