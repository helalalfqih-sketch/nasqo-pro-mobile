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
      final q = _searchQuery.toLowerCase();
      return switch (_searchCriterion) {
        'الرقم' => e.entryNumber.toString().contains(q),
        'البيان' => e.details.toLowerCase().contains(q),
        'رقم المستند' => e.id.toLowerCase().contains(q),
        'المبلغ عليه' =>
          e.direction == EntryDirection.debit && e.amount.toString().contains(q),
        'المبلغ له' => e.direction == EntryDirection.credit &&
            e.amount.toString().contains(q),
        _ => '${e.entryNumber} ${e.details} ${e.typeLabel} ${e.amount}'
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
                            return Container(
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
