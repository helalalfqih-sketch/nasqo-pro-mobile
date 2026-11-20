import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../models/draft_amount_text.dart';
import '../models/voucher_draft.dart';

typedef VoucherDraftSave = Future<VoucherDraft> Function(VoucherDraft);
String _label(VoucherDraftType type) =>
    type == VoucherDraftType.receipt ? 'قبض' : 'صرف';
String _normalize(String input) {
  var text = input.trim();
  for (var i = 0; i < 10; i++) {
    text = text
        .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
        .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
  }
  return text.replaceAll('٫', '.');
}

class VoucherDraftsView extends StatefulWidget {
  const VoucherDraftsView(
      {super.key,
      required this.type,
      required this.loadDrafts,
      required this.loadDraft,
      required this.loadAccounts,
      required this.saveDraft,
      this.createOnOpen = false,
      this.initialCurrency = CurrencyCode.sar});
  final VoucherDraftType type;
  final Future<List<VoucherDraft>> Function() loadDrafts;
  final Future<VoucherDraft?> Function(int) loadDraft;
  final Future<List<AccountRecord>> Function() loadAccounts;
  final VoucherDraftSave saveDraft;
  final bool createOnOpen;
  final CurrencyCode initialCurrency;
  @override
  State<VoucherDraftsView> createState() => _VoucherDraftsViewState();
}

class _VoucherDraftsViewState extends State<VoucherDraftsView> {
  late Future<List<VoucherDraft>> _drafts;
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
      if (id != null && (draft == null || draft.type != widget.type)) {
        throw StateError('Draft missing or wrong type');
      }
      final accounts = await widget.loadAccounts();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<VoucherDraft>(
          MaterialPageRoute(
              builder: (_) => VoucherDraftEditor(
                  type: widget.type,
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
          appBar: AppBar(title: Text('مسودات سندات ${_label(widget.type)}')),
          floatingActionButton: FloatingActionButton.extended(
              onPressed: _opening ? null : () => _open(),
              icon: const Icon(Icons.add),
              label: Text('إنشاء مسودة ${_label(widget.type)}')),
          body: Column(children: [
            const _VoucherNotice(),
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
                child: FutureBuilder<List<VoucherDraft>>(
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
                      final drafts = (snapshot.data ?? [])
                          .where((d) => d.type == widget.type)
                          .toList();
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
                                          'مسودة سند ${_label(d.type)} #${d.id ?? "—"}'),
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

class _VoucherNotice extends StatelessWidget {
  const _VoucherNotice();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.all(12),
      child: Text(
          'مسودة محلية فقط: ليست اعتماداً أو دفعاً أو قبضاً فعلياً. لا تغيّر الحسابات أو النقدية أو المخزون، ولا تُرحّل قيوداً.'));
}

class VoucherDraftEditor extends StatefulWidget {
  const VoucherDraftEditor(
      {super.key,
      required this.type,
      required this.accounts,
      required this.saveDraft,
      this.draft,
      this.initialCurrency = CurrencyCode.sar});
  final VoucherDraftType type;
  final List<AccountRecord> accounts;
  final VoucherDraftSave saveDraft;
  final VoucherDraft? draft;
  final CurrencyCode initialCurrency;
  @override
  State<VoucherDraftEditor> createState() => _VoucherDraftEditorState();
}

class _VoucherDraftEditorState extends State<VoucherDraftEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _date, _amount, _note;
  late CurrencyCode _currency;
  String? _partyId, _cashId, _error;
  bool _saving = false;
  List<AccountRecord> get _parties => widget.accounts
      .where((a) => !a.isCashAccount && a.currency == _currency)
      .toList();
  List<AccountRecord> get _cashboxes => widget.accounts
      .where((a) => a.isCashAccount && a.currency == _currency)
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
    _partyId = d?.partyAccountId;
    _cashId = d?.cashAccountId;
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
        _parties.any((a) => a.id == _partyId) &&
        _cashboxes.any((a) => a.id == _cashId) &&
        _partyId != _cashId;
    if (!visibleValid || !valid) {
      setState(() =>
          _error = 'راجع التاريخ والمبلغ وحساب الطرف والصندوق بالعملة نفسها.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final d = widget.draft;
      final saved = await widget.saveDraft(VoucherDraft(
          id: d?.id,
          revision: d?.revision ?? 0,
          type: d?.type ?? widget.type,
          date: _normalize(_date.text),
          partyAccountId: _partyId!,
          cashAccountId: _cashId!,
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
    final party = _parties.any((a) => a.id == _partyId) ? _partyId : null;
    final cash = _cashboxes.any((a) => a.id == _cashId) ? _cashId : null;
    return PopScope(
        canPop: !_saving,
        child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                  title: Text(
                      '${widget.draft == null ? "إنشاء" : "تعديل"} مسودة سند ${_label(widget.type)}')),
              body: AbsorbPointer(
                  absorbing: _saving,
                  child: Form(
                      key: _form,
                      child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            const _VoucherNotice(),
                            DropdownButtonFormField<CurrencyCode>(
                                key: const Key('voucher-currency'),
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
                                      _partyId = null;
                                      _cashId = null;
                                    });
                                  }
                                }),
                            if (_parties.isEmpty || _cashboxes.isEmpty)
                              const Text(
                                  'يلزم حساب طرف غير نقدي وصندوق نقدي محفوظان بالعملة المختارة. لا تُنشأ حسابات تلقائياً.'),
                            DropdownButtonFormField<String>(
                                key:
                                    ValueKey('voucher-party-${_currency.name}'),
                                value: party,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'حساب الطرف غير النقدي'),
                                items: _parties
                                    .map((a) => DropdownMenuItem(
                                        value: a.id,
                                        child: Text(a.name,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                validator: (id) =>
                                    id == null ? 'اختر حساب الطرف' : null,
                                onChanged: (id) =>
                                    setState(() => _partyId = id)),
                            DropdownButtonFormField<String>(
                                key: ValueKey('voucher-cash-${_currency.name}'),
                                value: cash,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'الصندوق النقدي'),
                                items: _cashboxes
                                    .map((a) => DropdownMenuItem(
                                        value: a.id,
                                        child: Text(a.name,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                validator: (id) =>
                                    id == null ? 'اختر الصندوق' : null,
                                onChanged: (id) =>
                                    setState(() => _cashId = id)),
                            TextFormField(
                                key: const Key('voucher-date'),
                                controller: _date,
                                decoration: const InputDecoration(
                                    labelText: 'التاريخ YYYY-MM-DD'),
                                validator: _dateError),
                            TextFormField(
                                key: const Key('voucher-amount'),
                                controller: _amount,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText:
                                        'مبلغ المسودة (${_currency.label})'),
                                validator: _amountError),
                            TextFormField(
                                key: const Key('voucher-note'),
                                controller: _note,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                    labelText: 'ملاحظة اختيارية')),
                            if (_error != null)
                              Semantics(liveRegion: true, child: Text(_error!)),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                                key: const Key('voucher-save'),
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
