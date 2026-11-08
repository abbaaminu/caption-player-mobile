import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/models/license_state.dart';

void main() {
  group('LicenseState', () {
    test('parses and trims a persisted license', () {
      final license = LicenseState.fromJson(<String, dynamic>{
        'key': '  CLP-1234  ',
        'subscribed': true,
      });

      expect(license.key, 'CLP-1234');
      expect(license.isSubscribed, isTrue);
      expect(license.isValid, isTrue);
    });

    test('tolerates legacy or malformed values', () {
      for (final json in <Map<String, dynamic>>[
        <String, dynamic>{},
        <String, dynamic>{'key': '   ', 'subscribed': true},
        <String, dynamic>{'key': 42, 'subscribed': true},
        <String, dynamic>{'key': 'CLP-1234', 'subscribed': 'yes'},
      ]) {
        final license = LicenseState.fromJson(json);
        expect(license.isValid, isFalse, reason: json.toString());
      }
    });

    test('requires a key for a subscription to be valid', () {
      expect(const LicenseState(isSubscribed: true).isValid, isFalse);
      expect(const LicenseState(key: 'CLP-1234').isValid, isFalse);
    });

    test('round-trips through JSON', () {
      const license = LicenseState(key: 'CLP-1234', isSubscribed: true);

      expect(LicenseState.fromJson(license.toJson()), license);
      expect(license.toJson(), <String, dynamic>{
        'key': 'CLP-1234',
        'subscribed': true,
      });
    });

    test('copies individual fields', () {
      const license = LicenseState(key: 'CLP-1234', isSubscribed: true);

      expect(
        license.copyWith(isSubscribed: false),
        const LicenseState(key: 'CLP-1234'),
      );
      expect(
        license.copyWith(key: 'CLP-9999'),
        const LicenseState(key: 'CLP-9999', isSubscribed: true),
      );
      expect(license.copyWith(), license);
    });

    test('implements value equality', () {
      const a = LicenseState(key: 'CLP-1234', isSubscribed: true);
      const b = LicenseState(key: 'CLP-1234', isSubscribed: true);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const LicenseState(key: 'CLP-0000', isSubscribed: true)));
    });
  });
}
