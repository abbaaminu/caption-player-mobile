import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/config/app_config.dart';
import 'package:live_caption_player/services/storage_service.dart';

void main() {
  group('StorageService trial time', () {
    test('returns zero when nothing is stored', () async {
      final service = StorageService(store: _MemoryStore());

      expect(await service.loadSavedTime(), 0);
    });

    test('loads a valid stored duration', () async {
      final service = StorageService(
        store: _MemoryStore(<String, String>{
          StorageService.trialTimeKey: '125000',
        }),
      );

      expect(await service.loadSavedTime(), 125000);
    });

    test('treats corrupt or negative values as zero', () async {
      for (final value in <String>['not-a-number', '-1', '0', '']) {
        final service = StorageService(
          store: _MemoryStore(<String, String>{
            StorageService.trialTimeKey: value,
          }),
        );

        expect(await service.loadSavedTime(), 0, reason: value);
      }
    });

    test('clamps tampered values to the configured trial length', () async {
      final service = StorageService(
        store: _MemoryStore(<String, String>{
          StorageService.trialTimeKey: '999999999',
        }),
      );

      expect(await service.loadSavedTime(), AppConfig.maxFreeTrialMs);
    });

    test('clamps progress before writing it', () async {
      final store = _MemoryStore();
      final service = StorageService(store: store);

      await service.saveCurrentTime(-5000);
      expect(store.values[StorageService.trialTimeKey], '0');

      await service.saveCurrentTime(90000);
      expect(store.values[StorageService.trialTimeKey], '90000');

      await service.saveCurrentTime(AppConfig.maxFreeTrialMs + 5000);
      expect(
        store.values[StorageService.trialTimeKey],
        AppConfig.maxFreeTrialMs.toString(),
      );
    });
  });

  group('StorageService license', () {
    test('returns null when no license is stored', () async {
      final service = StorageService(store: _MemoryStore());

      expect(await service.loadLicense(), isNull);
    });

    test('saves a trimmed key and reloads it as active', () async {
      final store = _MemoryStore();
      final service = StorageService(store: store);

      await service.saveLicense('  CLP-1234  ');

      final rawValue = store.values[StorageService.licenseStateKey];
      expect(rawValue, isNotNull);
      expect(jsonDecode(rawValue!), <String, dynamic>{
        'key': 'CLP-1234',
        'subscribed': true,
      });

      final license = await service.loadLicense();
      expect(license?.key, 'CLP-1234');
      expect(license?.isValid, isTrue);
    });

    test('rejects an empty key', () async {
      final store = _MemoryStore();
      final service = StorageService(store: store);

      await expectLater(service.saveLicense('   '), throwsArgumentError);
      expect(store.values, isEmpty);
    });

    test('ignores malformed persisted JSON', () async {
      for (final value in <String>['{', '[]', 'null', '']) {
        final service = StorageService(
          store: _MemoryStore(<String, String>{
            StorageService.licenseStateKey: value,
          }),
        );

        expect(await service.loadLicense(), isNull, reason: value);
      }
    });

    test('does not trust an incomplete license payload', () async {
      final service = StorageService(
        store: _MemoryStore(<String, String>{
          StorageService.licenseStateKey: jsonEncode(<String, dynamic>{
            'key': '   ',
            'subscribed': true,
          }),
        }),
      );

      expect(await service.loadLicense(), isNull);
    });

    test('clears a stored license', () async {
      final store = _MemoryStore();
      final service = StorageService(store: store);
      await service.saveLicense('CLP-1234');

      await service.clearLicense();

      expect(store.values, isEmpty);
      expect(await service.loadLicense(), isNull);
    });
  });
}

class _MemoryStore implements KeyValueStore {
  _MemoryStore([Map<String, String>? initialValues])
    : values = <String, String>{...?initialValues};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
