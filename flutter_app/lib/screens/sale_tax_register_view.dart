import 'package:flutter/material.dart';

import '../models/sale_tax_register.dart';

/// A local, read-only register of stored sale facts, not a tax declaration.
class SaleTaxRegisterView extends StatefulWidget {
  const SaleTaxRegisterView({super.key, required this.loadRegister});
  final Future<SaleTaxRegister> Function({String? from, String? through})
      loadRegister;

  @override
  State<SaleTaxRegisterView> createState() => _SaleTaxRegisterViewState();
}

class _SaleTaxRegisterViewState extends State<SaleTaxRegisterView> {
  final _from = TextEditingController();
  final _through = TextEditingController();
  final _form = GlobalKey<FormState>();
  SaleTaxRegister? _register;
  bool _loading = true;
  bool _failed = false;
  int _request = 0;
  String? _appliedFrom;
  String? _appliedThrough;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _dateError(String? text) {
    final value = text?.trim() ?? '';
    if (value.isEmpty) return null;
    final date = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        date == null ||
        date.toIso8601String().substring(0, 10) != value) {
      return 'أدخل تاريخاً صحيحاً YYYY-MM-DD';
    }
    return null;
  }

  Future<void> _load({bool apply = false}) async {
    if (apply) {
      if (!(_form.currentState?.validate() ?? false)) return;
      final from = _from.text.trim();
      final through = _through.text.trim();
      if (from.isNotEmpty &&
          through.isNotEmpty &&
          from.compareTo(through) > 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تاريخ البداية يجب ألا يتجاوز النهاية')));
        return;
      }
      _appliedFrom = from.isEmpty ? null : from;
      _appliedThrough = through.isEmpty ? null : through;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final value = await widget.loadRegister(
          from: _appliedFrom, through: _appliedThrough);
      if (!mounted || request != _request) return;
      setState(() {
        _register = value;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _from.dispose();
    _through.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar:
              AppBar(title: const Text('الضريبة الموثقة على المبيعات المحلية')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'سجل محلي للقراءة فقط يعرض الضريبة المحفوظة كما هي، دون إعادة احتساب. ليس إقراراً ضريبياً أو تحديداً للالتزام الضريبي. لا يشمل المرتجعات أو تحويل العملات.'),
            const SizedBox(height: 12),
            Form(
                key: _form,
                child: Column(children: [
                  TextFormField(
                      key: const Key('tax-from'),
                      controller: _from,
                      validator: _dateError,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'من (اختياري، YYYY-MM-DD)')),
                  TextFormField(
                      key: const Key('tax-through'),
                      controller: _through,
                      validator: _dateError,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'حتى (اختياري، YYYY-MM-DD)')),
                  const Text(
                      'يشمل النطاق يومي البداية والنهاية. اترك الحقول فارغة لعرض كل التواريخ.'),
                  FilledButton(
                      onPressed: _loading ? null : () => _load(apply: true),
                      child: const Text('تطبيق الفترة')),
                ])),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_failed) ...[
              const Text('تعذر تحميل السجل المحلي. لم تُغيّر أي بيانات.'),
              OutlinedButton(
                  onPressed: _load, child: const Text('إعادة المحاولة')),
            ] else if (_register != null)
              ..._results(_register!),
          ]),
        ),
      );

  List<Widget> _results(SaleTaxRegister register) => [
        Text(
            'الفترة المعروضة: ${_appliedFrom ?? 'البداية'} إلى ${_appliedThrough ?? 'النهاية'}'),
        if (register.currencies.isEmpty && register.invalidHeaderCount == 0)
          const Text('لا توجد مبيعات محلية ضمن الفترة المحددة.'),
        if (register.invalidHeaderCount > 0)
          Text(
              'رؤوس غير صالحة مستبعدة من الإجماليات: ${register.invalidHeaderCount}'),
        for (final summary in register.currencies)
          Card(
              child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(summary.currency.label,
                  style: Theme.of(context).textTheme.titleLarge),
              Text('عدد المبيعات ذات الضريبة الموثقة: ${summary.knownCount}'),
              if (summary.knownCount == 0)
                const Text('لا توجد مبالغ ضريبية موثقة لهذه العملة.')
              else ...[
                Text(
                    'قبل الضريبة الموثق: ${summary.preTaxTotal.toStringAsFixed(2)} ${summary.currency.label}'),
                Text(
                    'الضريبة المحفوظة: ${summary.taxAmount.toStringAsFixed(2)} ${summary.currency.label}'),
                Text(
                    'الإجمالي النهائي الموثق: ${summary.finalTotal.toStringAsFixed(2)} ${summary.currency.label}'),
              ],
              const Divider(),
              Text(
                  'مبيعات قديمة أو غير موثقة ضريبياً: ${summary.unknownCount}'),
              const Text(
                  'المجهول ليس ضريبة صفرية؛ لا يدخل في الإجماليات الموثقة أعلاه.'),
            ]),
          )),
        const Text(
            'تُعرض كل عملة مستقلة دون إجمالي مشترك. لا يثبت هذا السجل اكتمال البيانات أو صحة الالتزام الضريبي.'),
      ];
}
