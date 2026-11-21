import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';
import 'nasqo_brand_mark.dart';

// ============================================================================
// 1. SalesTrendChartCard (Port of src/components/SalesTrendChart.tsx)
// ============================================================================

class SalesTrendPoint {
  const SalesTrendPoint({
    required this.dateIso,
    required this.shortLabel,
    required this.weekdayLabel,
    required this.salesTotal,
  });

  final String dateIso;
  final String shortLabel;
  final String weekdayLabel;
  final double salesTotal;
}

List<SalesTrendPoint> computeSalesTrendPoints(
  Iterable<LedgerEntryRecord> ledger,
  CurrencyCode currency, {
  DateTime? referenceDate,
}) {
  const weekdays = [
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];
  final activeSales = ledger
      .where((e) =>
          !e.deleted &&
          e.currency == currency &&
          e.kind == LedgerKind.invoice &&
          (e.direction == EntryDirection.debit ||
              e.typeLabel.contains('مبيعات') ||
              e.typeLabel.contains('بيع')))
      .toList();

  DateTime anchor = referenceDate ?? DateTime.now();
  if (referenceDate == null && activeSales.isNotEmpty) {
    final latestIso = activeSales
        .map((e) => e.entryDate.length >= 10 ? e.entryDate.substring(0, 10) : '')
        .where((d) => d.isNotEmpty)
        .fold<String>('', (prev, curr) => curr.compareTo(prev) > 0 ? curr : prev);
    final parsed = DateTime.tryParse(latestIso);
    if (parsed != null) anchor = parsed;
  }

  final baseDay = DateTime.utc(anchor.year, anchor.month, anchor.day);
  final totalsByDay = <String, double>{};
  for (final e in activeSales) {
    final iso = e.entryDate.length >= 10 ? e.entryDate.substring(0, 10) : e.entryDate;
    totalsByDay[iso] = (totalsByDay[iso] ?? 0) + e.amount;
  }

  final points = <SalesTrendPoint>[];
  for (var i = 6; i >= 0; i--) {
    final d = baseDay.subtract(Duration(days: i));
    final iso =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final shortLabel =
        '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final weekday = weekdays[(d.weekday - 1).clamp(0, 6)];
    points.add(SalesTrendPoint(
      dateIso: iso,
      shortLabel: shortLabel,
      weekdayLabel: weekday,
      salesTotal: totalsByDay[iso] ?? 0,
    ));
  }
  return points;
}

class SalesTrendChartCard extends StatefulWidget {
  const SalesTrendChartCard({
    super.key,
    required this.ledger,
    required this.currency,
  });

  final Iterable<LedgerEntryRecord> ledger;
  final CurrencyCode currency;

  @override
  State<SalesTrendChartCard> createState() => _SalesTrendChartCardState();
}

class _SalesTrendChartCardState extends State<SalesTrendChartCard> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final points = computeSalesTrendPoints(widget.ledger, widget.currency);
    final total7Days = points.fold<double>(0, (s, p) => s + p.salesTotal);
    final maxVal = points.fold<double>(0, (m, p) => p.salesTotal > m ? p.salesTotal : m);
    final activeIdx = (_selectedIndex ?? (points.length - 1)).clamp(0, points.length - 1);
    final activePoint = points.isNotEmpty ? points[activeIdx] : null;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      key: const ValueKey('sales-trend-chart-card'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اتجاه المبيعات (آخر 7 أيام)',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'إجمالي 7 أيام: ${AccountingEngine.formatAmount(total7Days)} ${widget.currency.label}'
              '${activePoint != null ? ' · ${activePoint.weekdayLabel} (${activePoint.shortLabel}): ${AccountingEngine.formatAmount(activePoint.salesTotal)} ${widget.currency.label}' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (maxVal == 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'لا توجد مبيعات مسجلة خلال آخر 7 أيام',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                painter: _SalesTrendPainter(
                  points: points,
                  activeIndex: activeIdx,
                  primaryColor: scheme.primary,
                  gridColor: scheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (idx, pt) in points.indexed)
                  ChoiceChip(
                    label: Text(pt.shortLabel, style: const TextStyle(fontSize: 11)),
                    selected: activeIdx == idx,
                    onSelected: (_) => setState(() => _selectedIndex = idx),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesTrendPainter extends CustomPainter {
  _SalesTrendPainter({
    required this.points,
    required this.activeIndex,
    required this.primaryColor,
    required this.gridColor,
  });

  final List<SalesTrendPoint> points;
  final int activeIndex;
  final Color primaryColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const padLeft = 14.0;
    const padRight = 14.0;
    const padTop = 12.0;
    const padBottom = 18.0;
    final w = math.max(1.0, size.width - padLeft - padRight);
    final h = math.max(1.0, size.height - padTop - padBottom);

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = padTop + (h * i / 3);
      canvas.drawLine(Offset(padLeft, y), Offset(padLeft + w, y), gridPaint);
    }

    final maxRaw = points.fold<double>(0, (m, p) => p.salesTotal > m ? p.salesTotal : m);
    final domainMax = maxRaw > 0 ? maxRaw * 1.15 : 1000.0;

    final offsets = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = padLeft + (points.length == 1 ? w / 2 : (w * i / (points.length - 1)));
      final y = padTop + h - ((points[i].salesTotal / domainMax).clamp(0.0, 1.0) * h);
      offsets.add(Offset(x, y));
    }

    final areaPath = Path()..moveTo(offsets.first.dx, padTop + h);
    for (final pt in offsets) {
      areaPath.lineTo(pt.dx, pt.dy);
    }
    areaPath
      ..lineTo(offsets.last.dx, padTop + h)
      ..close();

    final areaPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    canvas.drawPath(areaPath, areaPaint);

    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 1; i < offsets.length; i++) {
      linePath.lineTo(offsets[i].dx, offsets[i].dy);
    }
    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, linePaint);

    for (var i = 0; i < offsets.length; i++) {
      final isSel = i == activeIndex;
      canvas.drawCircle(
        offsets[i],
        isSel ? 5.5 : 3.5,
        Paint()..color = isSel ? const Color(0xFFD97706) : primaryColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SalesTrendPainter oldDelegate) =>
      oldDelegate.activeIndex != activeIndex || oldDelegate.points != points;
}

// ============================================================================
// 2. ExpenseTrendsChartCard (Port of src/components/ExpenseTrendsChart.tsx)
// ============================================================================

class ExpenseCategorySlice {
  const ExpenseCategorySlice({
    required this.category,
    required this.total,
    required this.count,
    required this.percentage,
    required this.color,
  });

  final String category;
  final double total;
  final int count;
  final double percentage;
  final Color color;
}

class ExpenseTrendsChartCard extends StatefulWidget {
  const ExpenseTrendsChartCard({
    super.key,
    required this.accounts,
    required this.ledger,
    required this.currency,
  });

  final List<AccountRecord> accounts;
  final List<LedgerEntryRecord> ledger;
  final CurrencyCode currency;

  @override
  State<ExpenseTrendsChartCard> createState() => _ExpenseTrendsChartCardState();
}

class _ExpenseTrendsChartCardState extends State<ExpenseTrendsChartCard> {
  String _range = 'all'; // 'month' | 'quarter' | 'all'
  int? _activeSliceIndex;

  static const _palette = [
    Color(0xFF4338CA),
    Color(0xFF0891B2),
    Color(0xFF16A34A),
    Color(0xFFD97706),
    Color(0xFFDC2626),
    Color(0xFF9333EA),
    Color(0xFF2563EB),
    Color(0xFF475569),
  ];

  void _cycleRange() {
    const order = ['month', 'quarter', 'all'];
    final next = order[(order.indexOf(_range) + 1) % order.length];
    setState(() => _range = next);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cutoff = switch (_range) {
      'month' => now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10),
      'quarter' => now.subtract(const Duration(days: 90)).toIso8601String().substring(0, 10),
      _ => '',
    };
    final accountMap = {for (final a in widget.accounts) a.id: a};
    final totals = <String, double>{};
    final counts = <String, int>{};
    var totalSpend = 0.0;
    var entryCount = 0;

    for (final e in widget.ledger) {
      if (e.deleted ||
          e.currency != widget.currency ||
          e.kind == LedgerKind.quote ||
          e.kind == LedgerKind.order) {
        continue;
      }
      if (cutoff.isNotEmpty && e.entryDate.compareTo(cutoff) < 0) continue;
      final isExpenseOrPurchase = e.expenseCategory.trim().isNotEmpty ||
          e.typeLabel.contains('مشتريات') ||
          e.typeLabel.contains('سند') ||
          e.typeLabel.contains('رواتب') ||
          (accountMap[e.accountId]?.category == AccountCategory.purchases) ||
          (accountMap[e.accountId]?.category == AccountCategory.shop) ||
          (accountMap[e.accountId]?.category == AccountCategory.employees);
      if (!isExpenseOrPurchase) continue;

      final cat = e.expenseCategory.trim().isNotEmpty
          ? e.expenseCategory.trim()
          : ErpController.inferExpenseCategory(
              e.details,
              e.accountName,
              accountMap[e.accountId]?.category,
            );
      totals[cat] = (totals[cat] ?? 0) + e.amount;
      counts[cat] = (counts[cat] ?? 0) + 1;
      totalSpend += e.amount;
      entryCount++;
    }

    final sortedCats = totals.keys.toList()
      ..sort((a, b) => (totals[b] ?? 0).compareTo(totals[a] ?? 0));
    final slices = <ExpenseCategorySlice>[
      for (final (i, cat) in sortedCats.indexed)
        ExpenseCategorySlice(
          category: cat,
          total: totals[cat]!,
          count: counts[cat] ?? 1,
          percentage: totalSpend > 0 ? (totals[cat]! / totalSpend) * 100 : 0,
          color: _palette[i % _palette.length],
        ),
    ];

    final rangeLabel = switch (_range) {
      'month' => 'هذا الشهر (30 يوم)',
      'quarter' => 'آخر 3 أشهر',
      _ => 'كل الفترات',
    };

    return Card(
      key: const ValueKey('expense-trends-chart-card'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onLongPress: _cycleRange,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'اتجاهات المصروفات والتصنيف الذكي',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$rangeLabel · ${AccountingEngine.formatAmount(totalSpend)} ${widget.currency.label} ($entryCount عملية)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final (id, label) in const [
                    ('month', 'شهري'),
                    ('quarter', '3 أشهر'),
                    ('all', 'الكل'),
                  ])
                    ChoiceChip(
                      key: ValueKey('expense-range-$id'),
                      label: Text(label),
                      selected: _range == id,
                      onSelected: (_) => setState(() => _range = id),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (slices.isEmpty)
                const Text('لا توجد مصروفات مصنفة في هذه الفترة.')
              else
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: CustomPaint(
                        painter: _DonutChartPainter(
                          slices: slices,
                          activeIndex: _activeSliceIndex,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        children: [
                          for (final (idx, s) in slices.indexed)
                            InkWell(
                              onTap: () => setState(() => _activeSliceIndex = idx),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: s.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        s.category,
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${s.percentage.toStringAsFixed(0)}% · ${AccountingEngine.formatAmount(s.total)}',
                                      style: const TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({required this.slices, required this.activeIndex});

  final List<ExpenseCategorySlice> slices;
  final int? activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (s, e) => s + e.total);
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    var startAngle = -math.pi / 2;

    for (var i = 0; i < slices.length; i++) {
      final sweep = (slices[i].total / total) * 2 * math.pi;
      final isSel = activeIndex == i;
      final paint = Paint()
        ..color = slices[i].color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 20 : 16;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        math.max(0.02, sweep - 0.04),
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.activeIndex != activeIndex;
}

// ============================================================================
// 3. SupplierPerformanceChartCard (Port of SupplierPerformanceChart.tsx)
// ============================================================================

class SupplierPerformanceMetric {
  const SupplierPerformanceMetric({
    required this.accountId,
    required this.name,
    required this.orderCount,
    required this.totalSpend,
    required this.avgOrderCost,
    this.avgDeliveryDays,
    this.onTimeScore,
  });

  final String accountId;
  final String name;
  final int orderCount;
  final double totalSpend;
  final double avgOrderCost;
  final double? avgDeliveryDays;
  final int? onTimeScore;
}

bool _isSupplierPurchaseInvoice(
  LedgerEntryRecord e,
  String supplierId,
  CurrencyCode currency,
) {
  if (e.deleted ||
      e.accountId != supplierId ||
      e.currency != currency ||
      e.kind != LedgerKind.invoice ||
      !e.amount.isFinite ||
      e.amount <= 0) {
    return false;
  }
  final label = e.typeLabel.trim();
  if (label.contains('مبيعات') ||
      label.contains('بيع') ||
      label.contains('مردود') ||
      label.contains('مرتجع')) {
    return false;
  }
  return e.direction == EntryDirection.credit ||
      label.contains('مشتريات') ||
      label.contains('شراء') ||
      e.id.startsWith('purchase_');
}

List<SupplierPerformanceMetric> computeSupplierMetrics(
  List<AccountRecord> accounts,
  List<LedgerEntryRecord> ledger,
  CurrencyCode currency, {
  List<ErpPurchaseOrder> purchaseOrders = const [],
}) {
  final suppliers = accounts
      .where((a) => a.category == AccountCategory.purchases)
      .toList()
    ..sort((a, b) {
      final codeCmp = a.codeNumber.compareTo(b.codeNumber);
      return codeCmp != 0 ? codeCmp : a.id.compareTo(b.id);
    });
  final metrics = <SupplierPerformanceMetric>[];

  for (final s in suppliers) {
    final purchaseInvoices = ledger
        .where((e) => _isSupplierPurchaseInvoice(e, s.id, currency))
        .toList();
    final total = purchaseInvoices.fold<double>(0, (sum, e) => sum + e.amount);
    final count = purchaseInvoices.length;

    final deliveryDays = <double>[];
    var onTimeCount = 0;
    var evaluatedOnTime = 0;

    final supplierReceivedPos = purchaseOrders
        .where((po) =>
            po.supplierAccountId == s.id &&
            po.currency == currency &&
            po.status == PurchaseOrderStatus.received)
        .toList();

    final allExplicitTargetIds = purchaseOrders
        .map((po) => po.postedLedgerEntryId?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final usedInvoiceIds = <String>{};
    final matchedPoIndices = <int>{};
    final matchedPairs = <({ErpPurchaseOrder po, LedgerEntryRecord invoice})>[];

    // Pass 1: Explicit postedLedgerEntryId links take priority regardless of PO order.
    for (var i = 0; i < supplierReceivedPos.length; i++) {
      final po = supplierReceivedPos[i];
      final explicitId = po.postedLedgerEntryId?.trim() ?? '';
      if (explicitId.isEmpty || usedInvoiceIds.contains(explicitId)) continue;

      final sameExplicitCount = supplierReceivedPos
          .where((other) =>
              (other.postedLedgerEntryId?.trim() ?? '') == explicitId)
          .length;
      if (sameExplicitCount != 1) continue;

      final idMatches = purchaseInvoices
          .where((e) => e.id == explicitId && !usedInvoiceIds.contains(e.id))
          .toList();
      if (idMatches.length == 1) {
        final candidate = idMatches.single;
        final docNum = po.poNumber.trim();
        final docConsistent = docNum.isEmpty ||
            candidate.documentNumber.trim().isEmpty ||
            candidate.documentNumber.trim() == docNum;
        if (docConsistent) {
          usedInvoiceIds.add(candidate.id);
          matchedPoIndices.add(i);
          matchedPairs.add((po: po, invoice: candidate));
        }
      }
    }

    // Pass 2: Fallback to unique documentNumber only against unclaimed receipt entries.
    for (var i = 0; i < supplierReceivedPos.length; i++) {
      if (matchedPoIndices.contains(i)) continue;
      final po = supplierReceivedPos[i];
      final explicitId = po.postedLedgerEntryId?.trim() ?? '';
      final docNum = po.poNumber.trim();
      if (explicitId.isNotEmpty || docNum.isEmpty) continue;

      var unmatchedSameDocCount = 0;
      for (var j = 0; j < supplierReceivedPos.length; j++) {
        if (!matchedPoIndices.contains(j) &&
            supplierReceivedPos[j].poNumber.trim() == docNum) {
          unmatchedSameDocCount++;
        }
      }
      if (unmatchedSameDocCount != 1) continue;

      final docMatches = purchaseInvoices
          .where((e) =>
              !usedInvoiceIds.contains(e.id) &&
              !allExplicitTargetIds.contains(e.id) &&
              e.documentNumber.trim() == docNum)
          .toList();
      if (docMatches.length == 1) {
        final candidate = docMatches.single;
        usedInvoiceIds.add(candidate.id);
        matchedPoIndices.add(i);
        matchedPairs.add((po: po, invoice: candidate));
      }
    }

    for (final pair in matchedPairs) {
      final orderDt = DateTime.tryParse(pair.po.orderDate);
      final expectedDt = DateTime.tryParse(pair.po.expectedDate);
      final receivedDt = DateTime.tryParse(pair.invoice.entryDate);
      if (orderDt != null && receivedDt != null && !receivedDt.isBefore(orderDt)) {
        deliveryDays.add(receivedDt.difference(orderDt).inDays.toDouble());
        if (expectedDt != null) {
          evaluatedOnTime++;
          if (!receivedDt.isAfter(expectedDt)) {
            onTimeCount++;
          }
        }
      }
    }

    if (count == 0) continue;
    final avgDelivery = deliveryDays.isEmpty
        ? null
        : deliveryDays.reduce((a, b) => a + b) / deliveryDays.length;
    final score = evaluatedOnTime == 0
        ? null
        : ((onTimeCount / evaluatedOnTime) * 100).round();

    metrics.add(SupplierPerformanceMetric(
      accountId: s.id,
      name: s.name,
      orderCount: count,
      totalSpend: total,
      avgOrderCost: total / count,
      avgDeliveryDays: avgDelivery,
      onTimeScore: score,
    ));
  }
  return metrics;
}

class SupplierPerformanceChartCard extends StatefulWidget {
  const SupplierPerformanceChartCard({
    super.key,
    required this.accounts,
    required this.ledger,
    required this.currency,
    this.purchaseOrders = const [],
  });

  final List<AccountRecord> accounts;
  final List<LedgerEntryRecord> ledger;
  final CurrencyCode currency;
  final List<ErpPurchaseOrder> purchaseOrders;

  @override
  State<SupplierPerformanceChartCard> createState() =>
      _SupplierPerformanceChartCardState();
}

class _SupplierPerformanceChartCardState
    extends State<SupplierPerformanceChartCard> {
  String _metricView = 'delivery'; // 'delivery' | 'cost'
  int _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final suppliers = computeSupplierMetrics(
      widget.accounts,
      widget.ledger,
      widget.currency,
      purchaseOrders: widget.purchaseOrders,
    );
    final withDelivery = suppliers.where((m) => m.avgDeliveryDays != null).toList();
    final avgDelivery = withDelivery.isEmpty
        ? null
        : withDelivery.fold<double>(0, (s, m) => s + m.avgDeliveryDays!) /
            withDelivery.length;
    final avgCost = suppliers.isEmpty
        ? 0.0
        : suppliers.fold<double>(0, (s, m) => s + m.avgOrderCost) /
            suppliers.length;
    final focused = suppliers.isNotEmpty
        ? suppliers[_activeIndex.clamp(0, suppliers.length - 1)]
        : null;

    return Card(
      key: const ValueKey('supplier-performance-chart-card'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'أداء الموردين (التسليم والتكاليف)',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              suppliers.isEmpty
                  ? 'لا توجد بيانات موردين كافية للمقارنة'
                  : 'متوسط التوريد: ${avgDelivery == null ? "غير متاح" : "${avgDelivery.toStringAsFixed(1)} يوم"} · متوسط الفاتورة: ${AccountingEngine.formatAmount(avgCost)} ${widget.currency.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  key: const ValueKey('supplier-metric-delivery'),
                  label: const Text('أيام التسليم'),
                  selected: _metricView == 'delivery',
                  onSelected: (_) => setState(() => _metricView = 'delivery'),
                ),
                ChoiceChip(
                  key: const ValueKey('supplier-metric-cost'),
                  label: const Text('متوسط التكلفة'),
                  selected: _metricView == 'cost',
                  onSelected: (_) => setState(() => _metricView = 'cost'),
                ),
              ],
            ),
            if (focused != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'المورد: ${focused.name} · الالتزام: ${focused.onTimeScore == null ? "غير متاح" : "${focused.onTimeScore}%"} · متوسط التوريد: ${focused.avgDeliveryDays == null ? "غير متاح" : "${focused.avgDeliveryDays!.toStringAsFixed(1)} يوم"} · الإجمالي: ${AccountingEngine.formatAmount(focused.totalSpend)} ${widget.currency.label}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 10),
              for (final (idx, s) in suppliers.take(5).indexed)
                InkWell(
                  onTap: () => setState(() => _activeIndex = idx),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: idx == _activeIndex
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                            value: _metricView == 'delivery'
                                ? (s.avgDeliveryDays == null
                                    ? 0.0
                                    : (s.avgDeliveryDays! / 7.0).clamp(0.1, 1.0))
                                : (avgCost > 0
                                    ? (s.avgOrderCost / (avgCost * 2))
                                        .clamp(0.1, 1.0)
                                    : 0.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _metricView == 'delivery'
                              ? (s.avgDeliveryDays == null
                                  ? 'غير متاح'
                                  : '${s.avgDeliveryDays!.toStringAsFixed(1)} يوم')
                              : AccountingEngine.formatAmount(s.avgOrderCost),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 4. PrintOptionsModal (Port of src/components/PrintOptionsModal.tsx)
// ============================================================================

Future<void> showPrintOptionsModal(
  BuildContext context, {
  String? subjectLabel,
  required ValueChanged<String> onAction,
}) {
  var allCurrencies = true;
  var format = 'pdf'; // 'pdf' | 'excel' | 'image'
  var paperSize = 'A4'; // 'A4' | '80mm' | '58mm'

  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, update) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          key: const ValueKey('print-options-modal'),
          title: const Text('خيارات الطباعة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subjectLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(subjectLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('طباعة جميع العملات'),
                  value: allCurrencies,
                  onChanged: (v) => update(() => allCurrencies = v ?? true),
                ),
                const Text('صيغة التصدير:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (id, label) in const [
                      ('pdf', 'PDF'),
                      ('excel', 'Excel'),
                      ('image', 'صورة'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: format == id,
                        onSelected: (_) => update(() => format = id),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('مقاس الورق:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final size in const ['A4', '80mm', '58mm'])
                      ChoiceChip(
                        label: Text(size),
                        selected: paperSize == size,
                        onSelected: (_) => update(() => paperSize = size),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                onAction('طباعة ($format · $paperSize · ${allCurrencies ? "كل العملات" : "عملة واحدة"})');
              },
              child: const Text('طباعة'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                onAction('مشاركة ($format · $paperSize)');
              },
              child: const Text('مشاركة'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                onAction('إرسال عبر واتساب ($format)');
              },
              child: const Text('إرسال'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ============================================================================
// 5. BackupNameModal (Port of src/components/BackupNameModal.tsx)
// ============================================================================

String formatNasqoBackupFilename([DateTime? now]) {
  final d = now ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  final h = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return 'nasqo_backup_$y-$m-${day}_$h-$min';
}

Future<void> showBackupNameModal(
  BuildContext context, {
  required Future<void> Function(String name) onSaveLocal,
}) {
  final controller = TextEditingController(text: formatNasqoBackupFilename());
  var saving = false;

  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, update) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          key: const ValueKey('backup-name-modal'),
          title: const Text('اسم النسخة الاحتياطية'),
          content: TextField(
            key: const ValueKey('backup-name-input'),
            controller: controller,
            enabled: !saving,
            decoration: const InputDecoration(
              labelText: 'اسم النسخة الاحتياطية',
              hintText: 'أدخل اسم النسخة الاحتياطية',
            ),
          ),
          actions: [
            FilledButton(
              key: const ValueKey('backup-save-local-btn'),
              onPressed: saving
                  ? null
                  : () async {
                      final trimmed = controller.text.trim().isEmpty
                          ? formatNasqoBackupFilename()
                          : controller.text.trim();
                      update(() => saving = true);
                      try {
                        await onSaveLocal(trimmed);
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      } finally {
                        if (ctx.mounted) update(() => saving = false);
                      }
                    },
              child: const Text('حفظ'),
            ),
            OutlinedButton(
              key: const ValueKey('backup-save-google-btn'),
              onPressed: saving
                  ? null
                  : () {
                      Navigator.pop(dialogCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'النسخ السحابي إلى Google Drive وضع معاينة؛ استخدم الحفظ المحلي وتصدير الملف على الهاتف.',
                          ),
                        ),
                      );
                    },
              child: const Text('حفظ إلى جوجل'),
            ),
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ============================================================================
// 6. Drawer Auxiliary Dialogs (Activation, SMS, Support, About)
// ============================================================================

Future<void> showNasqoActivationDialog(BuildContext context, String companyName) {
  final codeController = TextEditingController();
  const deviceCode = 'NSQ-AND-8841-PRO';
  String? status;

  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, update) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          key: const ValueKey('nasqo-activation-modal'),
          title: const Text('تفعيل نسخة نسقو برو'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المنشأة: $companyName'),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('رقم الجهاز (Device ID)'),
                  subtitle: const SelectableText(deviceCode),
                  trailing: IconButton(
                    tooltip: 'نسخ رقم الجهاز',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: deviceCode));
                      update(() => status = 'تم نسخ رقم الجهاز للحافظة.');
                    },
                  ),
                ),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'كود التفعيل',
                    hintText: 'أدخل كود التفعيل المكون من 16 رمزاً',
                  ),
                ),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      status!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إغلاق'),
            ),
            FilledButton(
              onPressed: () {
                update(() => status =
                    'النسخة المحلية مفعلة في وضع المعاينة والتشغيل المحلي الكامل (SQLite).');
              },
              child: const Text('تحقق وتفعيل'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showNasqoSmsSettingsDialog(BuildContext context) {
  var sendTrigger = 'لا ترسل'; // 'لا ترسل' | 'بعد التأكيد' | 'تلقائي'
  var includeBalance = true;

  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, update) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          key: const ValueKey('nasqo-sms-modal'),
          title: const Text('إعدادات رسائل SMS'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('توقيت إرسال إشعار العملية:'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final opt in const ['لا ترسل', 'بعد التأكيد', 'تلقائي'])
                    ChoiceChip(
                      label: Text(opt),
                      selected: sendTrigger == opt,
                      onSelected: (_) => update(() => sendTrigger = opt),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تضمين الرصيد المتبقي في الرسالة'),
                value: includeBalance,
                onChanged: (v) => update(() => includeBalance = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم حفظ تفضيل رسائل SMS ($sendTrigger) محلياً.'),
                  ),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showNasqoAboutDialog(
  BuildContext context, {
  required ErpController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        key: const ValueKey('nasqo-about-modal'),
        title: const Row(
          children: [
            NasqoBrandMark(size: 32),
            SizedBox(width: 10),
            Expanded(child: Text('حول نسقو برو ERP')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المنشأة: ${controller.companyName}'),
            const Text('الإصدار: v1.0.17 (SQLite Local-First)'),
            const Text('معرّف الحزمة: com.indexesstore.nasqo_qa'),
            const SizedBox(height: 8),
            const Text(
              'نظام محاسبي متكامل لإدارة الحسابات والمبيعات والمخازن والرواتب والتقارير المالية يعمل محلياً بالكامل بدون اتصال.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    ),
  );
}
