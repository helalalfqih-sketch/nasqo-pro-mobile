import 'package:intl/intl.dart';
import 'cash_sale_settlement.dart';
import '../models/erp_models.dart';

class AccountSummary {
  const AccountSummary({
    required this.debitTotal,
    required this.creditTotal,
    required this.netBalance,
  });

  final double debitTotal;
  final double creditTotal;
  final double netBalance;
}

class TrialBalanceRow {
  const TrialBalanceRow({
    required this.accountId,
    required this.codeNumber,
    required this.accountName,
    required this.category,
    required this.debitTurnover,
    required this.creditTurnover,
    required this.closingDebit,
    required this.closingCredit,
  });

  final String accountId;
  final int codeNumber;
  final String accountName;
  final AccountCategory category;
  final double debitTurnover;
  final double creditTurnover;
  final double closingDebit;
  final double closingCredit;
}

class TrialBalanceReport {
  const TrialBalanceReport({
    required this.rows,
    required this.totalDebitTurnover,
    required this.totalCreditTurnover,
    required this.totalClosingDebit,
    required this.totalClosingCredit,
  });

  final List<TrialBalanceRow> rows;
  final double totalDebitTurnover;
  final double totalCreditTurnover;
  final double totalClosingDebit;
  final double totalClosingCredit;
}

class IncomeStatementReport {
  const IncomeStatementReport({
    required this.salesRevenue,
    required this.salesReturns,
    required this.netSales,
    required this.cogs,
    required this.grossProfit,
    required this.totalOperatingExpenses,
    required this.netProfit,
  });

  final double salesRevenue;
  final double salesReturns;
  final double netSales;
  final double cogs;
  final double grossProfit;
  final double totalOperatingExpenses;
  final double netProfit;
}

class VatSummaryReport {
  const VatSummaryReport({
    required this.taxableSales,
    required this.outputVat,
    required this.taxablePurchases,
    required this.inputVat,
    required this.netVatPayable,
  });

  final double taxableSales;
  final double outputVat;
  final double taxablePurchases;
  final double inputVat;
  final double netVatPayable;
}

class AccountingEngine {
  static const String _arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  static const String _persianIndic = '۰۱۲۳۴۵۶۷۸۹';

  static double parseArabicNumber(String raw) {
    if (raw.trim().isEmpty) return 0;
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      final arIdx = _arabicIndic.indexOf(ch);
      if (arIdx >= 0) {
        buffer.write(arIdx);
        continue;
      }
      final faIdx = _persianIndic.indexOf(ch);
      if (faIdx >= 0) {
        buffer.write(faIdx);
        continue;
      }
      if (ch == '٫') {
        buffer.write('.');
        continue;
      }
      if (ch == ',' || ch == '٬' || ch.trim().isEmpty) {
        continue;
      }
      buffer.write(ch);
    }
    return double.tryParse(buffer.toString()) ?? 0;
  }

  static String formatAmount(double value) {
    final safe = value.isFinite ? value : 0.0;
    final rounded = (safe * 100).roundToDouble() / 100.0;
    return NumberFormat('#,##0.##', 'en_US').format(rounded);
  }

  static AccountSummary computeAccountSummary(
    AccountRecord account,
    List<LedgerEntryRecord> entries,
  ) {
    double debit = account.openingDirection == EntryDirection.debit
        ? account.openingBalance
        : 0;
    double credit = account.openingDirection == EntryDirection.credit
        ? account.openingBalance
        : 0;

    for (final entry in entries) {
      if (entry.deleted || entry.accountId != account.id) continue;
      if (entry.kind == LedgerKind.quote || entry.kind == LedgerKind.order) {
        continue;
      }
      final amt = entry.amount * entry.exchangeRate;
      if (entry.direction == EntryDirection.debit) {
        debit += amt;
      } else {
        credit += amt;
      }
    }

    return AccountSummary(
      debitTotal: debit,
      creditTotal: credit,
      netBalance: credit - debit,
    );
  }

  static TrialBalanceReport computeTrialBalance(
    List<AccountRecord> accounts,
    List<LedgerEntryRecord> entries,
  ) {
    final rows = <TrialBalanceRow>[];
    double totalDebit = 0;
    double totalCredit = 0;
    double totalClosingDebit = 0;
    double totalClosingCredit = 0;

    for (final acc in accounts) {
      final s = computeAccountSummary(acc, entries);
      final netSigned = s.creditTotal - s.debitTotal;
      final closingDebit = netSigned < 0 ? netSigned.abs() : 0.0;
      final closingCredit = netSigned > 0 ? netSigned : 0.0;

      rows.add(TrialBalanceRow(
        accountId: acc.id,
        codeNumber: acc.codeNumber,
        accountName: acc.name,
        category: acc.category,
        debitTurnover: s.debitTotal,
        creditTurnover: s.creditTotal,
        closingDebit: closingDebit,
        closingCredit: closingCredit,
      ));

      totalDebit += s.debitTotal;
      totalCredit += s.creditTotal;
      totalClosingDebit += closingDebit;
      totalClosingCredit += closingCredit;
    }

    return TrialBalanceReport(
      rows: rows,
      totalDebitTurnover: totalDebit,
      totalCreditTurnover: totalCredit,
      totalClosingDebit: totalClosingDebit,
      totalClosingCredit: totalClosingCredit,
    );
  }

  static IncomeStatementReport computeIncomeStatement(
    List<AccountRecord> accounts,
    List<LedgerEntryRecord> entries,
  ) {
    final accountMap = {for (final a in accounts) a.id: a};
    double salesRevenue = 0;
    double salesReturns = 0;
    double cogs = 0;
    double operatingExpenses = 0;

    for (final acc in accounts) {
      if (acc.category == AccountCategory.sales && acc.openingBalance > 0) {
        salesRevenue += acc.openingBalance;
      }
    }

    for (final entry in entries) {
      if (entry.deleted || isCashSaleSettlement(entry)) continue;
      if (entry.kind == LedgerKind.quote || entry.kind == LedgerKind.order) {
        continue;
      }
      final amt = entry.amount * entry.exchangeRate;
      if (amt <= 0) continue;

      final acc = accountMap[entry.accountId];
      final isSale = (entry.kind == LedgerKind.returnEntry && entry.typeLabel == 'مرتجع مبيعات') ||
          acc?.category == AccountCategory.sales ||
          (entry.kind == LedgerKind.invoice &&
              entry.direction == EntryDirection.debit);

      if (isSale) {
        if (entry.kind == LedgerKind.returnEntry) {
          salesReturns += amt;
        } else {
          salesRevenue += amt;
        }
        continue;
      }

      if (acc?.category == AccountCategory.purchases ||
          (entry.kind == LedgerKind.invoice &&
              entry.direction == EntryDirection.credit)) {
        if (entry.kind == LedgerKind.returnEntry) {
          cogs = (cogs - amt).clamp(0, double.infinity);
        } else {
          cogs += amt;
        }
        continue;
      }

      if (acc?.category == AccountCategory.shop ||
          acc?.category == AccountCategory.employees ||
          (entry.kind == LedgerKind.voucher &&
              entry.direction == EntryDirection.debit)) {
        operatingExpenses += amt;
      }
    }

    final netSales = (salesRevenue - salesReturns).clamp(0.0, double.infinity);
    final grossProfit = netSales - cogs;
    final netProfit = grossProfit - operatingExpenses;

    return IncomeStatementReport(
      salesRevenue: salesRevenue,
      salesReturns: salesReturns,
      netSales: netSales,
      cogs: cogs,
      grossProfit: grossProfit,
      totalOperatingExpenses: operatingExpenses,
      netProfit: netProfit,
    );
  }

  static VatSummaryReport computeVatSummary(
    List<AccountRecord> accounts,
    List<LedgerEntryRecord> entries, {
    double vatRate = 0.15,
  }) {
    final accountMap = {for (final a in accounts) a.id: a};
    double taxableSales = 0;
    double taxablePurchases = 0;

    for (final entry in entries) {
      if (entry.deleted) continue;
      if (entry.kind != LedgerKind.invoice &&
          entry.kind != LedgerKind.returnEntry) {
        continue;
      }
      final amt = entry.amount * entry.exchangeRate;
      final acc = accountMap[entry.accountId];
      final isSale = (entry.kind == LedgerKind.returnEntry && entry.typeLabel == 'مرتجع مبيعات') ||
          acc?.category == AccountCategory.sales ||
          (entry.direction == EntryDirection.debit && entry.typeLabel != 'مردود شراء');
      if (isSale) {
        taxableSales += entry.kind == LedgerKind.returnEntry ? -amt : amt;
      } else {
        taxablePurchases += entry.kind == LedgerKind.returnEntry ? -amt : amt;
      }
    }

    taxableSales = taxableSales < 0 ? 0 : taxableSales;
    taxablePurchases = taxablePurchases < 0 ? 0 : taxablePurchases;
    final outputVat = ((taxableSales * vatRate) * 100).roundToDouble() / 100;
    final inputVat = ((taxablePurchases * vatRate) * 100).roundToDouble() / 100;

    return VatSummaryReport(
      taxableSales: taxableSales,
      outputVat: outputVat,
      taxablePurchases: taxablePurchases,
      inputVat: inputVat,
      netVatPayable: ((outputVat - inputVat) * 100).roundToDouble() / 100,
    );
  }

  static double computeInventoryValue(List<InventoryItemRecord> items) {
    return items.fold(0.0, (sum, item) => sum + item.quantity * item.avgCost);
  }

  static double computeWeightedAverageCost(
    double currentQty,
    double currentAvgCost,
    double addedQty,
    double addedCost,
  ) {
    final totalQty = currentQty + addedQty;
    if (totalQty <= 0) return addedCost;
    return ((currentQty * currentAvgCost) + (addedQty * addedCost)) / totalQty;
  }

  static double computePurchaseOrderTotal(ErpPurchaseOrder po) {
    return po.lines.fold(0.0, (sum, l) => sum + l.quantity * l.unitCost);
  }

  static double computeTotalNetPayroll(List<ErpEmployeeProfile> employees) {
    return employees
        .where((e) => e.status == 'active')
        .fold(0.0, (sum, e) => sum + e.netSalary);
  }
}
