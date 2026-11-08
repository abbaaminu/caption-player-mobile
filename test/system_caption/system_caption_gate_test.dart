import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_caption_player/config/app_config.dart';
import 'package:live_caption_player/services/api_service.dart';
import 'package:live_caption_player/services/storage_service.dart';
import 'package:live_caption_player/system_caption/system_caption_gate.dart';

class _MemoryStore implements KeyValueStore {
  _MemoryStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

ApiService _api(http.Response Function() respond) =>
    ApiService(client: MockClient((_) async => respond()));

String _license() => jsonEncode({'key': 'CLP-1', 'subscribed': true});

void main() {
  group('SystemCaptionGate', () {
    test('a fresh install has the full trial', () async {
      final gate = SystemCaptionGate(
        storage: StorageService(store: _MemoryStore()),
        api: _api(() => http.Response('{"valid":true}', 200)),
      );
      await gate.load();

      expect(gate.isUnlimited, isFalse);
      expect(gate.isExhausted, isFalse);
      expect(gate.remainingMs, AppConfig.maxFreeTrialMs);
    });

    test('is exhausted when the stored trial is used up', () async {
      final gate = SystemCaptionGate(
        storage: StorageService(
          store: _MemoryStore({
            StorageService.trialTimeKey: '${AppConfig.maxFreeTrialMs}',
          }),
        ),
        api: _api(() => http.Response('{"valid":true}', 200)),
      );
      await gate.load();

      expect(gate.isExhausted, isTrue);
      expect(gate.remainingMs, 0);
    });

    test('spending time shares the trial counter with the player', () async {
      final store = _MemoryStore({StorageService.trialTimeKey: '60000'});
      var clock = DateTime(2026, 1, 1);
      final gate = SystemCaptionGate(
        storage: StorageService(store: store),
        api: _api(() => http.Response('{"valid":true}', 200)),
        now: () => clock,
      );
      await gate.load();

      expect(await gate.spend(2500), isTrue);
      expect(store.values[StorageService.trialTimeKey], '62500');

      // Within the save interval nothing more is written yet.
      clock = clock.add(const Duration(seconds: 1));
      await gate.spend(2500);
      expect(store.values[StorageService.trialTimeKey], '62500');

      await gate.flush();
      expect(store.values[StorageService.trialTimeKey], '65000');
    });

    test('spend reports false once the trial runs out', () async {
      final gate = SystemCaptionGate(
        storage: StorageService(
          store: _MemoryStore({
            StorageService.trialTimeKey: '${AppConfig.maxFreeTrialMs - 1000}',
          }),
        ),
        api: _api(() => http.Response('{"valid":true}', 200)),
      );
      await gate.load();

      expect(await gate.spend(2500), isFalse);
      expect(gate.isExhausted, isTrue);
    });

    test('a stored license is unlimited and spends no trial', () async {
      final store = _MemoryStore({
        StorageService.licenseStateKey: _license(),
        StorageService.trialTimeKey: '${AppConfig.maxFreeTrialMs}',
      });
      final gate = SystemCaptionGate(
        storage: StorageService(store: store),
        api: _api(() => http.Response('{"valid":true}', 200)),
      );
      await gate.load();

      expect(gate.isUnlimited, isTrue);
      expect(gate.isExhausted, isFalse);
      expect(await gate.spend(5000), isTrue);
      expect(
        store.values[StorageService.trialTimeKey],
        '${AppConfig.maxFreeTrialMs}',
      );
    });

    test('the server revoking a license locks it again', () async {
      final gate = SystemCaptionGate(
        storage: StorageService(
          store: _MemoryStore({
            StorageService.licenseStateKey: _license(),
            StorageService.trialTimeKey: '${AppConfig.maxFreeTrialMs}',
          }),
        ),
        api: _api(() => http.Response('{"valid":false}', 200)),
      );
      await gate.load();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(gate.isUnlimited, isFalse);
      expect(gate.isExhausted, isTrue);
    });

    test('being offline never revokes a license', () async {
      final gate = SystemCaptionGate(
        storage: StorageService(
          store: _MemoryStore({StorageService.licenseStateKey: _license()}),
        ),
        api: ApiService(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
      );
      await gate.load();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(gate.isUnlimited, isTrue);
    });
  });

  group('StorageService trial time', () {
    test('saveCurrentTime never moves the counter backwards', () async {
      final store = _MemoryStore({StorageService.trialTimeKey: '90000'});
      final service = StorageService(store: store);

      await service.saveCurrentTime(30000);
      expect(store.values[StorageService.trialTimeKey], '90000');

      await service.saveCurrentTime(120000);
      expect(store.values[StorageService.trialTimeKey], '120000');
    });

    test('addTrialTime adds and clamps to the trial length', () async {
      final store = _MemoryStore({StorageService.trialTimeKey: '1000'});
      final service = StorageService(store: store);

      expect(await service.addTrialTime(2500), 3500);
      expect(await service.addTrialTime(-10), 3500);
      expect(
        await service.addTrialTime(AppConfig.maxFreeTrialMs),
        AppConfig.maxFreeTrialMs,
      );
    });
  });
}
