import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../state/erp_controller.dart';

/// Local read-only lookup; no remote search, persistence or historical claims.
String _normalize(String value) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  return value
      .split('')
      .map((c) {
        if (ar.contains(c)) return ar.indexOf(c).toString();
        if (fa.contains(c)) return fa.indexOf(c).toString();
        if ('أإآ'.contains(c)) return 'ا';
        return c == 'ـ' ? '' : c;
      })
      .join()
      .toLowerCase()
      .trim();
}

bool _matches(String query, Iterable<Object> values) =>
    _normalize(values.join(' ')).contains(_normalize(query));
String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _amount(double v) => v.toString().replaceFirst(RegExp(r'\.0$'), '');
bool _financial(LedgerEntryRecord e) =>
    e.kind != LedgerKind.quote && e.kind != LedgerKind.order;
bool _entryMatches(String query, LedgerEntryRecord e) => _matches(query, [
      e.entryNumber,
      e.documentNumber,
      e.accountName,
      e.details,
      e.typeLabel,
      e.entryDate,
      e.warehouseName,
      _amount(e.amount),
    ]);

void _details(BuildContext context, String title, String body) {
  showDialog<void>(
      context: context,
      builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(child: SelectableText(body)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق'))
                ]),
          ));
}

Widget _entryTile(BuildContext context, LedgerEntryRecord e) => Card(
      child: ListTile(
        key: ValueKey('lookup-entry-${e.id}'),
        title: Text('${e.entryNumber} · ${e.accountName}'),
        subtitle: Text('${e.typeLabel} · ${e.entryDate}\n'
            '${_amount(e.amount)} ${e.currency.label} · '
            '${_financial(e) ? (e.direction == EntryDirection.debit ? 'مدين' : 'دائن') : 'غير مالي'}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_left),
        onTap: () => _details(
            context,
            'تفاصيل القيد ${e.entryNumber}',
            'الحساب: ${e.accountName}\nالنوع: ${e.typeLabel}\n'
                'التاريخ: ${e.entryDate}\nالمستند: ${e.documentNumber}\n'
                'المبلغ: ${_amount(e.amount)} ${e.currency.label}\n'
                'الجهة المسجلة: ${e.direction == EntryDirection.debit ? 'مدين' : 'دائن'}\n'
                'الدفع: ${e.payment.label}\nالمستودع: ${e.warehouseName}\n'
                'البيان: ${e.details}\n\n'
                'عرض محلي فقط؛ وصف الأصناف نصي ولا يمثل بنود فاتورة محفوظة.'),
      ),
    );

class HomeQuickSearchScreen extends StatefulWidget {
  const HomeQuickSearchScreen({super.key, required this.controller});
  final ErpController controller;
  @override
  State<HomeQuickSearchScreen> createState() => _HomeQuickSearchScreenState();
}

class _HomeQuickSearchScreenState extends State<HomeQuickSearchScreen> {
  String _query = '';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final active = _query.trim().isNotEmpty;
          final accounts = active
              ? c.accounts
                  .where((a) =>
                      _matches(_query, [a.name, a.codeNumber, a.phone, a.note]))
                  .toList()
              : <AccountRecord>[];
          final entries = active
              ? c.ledger
                  .where((e) => !e.deleted && _entryMatches(_query, e))
                  .toList()
              : <LedgerEntryRecord>[];
          final items = active
              ? c.inventory
                  .where((i) => _matches(_query, [i.name, i.sku, i.id]))
                  .toList()
              : <InventoryItemRecord>[];
          return Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('البحث السريع المحلي'),
                  const Text(
                      'بحث في السجلات المحملة فقط. لا يشمل المحذوف ولا يتصل بالخادم.'),
                  TextField(
                      key: const ValueKey('quick-search-query'),
                      decoration: const InputDecoration(
                          labelText: 'اسم، رقم، هاتف، مستند أو بيان'),
                      onChanged: (v) => setState(() => _query = v)),
                  if (!active) const Text('اكتب كلمة أو رقماً لبدء البحث.'),
                  if (active) ...[
                    Text(
                        'الحسابات: ${accounts.length} · القيود: ${entries.length} · الأصناف: ${items.length}'),
                    if (accounts.isEmpty && entries.isEmpty && items.isEmpty)
                      const Text('لا توجد نتائج مطابقة.'),
                    ...accounts.map((a) => Card(
                            child: ListTile(
                          key: ValueKey('lookup-account-${a.id}'),
                          title: Text(a.name),
                          subtitle:
                              Text('${a.codeNumber} · ${a.category.label}'),
                          onTap: () => _details(
                              context,
                              a.name,
                              'الفئة: ${a.category.label}\nالرقم: ${a.codeNumber}\nالهاتف: ${a.phone}\n'
                              'عملة الحساب: ${a.currency.label}\n'
                              'الافتتاحي فقط: ${_amount(a.openingBalance)} '
                              '${a.openingDirection == EntryDirection.debit ? 'مدين' : 'دائن'}\n'
                              'ملاحظات: ${a.note}'),
                        ))),
                    ...entries.map((e) => _entryTile(context, e)),
                    ...items.map((i) => Card(
                            child: ListTile(
                          key: ValueKey('lookup-item-${i.id}'),
                          title: Text(i.name),
                          subtitle: Text(
                              '${i.sku} · الرصيد الحالي ${_amount(i.quantity)} ${i.unit}'),
                          onTap: () => _details(
                              context,
                              i.name,
                              'SKU: ${i.sku}\nالمستودع (معرف): ${i.warehouseId}\n'
                              'الرصيد الحالي: ${_amount(i.quantity)} ${i.unit}\n'
                              'متوسط التكلفة المسجل: ${_amount(i.avgCost)}\n'
                              'حد التنبيه: ${_amount(i.minThreshold)}\n'
                              'لقطة حالية وليست حركة تاريخية؛ عملة تكلفة الصنف غير متاحة في النموذج.'),
                        ))),
                  ],
                ],
              ));
        },
      );
}

class DailyMovementScreen extends StatefulWidget {
  const DailyMovementScreen(
      {super.key, required this.controller, this.initialDate});
  final ErpController controller;
  final DateTime? initialDate;
  @override
  State<DailyMovementScreen> createState() => _DailyMovementScreenState();
}

class _DailyMovementScreenState extends State<DailyMovementScreen> {
  late DateTime _day;
  String _query = '';
  CurrencyCode? _currency;
  LedgerKind? _kindFilter;
  @override
  void initState() {
    super.initState();
    _day = widget.initialDate ?? DateTime.now();
  }

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(
        context: context,
        initialDate: _day,
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, 31));
    if (chosen != null && mounted) setState(() => _day = chosen);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final day = _date(_day);
          final entries = widget.controller.ledger
              .where((e) =>
                  !e.deleted &&
                  (e.entryDate == day || e.entryDate.startsWith('${day}T')) &&
                  (_currency == null || e.currency == _currency) &&
                  (_kindFilter == null || e.kind == _kindFilter) &&
                  _entryMatches(_query, e))
              .toList()
            ..sort((a, b) => b.entryNumber.compareTo(a.entryNumber));
          final financialEntries = entries.where(_financial).toList();
          final dayDebit = financialEntries
              .where((e) => e.direction == EntryDirection.debit)
              .fold<double>(0, (s, e) => s + e.amount);
          final dayCredit = financialEntries
              .where((e) => e.direction == EntryDirection.credit)
              .fold<double>(0, (s, e) => s + e.amount);
          return Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('الحركة اليومية المحلية'),
                  const Text('رؤوس القيود حسب تاريخها المسجل، وليست سجل مخزون. '
                      'المحذوف مستبعد، والعروض والطلبات موسومة غير مالية. لا تُجمع العملات.'),
                  OutlinedButton.icon(
                      key: const ValueKey('daily-date'),
                      onPressed: _chooseDate,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(day)),
                  DropdownButtonFormField<CurrencyCode>(
                      key: const ValueKey('daily-currency'),
                      isExpanded: true,
                      value: _currency,
                      decoration: const InputDecoration(labelText: 'العملة'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('كل العملات (بدون جمع)')),
                        ...CurrencyCode.values.map((c) =>
                            DropdownMenuItem(value: c, child: Text(c.label)))
                      ],
                      onChanged: (v) => setState(() => _currency = v)),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final (kind, label) in const [
                        (null, 'الكل'),
                        (LedgerKind.invoice, 'فواتير'),
                        (LedgerKind.voucher, 'سندات'),
                        (LedgerKind.transfer, 'حوالات'),
                        (LedgerKind.simpleEntry, 'قيود'),
                        (LedgerKind.currency, 'مصارفة'),
                        (LedgerKind.returnEntry, 'مرتجعات'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _kindFilter == kind,
                          onSelected: (_) => setState(() => _kindFilter = kind),
                        ),
                    ],
                  ),
                  if (_currency != null && financialEntries.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text('مدين اليوم: ${_amount(dayDebit)} ${_currency!.label}'),
                            Text('دائن اليوم: ${_amount(dayCredit)} ${_currency!.label}'),
                            Text(
                              'صافي اليوم: ${_amount(dayDebit - dayCredit)} ${_currency!.label}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextField(
                      key: const ValueKey('daily-search'),
                      decoration:
                          const InputDecoration(labelText: 'بحث ضمن اليوم'),
                      onChanged: (v) => setState(() => _query = v)),
                  Text('عدد السجلات: ${entries.length}'),
                  if (entries.isEmpty)
                    const Text('لا توجد قيود مطابقة لهذا اليوم.'),
                  ...entries.map((e) => _entryTile(context, e)),
                ],
              ));
        },
      );
}
