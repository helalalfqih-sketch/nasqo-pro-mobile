import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/invoice_print_snapshot.dart';
import '../services/local_invoice_pdf.dart';
import 'web_auxiliary_views.dart';

class InvoicePdfPreviewView extends StatefulWidget {
  const InvoicePdfPreviewView({
    super.key,
    required this.load,
    required this.openPrintDialog,
    this.render = LocalInvoicePdf.render,
  });

  final Future<InvoicePrintSnapshot> Function() load;
  final Future<void> Function(Uint8List bytes) openPrintDialog;
  final Future<LocalInvoicePdfResult> Function(InvoicePrintSnapshot) render;

  @override
  State<InvoicePdfPreviewView> createState() => _InvoicePdfPreviewViewState();
}

class _InvoicePdfPreviewViewState extends State<InvoicePdfPreviewView> {
  late Future<LocalInvoicePdfResult> _preview;
  bool _printing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _preview = _load();
  }

  Future<LocalInvoicePdfResult> _load() async {
    final snapshot = await widget.load();
    return widget.render(snapshot);
  }

  Future<void> _print(LocalInvoicePdfResult result) async {
    if (_printing) return;
    setState(() {
      _printing = true;
      _message = null;
    });
    try {
      await widget.openPrintDialog(Uint8List.fromList(result.bytes));
      if (!mounted) return;
      setState(() => _message =
          'فُتح مربع طباعة Android. لم تُؤكّد نتيجة الطباعة داخل التطبيق.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _message =
          'تعذّر فتح الطباعة على هذا الجهاز. لا توجد نتيجة طباعة مؤكدة.');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('معاينة الفاتورة PDF')),
          body: FutureBuilder<LocalInvoicePdfResult>(
            future: _preview,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'جارٍ إعداد معاينة الفاتورة',
                  ),
                );
              }
              final result = state.data;
              if (state.hasError || result == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                            'تعذّر إعداد نسخة PDF كاملة من السجل المحلي. لم تُطبع الفاتورة ولم تتغير بياناتها.'),
                        TextButton(
                          onPressed: () => setState(() => _preview = _load()),
                          child: const Text('إعادة المعاينة'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: _printing ? null : () => _print(result),
                              label: const Text('طباعة / حفظ PDF'),
                              icon: const Icon(Icons.print_outlined),
                            ),
                            OutlinedButton.icon(
                              key: const ValueKey('invoice-pdf-print-options'),
                              onPressed: _printing
                                  ? null
                                  : () => showPrintOptionsModal(
                                        context,
                                        subjectLabel: 'معاينة الفاتورة PDF',
                                        onAction: (action) {
                                          if (action.startsWith('طباعة')) {
                                            _print(result);
                                          } else {
                                            setState(() => _message = 'تم اختيار: $action');
                                          }
                                        },
                                      ),
                              icon: const Icon(Icons.tune_outlined),
                              label: const Text('خيارات الطباعة'),
                            ),
                          ],
                        ),
                        const Text(
                            'اختر جميع الصفحات. يمكنك اختيار الطابعة أو الحفظ بتنسيق PDF من خيارات Android إن توفرت.'),
                        if (_message != null)
                          Semantics(liveRegion: true, child: Text(_message!)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: result.previewPages.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: InkWell(
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => Dialog(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: InteractiveViewer(
                                  maxScale: 5,
                                  child: Image.memory(
                                      result.previewPages[index],
                                      fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          ),
                          child: Image.memory(
                            result.previewPages[index],
                            semanticLabel:
                                'معاينة الصفحة ${index + 1} من ${result.previewPages.length}. اضغط للتكبير.',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}
