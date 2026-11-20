import 'package:flutter/material.dart';

import '../models/sale_facts.dart';

/// Displays persisted facts only. Never reconstructs historical tax or costs.
class OriginalSaleFactsView extends StatefulWidget {
  const OriginalSaleFactsView({
    super.key,
    required this.entryId,
    required this.loadFacts,
  });

  final String entryId;
  final Future<SaleFacts?> Function(String) loadFacts;

  @override
  State<OriginalSaleFactsView> createState() => _OriginalSaleFactsViewState();
}

class _OriginalSaleFactsViewState extends State<OriginalSaleFactsView> {
  late Future<SaleFacts?> _facts;

  @override
  void initState() {
    super.initState();
    _facts = _load();
  }

  @override
  void didUpdateWidget(covariant OriginalSaleFactsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId ||
        oldWidget.loadFacts != widget.loadFacts) {
      _facts = _load();
    }
  }

  Future<SaleFacts?> _load() async {
    final requestedId = widget.entryId;
    final facts = await widget.loadFacts(requestedId);
    if (facts != null && facts.entryId != requestedId) {
      throw StateError('The stored facts do not match the requested entry.');
    }
    return facts;
  }

  void _retry() => setState(() {
        _facts = _load();
      });

  // Do not round/recalculate source values, including tax and cost snapshots.
  String _value(double value) => value.isFinite
      ? value.toString().replaceFirst(RegExp(r'\.0$'), '')
      : 'قيمة محفوظة غير صالحة';

  Widget _fact(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          SelectableText(value),
        ]),
      );

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('حقائق البيع الأصلية')),
          body: FutureBuilder<SaleFacts?>(
            future: _facts,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Semantics(
                        liveRegion: true,
                        child: const Text(
                            'تعذر قراءة حقائق البيع المحلية. لم يتم تغيير أي بيانات.')),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة')),
                  ]),
                ));
              }
              final facts = snapshot.data;
              return ListView(padding: const EdgeInsets.all(16), children: [
                const Text(
                    'للاطلاع فقط: القيم الأصلية المخزنة وقت البيع، وليست اعتماداً لمرتجع أو رد مبلغ. لا ترحيل ولا إعادة حساب للضريبة.'),
                _fact('مرجع البيع الأصلي', widget.entryId),
                if (facts == null) ...[
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                              'لا توجد حقائق أصلية محفوظة لهذا المرجع. قد تكون الفاتورة قديمة؛ الضريبة وتكلفة البيع التاريخيتان غير معلومتين. لا تُستنتج القيم من الإجمالي أو من تكلفة المخزون الحالية.'))),
                ] else ...[
                  _fact('عملة البيع المحفوظة', facts.currency.label),
                  _fact('الإجمالي قبل الضريبة المحفوظ',
                      '${_value(facts.preTaxTotal)} ${facts.currency.label}'),
                  _fact('حالة الضريبة وقت البيع',
                      facts.taxEnabled ? 'مفعّلة' : 'غير مفعّلة'),
                  _fact('نسبة الضريبة المحفوظة (كسر عشري)',
                      _value(facts.appliedTaxRate)),
                  const Text(
                      'مثال توضيحي للنسبة: 0.15 تعني 15٪. لا تُطبّق نسبة جديدة على الفاتورة.'),
                  _fact('مبلغ الضريبة المحفوظ',
                      '${_value(facts.taxAmount)} ${facts.currency.label}'),
                  _fact('الإجمالي النهائي المحفوظ',
                      '${_value(facts.finalTotal)} ${facts.currency.label}'),
                  const Divider(),
                  Text('لقطات تكلفة بنود البيع',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Text(
                      'متوسط تكلفة المخزون المحفوظ عند البيع. عملة تكلفة المخزون غير مسجلة؛ لا يُفترض أنها عملة الفاتورة. ليست تكلفة بضاعة مباعة معتمدة ولا تكلفة المخزون الحالية.'),
                  if (facts.lineCosts.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('لا توجد لقطات تكلفة محفوظة للبنود.')),
                  for (final line in facts.lineCosts)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'البند ${line.position + 1} • الموضع الأصلي ${line.position}'),
                                  Text(line.stockAverageCost == null
                                      ? 'متوسط التكلفة التاريخي غير محفوظ؛ ليس صفراً.'
                                      : 'متوسط التكلفة المحفوظ: ${_value(line.stockAverageCost!)} (دون تحويل)'),
                                ]))),
                ],
              ]);
            },
          ),
        ),
      );
}
