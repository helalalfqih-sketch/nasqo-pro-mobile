import 'package:flutter/material.dart';
import '../services/android_invoice_pdf_printer.dart';
import '../state/erp_controller.dart';
import 'invoice_pdf_preview_view.dart';

class InvoiceDateField extends StatelessWidget {
  const InvoiceDateField({super.key, required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('تاريخ الفاتورة'),
    subtitle: Text(value.toIso8601String().substring(0,10)),
    trailing: const Icon(Icons.calendar_today_outlined),
    onTap: () async {
      final selected = await showDatePicker(context:context,initialDate:value,
        firstDate:DateTime(1900),lastDate:DateTime(2199,12,31));
      if(context.mounted && selected!=null) onChanged(selected);
    },
  );
}

void showCommittedInvoice(BuildContext context, ErpController controller, String entryId) {
  Navigator.of(context).pushReplacement<void,void>(MaterialPageRoute(
    builder: (_) => InvoicePdfPreviewView(load: () => controller.loadInvoiceForPrint(entryId),
        openPrintDialog: const AndroidInvoicePdfPrinter().openPrintDialog),
  ));
}
