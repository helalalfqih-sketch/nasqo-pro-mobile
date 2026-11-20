import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidCsvWriter {
  const AndroidCsvWriter();

  static const channelName = 'com.indexesstore.nasqo_qa/csv_export';
  static const maxBytes = 8 * 1024 * 1024;
  static const _channel = MethodChannel(channelName);
  static final _name = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,95}\.csv$');

  /// True only after Android finished writing; false means user canceled.
  /// The native picker grants access only to the selected destination.
  Future<bool> saveToChosenFile(Uint8List bytes, String suggestedName) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('اختيار وجهة CSV متاح على Android فقط.');
    }
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        !_name.hasMatch(suggestedName)) {
      throw ArgumentError('ملف CSV غير صالح.');
    }
    final outcome = await _channel.invokeMethod<bool>('saveCsv', {
      'bytes': bytes,
      'suggestedName': suggestedName,
    });
    if (outcome == null) {
      throw StateError('لم يتم تأكيد حفظ الملف.');
    }
    return outcome;
  }
}
