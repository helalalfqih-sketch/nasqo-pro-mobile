import 'cash_sale_settlement.dart' show linkedCashVoucherIds;
import '../models/erp_models.dart';
import '../state/erp_controller.dart';

class AccountAmounts {
  double debit = 0, credit = 0;
  int entries = 0;

  void add(double amount, bool isCredit) {
    if (isCredit) {
      credit += amount;
    } else {
      debit += amount;
    }
  }

  Map<String, Object> toJson() {
    final net = credit - debit;
    return {
      'debitTotal': debit,
      'creditTotal': credit,
      'netBalance': net.abs(),
      'tone': net.abs() < .005
          ? 'neutral'
          : net > 0
              ? 'credit'
              : 'debit',
      'entryCount': entries,
    };
  }
}

Map<(String, CurrencyCode), AccountAmounts> accountAmountsByCurrency(
    ErpController controller, Iterable<AccountRecord> records,
    {String period = 'الكل'}) {
  final accounts = {for (final a in records) a.id: a};
  final result = <(String, CurrencyCode), AccountAmounts>{};
  AccountAmounts bucket(String id, CurrencyCode c) =>
      result.putIfAbsent((id, c), AccountAmounts.new);
  for (final a in accounts.values) {
    if (a.openingBalance > 0) {
      bucket(a.id, a.currency)
          .add(a.openingBalance, a.openingDirection == EntryDirection.credit);
    }
  }
  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final start = switch (period) {
    'يومي' => today,
    'شهري' => '${today.substring(0, 7)}-01',
    'سنوي' => '${today.substring(0, 4)}-01-01',
    _ => '',
  };
  final archive = controller.restoredGroups;
  final linkedVouchers = linkedCashVoucherIds(controller.ledger);
  for (final e in controller.ledger) {
    if (e.deleted ||
        (start.isNotEmpty &&
            (e.entryDate.compareTo(start) < 0 ||
                e.entryDate.compareTo(today) > 0))) {
      continue;
    }
    final primary = accounts[e.accountId];
    final other = accounts[archive?.counterparts[e.id]];
    final posting = e.kind != LedgerKind.quote && e.kind != LedgerKind.order;
    final credit = e.direction == EntryDirection.credit;
    if (primary != null) {
      final b = bucket(primary.id, e.currency);
      b.entries++;
      if (posting) {
        final wash = (archive?.settledEntries.contains(e.id) ?? false) ||
            (archive?.sides[e.id] == null &&
                primary.isCashAccount &&
                !linkedVouchers.contains(e.id) &&
                e.payment == PaymentMethod.cash);
        b.add(e.amount, credit);
        if (wash) b.add(e.amount, !credit);
      }
    }
    if (other != null && other.id != primary?.id) {
      final b = bucket(other.id, e.currency);
      b.entries++;
      if (posting) b.add(e.amount, !credit);
    }
  }
  return result;
}
