import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_caption_player/config/app_config.dart';
import 'package:live_caption_player/services/api_service.dart';

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
      'reports backend failures without treating them as an invalid key',
      () async {
        final client = MockClient(
          (_) async => http.Response('{"valid":false}', 503),
        );
        final service = ApiService(client: client);

        await expectLater(
          service.verifyLicenseKey('CLP-1234-5678-9ABC'),
          throwsA(
            isA<LicenseVerificationException>()
                .having((error) => error.statusCode, 'statusCode', 503)
                .having(
                  (error) => error.message,
                  'message',
                  contains('HTTP 503'),
                ),
          ),
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

    test('rejects an oversized key without calling the server', () async {
      final client = MockClient((_) async {
        fail('An oversized key should not be sent to the server.');
      });
      final service = ApiService(client: client);

      await expectLater(
        service.verifyLicenseKey('x' * (AppConfig.maxLicenseKeyLength + 1)),
        throwsA(
          isA<LicenseVerificationException>().having(
            (error) => error.message,
            'message',
            contains('too long'),
          ),
        ),
      );
      service.close();
    });

    test('wraps connection failures with an actionable message', () async {
      final client = MockClient((_) async {
        throw http.ClientException('offline');
      });
      final service = ApiService(client: client);

      await expectLater(
        service.verifyLicenseKey('CLP-1234-5678-9ABC'),
        throwsA(
          isA<LicenseVerificationException>().having(
            (error) => error.message,
            'message',
            contains('internet connection'),
          ),
        ),
      );
      service.close();
    });

    test('wraps timeouts with an actionable message', () async {
      final client = MockClient((_) async {
        throw TimeoutException('slow');
      });
      final service = ApiService(client: client);

      await expectLater(
        service.verifyLicenseKey('CLP-1234-5678-9ABC'),
        throwsA(
          isA<LicenseVerificationException>().having(
            (error) => error.message,
            'message',
            contains('too long to respond'),
          ),
        ),
      );
      service.close();
    });

    test('rejects malformed JSON responses', () async {
      final client = MockClient((_) async => http.Response('not-json', 200));
      final service = ApiService(client: client);

      await expectLater(
        service.verifyLicenseKey('CLP-1234-5678-9ABC'),
        throwsA(
          isA<LicenseVerificationException>().having(
            (error) => error.message,
            'message',
            contains('unreadable response'),
          ),
        ),
      );
      service.close();
    });

    test('rejects responses without a boolean valid flag', () async {
      final client = MockClient(
        (_) async => http.Response('{"valid":"yes"}', 200),
      );
      final service = ApiService(client: client);

      await expectLater(
        service.verifyLicenseKey('CLP-1234-5678-9ABC'),
        throwsA(
          isA<LicenseVerificationException>().having(
            (error) => error.message,
            'message',
            contains('invalid response'),
          ),
        ),
      );
      service.close();
    });
  });
}
