import 'package:flutter/material.dart';
import '../models/sales_return_draft.dart';
import '../state/erp_controller.dart';
import '../services/android_csv_writer.dart';
import 'original_sale_facts_view.dart';
import 'invoice_pdf_preview_view.dart';
import '../services/android_invoice_pdf_printer.dart';
import 'sales_csv_export_view.dart';

/// Partial local register, not a comprehensive sales or tax report.
class HomeSalesRegisterView extends StatefulWidget {
  const HomeSalesRegisterView({super.key, required this.controller});
  final ErpController controller;
  @override
  State<HomeSalesRegisterView> createState() => _HomeSalesRegisterViewState();
}

class _HomeSalesRegisterViewState extends State<HomeSalesRegisterView> {
  String _query = '';
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('سجل المبيعات المحلي')),
          body: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final entries = widget.controller.ledger
                    .where(isEligibleSalesReturnSource)
                    .where((e) => '${e.documentNumber} ${e.accountName}'
                        .toLowerCase()
                        .contains(_query.trim().toLowerCase()))
                    .toList()
                  ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
                return ListView(padding: const EdgeInsets.all(16), children: [
                  const Text(
                      'فواتير المبيعات المحلية النشطة المعروفة فقط؛ ليس تقريراً شاملاً. المبالغ كما حُفظت، دون جمع العملات.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('تصدير المبيعات CSV'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SalesCsvExportView(
                          loadEntries:
                              widget.controller.loadCommittedSalesForExport,
                          saveToChosenFile:
                              const AndroidCsvWriter().saveToChosenFile,
                        ),
                      ),
                    ),
                  ),
                  TextField(
                      decoration: const InputDecoration(
                          labelText: 'بحث برقم المستند أو اسم العميل',
                          prefixIcon: Icon(Icons.search)),
                      onChanged: (value) => setState(() => _query = value)),
                  const SizedBox(height: 12),
                  if (entries.isEmpty)
                    const Text('لا توجد فواتير مبيعات محلية مطابقة'),
                  for (final entry in entries)
                    Card(
                        child: InkWell(
                      key: ValueKey('sales-entry-${entry.id}'),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => _SaleDetail(
                                  controller: widget.controller,
                                  entryId: entry.id))),
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.accountName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Text(
                                    'المستند: ${entry.documentNumber.isEmpty ? 'غير مسجل' : entry.documentNumber}'),
                                Text(
                                    'رقم القيد: ${entry.entryNumber} · ${entry.entryDate}'),
                                Text('${entry.amount} ${entry.currency.label}'),
                                Text(widget.controller.saleLines
                                        .any((line) => line.entryId == entry.id)
                                    ? 'عرض البنود المحفوظة'
                                    : 'تفاصيل الأصناف غير متاحة'),
                              ])),
                    )),
                ]);
              }),
        ),
      );
}

class _SaleDetail extends StatelessWidget {
  const _SaleDetail({required this.controller, required this.entryId});
  final ErpController controller;
  final String entryId;
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('تفاصيل المبيعات المحفوظة')),
          body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final entries = controller.ledger.where((entry) =>
                    entry.id == entryId && isEligibleSalesReturnSource(entry));
                if (entries.isEmpty) {
                  return const Center(
                      child: Text(
                          'لم يعد هذا المستند متاحاً ضمن المبيعات النشطة'));
                }
                final entry = entries.first;
                final lines = controller.saleLines
                    .where((line) => line.entryId == entryId)
                    .toList()
                  ..sort((a, b) => a.position.compareTo(b.position));
                return ListView(padding: const EdgeInsets.all(16), children: [
                  Text(entry.accountName,
                      style: Theme.of(context).textTheme.titleLarge),
                  Text('المستند: ${entry.documentNumber} · ${entry.entryDate}'),
                  const Text('المبلغ المحفوظ في القيد'),
                  Text('${entry.amount} ${entry.currency.label}'),
                  const Text(
                      'قراءة فقط. أسعار البنود لا تعيد حساب مبلغ القيد أو ضرائبه.'),
                  OutlinedButton.icon(
                    key: ValueKey('invoice-pdf-$entryId'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => InvoicePdfPreviewView(
                          load: () => controller.loadInvoiceForPrint(entryId),
                          openPrintDialog:
                              const AndroidInvoicePdfPrinter().openPrintDialog,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('معاينة وطباعة PDF'),
                  ),
                  const SizedBox(height: 12),
                  if (lines.isEmpty)
                    const Text(
                        'تفاصيل الأصناف غير متاحة لهذا المستند القديم؛ لا تُستنتج من الملاحظات.'),
                  for (final line in lines)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(line.itemName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  Text('الموضع الأصلي: ${line.position}'),
                                  Text(
                                      'الكمية: ${line.quantity} · الوحدة: ${line.unit}'),
                                  Text(
                                      'سعر الوحدة: ${line.unitPrice} ${entry.currency.label}'),
                                ]))),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => OriginalSaleFactsView(
                                entryId: entryId,
                                loadFacts: controller.loadOriginalSaleFacts))),
                    child: const Text('الحقائق الأصلية المتاحة'),
                  ),
                ]);
              }),
        ),
      );
}
