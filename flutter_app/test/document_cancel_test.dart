import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/customer_list_sheet.dart';
import 'package:nasqo_pro_erp/screens/invoice_form_sheet.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

// Neither override calls super: any accidental persistence entry point is
// counted, without opening SQLite or writing to the host filesystem.
class DocumentSpy extends ErpController {
  DocumentSpy() : super(autoInitDb: false);
  int invoiceCalls = 0;
  int customerCalls = 0;

  @override
  Future<void> submitSalesInvoice({
    required String accountId,
    required String customerName,
    required WarehouseRecord warehouse,
    required PaymentMethod payment,
    required bool includeVat,
    required List<InvoiceItemRow> rows,
    String documentNumber = '',
    String memo = '',
  }) async {
    invoiceCalls++;
  }

  @override
  AccountRecord addCustomer({
    required String name,
    String phone = '',
    String note = '',
  }) {
    customerCalls++;
    throw StateError('Customer persistence must not run inside a draft');
  }
}

Future<void> openDraft(WidgetTester tester, DocumentSpy controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => InvoiceFormSheet(controller: controller),
            ),
            child: const Text('Open synthetic draft'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open synthetic draft'));
  await tester.pumpAndSettle();
}

Future<void> editDraft(WidgetTester tester) async {
  await tester.tap(find.text('اسم حر'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'اسم العميل أو الجهة'),
    'مسودة اصطناعية',
  );
  await tester.enterText(find.widgetWithText(TextFormField, 'الكمية'), '3');
  await tester.enterText(find.widgetWithText(TextFormField, 'السعر'), '25');
  await tester.enterText(
      find.byKey(const Key('invoice-document-number')), 'QA-321');
  await tester.enterText(find.byKey(const Key('invoice-memo')), 'بيان اختباري');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  for (final exit in ['cancel', 'close', 'navigator', 'system']) {
    testWidgets('$exit discards populated draft without writes', (
      tester,
    ) async {
      final controller = DocumentSpy();
      addTearDown(controller.dispose);
      final accounts = List<AccountRecord>.of(controller.accounts);
      final ledger = List<LedgerEntryRecord>.of(controller.ledger);
      final inventory = List<InventoryItemRecord>.of(controller.inventory);
      final quantities = controller.inventory.map((i) => i.quantity).toList();
      await openDraft(tester, controller);
      await editDraft(tester);
      if (exit == 'cancel' || exit == 'close') {
        final target = find.byKey(
          Key(exit == 'cancel' ? 'invoice-cancel' : 'invoice-close'),
        );
        await tester.ensureVisible(target);
        await tester.tap(target);
      } else if (exit == 'navigator') {
        Navigator.of(tester.element(find.byType(InvoiceFormSheet))).pop();
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceFormSheet), findsNothing);
      expect(controller.invoiceCalls, 0);
      expect(controller.customerCalls, 0);
      expect(controller.accounts, orderedEquals(accounts));
      expect(controller.ledger, orderedEquals(ledger));
      expect(controller.inventory, orderedEquals(inventory));
      expect(
        controller.inventory.map((i) => i.quantity),
        orderedEquals(quantities),
      );
      expect(tester.takeException(), isNull);
      // A reopened route owns a fresh draft, not the discarded TextController.
      await tester.tap(find.text('Open synthetic draft'));
      await tester.pumpAndSettle();
      expect(find.text('مسودة اصطناعية'), findsNothing);
      await tester.tap(find.byKey(const Key('invoice-close')));
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'nested system Back closes picker first; picker cannot add accounts',
    (tester) async {
      final controller = DocumentSpy();
      addTearDown(controller.dispose);
      final accounts = List<AccountRecord>.of(controller.accounts);
      await openDraft(tester, controller);
      await editDraft(tester);
      await tester.ensureVisible(find.text('قائمة العملاء'));
      await tester.tap(find.text('قائمة العملاء'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerListSheet), findsOneWidget);
      expect(find.text('جديد'), findsNothing);
      expect(
        tester
            .widget<CustomerListSheet>(find.byType(CustomerListSheet))
            .allowAdd,
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CustomerListSheet), findsNothing);
      expect(find.byType(InvoiceFormSheet), findsOneWidget);
      expect(find.text('مسودة اصطناعية'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceFormSheet), findsNothing);
      expect(controller.accounts, orderedEquals(accounts));
      expect(controller.customerCalls, 0);
      expect(controller.invoiceCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty data opens safely, disables save, and permits cancel', (
    tester,
  ) async {
    final controller = DocumentSpy();
    addTearDown(controller.dispose);
    controller.accounts.clear();
    controller.warehouses.clear();
    controller.inventory.clear();
    controller.ledger.clear();
    await openDraft(tester, controller);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('invoice-save')))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byKey(const Key('invoice-cancel')));
    await tester.tap(find.byKey(const Key('invoice-cancel')));
    await tester.pumpAndSettle();
    expect(controller.invoiceCalls, 0);
    expect(controller.customerCalls, 0);
    expect(controller.accounts, isEmpty);
    expect(controller.inventory, isEmpty);
    expect(controller.ledger, isEmpty);
  });

  testWidgets(
    'explicit save invokes the persistence entry point exactly once',
    (tester) async {
      final controller = DocumentSpy();
      addTearDown(controller.dispose);
      await openDraft(tester, controller);
      await tester.ensureVisible(find.byKey(const Key('invoice-save')));
      await tester.tap(find.byKey(const Key('invoice-save')));
      await tester.pumpAndSettle();
      expect(controller.invoiceCalls, 1);
      expect(controller.customerCalls, 0);
      expect(find.byType(InvoiceFormSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
