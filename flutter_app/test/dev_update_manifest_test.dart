import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/dev_update_service.dart';

Map<String, dynamic> validManifest() => {
  'enabled': true,
  'versionCode': 10004,
  'versionName': '1.0.19',
  'apkUrl': 'https://erp.indexesstore.com/flutter-updates/nasqo-dev-10004.apk',
  'sha256': 'a' * 64,
  'sizeBytes': 80000000,
  'notes': 'Development release',
};

void main() {
  test('accepts a valid signed APK release manifest', () {
    final release = DevRelease.fromJson(validManifest());
    expect(release.versionCode, 10004);
    expect(release.versionName, '1.0.19');
    expect(release.sizeBytes, 80000000);
    expect(release.sha256, 'a' * 64);
  });

  test('rejects disabled update channels', () {
    final data = validManifest()..['enabled'] = false;
    expect(() => DevRelease.fromJson(data), throwsFormatException);
  });

  test('rejects non-HTTPS and foreign download origins', () {
    for (final url in [
      'http://erp.indexesstore.com/flutter-updates/nasqo-dev-10004.apk',
      'https://example.org/flutter-updates/nasqo-dev-10004.apk',
      'https://erp.indexesstore.com.evil.org/flutter-updates/a.apk',
      'https://erp.indexesstore.com/other/nasqo-dev-10004.apk',
    ]) {
      final data = validManifest()..['apkUrl'] = url;
      expect(() => DevRelease.fromJson(data), throwsFormatException, reason: url);
    }
  });

  test('rejects malformed digest, version and APK size', () {
    for (final change in <Map<String, Object>>[
      {'sha256': 'bad'},
      {'sha256': 'Z' * 64},
      {'versionCode': 0},
      {'versionCode': '10004'},
      {'versionName': ''},
      {'sizeBytes': 0},
      {'sizeBytes': 300 * 1024 * 1024},
    ]) {
      final data = validManifest()..addAll(change);
      expect(() => DevRelease.fromJson(data), throwsFormatException, reason: '$change');
    }
  });
}
