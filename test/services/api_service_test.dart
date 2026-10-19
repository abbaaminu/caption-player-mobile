import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:premium_live_caption/config/app_config.dart';
import 'package:premium_live_caption/services/api_service.dart';

void main() {
  group('ApiService.verifyLicenseKey', () {
    test('posts the trimmed key to the production license endpoint', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url, Uri.parse(AppConfig.licenseVerificationUrl));
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {'license_key': 'CLP-1234-5678-9ABC'});
        return http.Response('{"valid":true}', 200);
      });
      final service = ApiService(client: client);

      expect(await service.verifyLicenseKey('  CLP-1234-5678-9ABC  '), isTrue);
      service.close();
    });

    test('returns false for an invalid license', () async {
      final client = MockClient(
        (_) async => http.Response('{"valid":false}', 200),
      );
      final service = ApiService(client: client);

      expect(await service.verifyLicenseKey('CLP-INVALID'), isFalse);
      service.close();
    });

    test(
      'rejects backend failures without treating them as an invalid key',
      () async {
        final client = MockClient(
          (_) async => http.Response('{"valid":false}', 503),
        );
        final service = ApiService(client: client);

        await expectLater(
          service.verifyLicenseKey('CLP-1234-5678-9ABC'),
          throwsA(isA<HttpException>()),
        );
        service.close();
      },
    );

    test('does not call the server for an empty key', () async {
      final client = MockClient((_) async {
        fail('An empty license key should not be sent to the server.');
      });
      final service = ApiService(client: client);

      expect(await service.verifyLicenseKey('  '), isFalse);
      service.close();
    });
  });
}
