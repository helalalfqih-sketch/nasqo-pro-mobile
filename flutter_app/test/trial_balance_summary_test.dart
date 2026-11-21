import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/trial_balance_summary.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  test(
      'trial filters include boundary dates, exclude drafts and keep inventory in base currency',
      () {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    c.accounts
      ..clear()
      ..add(const AccountRecord(
          id: 's', name: 'عميل', category: AccountCategory.clients));
    LedgerEntryRecord entry(int id, CurrencyCode cur, String day, double amount,
            {LedgerKind kind = LedgerKind.invoice, bool deleted = false}) =>
        LedgerEntryRecord(
            id: 'e$id',
            accountId: 's',
            accountName: 'عميل',
            kind: kind,
            typeLabel: 'بيع',
            payment: PaymentMethod.cash,
            direction: EntryDirection.debit,
            amount: amount,
            currency: cur,
            entryNumber: id,
            entryDate: day,
            deleted: deleted);
    c.ledger
      ..clear()
      ..addAll([
        entry(1, CurrencyCode.sar, '2026-11-20', 31),
        entry(2, CurrencyCode.usd, '2026-11-21', 7),
        entry(3, CurrencyCode.sar, '2026-11-21', 100, kind: LedgerKind.quote),
        entry(4, CurrencyCode.sar, '2026-11-21', 100, deleted: true)
      ]);
    c.inventory
      ..clear()
      ..add(const InventoryItemRecord(
          id: 'i', name: 'صنف', unit: 'قطعة', quantity: 2, avgCost: 8));
    final base = trialBalanceSummary(c, CurrencyCode.sar,
        from: '2026-11-20', through: '2026-11-20');
    expect([base.debit, base.credit, base.sales, base.inventory, base.profit],
        [31, 0, 31, 16, 47]);
    final usd = trialBalanceSummary(c, CurrencyCode.usd);
    expect([usd.sales, usd.debit, usd.cash, usd.inventory, usd.profit],
        [7, 7, 7, null, null]);
    expect(
        trialBalanceSummary(c, CurrencyCode.sar, from: '2026-11-21').sales, 0);
  });
  test('a transfer between two linked cash accounts does not create cash', () async {
    final c = ErpController(autoInitDb: false);
    addTearDown(c.dispose);
    c.accounts
      ..clear()
      ..addAll(const [
        AccountRecord(id: 'from', name: 'صندوق أ', category: AccountCategory.transfers, isCashAccount: true),
        AccountRecord(id: 'to', name: 'صندوق ب', category: AccountCategory.transfers, isCashAccount: true),
      ]);
    c.ledger.clear();
    await c.postLocalEntry(accountId: 'from', cashboxAccountId: 'to',
        requestId: 'cash-to-cash', kind: LedgerKind.voucher,
        direction: EntryDirection.credit, payment: PaymentMethod.cash,
        amount: 17, currency: CurrencyCode.sar);
    final report = trialBalanceSummary(c, CurrencyCode.sar);
    expect([report.debit, report.credit, report.cash], [17, 17, 0]);
  });
}
