import 'cash_sale_settlement.dart' show linkedCashVoucherIds;
import '../models/erp_models.dart';
import '../state/erp_controller.dart';

/// Uses recorded amounts in a single denomination. Native purchase posting
/// values catalog stock at unit cost converted to the workspace's base currency.
class TrialBalanceSummary {
  const TrialBalanceSummary(this.currency, this.debit, this.credit, this.cash,
      this.sales, this.purchases, this.inventory);
  final CurrencyCode currency;
  final double debit, credit, cash, sales, purchases;
  final double? inventory;
  double get net => debit - credit;
  double? get profit =>
      inventory == null ? null : sales + inventory! - purchases;
  double get liquidity => credit > 0 ? (cash / credit * 1000).round() / 10 : 0;
  String get result => net.abs() < 0.005
      ? 'متزن'
      : net > 0
          ? 'فائض'
          : 'عجز';
  Map<String, Object?> toJson() => {
        'currency': currency.label,
        'totalDebitAccounts': debit,
        'totalCreditAccounts': credit,
        'cashTotal': cash,
        'netBalance': net,
        'resultLabel': result,
        'liquidityRatioPercent': liquidity,
        'salesTotal': sales,
        'purchasesTotal': purchases,
        'inventoryValue': inventory,
        'netProfit': profit,
      };
}

TrialBalanceSummary trialBalanceSummary(ErpController c, CurrencyCode currency,
    {String from = '', String through = ''}) {
  final balances = <String, double>{
    for (final a in c.accounts)
      a.id: a.currency == currency && a.openingBalance > 0
          ? a.openingBalance *
              (a.openingDirection == EntryDirection.debit ? 1 : -1)
          : 0
  };
  // A native cash voucher records both the counterparty and the cashbox.
  // For a linked pair only actual cash accounts contribute to the cash total.
  final cashAccounts = {for (final a in c.accounts) if (a.isCashAccount) a.id};
  final linked = linkedCashVoucherIds(c.ledger);
  var cash = 0.0, sales = 0.0, purchases = 0.0;
  for (final e in c.ledger) {
    if (e.deleted ||
        e.currency != currency ||
        e.kind == LedgerKind.quote ||
        e.kind == LedgerKind.order) {
      continue;
    }
    if ((from.isNotEmpty && e.entryDate.compareTo(from) < 0) ||
        (through.isNotEmpty && e.entryDate.compareTo(through) > 0)) {
      continue;
    }
    final debit = e.direction == EntryDirection.debit;
    final side = c.restoredGroups?.sides[e.id];
    final settled = c.restoredGroups?.settledEntries.contains(e.id) ?? false;
    if (!settled) {
      final change = (side?.debit ?? (debit ? e.amount : 0.0)) -
          (side?.credit ?? (debit ? 0.0 : e.amount));
      balances[e.accountId] = (balances[e.accountId] ?? 0) + change;
    }
    if (linked.contains(e.id)) {
      if (cashAccounts.contains(e.accountId)) cash += debit ? e.amount : -e.amount;
    } else if (e.payment == PaymentMethod.cash || settled) {
      final type = c.restoredGroups?.documentTypes[e.id];
      final cashDocument = [
        LedgerKind.voucher,
        LedgerKind.transfer,
        LedgerKind.simpleEntry
      ].contains(e.kind);
      final inflow = cashDocument
          ? !debit
          : type == null
              ? debit
              : [2, 7, 5].contains(type);
      cash += inflow ? e.amount : -e.amount;
    }
    if (e.kind == LedgerKind.invoice) {
      if (e.typeLabel.contains('بيع') || debit) {
        sales += e.amount;
      } else {
        purchases += e.amount;
      }
    } else if (e.kind == LedgerKind.returnEntry) {
      if (e.typeLabel.contains('مبيعات') || !debit) {
        sales -= e.amount;
      } else {
        purchases -= e.amount;
      }
    }
  }
  final debit =
      balances.values.where((v) => v > 0.005).fold<double>(0, (s, v) => s + v);
  final credit =
      balances.values.where((v) => v < -0.005).fold<double>(0, (s, v) => s - v);
  final inventory = c.inventory
      .where((i) => i.avgCost > 0)
      .fold<double>(0, (s, i) => s + i.quantity * i.avgCost);
  final valuationAvailable = currency == c.defaultCurrency ||
      !c.inventory.any((item) => item.quantity != 0 && item.avgCost > 0);
  return TrialBalanceSummary(currency, debit, credit, cash < 0 ? 0 : cash,
      sales, purchases, valuationAvailable ? inventory : null);
}
