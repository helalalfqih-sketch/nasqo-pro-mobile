import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/models/invoice_print_snapshot.dart';
import 'package:nasqo_pro_erp/screens/invoice_pdf_preview_view.dart';
import 'package:nasqo_pro_erp/services/local_invoice_pdf.dart';

final _snapshot = InvoicePrintSnapshot(
    const LedgerEntryRecord(
      id: 's',
      accountId: 'a',
      accountName: 'اصطناعي',
      kind: LedgerKind.invoice,
      typeLabel: 'ف.مبيعات نقدية',
      payment: PaymentMethod.cash,
      direction: EntryDirection.debit,
      amount: 5,
      entryNumber: 1,
      entryDate: '2026-11-19',
    ),
    [],
    null);

void main() {
  testWidgets(
      'preview never auto prints and double tap uses exact same PDF once',
      (tester) async {
    final bytes = Uint8List.fromList('%PDF-1.4'.codeUnits);
    final sent = <Uint8List>[];
    final done = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: InvoicePdfPreviewView(
      load: () async => _snapshot,
      render: (_) async => LocalInvoicePdfResult(bytes, []),
      openPrintDialog: (data) {
        sent.add(data);
        return done.future;
      },
    )));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    final print = find.text('طباعة / حفظ PDF');
    await tester.tap(print);
    await tester.pump();
    await tester.tap(print);
    expect(sent, hasLength(1));
    expect(sent.single, orderedEquals(bytes));
    done.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('لم تُؤكّد نتيجة الطباعة'), findsOneWidget);
  });

  testWidgets(
      'unavailable invoice never offers a send action; retry is available',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: InvoicePdfPreviewView(
      load: () async => throw const FormatException('synthetic reject'),
      openPrintDialog: (_) async => fail('must not print'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('طباعة / حفظ PDF'), findsNothing);
    expect(find.text('إعادة المعاينة'), findsOneWidget);
  });
}
