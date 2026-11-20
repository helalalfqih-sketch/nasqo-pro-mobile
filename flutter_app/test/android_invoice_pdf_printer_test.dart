import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/android_invoice_pdf_printer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.indexesstore.nasqo_qa/invoice_pdf_print');
  const printer = AndroidInvoicePdfPrinter();
  final bytes = Uint8List.fromList(
      utf8.encode('%PDF-1.4\nsynthetic-channel-contract-only'));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test(
      'explicit call forwards generated PDF once; success only acknowledges dialog',
      () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.method, 'openPrintDialog');
      expect((call.arguments as Map)['bytes'], bytes);
      return true;
    });
    expect(calls, 0);
    await printer.openPrintDialog(bytes);
    expect(calls, 1);
  });
  test('empty invalid and oversized inputs never invoke native channel',
      () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return true;
    });
    for (final invalid in [
      Uint8List(0),
      Uint8List.fromList([1, 2, 3, 4, 5]),
      Uint8List(AndroidInvoicePdfPrinter.maxBytes + 1)
    ]) {
      await expectLater(printer.openPrintDialog(invalid), throwsArgumentError);
    }
    expect(calls, 0);
  });
  test('native refusal and missing dialog acknowledgement are not success',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    await expectLater(
        printer.openPrintDialog(bytes),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'PRINT_NOT_REQUESTED')));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'PRINT_BUSY');
    });
    await expectLater(
        printer.openPrintDialog(bytes),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'PRINT_BUSY')));
  });
  test(
      'unsupported platform propagates missing plugin rather than fake success',
      () async {
    await expectLater(
        printer.openPrintDialog(bytes), throwsA(isA<MissingPluginException>()));
  });
}
