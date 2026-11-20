import '../models/nonposting_document.dart';
import 'package:flutter/material.dart';

import '../models/erp_models.dart';

typedef NonpostingSave = Future<NonpostingDocument> Function(
    NonpostingDocument);

String _kind(NonpostingDocumentType type) =>
    type == NonpostingDocumentType.quote ? 'عرض سعر' : 'طلب بيع';
String _number(double value) => value.toStringAsFixed(2);
String _latinDigits(String value) {
  var result = value.trim();
  for (var i = 0; i < 10; i++) {
    result = result
        .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
        .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
  }
  return result.replaceAll('٫', '.');
}

/// Local-only document workflow. Callbacks must commit before completing save.
class NonpostingDocumentsView extends StatefulWidget {
  const NonpostingDocumentsView(
      {super.key,
      required this.type,
      required this.loadDocuments,
      required this.loadDocument,
      required this.saveDocument,
      this.createOnOpen = false,
      this.initialCurrency = CurrencyCode.sar});
  final NonpostingDocumentType type;
  final bool createOnOpen;
  final CurrencyCode initialCurrency;
  final Future<List<NonpostingDocument>> Function() loadDocuments;
  final Future<NonpostingDocument?> Function(int id) loadDocument;
  final NonpostingSave saveDocument;
  @override
  State<NonpostingDocumentsView> createState() =>
      _NonpostingDocumentsViewState();
}

class _NonpostingDocumentsViewState extends State<NonpostingDocumentsView> {
  late Future<List<NonpostingDocument>> _documents;
  bool _opening = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _documents = Future.sync(widget.loadDocuments);
    if (widget.createOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _create();
      });
    }
  }

  void _refresh() => setState(() {
        _documents = Future.sync(widget.loadDocuments);
        _error = null;
      });

  Future<void> _create() async {
    if (_opening) return;
    setState(() => _opening = true);
    final saved = await Navigator.of(context).push<NonpostingDocument>(
        MaterialPageRoute(
            builder: (_) => NonpostingDocumentEditor(
                type: widget.type,
                initialCurrency: widget.initialCurrency,
                saveDocument: widget.saveDocument)));
    if (mounted) {
      setState(() => _opening = false);
      if (saved != null) _refresh();
    }
  }

  Future<void> _open(int id) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final document = await widget.loadDocument(id);
      if (!mounted) return;
      if (document == null || document.type != widget.type) {
        setState(() => _error = 'المستند غير موجود. حدّث القائمة.');
        return;
      }
      final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => NonpostingDocumentDetails(
              document: document, saveDocument: widget.saveDocument)));
      if (mounted && changed == true) _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر فتح المستند المحلي. حاول مجدداً.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
            title: Text(widget.type == NonpostingDocumentType.quote
                ? 'عروض الأسعار المحلية'
                : 'طلبات البيع المحلية')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _opening ? null : _create,
            icon: const Icon(Icons.add),
            label: Text('إنشاء ${_kind(widget.type)}')),
        body: Column(children: [
          const _NonpostingNotice(),
          if (_opening) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
              child: FutureBuilder<List<NonpostingDocument>>(
                  future: _documents,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('تعذر تحميل المستندات المحلية.'),
                        TextButton(
                            onPressed: _refresh,
                            child: const Text('إعادة المحاولة'))
                      ]));
                    }
                    final documents = (snapshot.data ?? [])
                        .where((d) => d.type == widget.type)
                        .toList();
                    if (documents.isEmpty) {
                      return const Center(
                          child: Text('لا توجد مستندات محلية بعد.'));
                    }
                    return RefreshIndicator(
                        onRefresh: () async {
                          _refresh();
                          try {
                            await _documents;
                          } catch (_) {
                            /* FutureBuilder displays the load error. */
                          }
                        },
                        child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                            itemCount: documents.length,
                            itemBuilder: (context, index) {
                              final d = documents[index];
                              return Card(
                                  child: ListTile(
                                      title: Text(
                                          '${_kind(d.type)} #${d.id ?? "—"} • ${d.customerName}'),
                                      subtitle: Text(
                                          '${d.date}\n${_number(d.total)} ${d.currency.label} • غير مرحّل'),
                                      isThreeLine: true,
                                      onTap: _opening || d.id == null
                                          ? null
                                          : () => _open(d.id!)));
                            }));
                  })),
        ]),
      ));
}

class _NonpostingNotice extends StatelessWidget {
  const _NonpostingNotice();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.all(12),
      child: Text(
          'مستند محلي غير مرحّل: لا يغيّر الحسابات أو المخزون. لا إرسال ولا نشر.'));
}

class NonpostingDocumentDetails extends StatefulWidget {
  const NonpostingDocumentDetails(
      {super.key, required this.document, required this.saveDocument});
  final NonpostingDocument document;
  final NonpostingSave saveDocument;
  @override
  State<NonpostingDocumentDetails> createState() =>
      _NonpostingDocumentDetailsState();
}

class _NonpostingDocumentDetailsState extends State<NonpostingDocumentDetails> {
  late NonpostingDocument _document;
  bool _changed = false;
  @override
  void initState() {
    super.initState();
    _document = widget.document;
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<NonpostingDocument>(
        MaterialPageRoute(
            builder: (_) => NonpostingDocumentEditor(
                type: _document.type,
                document: _document,
                saveDocument: widget.saveDocument)));
    if (mounted && saved != null) {
      setState(() {
        _document = saved;
        _changed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _changed) Navigator.of(context).pop(true);
      },
      child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
                title:
                    Text('${_kind(_document.type)} #${_document.id ?? "—"}')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              const _NonpostingNotice(),
              Text(_document.customerName,
                  style: Theme.of(context).textTheme.titleLarge),
              Text('التاريخ: ${_document.date}'),
              Text('العملة: ${_document.currency.label}'),
              if (_document.notes.isNotEmpty)
                Text('ملاحظات: ${_document.notes}'),
              const Divider(),
              for (final line in _document.lines)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.description),
                              Text(
                                  '${_number(line.quantity)} × ${_number(line.unitPrice)} = ${_number(line.total)} ${_document.currency.label}'),
                            ]))),
              Text(
                  'الإجمالي: ${_number(_document.total)} ${_document.currency.label}'),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit),
                  label: const Text('تعديل المستند')),
            ]),
          )));
}

class NonpostingDocumentEditor extends StatefulWidget {
  const NonpostingDocumentEditor(
      {super.key,
      required this.type,
      required this.saveDocument,
      this.document,
      this.initialCurrency = CurrencyCode.sar});
  final NonpostingDocumentType type;
  final NonpostingSave saveDocument;
  final NonpostingDocument? document;
  final CurrencyCode initialCurrency;
  @override
  State<NonpostingDocumentEditor> createState() =>
      _NonpostingDocumentEditorState();
}

class _LineFields {
  _LineFields([NonpostingLine? line])
      : itemId = line?.itemId ?? '',
        description = TextEditingController(text: line?.description ?? ''),
        quantity =
            TextEditingController(text: line?.quantity.toString() ?? '1'),
        price = TextEditingController(text: line?.unitPrice.toString() ?? '0');
  final String itemId;
  final TextEditingController description, quantity, price;
  void dispose() {
    description.dispose();
    quantity.dispose();
    price.dispose();
  }
}

class _NonpostingDocumentEditorState extends State<NonpostingDocumentEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _customer, _date, _notes;
  late CurrencyCode _currency;
  late final List<_LineFields> _lines;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final d = widget.document;
    _customer = TextEditingController(text: d?.customerName ?? '');
    _date = TextEditingController(
        text: d?.date ?? DateTime.now().toIso8601String().substring(0, 10));
    _notes = TextEditingController(text: d?.notes ?? '');
    _currency = d?.currency ?? widget.initialCurrency;
    _lines =
        d == null ? [_LineFields()] : d.lines.map(_LineFields.new).toList();
  }

  @override
  void dispose() {
    _customer.dispose();
    _date.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String? _amountError(String? text, bool positive) {
    final normalized = _latinDigits(text ?? '');
    final value = double.tryParse(normalized);
    return !RegExp(r'^\d+(\.\d+)?$').hasMatch(normalized) ||
            value == null ||
            !value.isFinite ||
            (positive ? value <= 0 : value < 0)
        ? (positive ? 'أدخل كمية أكبر من صفر' : 'أدخل سعراً صفراً أو أكبر')
        : null;
  }

  String? _dateError(String? text) {
    final value = _latinDigits(text ?? '');
    final parsed = DateTime.tryParse(value);
    return !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
            parsed == null ||
            parsed.toIso8601String().substring(0, 10) != value
        ? 'أدخل تاريخاً صحيحاً YYYY-MM-DD'
        : null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final visibleValid = _form.currentState!.validate();
    final allValid = _customer.text.trim().isNotEmpty &&
        _dateError(_date.text) == null &&
        _lines.isNotEmpty &&
        _lines.every((line) =>
            line.description.text.trim().isNotEmpty &&
            _amountError(line.quantity.text, true) == null &&
            _amountError(line.price.text, false) == null);
    if (!visibleValid || !allValid) {
      setState(() =>
          _error = 'راجع اسم العميل والتاريخ والكمية والسعر ووصف كل بند.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final original = widget.document;
      final saved = await widget.saveDocument(NonpostingDocument(
          id: original?.id,
          revision: original?.revision ?? 0,
          type: original?.type ?? widget.type,
          date: _latinDigits(_date.text),
          currency: _currency,
          customerName: _customer.text.trim(),
          accountId: original?.accountId ?? '',
          notes: _notes.text.trim(),
          lines: [
            for (final line in _lines)
              NonpostingLine(
                  itemId: line.itemId,
                  description: line.description.text.trim(),
                  quantity: double.parse(_latinDigits(line.quantity.text)),
                  unitPrice: double.parse(_latinDigits(line.price.text)))
          ]));
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'لم يتم تأكيد الحفظ. بقيت بياناتك هنا؛ إن عُدّل المستند من نافذة أخرى فأعد فتحه قبل المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
                title: Text(
                    '${widget.document == null ? "إنشاء" : "تعديل"} ${_kind(widget.type)}')),
            body: AbsorbPointer(
                absorbing: _saving,
                child: Form(
                    key: _form,
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      const _NonpostingNotice(),
                      TextFormField(
                          key: const Key('document-customer'),
                          controller: _customer,
                          decoration:
                              const InputDecoration(labelText: 'اسم العميل'),
                          validator: (text) => (text ?? '').trim().isEmpty
                              ? 'اسم العميل مطلوب'
                              : null),
                      TextFormField(
                          key: const Key('document-date'),
                          controller: _date,
                          decoration: const InputDecoration(
                              labelText: 'التاريخ YYYY-MM-DD'),
                          keyboardType: TextInputType.datetime,
                          validator: _dateError),
                      DropdownButtonFormField<CurrencyCode>(
                          value: _currency,
                          decoration:
                              const InputDecoration(labelText: 'العملة'),
                          items: CurrencyCode.values
                              .map((c) => DropdownMenuItem(
                                  value: c, child: Text(c.label)))
                              .toList(),
                          onChanged: (c) {
                            if (c != null) setState(() => _currency = c);
                          }),
                      TextFormField(
                          controller: _notes,
                          decoration:
                              const InputDecoration(labelText: 'ملاحظات'),
                          maxLines: 2),
                      for (var i = 0; i < _lines.length; i++)
                        Card(
                            key: ObjectKey(_lines[i]),
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(children: [
                                  Text('البند ${i + 1}'),
                                  if (_lines.length > 1)
                                    TextButton.icon(
                                        key: Key('remove-line-$i'),
                                        onPressed: () {
                                          final removed = _lines[i];
                                          setState(() => _lines.removeAt(i));
                                          removed.dispose();
                                        },
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        label: const Text(
                                            'إزالة البند من المسودة')),
                                  TextFormField(
                                      key: Key('line-description-$i'),
                                      controller: _lines[i].description,
                                      decoration: const InputDecoration(
                                          labelText: 'وصف البند'),
                                      validator: (text) =>
                                          (text ?? '').trim().isEmpty
                                              ? 'الوصف مطلوب'
                                              : null),
                                  TextFormField(
                                      key: Key('line-quantity-$i'),
                                      controller: _lines[i].quantity,
                                      decoration: const InputDecoration(
                                          labelText: 'الكمية'),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      validator: (v) => _amountError(v, true)),
                                  TextFormField(
                                      key: Key('line-price-$i'),
                                      controller: _lines[i].price,
                                      decoration: const InputDecoration(
                                          labelText: 'سعر الوحدة'),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      validator: (v) => _amountError(v, false)),
                                ]))),
                      OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => _lines.add(_LineFields())),
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة بند')),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_error!)),
                      FilledButton(
                          key: const Key('document-save'),
                          onPressed: _saving ? null : _save,
                          child: Text(
                              _saving ? 'جارٍ الحفظ…' : 'حفظ محلي دون ترحيل')),
                      TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('إلغاء')),
                    ]))),
          )));
}
