import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Development-only APK updates. The server never receives the local SQLite DB.
class DevUpdateService {
  static const manifestUrl = 'https://erp.indexesstore.com/flutter-updates/manifest.json';
  static const _installer = MethodChannel('com.indexesstore.nasqo_qa/dev_updates');
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<DevRelease?> check() async {
    if (!supported) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(manifestUrl));
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw const FormatException('Update server unavailable');
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.length > 8192) throw const FormatException('Invalid manifest size');
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final release = DevRelease.fromJson(json);
      final current = await PackageInfo.fromPlatform();
      final installedCode = int.tryParse(current.buildNumber) ?? 0;
      return release.versionCode > installedCode ? release : null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> downloadAndInstall(DevRelease release) async {
    if (!supported) throw UnsupportedError('Android only');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final dir = await getTemporaryDirectory();
    final partial = File('${dir.path}/nasqo-dev-update.part');
    final apk = File('${dir.path}/nasqo-dev-update.apk');
    try {
      final request = await client.getUrl(release.apkUrl);
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw const HttpException('Download failed');
      final sink = partial.openWrite();
      var count = 0;
      final digestSink = AccumulatorSink<Digest>();
      final hashInput = sha256.startChunkedConversion(digestSink);
      try {
        await for (final chunk in response.timeout(const Duration(minutes: 4))) {
          count += chunk.length;
          if (count > 250 * 1024 * 1024) throw const FormatException('APK too large');
          hashInput.add(chunk);
          sink.add(chunk);
        }
      } finally {
        hashInput.close();
        await sink.close();
      }
      if (count != release.sizeBytes || digestSink.events.single.toString() != release.sha256) {
        throw const FormatException('APK integrity verification failed');
      }
      if (await apk.exists()) await apk.delete();
      await partial.rename(apk.path);
      await _installer.invokeMethod<void>('install', {'path': apk.path});
    } finally {
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }
}

class DevRelease {
  final int versionCode;
  final String versionName;
  final Uri apkUrl;
  final String sha256;
  final int sizeBytes;
  final String notes;

  DevRelease._(this.versionCode, this.versionName, this.apkUrl, this.sha256, this.sizeBytes, this.notes);

  factory DevRelease.fromJson(Map<String, dynamic> data) {
    if (data['enabled'] != true) throw const FormatException('Updates disabled');
    final code = data['versionCode'];
    final name = data['versionName'];
    final url = Uri.tryParse(data['apkUrl']?.toString() ?? '');
    final hash = data['sha256']?.toString() ?? '';
    final size = data['sizeBytes'];
    if (code is! int || code < 1 || name is! String || name.isEmpty ||
        url == null || url.scheme != 'https' || url.host != 'erp.indexesstore.com' ||
        !url.path.startsWith('/flutter-updates/') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        size is! int || size < 1024 || size > 250 * 1024 * 1024) {
      throw const FormatException('Invalid update manifest');
    }
    return DevRelease._(code, name, url, hash, size, (data['notes'] ?? '').toString());
  }
}
