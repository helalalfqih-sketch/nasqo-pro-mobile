import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../models/draft_amount_text.dart';
import '../models/simple_journal_draft.dart';

typedef SimpleJournalDraftSave = Future<SimpleJournalDraft> Function(
    SimpleJournalDraft);
String _normalize(String input) {
  var text = input.trim();
  for (var i = 0; i < 10; i++) {
    text = text
        .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
        .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
  }
  return text.replaceAll('٫', '.');
}

class SimpleJournalDraftsView extends StatefulWidget {
  const SimpleJournalDraftsView(
      {super.key,
      required this.loadDrafts,
      required this.loadDraft,
      required this.loadAccounts,
      required this.saveDraft,
      this.createOnOpen = false,
      this.initialCurrency = CurrencyCode.sar});
  final Future<List<SimpleJournalDraft>> Function() loadDrafts;
  final Future<SimpleJournalDraft?> Function(int) loadDraft;
  final Future<List<AccountRecord>> Function() loadAccounts;
  final SimpleJournalDraftSave saveDraft;
  final bool createOnOpen;
  final CurrencyCode initialCurrency;
  @override
  State<SimpleJournalDraftsView> createState() =>
      _SimpleJournalDraftsViewState();
}

class _SimpleJournalDraftsViewState extends State<SimpleJournalDraftsView> {
  late Future<List<SimpleJournalDraft>> _drafts;
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
      final saved = await Navigator.of(context).push<SimpleJournalDraft>(
          MaterialPageRoute(
              builder: (_) => SimpleJournalDraftEditor(
                  accounts: accounts,
                  saveDraft: widget.saveDraft,
                  draft: draft,
                  initialCurrency: widget.initialCurrency)));
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
          appBar: AppBar(title: const Text('مسودات القيود اليومية البسيطة')),
          floatingActionButton: FloatingActionButton.extended(
              onPressed: _opening ? null : () => _open(),
              icon: const Icon(Icons.add),
              label: const Text('إنشاء مسودة قيد')),
          body: Column(children: [
            const _JournalNotice(),
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
                child: FutureBuilder<List<SimpleJournalDraft>>(
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
                                      title: Text('مسودة قيد #${d.id ?? "—"}'),
                                      subtitle: Text(
                                          '${d.date} • ${d.amount} ${d.currency.label}\nغير معتمد وغير مرحّل'),
                                      isThreeLine: true,
                                      onTap: _opening || d.id == null
                                          ? null
                                          : () => _open(d.id))),
                          ]);
                    })),
          ])));
}

class _JournalNotice extends StatelessWidget {
  const _JournalNotice();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.all(12),
      child: Text(
          'مسودة قيد فقط وليست قيداً مرحّلاً أو اعتماداً. مبلغ واحد متساوٍ للطرف المدين والطرف الدائن؛ لا تغيّر الأرصدة أو النقدية أو المخزون، ولا تحويل عملات.'));
}

class SimpleJournalDraftEditor extends StatefulWidget {
  const SimpleJournalDraftEditor(
      {super.key,
      required this.accounts,
      required this.saveDraft,
      this.draft,
      this.initialCurrency = CurrencyCode.sar});
  final List<AccountRecord> accounts;
  final SimpleJournalDraftSave saveDraft;
  final SimpleJournalDraft? draft;
  final CurrencyCode initialCurrency;
  @override
  State<SimpleJournalDraftEditor> createState() =>
      _SimpleJournalDraftEditorState();
}

class _SimpleJournalDraftEditorState extends State<SimpleJournalDraftEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _date, _amount, _note;
  late CurrencyCode _currency;
  String? _debitId, _creditId, _error;
  bool _saving = false;
  List<AccountRecord> get _debits =>
      widget.accounts.where((a) => a.currency == _currency).toList();
  List<AccountRecord> get _credits => widget.accounts
      .where((a) => a.currency == _currency && a.id != _debitId)
      .toList();
  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _date = TextEditingController(
        text: d?.date ?? DateTime.now().toIso8601String().substring(0, 10));
    _amount = TextEditingController(text: draftAmountText(d?.amount));
    _note = TextEditingController(text: d?.note ?? '');
    _currency = d?.currency ?? widget.initialCurrency;
    _debitId = d?.debitAccountId;
    _creditId = d?.creditAccountId;
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
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
    final amount = double.tryParse(s);
    return !RegExp(r'^\d+(\.\d+)?$').hasMatch(s) ||
            amount == null ||
            !amount.isFinite ||
            amount <= 0
        ? 'أدخل مبلغاً موجباً صالحاً'
        : null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final visibleValid = _form.currentState!.validate();
    final valid = _dateError(_date.text) == null &&
        _amountError(_amount.text) == null &&
        _debits.any((a) => a.id == _debitId) &&
        _credits.any((a) => a.id == _creditId) &&
        _debitId != _creditId;
    if (!visibleValid || !valid) {
      setState(() => _error =
          'راجع التاريخ والمبلغ والحساب المدين والدائن بالعملة نفسها.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final d = widget.draft;
      final saved = await widget.saveDraft(SimpleJournalDraft(
          id: d?.id,
          revision: d?.revision ?? 0,
          date: _normalize(_date.text),
          debitAccountId: _debitId!,
          creditAccountId: _creditId!,
          currency: _currency,
          amount: double.parse(_normalize(_amount.text)),
          note: _note.text.trim()));
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'لم يتم تأكيد حفظ المسودة. بقيت البيانات هنا؛ إن تغيّرت الحسابات أو المسودة فأعد فتحها قبل المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debit = _debits.any((a) => a.id == _debitId) ? _debitId : null;
    final credit = _credits.any((a) => a.id == _creditId) ? _creditId : null;
    return PopScope(
        canPop: !_saving,
        child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                  title: Text(
                      '${widget.draft == null ? "إنشاء" : "تعديل"} مسودة قيد يومية بسيط')),
              body: AbsorbPointer(
                  absorbing: _saving,
                  child: Form(
                      key: _form,
                      child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            const _JournalNotice(),
                            DropdownButtonFormField<CurrencyCode>(
                                key: const Key('journal-currency'),
                                value: _currency,
                                decoration: const InputDecoration(
                                    labelText: 'العملة دون تحويل'),
                                items: CurrencyCode.values
                                    .map((c) => DropdownMenuItem(
                                        value: c, child: Text(c.label)))
                                    .toList(),
                                onChanged: (c) {
                                  if (c != null && c != _currency) {
                                    setState(() {
                                      _currency = c;
                                      _debitId = null;
                                      _creditId = null;
                                    });
                                  }
                                }),
                            if (_debits.length < 2)
                              const Text(
                                  'يلزم حسابان مختلفان محفوظان بالعملة المختارة، من أي فئة. لا تُنشأ حسابات تلقائياً.'),
                            DropdownButtonFormField<String>(
                                key:
                                    ValueKey('journal-debit-${_currency.name}'),
                                value: debit,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'الحساب المدين'),
                                items: _debits
                                    .map((a) => DropdownMenuItem(
                                        value: a.id,
                                        child: Text(a.name,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                validator: (id) =>
                                    id == null ? 'اختر الحساب المدين' : null,
                                onChanged: (id) => setState(() {
                                      _debitId = id;
                                      _creditId = null;
                                    })),
                            DropdownButtonFormField<String>(
                                key: ValueKey(
                                    'journal-credit-${_currency.name}'),
                                value: credit,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'الحساب الدائن'),
                                items: _credits
                                    .map((a) => DropdownMenuItem(
                                        value: a.id,
                                        child: Text(a.name,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                validator: (id) =>
                                    id == null ? 'اختر الحساب الدائن' : null,
                                onChanged: (id) =>
                                    setState(() => _creditId = id)),
                            TextFormField(
                                key: const Key('journal-date'),
                                controller: _date,
                                decoration: const InputDecoration(
                                    labelText: 'التاريخ YYYY-MM-DD'),
                                validator: _dateError),
                            TextFormField(
                                key: const Key('journal-amount'),
                                controller: _amount,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText:
                                        'المبلغ المتساوي لكل طرف (${_currency.label})'),
                                validator: _amountError,
                                onChanged: (_) => setState(() {})),
                            if (_amountError(_amount.text) == null)
                              Text(
                                  'طرف مدين: ${_normalize(_amount.text)} ${_currency.label} • طرف دائن: ${_normalize(_amount.text)} ${_currency.label} — تعادل مسودة فقط',
                                  key: const Key('journal-balanced-preview')),
                            TextFormField(
                                key: const Key('journal-note'),
                                controller: _note,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                    labelText: 'ملاحظة اختيارية')),
                            if (_error != null)
                              Semantics(liveRegion: true, child: Text(_error!)),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                                key: const Key('journal-save'),
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
