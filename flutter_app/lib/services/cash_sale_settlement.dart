import '../models/erp_models.dart';

bool isCashSaleSettlement(LedgerEntryRecord entry) =>
    entry.kind == LedgerKind.voucher &&
    const {'تحصيل فاتورة نقدية','رد نقدي لمرتجع مبيعات','سداد فاتورة شراء نقدية','استرداد مردود شراء'}.contains(entry.typeLabel) &&
    (entry.id.endsWith('/cashbox') || entry.id.endsWith('/settlement'));

/// The invoice or return remains on the customer's statement. The linked
/// settlement clears that amount and records the cashbox receipt or refund.
List<LedgerEntryRecord> cashSaleSettlement(LedgerEntryRecord document,
    {required String cashboxId, required String cashboxName}) {
  if (cashboxId == document.accountId) return const [];
  final refund = document.kind == LedgerKind.returnEntry;
  final purchase = document.typeLabel.contains('مشتريات') || document.typeLabel == 'مردود شراء';
  final title = purchase
      ? (refund ? 'استرداد مردود شراء' : 'سداد فاتورة شراء نقدية')
      : (refund ? 'رد نقدي لمرتجع مبيعات' : 'تحصيل فاتورة نقدية');
  final cashOut = document.direction == EntryDirection.credit;
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
        cashOut ? EntryDirection.credit : EntryDirection.debit),
    movement('settlement', document.accountId, document.accountName,
        cashOut ? EntryDirection.debit : EntryDirection.credit),
  ];
}
