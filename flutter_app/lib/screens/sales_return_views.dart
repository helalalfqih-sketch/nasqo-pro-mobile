import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../models/sales_return_draft.dart';
import '../models/sale_facts.dart';
import '../models/sales_return_estimate.dart';

/// Original immutable sale data supplied by the local controller/store.
class SalesReturnSource {
  SalesReturnSource({required this.entry, required List<SavedSaleLine> lines})
      : lines = List.unmodifiable(lines);
  final LedgerEntryRecord entry;
  final List<SavedSaleLine> lines;
  bool get eligible =>
      isEligibleSalesReturnSource(entry) &&
      lines.isNotEmpty &&
      lines.every((l) =>
          l.entryId == entry.id &&
          l.quantity.isFinite &&
          l.quantity > 0 &&
          l.unitPrice.isFinite &&
          l.unitPrice >= 0) &&
      lines.map((l) => l.position).toSet().length == lines.length;
}

typedef SalesReturnSave = Future<SalesReturnDraft> Function(
    {int? id,
    int revision,
    required String sourceEntryId,
    required String date,
    required String reason,
    required List<SalesReturnSelection> selections});

class SalesReturnDraftsView extends StatefulWidget {
  const SalesReturnDraftsView(
      {super.key,
      required this.loadDrafts,
      required this.loadDraft,
      required this.loadSales,
      required this.saveDraft,
      this.loadFacts});
  final Future<List<SalesReturnDraft>> Function() loadDrafts;
  final Future<SalesReturnDraft?> Function(int id) loadDraft;
  final Future<List<SalesReturnSource>> Function() loadSales;
  final SalesReturnSave saveDraft;
  final Future<SaleFacts?> Function(String)? loadFacts;
  @override
  State<SalesReturnDraftsView> createState() => _SalesReturnDraftsViewState();
}

class _SalesReturnDraftsViewState extends State<SalesReturnDraftsView> {
  late Future<List<SalesReturnDraft>> _drafts;
  bool _opening = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _drafts = Future.sync(widget.loadDrafts);
  }

  void _refresh() => setState(() {
        _drafts = Future.sync(widget.loadDrafts);
      });
  Future<void> _open([int? id]) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final draft = id == null ? null : await widget.loadDraft(id);
      if (id != null && draft == null) throw StateError('Missing draft');
      final sources =
          (await widget.loadSales()).where((s) => s.eligible).toList();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<SalesReturnDraft>(
          MaterialPageRoute(
              builder: (_) => SalesReturnDraftEditor(
                  sources: sources,
                  draft: draft,
                  saveDraft: widget.saveDraft)));
      if (mounted && saved != null) _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر فتح البيانات المحلية. حاول مجدداً.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openEstimate(int id) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final saved = await widget.loadDraft(id);
      if (saved == null) throw StateError('Missing saved draft');
      final sources = await widget.loadSales();
      SalesReturnSource? source;
      for (final candidate in sources) {
        if (candidate.entry.id == saved.sourceEntryId && candidate.eligible) {
          source = candidate;
          break;
        }
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => SalesReturnEstimateView(
              draft: saved, source: source, loadFacts: widget.loadFacts)));
      // Viewing an estimate never saves, reloads or replaces the list's drafts.
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'تعذر قراءة المسودة أو الفاتورة الأصلية. لم تتغير البيانات.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(title: const Text('مسودات مرتجعات المبيعات')),
          floatingActionButton: FloatingActionButton.extended(
              onPressed: _opening ? null : () => _open(),
              icon: const Icon(Icons.add),
              label: const Text('إنشاء مسودة مرتجع')),
          body: Column(children: [
            const _DraftNotice(),
            if (_opening) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            Expanded(
                child: FutureBuilder<List<SalesReturnDraft>>(
                    future: _drafts,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                            child: TextButton(
                                onPressed: _refresh,
                                child: const Text(
                                    'تعذر تحميل المسودات. إعادة المحاولة')));
                      }
                      final docs = snapshot.data ?? [];
                      if (docs.isEmpty) {
                        return const Center(
                            child: Text('لا توجد مسودات مرتجعات.'));
                      }
                      return ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                          children: [
                            for (final d in docs)
                              Card(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    ListTile(
                                        title: Text(
                                            'مسودة #${d.id} • ${d.accountName}'),
                                        subtitle: Text(
                                            '${d.date}\nتقدير قبل الضريبة: ${d.subtotal.toStringAsFixed(2)} ${d.currency.label}'),
                                        isThreeLine: true,
                                        onTap: _opening
                                            ? null
                                            : () => _open(d.id)),
                                    TextButton.icon(
                                        key: Key('estimate-draft-${d.id}'),
                                        onPressed: _opening
                                            ? null
                                            : () => _openEstimate(d.id),
                                        icon: const Icon(
                                            Icons.calculate_outlined),
                                        label: const Text(
                                            'تقدير ضريبة النسخة المحفوظة')),
                                  ])),
                          ]);
                    })),
          ])));
}

class _DraftNotice extends StatelessWidget {
  const _DraftNotice();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.all(12),
      child: Text(
          'مسودة غير مرحّلة فقط. لا تغيّر المخزون أو الحسابات أو الصندوق، ولا ترد أي مبلغ. المسودات لا تحجز كميات ولا تثبت تنفيذ مرتجع.'));
}

String _normalize(String input) {
  var value = input.trim();
  for (var i = 0; i < 10; i++) {
    value = value
        .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
        .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
  }
  return value.replaceAll('٫', '.');
}

class SalesReturnDraftEditor extends StatefulWidget {
  const SalesReturnDraftEditor(
      {super.key, required this.sources, required this.saveDraft, this.draft});
  final List<SalesReturnSource> sources;
  final SalesReturnSave saveDraft;
  final SalesReturnDraft? draft;
  @override
  State<SalesReturnDraftEditor> createState() => _SalesReturnDraftEditorState();
}

class _SalesReturnDraftEditorState extends State<SalesReturnDraftEditor> {
  final _form = GlobalKey<FormState>();
  final Map<int, TextEditingController> _quantities = {};
  late final TextEditingController _date, _reason;
  String? _sourceId;
  String? _error;
  bool _saving = false;
  List<SalesReturnSource> get _eligible =>
      widget.sources.where((s) => s.eligible).toList();
  SalesReturnSource? get _source {
    for (final source in _eligible) {
      if (source.entry.id == _sourceId) return source;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(
        text: widget.draft?.date ??
            DateTime.now().toIso8601String().substring(0, 10));
    _reason = TextEditingController(text: widget.draft?.reason ?? '');
    _sourceId = widget.draft?.sourceEntryId;
    _resetQuantities();
  }

  void _resetQuantities() {
    for (final c in _quantities.values) {
      c.dispose();
    }
    _quantities.clear();
    for (final line in _source?.lines ?? <SavedSaleLine>[]) {
      final saved =
          widget.draft?.lines.where((l) => l.position == line.position);
      _quantities[line.position] = TextEditingController(
          text: saved != null && saved.isNotEmpty
              ? saved.first.quantity.toString()
              : '0');
    }
  }

  @override
  void dispose() {
    for (final c in _quantities.values) {
      c.dispose();
    }
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  String? _dateError(String? raw) {
    final text = _normalize(raw ?? '');
    final parsed = DateTime.tryParse(text);
    return !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
            parsed == null ||
            parsed.toIso8601String().substring(0, 10) != text
        ? 'التاريخ غير صالح؛ استخدم YYYY-MM-DD'
        : null;
  }

  String? _quantityError(String? raw, double max) {
    final text = _normalize(raw ?? '');
    final q = double.tryParse(text);
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text) ||
        q == null ||
        !q.isFinite ||
        q < 0 ||
        q > max) {
      return 'أدخل كمية من صفر إلى $max';
    }
    return null;
  }

  double get _subtotal {
    var total = 0.0;
    for (final line in _source?.lines ?? <SavedSaleLine>[]) {
      final raw = _quantities[line.position]!.text;
      if (_quantityError(raw, line.quantity) == null) {
        total += double.parse(_normalize(raw)) * line.unitPrice;
      }
    }
    return total;
  }

  Future<void> _save() async {
    if (_saving) return;
    final source = _source;
    final formValid = _form.currentState!.validate();
    final valid = source != null &&
        _dateError(_date.text) == null &&
        _reason.text.trim().isNotEmpty &&
        source.lines.every((l) =>
            _quantityError(_quantities[l.position]!.text, l.quantity) == null);
    if (!formValid || !valid) {
      setState(
          () => _error = 'راجع الفاتورة الأصلية والتاريخ والسبب والكميات.');
      return;
    }
    final selections = [
      for (final l in source.lines)
        if (double.parse(_normalize(_quantities[l.position]!.text)) > 0)
          SalesReturnSelection(
              position: l.position,
              quantity: double.parse(_normalize(_quantities[l.position]!.text)))
    ];
    if (selections.isEmpty || !_subtotal.isFinite) {
      setState(
          () => _error = 'حدد كمية موجبة لبند واحد على الأقل وبقيمة صالحة.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.saveDraft(
          id: widget.draft?.id,
          revision: widget.draft?.revision ?? 0,
          sourceEntryId: source.entry.id,
          date: _normalize(_date.text),
          reason: _reason.text.trim(),
          selections: selections);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'لم يتم تأكيد حفظ المسودة. بقيت البيانات هنا؛ إن تغيّرت الفاتورة أو المسودة فأعد فتحها.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return PopScope(
        canPop: !_saving,
        child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                  title: Text(widget.draft == null
                      ? 'إنشاء مسودة مرتجع'
                      : 'تعديل مسودة #${widget.draft!.id}')),
              body: AbsorbPointer(
                  absorbing: _saving,
                  child: Form(
                      key: _form,
                      child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            const _DraftNotice(),
                            if (_eligible.isEmpty ||
                                (widget.draft != null && source == null))
                              const Text(
                                  'لا توجد فاتورة أصلية مؤهلة ذات بنود محفوظة. لا يمكن حفظ هذه المسودة.'),
                            DropdownButtonFormField<String>(
                                key: const Key('return-source'),
                                value: source?.entry.id,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'فاتورة المبيعات الأصلية'),
                                items: _eligible
                                    .map((s) => DropdownMenuItem(
                                        value: s.entry.id,
                                        child: Text(
                                            '#${s.entry.entryNumber} • ${s.entry.accountName} • ${s.entry.currency.label}',
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: widget.draft != null
                                    ? null
                                    : (id) => setState(() {
                                          _sourceId = id;
                                          _resetQuantities();
                                          _error = null;
                                        })),
                            TextFormField(
                                key: const Key('return-date'),
                                controller: _date,
                                decoration: const InputDecoration(
                                    labelText: 'التاريخ YYYY-MM-DD'),
                                validator: _dateError),
                            TextFormField(
                                key: const Key('return-reason'),
                                controller: _reason,
                                decoration: const InputDecoration(
                                    labelText: 'سبب المرتجع'),
                                validator: (s) => (s ?? '').trim().isEmpty
                                    ? 'السبب مطلوب'
                                    : null),
                            if (source != null) ...[
                              Text(
                                  'العميل: ${source.entry.accountName} • ${source.entry.currency.label}'),
                              for (final line in source.lines)
                                Card(
                                    key: ValueKey(
                                        '${source.entry.id}:${line.position}'),
                                    child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  'البند ${line.position + 1}: ${line.itemName}'),
                                              Text(
                                                  'المباع: ${line.quantity} ${line.unit} • سعر الوحدة: ${line.unitPrice.toStringAsFixed(2)} ${source.entry.currency.label}'),
                                              TextFormField(
                                                  key: Key(
                                                      'return-qty-${line.position}'),
                                                  controller: _quantities[
                                                      line.position],
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  decoration: const InputDecoration(
                                                      labelText:
                                                          'كمية المسودة (صفر للاستبعاد)'),
                                                  validator: (raw) =>
                                                      _quantityError(
                                                          raw, line.quantity),
                                                  onChanged: (_) =>
                                                      setState(() {})),
                                            ]))),
                              Text(
                                  'تقدير جزئي قبل الضريبة: ${_subtotal.toStringAsFixed(2)} ${source.entry.currency.label}',
                                  key: const Key('return-estimate')),
                            ],
                            if (_error != null)
                              Semantics(liveRegion: true, child: Text(_error!)),
                            const SizedBox(height: 12),
                            FilledButton(
                                key: const Key('return-save'),
                                onPressed:
                                    _saving || source == null ? null : _save,
                                child: Text(_saving
                                    ? 'جارٍ حفظ المسودة…'
                                    : 'حفظ مسودة فقط')),
                            TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('إلغاء دون حفظ')),
                          ]))),
            )));
  }
}

/// Informational projection of an already saved draft; no persistence callback.
class SalesReturnEstimateView extends StatefulWidget {
  const SalesReturnEstimateView(
      {super.key, required this.draft, required this.source, this.loadFacts});
  final SalesReturnDraft draft;
  final SalesReturnSource? source;
  final Future<SaleFacts?> Function(String)? loadFacts;
  @override
  State<SalesReturnEstimateView> createState() =>
      _SalesReturnEstimateViewState();
}

class _SalesReturnEstimateViewState extends State<SalesReturnEstimateView> {
  late Future<SaleFacts?> _facts;
  @override
  void initState() {
    super.initState();
    _facts = _read();
  }

  Future<SaleFacts?> _read() async => widget.source == null
      ? null
      : await widget.loadFacts?.call(widget.draft.sourceEntryId);
  void _retry() {
    setState(() {
      _facts = _read();
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar:
              AppBar(title: Text('تقدير المسودة المحفوظة #${widget.draft.id}')),
          body: FutureBuilder<SaleFacts?>(
              future: _facts,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final source = widget.source;
                final sourceValid = source != null &&
                    source.eligible &&
                    source.entry.id == widget.draft.sourceEntryId &&
                    source.entry.currency == widget.draft.currency;
                final estimate = calculateSalesReturnEstimate(
                    draft: widget.draft,
                    originalLines: sourceValid ? source.lines : [],
                    facts: snapshot.data);
                final currency = widget.draft.currency.label;
                return ListView(padding: const EdgeInsets.all(16), children: [
                  const Text(
                      'تقدير إرشادي للنسخة المحفوظة فقط، وليس اعتماداً أو ترحيلاً أو استرداداً. لا يغيّر المخزون أو الحسابات أو الصندوق.'),
                  const SizedBox(height: 12),
                  const Text(
                      'كل مسودة تقدير مستقل. لا تجمع تقديرات المسودات، ولا تستخدمها للمقاصة أو التسوية أو تحديد مبلغ رد فعلي.'),
                  const Divider(),
                  Text('المرجع: ${widget.draft.sourceEntryId}'),
                  Text(
                      'النسخة المحفوظة: ${widget.draft.revision} • ${widget.draft.date}'),
                  Text('العميل: ${widget.draft.accountName}'),
                  Text('عملة البيع: $currency'),
                  const SizedBox(height: 16),
                  if (snapshot.hasError) ...[
                    Semantics(
                        liveRegion: true,
                        child: const Text(
                            'تعذر قراءة حقائق البيع الأصلية. لم تُحفظ أو تُعدّل أي بيانات.')),
                    OutlinedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة')),
                  ] else if (!sourceValid) ...[
                    const Text(
                        'التقدير غير متاح: الفاتورة الأصلية أو بنودها غير متاحة أو غير مؤهلة، أو العملة غير مطابقة.'),
                  ] else if (widget.loadFacts == null ||
                      snapshot.data == null) ...[
                    const Text(
                        'التقدير غير متاح: لا توجد حقائق ضريبية أصلية محفوظة. للفواتير القديمة تظل الضريبة والإجمالي مجهولين؛ لا يُفترضان صفراً ولا تُستخدم نسبة حالية.'),
                  ] else if (!estimate.available) ...[
                    Text(
                        'التقدير غير متاح: ${estimate.unavailableReason ?? "البيانات الأصلية غير متسقة."}'),
                  ] else ...[
                    Text(estimate.isFullReturn
                        ? 'تقدير لجميع الكميات الأصلية: يستخدم مبالغ البيع الأصلية المحفوظة.'
                        : 'تقدير جزئي: توزيع نسبي لمبلغ الضريبة الأصلي المحفوظ، مع التقريب إلى منزلتين؛ ليس ضريبة معتمدة.'),
                    const SizedBox(height: 12),
                    Text(
                        'قبل الضريبة: ${estimate.preTaxTotal!.toStringAsFixed(2)} $currency',
                        key: const Key('return-estimate-pretax')),
                    Text(
                        'الضريبة التقديرية: ${estimate.taxAmount!.toStringAsFixed(2)} $currency',
                        key: const Key('return-estimate-tax')),
                    Text(
                        'الإجمالي التقديري: ${estimate.finalTotal!.toStringAsFixed(2)} $currency',
                        key: const Key('return-estimate-total')),
                  ],
                  const SizedBox(height: 20),
                  OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('رجوع دون تغيير')),
                ]);
              })));
}
