import '../models/erp_models.dart';
import '../services/invoice_movement_report.dart';
import '../state/erp_controller.dart';

/// Present the existing Dart reports to React. Amounts in different currencies
/// are never added together.
Map<String, Object?> reactInventoryReport(ErpController controller,
    Map<String, Object?> options, CurrencyCode? selected) {
  final warehouse = options['warehouseId'] as String? ?? '';
  final itemId = options['itemId'];
  final from = options['fromDate'] as String? ?? '';
  final to = options['toDate'] as String? ?? '';
  final basis = switch (options['profitBasis']) {
    'cost' => CostBasis.catalog,
    'last' => CostBasis.lastPurchase,
    _ => CostBasis.average,
  };
  final primary = selected ?? controller.defaultCurrency;
  final currencies = {
    primary,
    if (selected == null)
      ...controller.ledger
          .where((e) =>
              !e.deleted &&
              (e.kind == LedgerKind.invoice ||
                  e.kind == LedgerKind.returnEntry))
          .map((e) => e.currency)
  };
  final totals = <Map<String, Object?>>[];
  final items = <Map<String, Object?>>[];
  final movements = <Map<String, Object?>>[];
  final names = {for (final w in controller.warehouses) w.id: w.name};
  for (final currency in currencies) {
    final rows = invoiceMovementReport(
            inventory: controller.inventory,
            ledger: controller.ledger,
            lines: controller.saleLines,
            metadata: controller.restoredGroups,
            currency: currency,
            warehouse: warehouse,
            from: from,
            through: to,
            basis: basis,
            onMovement: itemId == null
                ? null
                : (id, movement) {
                    if (id == itemId)
                      movements.add({
                        ...movement,
                        'warehouseName': names[movement['warehouseId']] ?? ''
                      });
                  })
        .where((r) => itemId == null || r.item.id == itemId);
    double sales = 0, purchases = 0, profit = 0, remaining = 0, quantity = 0;
    var active = 0;
    for (final r in rows) {
      final i = r.item;
      sales += r.sales;
      purchases += r.purchases;
      profit += r.profit;
      remaining += r.remaining * r.unitCost;
      quantity += r.remaining;
      if (r.active) active++;
      if (currency == primary || r.active) {
        items.add({
          'id': i.id,
          'code': null,
          'name': i.name,
          'unit': i.unit,
          'unit2': '',
          'count2': null,
          'sku': i.sku,
          'warehouseId': i.warehouseId,
          'currencyCode': currency.label,
          'openingQty': r.opening,
          'periodNetQty': r.remaining - r.opening,
          'buyQty': r.bought,
          'sellQty': r.sold,
          'transferInQty': r.incoming,
          'transferOutQty': r.outgoing,
          'buyTotal': r.purchases,
          'sellTotal': r.sales,
          'availableQty': r.remaining,
          'unitCost': r.unitCost,
          'remainingValue': r.remaining * r.unitCost,
          'profit': r.profit,
          'avgCost': i.avgCost,
          'catalogQuantity': i.quantity,
          'quantityUnverified': false,
          'hasMovement': r.active
        });
      }
    }
    totals.add({
      'currency': currency.label,
      'totalSales': sales,
      'totalPurchases': purchases,
      'totalProfit': profit,
      'totalRemainingValue': remaining,
      'totalRemainingQty': quantity,
      'activeItemsCount': active,
      'profitBasis': options['profitBasis'] ?? 'avg'
    });
  }
  return {
    'warehouses': [
      for (final w in controller.warehouses) {'id': w.id, 'name': w.name}
    ],
    'itemRows': items,
    'movements': movements,
    'totals': totals.first,
    'totalsByCurrency': totals,
    'warehouseStocks': [
      for (final i in items)
        {
          'inventoryItemId': i['id'],
          'warehouseId': i['warehouseId'],
          'warehouseName': names[i['warehouseId']],
          'netComputedQty': i['availableQty'],
          'transferInQty': i['transferInQty'],
          'transferOutQty': i['transferOutQty']
        }
    ],
    'anomalies': {
      'unverifiedItemsCount': 0,
      'negativeComputedItems': [
        for (final i in items)
          if ((i['availableQty'] as num) < 0)
            {
              'id': i['id'],
              'name': i['name'],
              'netComputedQty': i['availableQty']
            }
      ],
      'unresolvedTransfers': [],
      'unresolvedTransfersCount': 0
    }
  };
}

Map<String, Object?> reactCashboxReport(ErpController controller,
    Map<String, Object?> options, CurrencyCode? selected) {
  final from = options['fromDate'] as String? ?? '';
  final to = options['toDate'] as String? ?? '';
  final boxes = controller.accounts.where((a) => a.isCashAccount);
  final result = <Map<String, Object?>>[];
  for (final box in boxes) {
    final entries = controller.ledger.where((e) =>
        !e.deleted &&
        e.accountId == box.id &&
        e.kind != LedgerKind.order &&
        e.kind != LedgerKind.quote &&
        (from.isEmpty || e.entryDate.compareTo(from) >= 0) &&
        (to.isEmpty || e.entryDate.compareTo(to) <= 0));
    for (final currency in {box.currency, ...entries.map((e) => e.currency)}) {
      if (selected != null && selected != currency) continue;
      double incoming = 0, outgoing = 0;
      var count = 0;
      for (final e in entries.where((e) => e.currency == currency)) {
        if (e.direction == EntryDirection.debit) {
          incoming += e.amount;
        } else {
          outgoing += e.amount;
        }
        count++;
      }
      result.add({
        'id': box.codeNumber,
        'name': box.name,
        'currencyCode': currency.label,
        'isActive': true,
        'totalIn': incoming,
        'totalOut': outgoing,
        'netBalance': incoming - outgoing,
        'entryCount': count
      });
    }
  }
  return {'cashboxes': result};
}
