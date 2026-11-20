import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/android_csv_writer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('com.indexesstore.nasqo_qa/csv_export');
  const writer = AndroidCsvWriter();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
      'calls file chooser once with the exact prepared bytes and reports cancel',
      () async {
    final bytes = Uint8List.fromList([239, 187, 191, 65]);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return false;
    });

    expect(await writer.saveToChosenFile(bytes, 'nasqo-sales.csv'), isFalse);
    expect(calls.single.method, 'saveCsv');
    expect(calls.single.arguments,
        {'bytes': bytes, 'suggestedName': 'nasqo-sales.csv'});
  });

  test('rejects invalid suggestions without calling Android', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return true;
    });
    await expectLater(writer.saveToChosenFile(Uint8List(1), '../sales.csv'),
        throwsArgumentError);
    await expectLater(writer.saveToChosenFile(Uint8List(0), 'sales.csv'),
        throwsArgumentError);
    expect(calls, 0);
  });
}
