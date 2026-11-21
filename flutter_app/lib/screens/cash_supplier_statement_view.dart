import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../services/accounting_engine.dart';
import '../state/erp_controller.dart';
import 'invoice_form_sheet.dart';

const cashCurrencyOptions = [
  'ريال',
  'عملة 2',
  'دولار',
  'جميع العملات بدون مصارفة',
  'مصارفة الكل بعملة ريال',
];

const cashSearchOptions = [
  'الكل',
  'الرقم',
  'البيان',
  'رقم المستند',
  'اسم المرسل',
  'اسم المستلم',
  'اسم الشركة',
  'المبلغ عليه',
  'المبلغ له',
];

class CashSupplierStatementView extends StatefulWidget {
  const CashSupplierStatementView({
    super.key,
    required this.controller,
    required this.account,
    required this.onOpenModule,
  });

  final ErpController controller;
  final AccountRecord account;
  final ValueChanged<String> onOpenModule;

  @override
  State<CashSupplierStatementView> createState() =>
      _CashSupplierStatementViewState();
}

class _CashSupplierStatementViewState extends State<CashSupplierStatementView> {
  String _currency = 'ريال';
  String _period = 'شهري';
  bool _showPreviousBalance = false;
  String _searchCriterion = 'الكل';
  String _searchQuery = '';
  bool _searchBarVisible = false;
  bool _currencyOverlayOpen = false;
  bool _searchOverlayOpen = false;
  bool _operationsOverlayOpen = false;

  void _openInvoice() {
    setState(() => _operationsOverlayOpen = false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (_) => InvoiceFormSheet(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.controller.ledger
        .where((e) =>
            e.accountId == widget.account.id &&
            !e.deleted &&
            e.kind != LedgerKind.quote &&
            e.kind != LedgerKind.order)
        .toList();

    // Filter by query and criterion
    final filtered = ledger.where((e) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return switch (_searchCriterion) {
        'الرقم' => e.entryNumber.toString().contains(q),
        'البيان' => e.details.toLowerCase().contains(q),
        'رقم المستند' => e.documentNumber.toLowerCase().contains(q),
        'المبلغ عليه' =>
          e.direction == EntryDirection.debit && e.amount.toString().contains(q),
        'المبلغ له' => e.direction == EntryDirection.credit &&
            e.amount.toString().contains(q),
        _ => '${e.entryNumber} ${e.documentNumber} ${e.details} ${e.typeLabel} ${e.amount}'
            .toLowerCase()
            .contains(q),
      };
    }).toList();

    final debitTotal = filtered
        .where((e) => e.direction == EntryDirection.debit)
        .fold(0.0, (sum, e) => sum + e.amount);
    final creditTotal = filtered
        .where((e) => e.direction == EntryDirection.credit)
        .fold(0.0, (sum, e) => sum + e.amount);
    final netBalance = debitTotal - creditTotal;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('كشف حساب ${widget.account.name}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'خيارات البحث',
              onPressed: () {
                setState(() {
                  _searchOverlayOpen = !_searchOverlayOpen;
                  _currencyOverlayOpen = false;
                  _operationsOverlayOpen = false;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: () => setState(() {}),
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Fixed Filters Section
                Container(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('العملة:',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _currencyOverlayOpen = !_currencyOverlayOpen;
                                _searchOverlayOpen = false;
                                _operationsOverlayOpen = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.black26
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border:
                                    Border.all(color: const Color(0xFF0B5CA8)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _currency,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0B5CA8),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_drop_down,
                                      size: 16, color: Color(0xFF0B5CA8)),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          Wrap(
                            spacing: 4,
                            children: [
                              _periodChip('شهري'),
                              _periodChip('الكل'),
                              _periodChip('سنوي'),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() =>
                                  _showPreviousBalance = !_showPreviousBalance);
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: _showPreviousBalance,
                                  onChanged: (val) => setState(() =>
                                      _showPreviousBalance = val ?? false),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const Text('رصيد سابق',
                                    style: TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'الفترة: من ${DateTime.now().year}-01-01 إلى ${DateTime.now().toIso8601String().substring(0, 10)}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                      if (_searchBarVisible) ...[
                        const SizedBox(height: 6),
                        TextField(
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'البحث بواسطة $_searchCriterion...',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                setState(() {
                                  _searchBarVisible = false;
                                  _searchQuery = '';
                                });
                              },
                            ),
                          ),
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                        ),
                      ],
                    ],
                  ),
                ),

                // Table Header
                Container(
                  color: const Color(0xFF0B5CA8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: const Row(
                    children: [
                      SizedBox(
                          width: 60,
                          child: Text('النوع',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold))),
                      SizedBox(
                          width: 80,
                          child: Text('المبلغ',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('التفاصيل',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold))),
                      SizedBox(
                          width: 70,
                          child: Text('الرصيد',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),

                // Statement Rows
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد حركات نقدية مسجلة بهذه العملة.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, thickness: 0.5),
                          itemBuilder: (context, index) {
                            final e = filtered[index];
                            final isDebit = e.direction == EntryDirection.debit;
                            return InkWell(
                              onTap: () => showLandscapeInvoicePreview(
                                context,
                                controller: widget.controller,
                                entry: e,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        e.typeLabel,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF0B5CA8),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        AccountingEngine.formatAmount(e.amount),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isDebit
                                              ? const Color(0xFF16A34A)
                                              : const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(e.details,
                                              style:
                                                  const TextStyle(fontSize: 11)),
                                          Text(
                                            '${e.entryDate} • #${e.entryNumber}',
                                            style: const TextStyle(
                                                fontSize: 9, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 70,
                                      child: Text(
                                        '0.00',
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0B5CA8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Cash Statement Footer
                Container(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFF073B68),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, color: Colors.white),
                        tooltip: 'تحويل الرصيد',
                        onPressed: () =>
                            widget.onOpenModule('cash-transfer-drafts'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'عليه: ${AccountingEngine.formatAmount(debitTotal)}',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white70),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'له: ${AccountingEngine.formatAmount(creditTotal)}',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white70),
                                ),
                              ],
                            ),
                            Text(
                              'الرصيد عليه: ${AccountingEngine.formatAmount(netBalance.abs())} $_currency',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white),
                        tooltip: 'خيارات الرصيد والعمليات',
                        onPressed: () {
                          setState(() {
                            _operationsOverlayOpen = !_operationsOverlayOpen;
                            _currencyOverlayOpen = false;
                            _searchOverlayOpen = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 1. Currency Overlay (Centered popup with the 5 exact reference options)
            if (_currencyOverlayOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _currencyOverlayOpen = false),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    color: Colors.black26,
                    child: Center(
                      child: Container(
                        width: 240,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black38,
                                blurRadius: 10,
                                offset: Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(color: Colors.grey)),
                              ),
                              child: const Text('اختيار عملة الكشف',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                            for (final opt in cashCurrencyOptions)
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _currency = opt;
                                    _currencyOverlayOpen = false;
                                  });
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 11, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: _currency == opt
                                        ? const Color(0xFF0B5CA8)
                                            .withValues(alpha: 0.1)
                                        : null,
                                  ),
                                  child: Text(
                                    opt,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _currency == opt
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: _currency == opt
                                          ? const Color(0xFF0B5CA8)
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 2. Search Criteria Overlay (Top-left overlay with 9 criteria)
            if (_searchOverlayOpen)
              Positioned(
                top: 8,
                left: 10,
                child: Container(
                  width: 170,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final criterion in cashSearchOptions)
                        InkWell(
                          onTap: () {
                            setState(() {
                              _searchCriterion = criterion;
                              _searchOverlayOpen = false;
                              _searchBarVisible = true;
                            });
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Text(
                              'البحث بواسطة $criterion',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // 3. Operations Overlay (Lower-left text-only overlay ~48% width above footer without dimming)
            if (_operationsOverlayOpen)
              Positioned(
                bottom: 56,
                left: 8,
                width: MediaQuery.of(context).size.width * 0.48,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0B5CA8), width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, -2)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _opRow('فاتورة جديدة', _openInvoice),
                      _opRow('مردود جديد', () {
                        setState(() => _operationsOverlayOpen = false);
                        widget.onOpenModule('sales-return-drafts');
                      }),
                      _opRow('سند جديد', () {
                        setState(() => _operationsOverlayOpen = false);
                        widget.onOpenModule('vouchers');
                      }),
                      _opRow('حوالة جديدة', () {
                        setState(() => _operationsOverlayOpen = false);
                        widget.onOpenModule('cash-transfer-drafts');
                      }),
                      _opRow('صرف عملات', () {
                        setState(() => _operationsOverlayOpen = false);
                        widget.onOpenModule('fx-drafts');
                      }),
                      _opRow('عرض سعر', () {
                        setState(() => _operationsOverlayOpen = false);
                        widget.onOpenModule('quote-new');
                      }),
                      _opRow('طلبية جديدة', () {
                        setState(() => _operationsOverlayOpen = false);
                        widget.onOpenModule('order-new');
                      }),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _opRow(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x15000000))),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF073B68),
          ),
        ),
      ),
    );
  }

  Widget _periodChip(String label) {
    final active = _period == label;
    return InkWell(
      onTap: () => setState(() => _period = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0B5CA8) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? const Color(0xFF0B5CA8) : Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: active ? Colors.white : Colors.grey.shade700,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

Future<void> showLandscapeInvoicePreview(
  BuildContext context, {
  required ErpController controller,
  required LedgerEntryRecord entry,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => LandscapeInvoicePreviewDialog(
      controller: controller,
      entry: entry,
    ),
  );
}

class LandscapeInvoicePreviewDialog extends StatelessWidget {
  const LandscapeInvoicePreviewDialog({
    super.key,
    required this.controller,
    required this.entry,
  });

  final ErpController controller;
  final LedgerEntryRecord entry;

  @override
  Widget build(BuildContext context) {
    final savedLines = controller.saleLines
        .where((l) => l.entryId == entry.id)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final rows = [
      for (final (i, l) in savedLines.indexed)
        (
          index: i + 1,
          name: l.itemName,
          unit: l.unit,
          qty: l.quantity,
          price: l.unitPrice,
          total: l.quantity * l.unitPrice,
        ),
    ];
    final totalQty = rows.fold<double>(0, (s, r) => s + r.qty);
    final totalAmount = entry.amount;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'معاينة مستند نسقو برو (عرض أفقي للقراءة فقط دون تعديل مالي)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق المعاينة',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Bilingual Business Header
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF0B5CA8), width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              controller.companyName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Text('للتجارة والمحاسبة وإدارة المخزون',
                                style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF0B5CA8)),
                          borderRadius: BorderRadius.circular(6),
                          color: const Color(0xFFF8FAFC),
                        ),
                        child: Text(
                          entry.typeLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF0B5CA8),
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'NASQO PRO ERP',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            Text('Trading & Accounting System',
                                style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Date, Number, Recipient
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text('رقم القيد: #${entry.entryNumber}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    Text(
                        'رقم المستند: ${entry.documentNumber.isEmpty ? "—" : entry.documentNumber}',
                        style: const TextStyle(fontSize: 11)),
                    Text('التاريخ: ${entry.entryDate}',
                        style: const TextStyle(fontSize: 11)),
                    Text('الحساب / المستلم: ${entry.accountName}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                if (entry.details.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'البيان: ${entry.details}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                if (rows.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Text(
                      'تفاصيل البنود غير متاحة',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 34,
                      dataRowMinHeight: 32,
                      dataRowMaxHeight: 44,
                      columnSpacing: 18,
                      headingRowColor:
                          const WidgetStatePropertyAll(Color(0xFF0B5CA8)),
                      headingTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      columns: const [
                        DataColumn(label: Text('م')),
                        DataColumn(label: Text('البيان / الصنف')),
                        DataColumn(label: Text('الوحدة')),
                        DataColumn(label: Text('الكمية')),
                        DataColumn(label: Text('السعر')),
                        DataColumn(label: Text('الإجمالي')),
                      ],
                      rows: [
                        for (final r in rows)
                          DataRow(
                            cells: [
                              DataCell(Text('${r.index}')),
                              DataCell(Text(r.name)),
                              DataCell(Text(r.unit)),
                              DataCell(
                                  Text(AccountingEngine.formatAmount(r.qty))),
                              DataCell(
                                  Text(AccountingEngine.formatAmount(r.price))),
                              DataCell(
                                  Text(AccountingEngine.formatAmount(r.total))),
                            ],
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            rows.isEmpty
                                ? 'إجمالي الكميات: غير متاح'
                                : 'إجمالي الكميات: ${AccountingEngine.formatAmount(totalQty)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'الإجمالي الصافي: ${AccountingEngine.formatAmount(totalAmount)} ${entry.currency.label}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0B5CA8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'المبلغ كتابةً: فقط ${AccountingEngine.formatAmount(totalAmount)} ${entry.currency.label} لا غير.',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
