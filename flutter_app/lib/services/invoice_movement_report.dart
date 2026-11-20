import '../models/erp_models.dart';
import 'web_backup.dart';

enum CostBasis { average, catalog, lastPurchase }

double _round2(double value) => (value*100+0.5).floor()/100;

class InvoiceMovementRow {
  InvoiceMovementRow(this.item);
  final InventoryItemRecord item;
  double bought = 0, sold = 0, purchases = 0, sales = 0, profit = 0;
  double periodBuyQty = 0, periodBuyValue = 0, allBuyQty = 0, allBuyValue = 0;
  double? lastCost;
  String lastDate = '';
  int lastNumber = -1, lastPosition = -1;
  double invoiceNet = 0, prior = 0, incoming = 0, outgoing = 0, opening = 0, remaining = 0;
  bool active = false;
}

List<InvoiceMovementRow> invoiceMovementReport({
  required List<InventoryItemRecord> inventory, required List<LedgerEntryRecord> ledger,
  required List<SavedSaleLine> lines, RestoredGroups? metadata, required CurrencyCode currency,
  String warehouse = '',String from = '',String through = '',CostBasis basis = CostBasis.average,
}) {
  final entries = {for(final e in ledger) e.id:e};
  final rows = {for(final i in inventory) i.id:InvoiceMovementRow(i)};
  for(final line in lines) {
    final row = rows[line.itemId], entry = entries[line.entryId];
    if(row==null || entry==null || entry.deleted) continue;
    final detail = metadata?.reportLines[(entry.id,line.position)];
    if(detail?['lineKind']=='free') continue;
    final type = metadata?.documentTypes[entry.id];
    final debit = entry.direction==EntryDirection.debit;
    final doc = type ?? (entry.kind==LedgerKind.invoice ? (debit ? 2 : 3) :
        entry.kind==LedgerKind.returnEntry ? (debit ? 5 : 4) : 0);
    if(!const {2,3,4,5,7,9}.contains(doc)) continue;
    final purchase = doc==3 || doc==9 || doc==5;
    final sign = doc==4 || doc==5 ? -1 : 1;
    final factors = metadata?.unitFactors[line.itemId] ?? (1.0,1.0);
    final multiplier = switch(detail?['unitNum']) {
      2 => factors.$1, 3 => factors.$1*factors.$2, _ => 1.0
    };
    final qty = sign*(line.quantity*multiplier+((detail?['bonus'] as num?)?.toDouble() ?? 0));
    final value = sign*((detail?['total'] as num?)?.toDouble() ?? line.quantity*line.unitPrice);
    if(purchase) {
      row.allBuyQty+=qty;
      row.allBuyValue+=value;
      if(sign==1 && line.unitPrice>0 && (entry.entryDate.compareTo(row.lastDate)>0 ||
          entry.entryDate==row.lastDate && (entry.entryNumber>row.lastNumber ||
          entry.entryNumber==row.lastNumber && line.position>row.lastPosition))) {
        row.lastCost=line.unitPrice/multiplier;
        row.lastDate=entry.entryDate;
        row.lastNumber=entry.entryNumber;
        row.lastPosition=line.position;
      }
    }
    final wh = detail?['warehouseId'] as String?;
    final location = wh!=null && wh.isNotEmpty ? wh :
        entry.warehouseId.isNotEmpty ? entry.warehouseId : row.item.warehouseId;
    row.invoiceNet += purchase ? qty : -qty;
    if(from.isNotEmpty && entry.currency==currency && entry.entryDate.compareTo(from)<0 &&
        (warehouse.isEmpty || warehouse==location)) row.prior += purchase ? qty : -qty;
    if(entry.currency!=currency || (from.isNotEmpty && entry.entryDate.compareTo(from)<0) ||
        (through.isNotEmpty && entry.entryDate.compareTo(through)>0)) continue;
    if(purchase) {row.periodBuyQty+=qty;row.periodBuyValue+=value;}
    if(warehouse.isNotEmpty && location!=warehouse) continue;
    row.active = true;
    if(purchase) {row.bought+=qty;row.purchases+=value;}
    else {row.sold+=qty;row.sales+=value;}
  }
  if(metadata!=null) {
    for(final tx in metadata.transfers) {
      final row = rows[tx.item];
      if(row==null) continue;
      final factors = metadata.unitFactors[tx.item] ?? (1.0,1.0);
      final qty = tx.quantity*(tx.unit==3 ? factors.$1*factors.$2 : tx.unit==2 ? factors.$1 : 1.0);
      final incoming = tx.destination.isNotEmpty && (warehouse.isEmpty || warehouse==tx.destination);
      final outgoing = tx.source.isNotEmpty && (warehouse.isEmpty || warehouse==tx.source);
      if(from.isNotEmpty && tx.date.compareTo(from)<0) {
        row.prior += (incoming ? qty : 0) - (outgoing ? qty : 0);
        continue;
      }
      if(through.isNotEmpty && tx.date.compareTo(through)>0) continue;
      if(incoming) row.incoming+=qty;
      if(outgoing) row.outgoing+=qty;
      if(incoming || outgoing) row.active=true;
    }
  }
  for(final r in rows.values) {
    final baseline = warehouse.isEmpty || warehouse==r.item.warehouseId ? r.item.quantity-r.invoiceNet : 0;
    r.opening=_round2(baseline+r.prior);
    r.remaining=_round2(r.opening+_round2(r.bought)-_round2(r.sold)+_round2(r.incoming)-_round2(r.outgoing));
  }
  final result = rows.values.where((r)=>r.active || r.opening!=0).toList();
  for(final r in result) {
    r.sales=_round2(r.sales); r.sold=_round2(r.sold);
    r.purchases=_round2(r.purchases); r.bought=_round2(r.bought);
    final fallback = r.item.avgCost>0 ? r.item.avgCost :
      r.periodBuyQty>0 ? r.periodBuyValue/r.periodBuyQty : r.allBuyQty>0 ? r.allBuyValue/r.allBuyQty : 0.0;
    final avg = r.bought!=0 && r.purchases/r.bought>0 ? r.purchases/r.bought : fallback;
    final cost = switch(basis) {
      CostBasis.catalog => r.item.avgCost>0 ? r.item.avgCost : avg,
      CostBasis.lastPurchase => r.lastCost ?? avg,
      CostBasis.average => avg,
    };
    r.profit=_round2(r.sales-r.sold*cost);
  }
  result.sort((a,b)=>a.item.name.compareTo(b.item.name));
  return result;
}
