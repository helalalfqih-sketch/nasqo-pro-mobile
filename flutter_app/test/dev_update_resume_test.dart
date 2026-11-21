import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/services/dev_update_service.dart';
import 'dev_update_test.dart' show manifest, payload;

void main() {
  for (final mode in ['partial', 'full', 'wrong-range', 'tampered']) {
    test('interrupted HTTP response then $mode', () async {
      final dir = await Directory.systemTemp.createTemp('update-resume-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final ranges = <String?>[];
      server.listen((req) async {
        ranges.add(req.headers.value('range'));
        final res = req.response;
        if (ranges.length == 1) {
          res.add(payload.sublist(0, 512));
        } else if (mode == 'full') {
          res.add(payload);
        } else {
          res.statusCode = 206;
          res.headers.set('content-range',
              'bytes ${mode == "wrong-range" ? 511 : 512}-2047/2048');
          res.add(
              mode == 'tampered' ? List.filled(1536, 0) : payload.sublist(512));
        }
        await res.close();
      });
      final result =
          DevRelease.fromJson(manifest()).downloadVerified(dir, (offset) async {
        final req = await client
            .getUrl(Uri.parse('http://127.0.0.1:${server.port}/test'));
        if (offset > 0) req.headers.set('range', 'bytes=$offset-');
        return req.close();
      }, backoff: Duration.zero);
      if (mode == 'wrong-range' || mode == 'tampered') {
        await expectLater(result, throwsFormatException);
        expect(Directory('${dir.path}/dev-updates').listSync(), isEmpty);
      } else {
        expect(await (await result).readAsBytes(), payload);
      }
      expect(ranges, [null, 'bytes=512-']);
    });
  }
}
