import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
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
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final file = await release.downloadVerified(cache, (offset) async {
        final request = await client.getUrl(release.apkUrl);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (offset > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        }
        return request.close().timeout(const Duration(seconds: 20));
      });
      await _installer.invokeMethod<void>('install', {
        'path': file.path,
        'versionCode': release.versionCode,
      });
    } finally {
      client.close(force: true);
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

  Future<File> _finish(File partial, Directory updates) async {
    if (await partial.length() != sizeBytes ||
        (await crypto.sha256.bind(partial.openRead()).first).toString() !=
            sha256) {
      throw const FormatException('فشل التحقق من بصمة التحديث أو حجمه.');
    }
    return partial.rename('${updates.path}/nasqo-$versionCode-$sha256.apk');
  }

  Future<void> _write(File file, Stream<List<int>> stream, int offset) async {
    final out =
        await file.open(mode: offset == 0 ? FileMode.write : FileMode.append);
    var count = offset;
    try {
      await for (final chunk in stream) {
        count += chunk.length;
        if (count > sizeBytes) {
          throw const FormatException('حجم ملف التحديث غير مطابق.');
        }
        await out.writeFrom(chunk);
      }
    } finally {
      await out.close();
    }
  }

  Future<File> saveVerified(Stream<List<int>> bytes, Directory cache) async {
    final updates = await Directory('${cache.path}/dev-updates').create();
    final transfer = await updates.createTemp('download-');
    try {
      final partial = File('${transfer.path}/download.part');
      await _write(partial, bytes, 0);
      return await _finish(partial, updates);
    } finally {
      await transfer.delete(recursive: true);
    }
  }

  Future<File> downloadVerified(
      Directory cache, Future<HttpClientResponse> Function(int offset) fetch,
      {Duration backoff = const Duration(seconds: 1)}) async {
    final updates = await Directory('${cache.path}/dev-updates').create();
    final transfer = await updates.createTemp('download-');
    try {
      final partial = await File('${transfer.path}/download.part').create();
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          var offset = await partial.length();
          if (offset == sizeBytes) return await _finish(partial, updates);
          final response = await fetch(offset);
          if (response.statusCode == HttpStatus.ok) {
            // A server that ignores Range sent an entire new representation.
            offset = 0;
          } else if (offset > 0 &&
              response.statusCode == HttpStatus.partialContent) {
            final expected = 'bytes $offset-${sizeBytes - 1}/$sizeBytes';
            if (response.headers.value(HttpHeaders.contentRangeHeader) !=
                expected) {
              throw const FormatException('موضع استكمال التحديث غير مطابق.');
            }
          } else {
            throw const HttpException('تعذر جلب التحديث.');
          }
          final encoding =
              response.headers.value(HttpHeaders.contentEncodingHeader);
          if ((encoding != null && encoding != 'identity') ||
              (response.contentLength >= 0 &&
                  response.contentLength != sizeBytes - offset)) {
            throw const FormatException('بيانات حجم التحديث غير مطابقة.');
          }
          await _write(
              partial, response.timeout(const Duration(seconds: 60)), offset);
          if (await partial.length() < sizeBytes) {
            throw const HttpException('انقطع تنزيل التحديث.');
          }
          return await _finish(partial, updates);
        } on IOException catch (e) {
          if (e is! HttpException && e is! SocketException) rethrow;
        } on TimeoutException {
          // Resume from exactly the bytes successfully written.
        }
        if (attempt < 2) await Future<void>.delayed(backoff * (attempt + 1));
      }
      throw const HttpException('لم يكتمل التنزيل بعد ثلاث محاولات.');
    } finally {
      await transfer.delete(recursive: true);
    }
  }
}
