import '../models/erp_models.dart';

/// The invoice or return remains on the customer's statement. The linked
/// settlement clears that amount and records the cashbox receipt or refund.
List<LedgerEntryRecord> cashSaleSettlement(LedgerEntryRecord document,
    {required String cashboxId, required String cashboxName}) {
  if (cashboxId == document.accountId) return const [];
  final refund = document.kind == LedgerKind.returnEntry;
  final title = refund ? 'رد نقدي لمرتجع مبيعات' : 'تحصيل فاتورة نقدية';
  LedgerEntryRecord movement(String suffix, String accountId, String accountName,
          EntryDirection direction) =>
      LedgerEntryRecord(id: '${document.id}/$suffix', accountId: accountId,
        accountName: accountName, kind: LedgerKind.voucher, typeLabel: title,
        payment: PaymentMethod.cash, direction: direction, amount: document.amount,
        currency: document.currency, exchangeRate: document.exchangeRate,
        documentNumber: document.documentNumber, entryNumber: document.entryNumber,
        entryDate: document.entryDate, details: '$title · ${document.documentNumber}',
        warehouseId: '', warehouseName: '');
  return [
    movement('cashbox', cashboxId, cashboxName,
        refund ? EntryDirection.credit : EntryDirection.debit),
    movement('settlement', document.accountId, document.accountName,
        refund ? EntryDirection.debit : EntryDirection.credit),
  ];
}
