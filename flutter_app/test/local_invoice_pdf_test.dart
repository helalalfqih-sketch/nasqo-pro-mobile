import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/invoice_print_snapshot.dart';
import 'package:nasqo_pro_erp/models/sale_facts.dart';
import 'package:nasqo_pro_erp/services/local_invoice_pdf.dart';

const _entry = LedgerEntryRecord(
  id: 'synthetic',
  accountId: 'test-customer',
  accountName: 'شركة الأمانة للتجارة ABC',
  kind: LedgerKind.invoice,
  typeLabel: 'ف.مبيعات نقدية',
  payment: PaymentMethod.cash,
  direction: EntryDirection.debit,
  amount: 2185,
  documentNumber: 'QA-0642',
  entryNumber: 42,
  entryDate: '2026-11-19',
);
SavedSaleLine _line(int number) => SavedSaleLine(
    entryId: 'synthetic',
    position: number,
    itemId: 'item-$number',
    itemName: number == 18
        ? 'صنف مختلط QARobustExtraLongUnbrokenSKU1234567890XYZ1234567890'
        : 'أدوات مكتبية، نموذج QA-$number',
    unit: 'علبة',
    quantity: 1.25,
    unitPrice: 80);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('InvoiceArabic')
          ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf')))
        .load();
    await (FontLoader('InvoiceLatin')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf')))
        .load();
  });

  test('multipage raster PDF has both previews and offsets to real objects',
      () async {
    final lines = List.generate(19, (i) => _line(19 - i));
    final facts = SaleFacts(
        entryId: 'synthetic',
        currency: _entry.currency,
        preTaxTotal: 1900,
        taxEnabled: true,
        appliedTaxRate: .15,
        taxAmount: 285,
        finalTotal: 2185,
        lineCosts: const []);
    final input = InvoicePrintSnapshot(_entry, lines, facts);
    final output = await LocalInvoicePdf.render(input);
    expect(input.lines.first.position, 1);
    expect(lines.first.position, 19);
    final pdf = latin1.decode(output.bytes);
    expect(pdf, startsWith('%PDF-1.4'));
    expect(pdf, contains('/Count 2'));
    expect(output.previewPages, hasLength(2));
    expect(
        output.previewPages.first.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final xref = RegExp(r'startxref\n(\d+)\n%%EOF').firstMatch(pdf)!;
    expect(
        pdf.substring(int.parse(xref.group(1)!), int.parse(xref.group(1)!) + 4),
        'xref');
    final path = Platform.environment['NASQO_SYNTHETIC_PDF'];
    if (path != null) {
      await File(path).writeAsBytes(output.bytes);
      await File('$path.preview-1.png').writeAsBytes(output.previewPages.first);
      await File('$path.preview-2.png').writeAsBytes(output.previewPages.last);
    }
  });

  test('legacy invoice with no recorded lines or tax remains printable',
      () async {
    final output =
        await LocalInvoicePdf.render(InvoicePrintSnapshot(_entry, [], null));
    expect(output.previewPages, hasLength(1));
    expect(latin1.decode(output.bytes), contains('/Count 1'));
  });
}
