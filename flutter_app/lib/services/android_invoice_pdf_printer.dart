import 'package:flutter/services.dart';

/// Opens Android's user-controlled print dialog. Completion does NOT mean a
/// printer was selected, a job completed, or paper was printed. No auto-print.
/// Native implementation supports all pages only and rejects partial ranges.
class AndroidInvoicePdfPrinter {
  const AndroidInvoicePdfPrinter();
  static const maxBytes = 16 * 1024 * 1024;
  static const _channel =
      MethodChannel('com.indexesstore.nasqo_qa/invoice_pdf_print');
  Future<void> openPrintDialog(Uint8List bytes) async {
    if (bytes.length < 5 ||
        bytes.length > maxBytes ||
        bytes[0] != 0x25 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x44 ||
        bytes[3] != 0x46 ||
        bytes[4] != 0x2d) {
      throw ArgumentError('ملف PDF غير صالح أو يتجاوز حد الطباعة');
    }
    final requested = await _channel.invokeMethod<bool>(
        'openPrintDialog', {'bytes': Uint8List.fromList(bytes)});
    if (requested != true) {
      throw PlatformException(
          code: 'PRINT_NOT_REQUESTED', message: 'لم يتأكد فتح نافذة الطباعة');
    }
  }
}
