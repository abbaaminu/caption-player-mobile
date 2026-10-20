import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/utils/web_origin.dart';

void main() {
  group('isSecureWebOrigin', () {
    test('holds on non-web platforms regardless of the URL', () {
      expect(
        isSecureWebOrigin(Uri.parse('http://example.com'), isWeb: false),
        isTrue,
      );
    });

    test('accepts HTTPS on the web', () {
      expect(
        isSecureWebOrigin(
          Uri.parse('https://caption.example.com'),
          isWeb: true,
        ),
        isTrue,
      );
    });

    test('accepts localhost development origins over HTTP', () {
      for (final origin in <String>[
        'http://localhost:8080',
        'http://127.0.0.1:5000',
        'http://[::1]:3000',
      ]) {
        expect(
          isSecureWebOrigin(Uri.parse(origin), isWeb: true),
          isTrue,
          reason: origin,
        );
      }
    });

    test('rejects remote HTTP and non-HTTP origins', () {
      for (final origin in <String>[
        'http://caption.example.com',
        'ftp://localhost',
        'file:///index.html',
      ]) {
        expect(
          isSecureWebOrigin(Uri.parse(origin), isWeb: true),
          isFalse,
          reason: origin,
        );
      }
    });
  });
}
