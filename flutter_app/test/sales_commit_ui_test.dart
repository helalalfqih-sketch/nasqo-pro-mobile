import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';
import 'package:nasqo_pro_erp/screens/invoice_form_sheet.dart';
import 'package:nasqo_pro_erp/screens/pos_crm_screen.dart';

class PendingSalesController extends ErpController {
  PendingSalesController() : super(autoInitDb: false);
  Completer<void> pending = Completer<void>();
  int calls = 0;
  String? submittedCashbox;
  @override
  Future<void> submitSalesInvoice(
      {required String accountId,
      String? cashboxAccountId,
      double? freeAmount,
      DateTime? invoiceDate,
      ValueChanged<String>? onCommitted,
      String? requestId,
      required String customerName,
      required WarehouseRecord warehouse,
      required PaymentMethod payment,
      required bool includeVat,
      required List<InvoiceItemRow> rows,
      String documentNumber = '',
      String memo = ''}) {
    submittedCashbox = cashboxAccountId;
    calls++;
    return pending.future;
  }
}

void main() {
  testWidgets(
      'invoice awaits commit, blocks duplicate/back, failure retains draft and retry closes',
      (tester) async {
    final controller = PendingSalesController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        enableDrag: false,
                        builder: (_) =>
                            InvoiceFormSheet(controller: controller)),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('invoice-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invoice-save')));
    await tester.pump();
    expect(controller.calls, 1);
    expect(controller.submittedCashbox, controller.accounts.firstWhere((a) => a.isCashAccount).id);
    expect(find.text('جارٍ حفظ الفاتورة…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('invoice-save')),
        warnIfMissed: false);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(controller.calls, 1);
    await tester.dragFrom(
        tester.getCenter(find.byType(InvoiceFormSheet)), const Offset(0, 600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(InvoiceFormSheet), findsOneWidget);
    controller.pending
        .completeError(const SaleValidationException('فشل اصطناعي'));
    await tester.pumpAndSettle();
    expect(find.text('فشل اصطناعي'), findsOneWidget);
    expect(find.byType(InvoiceFormSheet), findsOneWidget);
    controller.pending = Completer<void>();
    await tester.ensureVisible(find.byKey(const Key('invoice-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invoice-save')));
    await tester.pump();
    expect(controller.calls, 2);
    controller.pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(InvoiceFormSheet), findsNothing);
    expect(find.textContaining('تمت إضافة الفاتورة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('POS waits, keeps cart on failure and clears only after commit',
      (tester) async {
    final controller = PendingSalesController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PosCrmScreen(controller: controller))));
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('pos-checkout')));
    await tester.pump();
    expect(controller.calls, 1);
    expect(find.text('جارٍ حفظ البيع…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos-checkout')),
        warnIfMissed: false);
    await tester.pump();
    expect(controller.calls, 1);
    controller.pending
        .completeError(const SaleValidationException('فشل تخزين اصطناعي'));
    await tester.pumpAndSettle();
    expect(find.text('فشل تخزين اصطناعي'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pos-checkout')))
            .onPressed,
        isNotNull);
    controller.pending = Completer<void>();
    await tester.tap(find.byKey(const Key('pos-checkout')));
    await tester.pump();
    expect(controller.calls, 2);
    controller.pending.complete();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pos-checkout')))
            .onPressed,
        isNull);
    expect(find.text('تم إتمام البيع وتحديث المخزون والأستاذ العام'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
