import '../models/erp_models.dart';

/// Reference: NASQO-PRO-ERP/src/accounting.ts at
/// 5c9a6850fda37117bd4c6c408181174fab8e3ca6,
/// computeAccountGroupsSummary (not income statement / COGS).
///
/// The Flutter model has no groupId or custom group records. These are category
/// buckets, NOT restored web groups. It also lacks rawDain/rawMadin,
/// settledOnReceipt and counterpartAccountId. This implements only the web
/// group function's ordinary primary-entry branch; it must not be advertised
/// as full imported-data parity. In particular, cash accounts are NOT washed
/// here (the separate web computeAccountSummary function does that).
class HomeBalanceGroup {
  const HomeBalanceGroup({
    required this.category,
    required this.currency,
    required this.debitTotal,
    required this.creditTotal,
    required this.accountCount,
  });

  final AccountCategory category;
  final CurrencyCode currency;
  final double debitTotal;
  final double creditTotal;

  /// Counts unique accounts in the category, regardless of currency, like web.
  final int accountCount;
  double get netDebitMinusCredit => debitTotal - creditTotal;
  double get magnitude => netDebitMinusCredit.abs();

  /// Web's display threshold is 0.005; retain the unrounded amount separately.
  String get balanceLabel => netDebitMinusCredit.abs() < 0.005
      ? 'متزن'
      : netDebitMinusCredit > 0
          ? 'عليه'
          : 'له';
}

/// Single-currency nominal balances. A required currency deliberately prevents
/// reproducing the web's unsafe mixed-currency "all" sum. No rate conversion:
/// exchangeRate is irrelevant to this web group function. Account currency
/// filters the opening only; each entry is filtered by its own currency.
/// Inputs are expected to be unique account records with finite ledger amounts,
/// as in the persisted model; neither input collection is mutated.
List<HomeBalanceGroup> computeHomeBalanceGroups(
  List<AccountRecord> accounts,
  List<LedgerEntryRecord> entries, {
  required CurrencyCode currency,
}) {
  final byId = {for (final account in accounts) account.id: account};
  final debit = {for (final category in AccountCategory.values) category: 0.0};
  final credit = {for (final category in AccountCategory.values) category: 0.0};
  final count = {for (final category in AccountCategory.values) category: 0};
  for (final account in byId.values) {
    count[account.category] = count[account.category]! + 1;
    if (account.currency != currency || account.openingBalance <= 0) continue;
    final target =
        account.openingDirection == EntryDirection.debit ? debit : credit;
    target[account.category] =
        target[account.category]! + account.openingBalance;
  }
  for (final entry in entries) {
    if (entry.deleted ||
        entry.kind == LedgerKind.quote ||
        entry.kind == LedgerKind.order ||
        entry.currency != currency) {
      continue;
    }
    final account = byId[entry.accountId];
    if (account == null) continue;
    final target = entry.direction == EntryDirection.debit ? debit : credit;
    target[account.category] = target[account.category]! + entry.amount;
  }
  return List.unmodifiable([
    for (final category in AccountCategory.values)
      HomeBalanceGroup(
        category: category,
        currency: currency,
        debitTotal: debit[category]!,
        creditTotal: credit[category]!,
        accountCount: count[category]!,
      ),
  ]);
}
