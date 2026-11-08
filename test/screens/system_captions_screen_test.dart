import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_caption_player/config/app_config.dart';
import 'package:live_caption_player/screens/system_captions_screen.dart';
import 'package:live_caption_player/services/storage_service.dart';
import 'package:live_caption_player/system_caption/system_caption_platform.dart';
import 'package:live_caption_player/theme/app_theme.dart';

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

class _FakePlatform implements SystemCaptionPlatform {
  _FakePlatform(this.currentStatus);

  SystemCaptionStatus currentStatus;
  CaptionStyle currentStyle = const CaptionStyle();

  @override
  Future<SystemCaptionStatus> status() async => currentStatus;

  @override
  Future<CaptionStyle> style() async => currentStyle;

  @override
  Future<void> setStyle(CaptionStyle style) async => currentStyle = style;

  @override
  Future<void> requestOverlayPermission() async {}

  @override
  Future<bool> requestRuntimePermissions() async => true;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required SystemCaptionStatus status,
  Map<String, String>? storage,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: SystemCaptionsScreen(
        isActive: false,
        platform: _FakePlatform(status),
        storageService: StorageService(store: _MemoryStore(storage)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _ready = SystemCaptionStatus(
  supported: true,
  running: false,
  overlayGranted: true,
  micGranted: true,
  notificationsGranted: true,
  sdkInt: 35,
);

void main() {
  testWidgets('explains that Android 10 is required on older phones', (
    tester,
  ) async {
    await _pump(tester, status: SystemCaptionStatus.unsupported);

    expect(find.textContaining('Android 10 or newer'), findsOneWidget);
    expect(find.text('Start live captions'), findsNothing);
  });

  testWidgets('offers Start when everything is allowed', (tester) async {
    await _pump(tester, status: _ready);

    expect(find.text('Start live captions'), findsOneWidget);
    expect(find.textContaining('Free trial'), findsOneWidget);
  });

  testWidgets('asks to finish setup when a permission is missing', (
    tester,
  ) async {
    await _pump(
      tester,
      status: const SystemCaptionStatus(
        supported: true,
        running: false,
        overlayGranted: false,
        micGranted: true,
        notificationsGranted: true,
      ),
    );

    expect(find.text('Set up live captions'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
  });

  testWidgets('shows Stop while captions are running', (tester) async {
    await _pump(
      tester,
      status: const SystemCaptionStatus(
        supported: true,
        running: true,
        overlayGranted: true,
        micGranted: true,
        notificationsGranted: true,
      ),
    );

    expect(find.text('Stop live captions'), findsOneWidget);
    expect(find.text('Live captions are on'), findsOneWidget);
  });

  testWidgets('shows pricing and activation once the trial is used', (
    tester,
  ) async {
    await _pump(
      tester,
      status: _ready,
      storage: {StorageService.trialTimeKey: '${AppConfig.maxFreeTrialMs}'},
    );

    expect(find.text('Unlock live captions'), findsOneWidget);
    expect(find.text(AppConfig.monthlyPlanLabel), findsOneWidget);
    expect(find.text(AppConfig.lifetimePlanLabel), findsOneWidget);
  });

  testWidgets('an activated license shows unlimited captions', (tester) async {
    await _pump(
      tester,
      status: _ready,
      storage: {
        StorageService.licenseStateKey: '{"key":"CLP-1","subscribed":true}',
        StorageService.trialTimeKey: '${AppConfig.maxFreeTrialMs}',
      },
    );

    expect(find.text('Unlimited captions activated'), findsOneWidget);
    expect(find.text('Start live captions'), findsOneWidget);
  });
}
