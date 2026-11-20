import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../models/draft_amount_text.dart';
import '../models/fx_draft.dart';

typedef FxDraftSave = Future<FxDraft> Function(FxDraft);
String _normalize(String input) {
  var text = input.trim();
  for (var i = 0; i < 10; i++) {
    text = text
        .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
        .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
  }
  return text.replaceAll('٫', '.');
}

class FxDraftsView extends StatefulWidget {
  const FxDraftsView(
      {super.key,
      required this.loadDrafts,
      required this.loadDraft,
      required this.loadAccounts,
      required this.saveDraft,
      this.createOnOpen = false});
  final Future<List<FxDraft>> Function() loadDrafts;
  final Future<FxDraft?> Function(int) loadDraft;
  final Future<List<AccountRecord>> Function() loadAccounts;
  final FxDraftSave saveDraft;
  final bool createOnOpen;
  @override
  State<FxDraftsView> createState() => _FxDraftsViewState();
}

class _FxDraftsViewState extends State<FxDraftsView> {
  late Future<List<FxDraft>> _drafts;
  bool _opening = false;
  String? _error;
  int? _lastOpenId;
  @override
  void initState() {
    super.initState();
    _drafts = Future.sync(widget.loadDrafts);
    if (widget.createOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open();
      });
    }
  }

  void _reload() {
    setState(() {
      _drafts = Future.sync(widget.loadDrafts);
    });
  }

  Future<void> _open([int? id]) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _lastOpenId = id;
      _error = null;
    });
    try {
      final draft = id == null ? null : await widget.loadDraft(id);
      if (id != null && draft == null) {
        throw StateError('Draft missing or wrong type');
      }
      final accounts = await widget.loadAccounts();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<FxDraft>(MaterialPageRoute(
          builder: (_) => FxDraftEditor(
              accounts: accounts, saveDraft: widget.saveDraft, draft: draft)));
      if (mounted && saved != null) _reload();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'تعذر قراءة المسودة أو الحسابات المحلية. لم تُغيّر البيانات.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(title: const Text('مسودات صرف العملات')),
          floatingActionButton: FloatingActionButton.extended(
              onPressed: _opening ? null : () => _open(),
              icon: const Icon(Icons.add),
              label: const Text('إنشاء مسودة صرف عملات')),
          body: Column(children: [
            const _FxNotice(),
            if (_opening) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    Semantics(liveRegion: true, child: Text(_error!)),
                    TextButton(
                        onPressed: _opening ? null : () => _open(_lastOpenId),
                        child: const Text('إعادة المحاولة')),
                  ])),
            Expanded(
                child: FutureBuilder<List<FxDraft>>(
                    future: _drafts,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                            child: TextButton(
                                onPressed: _reload,
                                child: const Text(
                                    'تعذر تحميل القائمة. إعادة المحاولة')));
                      }
                      final drafts = snapshot.data ?? [];
                      if (drafts.isEmpty) {
                        return const Center(
                            child: Text('لا توجد مسودات محفوظة.'));
                      }
                      return ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                          children: [
                            for (final d in drafts)
                              Card(
                                  child: ListTile(
                                      title: Text(
                                          'مسودة صرف عملات #${d.id ?? "—"}'),
                                      subtitle: Text(
                                          '${d.date} • ${d.sourceAmount} ${d.sourceCurrency.label} / ${d.destinationAmount} ${d.destinationCurrency.label}\nغير معتمد وغير مرحّل'),
                                      isThreeLine: true,
                                      onTap: _opening || d.id == null
                                          ? null
                                          : () => _open(d.id))),
                          ]);
                    })),
          ])));
}

class _FxNotice extends StatelessWidget {
  const _FxNotice();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.all(12),
      child: Text(
          'مسودة صرف عملات فقط، وليست صرفاً فعلياً أو اعتماداً. المبلغان يدويان مستقلان؛ لا حساب أو جلب لسعر صرف، ولا رسوم أو ترحيل أو تغيير أرصدة أو مخزون.'));
}

class FxDraftEditor extends StatefulWidget {
  const FxDraftEditor(
      {super.key, required this.accounts, required this.saveDraft, this.draft});
  final List<AccountRecord> accounts;
  final FxDraftSave saveDraft;
  final FxDraft? draft;
  @override
  State<FxDraftEditor> createState() => _FxDraftEditorState();
}

class _FxDraftEditorState extends State<FxDraftEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _date,
      _sourceAmount,
      _destinationAmount,
      _note;
  String? _sourceId, _destinationId, _error;
  bool _saving = false;
  List<AccountRecord> get _cashboxes =>
      widget.accounts.where((a) => a.isCashAccount).toList();
  AccountRecord? _account(String? id) {
    for (final a in _cashboxes) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<AccountRecord> get _sources => _cashboxes
      .where((a) =>
          _cashboxes.any((b) => b.id != a.id && b.currency != a.currency))
      .toList();
  List<AccountRecord> get _destinations {
    final source = _account(_sourceId);
    return source == null
        ? []
        : _cashboxes
            .where((a) => a.id != source.id && a.currency != source.currency)
            .toList();
  }

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _date = TextEditingController(
        text: d?.date ?? DateTime.now().toIso8601String().substring(0, 10));
    _sourceAmount =
        TextEditingController(text: draftAmountText(d?.sourceAmount));
    _destinationAmount =
        TextEditingController(text: draftAmountText(d?.destinationAmount));
    _note = TextEditingController(text: d?.note ?? '');
    _sourceId = d?.sourceCashId;
    _destinationId = d?.destinationCashId;
  }

  @override
  void dispose() {
    _date.dispose();
    _sourceAmount.dispose();
    _destinationAmount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _dateError(String? raw) {
    final s = _normalize(raw ?? '');
    final d = DateTime.tryParse(s);
    return !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ||
            d == null ||
            d.toIso8601String().substring(0, 10) != s
        ? 'أدخل تاريخاً صحيحاً YYYY-MM-DD'
        : null;
  }

  String? _amountError(String? raw) {
    final s = _normalize(raw ?? '');
    final n = double.tryParse(s);
    return !RegExp(r'^\d+(\.\d+)?$').hasMatch(s) ||
            n == null ||
            !n.isFinite ||
            n <= 0
        ? 'أدخل مبلغاً موجباً يدوياً'
        : null;
  }

  bool get _originalCurrenciesChanged {
    final d = widget.draft;
    if (d == null) return false;
    return (_sourceId == d.sourceCashId &&
            _account(_sourceId)?.currency != d.sourceCurrency) ||
        (_destinationId == d.destinationCashId &&
            _account(_destinationId)?.currency != d.destinationCurrency);
  }

  Future<void> _save() async {
    if (_saving) return;
    final formValid = _form.currentState!.validate();
    final source = _account(_sourceId), destination = _account(_destinationId);
    final valid = source != null &&
        destination != null &&
        source.id != destination.id &&
        source.currency != destination.currency &&
        !_originalCurrenciesChanged &&
        _dateError(_date.text) == null &&
        _amountError(_sourceAmount.text) == null &&
        _amountError(_destinationAmount.text) == null;
    if (!formValid || !valid) {
      setState(() => _error =
          'راجع الصندوقين بعملتين مختلفتين والتاريخ والمبلغين؛ لا يُحسب مبلغ من الآخر.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.saveDraft(FxDraft(
          id: widget.draft?.id,
          revision: widget.draft?.revision ?? 0,
          date: _normalize(_date.text),
          sourceCashId: source.id,
          destinationCashId: destination.id,
          sourceCurrency: source.currency,
          destinationCurrency: destination.currency,
          sourceAmount: double.parse(_normalize(_sourceAmount.text)),
          destinationAmount: double.parse(_normalize(_destinationAmount.text)),
          note: _note.text.trim()));
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'لم يتم تأكيد حفظ المسودة. بقيت المدخلات هنا؛ إن تغيّرت المسودة أو الحسابات فأعد فتحها قبل المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source =
        _sources.any((a) => a.id == _sourceId) ? _account(_sourceId) : null;
    final destination = _destinations.any((a) => a.id == _destinationId)
        ? _account(_destinationId)
        : null;
    return PopScope(
        canPop: !_saving,
        child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                  title: Text(
                      '${widget.draft == null ? "إنشاء" : "تعديل"} مسودة صرف عملات')),
              body: AbsorbPointer(
                  absorbing: _saving,
                  child: Form(
                      key: _form,
                      child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            const _FxNotice(),
                            if (_sources.isEmpty)
                              const Text(
                                  'يلزم صندوقان نقديان محفوظان بعملتين مختلفتين. لا تُنشأ حسابات تلقائياً.'),
                            if (_originalCurrenciesChanged)
                              const Text(
                                  'تغيّرت عملة صندوق مرتبط بالمسودة الأصلية أو لم يعد متاحاً. لا يمكن إعادة تفسير المبلغ المحفوظ بعملة جديدة.'),
                            DropdownButtonFormField<String>(
                                key: const Key('fx-source'),
                                value: source?.id,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'صندوق المصدر'),
                                items: _sources
                                    .map((a) => DropdownMenuItem(
                                        value: a.id,
                                        child: Text(
                                            '${a.name} • ${a.currency.label}',
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                validator: (v) =>
                                    v == null ? 'اختر صندوق المصدر' : null,
                                onChanged: (id) {
                                  if (id != _sourceId) {
                                    setState(() {
                                      _sourceId = id;
                                      _destinationId = null;
                                      _sourceAmount.clear();
                                      _destinationAmount.clear();
                                    });
                                  }
                                }),
                            DropdownButtonFormField<String>(
                                key: ValueKey('fx-destination-$_sourceId'),
                                value: destination?.id,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'صندوق الوجهة بعملة مختلفة'),
                                items: _destinations
                                    .map((a) => DropdownMenuItem(
                                        value: a.id,
                                        child: Text(
                                            '${a.name} • ${a.currency.label}',
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                validator: (v) =>
                                    v == null ? 'اختر صندوق الوجهة' : null,
                                onChanged: (id) {
                                  if (id != _destinationId) {
                                    setState(() {
                                      _destinationId = id;
                                      _destinationAmount.clear();
                                    });
                                  }
                                }),
                            TextFormField(
                                key: const Key('fx-date'),
                                controller: _date,
                                decoration: const InputDecoration(
                                    labelText: 'التاريخ YYYY-MM-DD'),
                                validator: _dateError),
                            TextFormField(
                                key: const Key('fx-source-amount'),
                                controller: _sourceAmount,
                                decoration: InputDecoration(
                                    labelText:
                                        'مبلغ المصدر اليدوي (${source?.currency.label ?? "اختر المصدر"})'),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                validator: _amountError),
                            TextFormField(
                                key: const Key('fx-destination-amount'),
                                controller: _destinationAmount,
                                decoration: InputDecoration(
                                    labelText:
                                        'مبلغ الوجهة اليدوي (${destination?.currency.label ?? "اختر الوجهة"})'),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                validator: _amountError),
                            TextFormField(
                                key: const Key('fx-note'),
                                controller: _note,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                    labelText: 'ملاحظة اختيارية')),
                            if (_error != null)
                              Semantics(liveRegion: true, child: Text(_error!)),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                                key: const Key('fx-save'),
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.save_outlined),
                                label: Text(_saving
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
