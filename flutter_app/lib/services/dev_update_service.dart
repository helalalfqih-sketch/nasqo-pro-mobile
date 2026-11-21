import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class DevUpdateService {
  const DevUpdateService();

  static const manifestUrl =
      'https://erp.indexesstore.com/flutter-updates/manifest.json';
  static const _installer = MethodChannel(
    'com.indexesstore.nasqo_qa/dev_updates',
  );
  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<HttpClientResponse> _get(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('تعذّر جلب ملف التحديث من الخادم.');
    }
    return response;
  }

  Future<DevRelease?> check() async {
    if (!supported) return null;
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final response = await _get(client, Uri.parse(manifestUrl));
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > 8192) {
          throw const FormatException('ملف وصف التحديث أكبر من المسموح.');
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (data['enabled'] == false) return null;
      final release = DevRelease.fromJson(data);
      final current = await PackageInfo.fromPlatform();
      final installedCode = int.parse(current.buildNumber);
      return release.versionCode > installedCode ? release : null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadAndInstall(DevRelease release) async {
    if (!supported) throw UnsupportedError('Android only');
    final cache = await getTemporaryDirectory();
    // Retry interrupted mobile-network transfers from the beginning. Each
    // attempt writes to a disposable file and verifies the full SHA-256 before
    // the Android installer is invoked. Never retry an integrity failure.
    for (var attempt = 1; attempt <= 3; attempt++) {
      final client =
          HttpClient()..connectionTimeout = const Duration(seconds: 20);
      try {
        final response = await _get(client, release.apkUrl);
        final apk = await release.saveVerified(
          response.timeout(const Duration(seconds: 60)),
          cache,
        );
        await _installer.invokeMethod<void>('install', {
          'path': apk.path,
          'versionCode': release.versionCode,
        });
        return;
      } on SocketException {
        if (attempt == 3) rethrow;
      } on HttpException {
        if (attempt == 3) rethrow;
      } on TimeoutException {
        if (attempt == 3) rethrow;
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(Duration(seconds: attempt * 2));
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

  DevRelease._(
    this.versionCode,
    this.versionName,
    this.apkUrl,
    this.sha256,
    this.sizeBytes,
    this.notes,
  );

  factory DevRelease.fromJson(Map<String, dynamic> data) {
    final code = data['versionCode'];
    final name = data['versionName'];
    final url = Uri.tryParse(data['apkUrl']?.toString() ?? '');
    final hash = data['sha256']?.toString() ?? '';
    final size = data['sizeBytes'];
    if (data['enabled'] != true ||
        code is! int ||
        code < 1 ||
        name is! String ||
        name.isEmpty ||
        url == null ||
        url.scheme != 'https' ||
        url.host != 'erp.indexesstore.com' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        !url.path.startsWith('/flutter-updates/') ||
        !url.path.endsWith('.apk') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        size is! int ||
        size < 1024 ||
        size > 250 * 1024 * 1024) {
      throw const FormatException('وصف التحديث غير صالح.');
    }
    return DevRelease._(
      code,
      name,
      url,
      hash,
      size,
      (data['notes'] ?? '').toString(),
    );
  }

  Future<File> saveVerified(Stream<List<int>> bytes, Directory cache) async {
    final updates = await Directory('${cache.path}/dev-updates').create();
    final transfer = await updates.createTemp('download-');
    try {
      final partial = File('${transfer.path}/download.part');
      final output = await partial.open(mode: FileMode.write);
      final digest = AccumulatorSink<crypto.Digest>();
      final hashInput = crypto.sha256.startChunkedConversion(digest);
      var count = 0;
      try {
        await for (final chunk in bytes) {
          count += chunk.length;
          if (count > sizeBytes)
            throw const FormatException('حجم ملف التحديث غير مطابق.');
          hashInput.add(chunk);
          await output.writeFrom(chunk);
        }
      } finally {
        hashInput.close();
        await output.close();
      }
      if (count != sizeBytes || digest.events.single.toString() != sha256) {
        throw const FormatException('فشل التحقق من بصمة التحديث أو حجمه.');
      }
      return await partial.rename(
        '${updates.path}/nasqo-$versionCode-$sha256.apk',
      );
    } finally {
      await transfer.delete(recursive: true);
    }
  }
}
