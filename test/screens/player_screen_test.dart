import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_caption_player/config/app_config.dart';
import 'package:live_caption_player/screens/player_screen.dart';
import 'package:live_caption_player/services/activation_link_service.dart';
import 'package:live_caption_player/services/api_service.dart';
import 'package:live_caption_player/services/media_picker_service.dart';
import 'package:live_caption_player/services/microphone_permission_service.dart';
import 'package:live_caption_player/services/storage_service.dart';
import 'package:live_caption_player/theme/app_theme.dart';

void main() {
  group('PlayerScreen startup', () {
    testWidgets('shows the paywall when the saved trial is exhausted', (
      tester,
    ) async {
      final store = _MemoryStore(<String, String>{
        StorageService.trialTimeKey: AppConfig.maxFreeTrialMs.toString(),
      });

      await _pumpPlayer(
        tester,
        store: store,
        client: _client('{"valid":true}'),
      );

      expect(find.text(_trialEndedMessage), findsOneWidget);
      expect(find.text('Free trial · 0 min left'), findsOneWidget);
    });

    testWidgets('shows the remaining whole minutes of the trial', (
      tester,
    ) async {
      final store = _MemoryStore(<String, String>{
        StorageService.trialTimeKey: const Duration(
          minutes: 25,
        ).inMilliseconds.toString(),
      });

      await _pumpPlayer(
        tester,
        store: store,
        client: _client('{"valid":true}'),
      );

      expect(find.text('Free trial · 5 min left'), findsOneWidget);
      expect(find.textContaining('free trial has ended'), findsNothing);
    });

    testWidgets('restores a cached license and revalidates it', (tester) async {
      final store = _MemoryStore(<String, String>{
        StorageService.licenseStateKey: _licenseJson('CLP-CACHED'),
      });
      var requestedKey = '';
      final client = MockClient((request) async {
        requestedKey =
            (jsonDecode(request.body) as Map<String, dynamic>)['license_key']
                as String;
        return http.Response('{"valid":true}', 200);
      });

      await _pumpPlayer(tester, store: store, client: client);

      expect(requestedKey, 'CLP-CACHED');
      expect(find.text('Activated · unlimited captions'), findsOneWidget);
      expect(find.textContaining('free trial has ended'), findsNothing);
    });

    testWidgets('drops a cached license that the server rejects', (
      tester,
    ) async {
      final store = _MemoryStore(<String, String>{
        StorageService.trialTimeKey: AppConfig.maxFreeTrialMs.toString(),
        StorageService.licenseStateKey: _licenseJson('CLP-REVOKED'),
      });

      await _pumpPlayer(
        tester,
        store: store,
        client: _client('{"valid":false}'),
      );

      expect(find.text(_trialEndedMessage), findsOneWidget);
      expect(store.values.containsKey(StorageService.licenseStateKey), isFalse);
    });

    testWidgets('recovers from a startup storage failure when retried', (
      tester,
    ) async {
      final store = _MemoryStore()..readError = StateError('storage offline');

      await _pumpPlayer(
        tester,
        store: store,
        client: _client('{"valid":true}'),
      );

      expect(find.text('Could not load saved progress'), findsOneWidget);
      expect(
        find.textContaining('Could not load your saved session'),
        findsOneWidget,
      );

      store
        ..readError = null
        ..values[StorageService.trialTimeKey] = AppConfig.maxFreeTrialMs
            .toString();

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load saved progress'), findsNothing);
      expect(find.text(_trialEndedMessage), findsOneWidget);
    });
  });

  group('PlayerScreen activation', () {
    testWidgets('activates the app with a key entered in the paywall', (
      tester,
    ) async {
      final store = _MemoryStore(<String, String>{
        StorageService.trialTimeKey: AppConfig.maxFreeTrialMs.toString(),
      });
      String? requestedKey;

      await _pumpPlayer(
        tester,
        store: store,
        client: MockClient((request) async {
          requestedKey =
              (jsonDecode(request.body) as Map<String, dynamic>)['license_key']
                  as String;
          return http.Response('{"valid":true}', 200);
        }),
      );

      await tester.enterText(find.byType(TextField), '  CLP-NEW-KEY  ');
      await tester.ensureVisible(find.text('Activate player'));
      await tester.tap(find.text('Activate player'));
      await tester.pumpAndSettle();

      expect(requestedKey, 'CLP-NEW-KEY');
      expect(find.text('Activated · unlimited captions'), findsOneWidget);
      expect(find.textContaining('free trial has ended'), findsNothing);
      expect(
        store.values[StorageService.licenseStateKey],
        contains('CLP-NEW-KEY'),
      );
    });

    testWidgets('keeps the paywall open and reports an invalid key', (
      tester,
    ) async {
      final store = _MemoryStore(<String, String>{
        StorageService.trialTimeKey: AppConfig.maxFreeTrialMs.toString(),
      });

      await _pumpPlayer(
        tester,
        store: store,
        client: _client('{"valid":false}'),
      );

      await tester.enterText(find.byType(TextField), 'CLP-BAD');
      await tester.ensureVisible(find.text('Activate player'));
      await tester.tap(find.text('Activate player'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('That activation key is not valid'),
        findsOneWidget,
      );
      expect(find.text(_trialEndedMessage), findsOneWidget);
      expect(store.values.containsKey(StorageService.licenseStateKey), isFalse);
    });

    testWidgets('activates from a deep link with a key', (tester) async {
      final store = _MemoryStore();

      await _pumpPlayer(
        tester,
        store: store,
        client: _client('{"valid":true}'),
        links: _FakeActivationLinks(
          initialLink: 'captionplayer://activate?key=CLP-DEEP-LINK',
        ),
      );

      expect(find.text('Activated · unlimited captions'), findsOneWidget);
      expect(
        store.values[StorageService.licenseStateKey],
        contains('CLP-DEEP-LINK'),
      );
    });
  });
}

final String _trialEndedMessage =
    'Your ${AppConfig.freeTrialDuration.inMinutes}-minute free trial has ended.';

Future<void> _pumpPlayer(
  WidgetTester tester, {
  required _MemoryStore store,
  required http.Client client,
  _FakeActivationLinks? links,
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final linkSource = links ?? _FakeActivationLinks();
  addTearDown(linkSource.dispose);
  final apiService = ApiService(client: client);
  addTearDown(apiService.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: PlayerScreen(
        storageService: StorageService(store: store),
        apiService: apiService,
        activationLinkSource: linkSource,
        microphonePermissions: _FakeMicrophonePermissions(),
        mediaPicker: _FakeMediaPicker(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MockClient _client(String body) {
  return MockClient((_) async => http.Response(body, 200));
}

String _licenseJson(String key) {
  return jsonEncode(<String, dynamic>{'key': key, 'subscribed': true});
}

class _MemoryStore implements KeyValueStore {
  _MemoryStore([Map<String, String>? initialValues])
    : values = <String, String>{...?initialValues};

  final Map<String, String> values;
  Object? readError;

  @override
  Future<String?> read(String key) async {
    final error = readError;
    if (error != null) {
      throw error;
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _FakeActivationLinks implements ActivationLinkSource {
  _FakeActivationLinks({this.initialLink});

  final String? initialLink;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  @override
  Stream<String> get links => _controller.stream;

  @override
  Future<String?> getInitialLink() async => initialLink;

  Future<void> dispose() => _controller.close();
}

class _FakeMediaPicker implements MediaPickerService {
  @override
  Future<PlatformFile?> pickMedia() async => null;
}

class _FakeMicrophonePermissions implements MicrophonePermissionService {
  @override
  Future<bool> request() async => true;

  @override
  Future<bool> openSettings() async => true;
}
