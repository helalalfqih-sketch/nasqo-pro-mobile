import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/erp_models.dart';
import '../services/local_sales_csv.dart';

class SalesCsvExportView extends StatefulWidget {
  const SalesCsvExportView(
      {super.key, required this.loadEntries, required this.saveToChosenFile});
  final Future<List<LedgerEntryRecord>> Function() loadEntries;

  /// true only after a completed write; false means the picker was cancelled.
  final Future<bool> Function(Uint8List bytes, String suggestedName)
      saveToChosenFile;
  @override
  State<SalesCsvExportView> createState() => _SalesCsvExportViewState();
}

class _SalesCsvExportViewState extends State<SalesCsvExportView> {
  final _from = TextEditingController();
  final _through = TextEditingController();
  CurrencyCode? _currency;
  LocalSalesCsvResult? _preview;
  bool _busy = false;
  String? _message;
  String? _error;
  @override
  void dispose() {
    _from.dispose();
    _through.dispose();
    super.dispose();
  }

  String _normalized(String text) {
    var value = text.trim();
    for (var i = 0; i < 10; i++) {
      value = value
          .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
          .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
    }
    return value;
  }

  bool _validDate(String value) {
    if (value.isEmpty) {
      return true;
    }
    final date = DateTime.tryParse(value);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
        date != null &&
        date.toIso8601String().substring(0, 10) == value;
  }

  void _invalidate() {
    setState(() {
      _preview = null;
      _message = null;
      _error = null;
    });
  }

  Future<void> _prepare() async {
    if (_busy) {
      return;
    }
    final from = _normalized(_from.text);
    final through = _normalized(_through.text);
    if (!_validDate(from) ||
        !_validDate(through) ||
        (from.isNotEmpty &&
            through.isNotEmpty &&
            from.compareTo(through) > 0)) {
      setState(() {
        _error =
            'أدخل نطاق تاريخ صحيحاً بصيغة YYYY-MM-DD؛ البداية لا تتجاوز النهاية.';
        _preview = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _preview = null;
      _error = null;
      _message = 'جارٍ قراءة المبيعات المحلية وإعداد المعاينة…';
    });
    try {
      final entries = await widget.loadEntries();
      final result = LocalSalesCsv.export(entries,
          currency: _currency,
          from: from.isEmpty ? null : from,
          through: through.isEmpty ? null : through);
      if (mounted) {
        setState(() {
          _preview = result;
          _message = 'المعاينة جاهزة. لم يُحفظ ملف بعد.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = null;
          _error =
              'تعذر إعداد CSV. تحقق من البيانات والنطاق ثم أعد المعاينة؛ لم يُصدّر ملف.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final preview = _preview;
    if (_busy || preview == null || preview.rowCount == 0) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = 'اختر وجهة حفظ CSV وانتظر اكتمال العملية…';
    });
    try {
      final saved = await widget.saveToChosenFile(
          Uint8List.fromList(preview.bytes), 'nasqo-sales.csv');
      if (mounted) {
        setState(() {
          _message = saved
              ? 'تم حفظ ملف CSV في الوجهة التي اخترتها.'
              : 'أُلغي اختيار الوجهة. لم يُحفظ ملف.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = null;
          _error =
              'تعذر إكمال حفظ الملف. قد يوجد ملف غير مكتمل في الوجهة؛ تحقق منه قبل إعادة المحاولة.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final raw = preview == null
        ? ''
        : utf8.decode(preview.bytes).replaceFirst('\uFEFF', '');
    final excerpt = raw.length > 3000
        ? '${raw.substring(0, 3000)}\n… (معاينة مختصرة)'
        : raw;
    return Directionality(
        textDirection: TextDirection.rtl,
        child: PopScope(
            canPop: !_busy,
            child: Scaffold(
              appBar: AppBar(title: const Text('تصدير المبيعات CSV')),
              body: ListView(padding: const EdgeInsets.all(16), children: [
                const Text(
                    'CSV قابل للقراءة في Excel، وليس ملف XLSX. تُقرأ المبيعات المحلية فقط دون تعديلها أو اختلاق مبالغ مفقودة. العملات منفصلة في السجلات ولا تُحوّل أو تُجمع هنا.'),
                const SizedBox(height: 8),
                const Text(
                    'قد يحتوي الملف بيانات عملاء ومبالغ. لن يُحفظ إلا عند اختيار الوجهة صراحةً؛ قد تكون الوجهة التي تختارها محلية أو موفراً سحابياً. اختر وجهة موثوقة.'),
                const SizedBox(height: 16),
                TextField(
                    controller: _from,
                    enabled: !_busy,
                    onChanged: (_) => _invalidate(),
                    decoration: const InputDecoration(
                        labelText: 'من تاريخ (اختياري)',
                        hintText: 'YYYY-MM-DD')),
                TextField(
                    controller: _through,
                    enabled: !_busy,
                    onChanged: (_) => _invalidate(),
                    decoration: const InputDecoration(
                        labelText: 'إلى تاريخ (اختياري)',
                        hintText: 'YYYY-MM-DD')),
                const SizedBox(height: 12),
                DropdownButtonFormField<CurrencyCode?>(
                    value: _currency,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'العملة'),
                    items: [
                      const DropdownMenuItem<CurrencyCode?>(
                          value: null, child: Text('جميع العملات دون تحويل')),
                      for (final currency in CurrencyCode.values)
                        DropdownMenuItem(
                            value: currency, child: Text(currency.label)),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            _currency = value;
                            _invalidate();
                          }),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _busy ? null : _prepare,
                    child: const Text('إعداد المعاينة')),
                if (_busy)
                  const LinearProgressIndicator(
                      semanticsLabel: 'تجري عملية التصدير المحلية'),
                if (_message != null)
                  Semantics(
                      liveRegion: true,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_message!))),
                if (_error != null)
                  Semantics(
                      liveRegion: true,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_error!,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error)))),
                if (preview != null) ...[
                  Text('عدد سجلات المبيعات: ${preview.rowCount}'),
                  Text('حجم CSV: ${preview.byteLength} بايت'),
                  if (preview.rowCount == 0)
                    const Text('لا توجد مبيعات مطابقة. لن يُصدّر ملف فارغ.'),
                  const Text('معاينة نص CSV (حتى ٣٠٠٠ محرف):'),
                  Container(
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(excerpt)),
                  OutlinedButton(
                      onPressed: _busy || preview.rowCount == 0 ? null : _save,
                      child: const Text('اختيار الوجهة وحفظ CSV')),
                  const Text(
                      'يُحفظ المحتوى الذي عاينته فقط. لإدراج تغييرات أحدث أعد إعداد المعاينة.'),
                ],
              ]),
            )));
  }
}
