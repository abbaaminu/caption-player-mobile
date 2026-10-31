import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_caption_player/config/app_config.dart';
import 'package:live_caption_player/screens/player_screen.dart';
import 'package:live_caption_player/services/activation_link_service.dart';
import 'package:live_caption_player/services/api_service.dart';
import 'package:live_caption_player/services/media_audio_source.dart';
import 'package:live_caption_player/services/media_picker_service.dart';
import 'package:live_caption_player/services/speech_service.dart';
import 'package:live_caption_player/services/storage_service.dart';
import 'package:live_caption_player/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

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

  group('PlayerScreen playback lifecycle', () {
    testWidgets('pauses playback and captions when the app is hidden', (
      tester,
    ) async {
      final controller = _FakeVideoController();
      final engine = _FakeSpeechEngine();
      final speechService = SpeechService(engine: engine);
      addTearDown(speechService.dispose);

      await _pumpPlayer(
        tester,
        store: _MemoryStore(),
        client: _client('{"valid":true}'),
        speechService: speechService,
        mediaPicker: _FakeMediaPicker(file: _TestMediaFile('clip.mp4', 2048)),
        videoControllerFactory: (_) async => controller,
      );

      await tester.tap(find.text('Open media'));
      await tester.pump();
      await tester.pump();

      expect(controller.value.isPlaying, isTrue);
      expect(engine.listenCalls, 1);

      await _sendAppLifecycleState(tester, AppLifecycleState.hidden);
      await tester.pump();
      await tester.pump();

      expect(controller.pauseCalls, 1);
      expect(controller.value.isPlaying, isFalse);
      expect(engine.stopCalls, 1);

      await _sendAppLifecycleState(tester, AppLifecycleState.resumed);
      await tester.pump();

      // Returning to the foreground must not resume playback on its own.
      expect(controller.playCalls, 1);
      expect(controller.value.isPlaying, isFalse);
    });
  });
}

Future<void> _sendAppLifecycleState(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  // The binding synthesizes the intermediate transitions, so sending the
  // target state is enough to reach it from any starting state.
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}

final String _trialEndedMessage =
    'Your ${AppConfig.freeTrialDuration.inMinutes}-minute free trial has ended.';

Future<void> _pumpPlayer(
  WidgetTester tester, {
  required _MemoryStore store,
  required http.Client client,
  _FakeActivationLinks? links,
  SpeechService? speechService,
  MediaPickerService? mediaPicker,
  Future<VideoPlayerController> Function(PlatformFile file)?
  videoControllerFactory,
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
        mediaPicker: mediaPicker ?? _FakeMediaPicker(),
        speechService: speechService,
        videoControllerFactory: videoControllerFactory,
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
  _FakeMediaPicker({this.file});

  final PlatformFile? file;

  @override
  Future<PlatformFile?> pickMedia() async => file;
}

/// A picked file that only exposes the metadata the player reads before a
/// controller is created.
base class _TestMediaFile extends PlatformFile {
  _TestMediaFile(this.name, this.size);

  @override
  final String name;

  final int size;

  @override
  Uri get uri => Uri.file('C:/media/$name');

  @override
  Never get xFile => throw UnsupportedError('Not needed in widget tests');

  @override
  int? lengthSync() => size;

  @override
  Future<int> length() async => size;

  @override
  Never readAsBytes() => throw UnsupportedError('Not needed in widget tests');

  @override
  Never readAsByteStream() =>
      throw UnsupportedError('Not needed in widget tests');
}

/// A controller that plays without touching the video_player plugin.
class _FakeVideoController extends VideoPlayerController {
  _FakeVideoController()
    : super.networkUrl(Uri.parse('https://example.com/clip.mp4'));

  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      duration: const Duration(seconds: 30),
      isInitialized: true,
    );
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    value = value.copyWith(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }
}

class _FakeSpeechEngine implements SpeechRecognitionEngine {
  int listenCalls = 0;
  int stopCalls = 0;
  bool _listening = false;

  @override
  bool get isSupported => true;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize({
    required void Function(String message, bool permanent) onError,
    required void Function(SpeechEngineStatus status) onStatus,
    required void Function(int progress) onProgress,
  }) async => true;

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    required void Function(String message) onError,
    required MediaAudioSource? audioSource,
    required Duration Function() position,
  }) async {
    listenCalls += 1;
    _listening = true;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    _listening = false;
  }

  @override
  Future<void> cancel() async {
    _listening = false;
  }

  @override
  void resetTimeline() {}

  @override
  Future<void> dispose() async {}
}
