import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// True where the system-wide caption feature can exist at all: the Android
/// app. (iOS does not let apps capture other apps' audio, and the web cannot
/// draw over other apps.)
bool get systemCaptionsAvailableOnThisPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Snapshot of what Android currently allows.
@immutable
class SystemCaptionStatus {
  const SystemCaptionStatus({
    required this.supported,
    required this.running,
    required this.overlayGranted,
    required this.micGranted,
    required this.notificationsGranted,
    this.sdkInt = 0,
  });

  factory SystemCaptionStatus.fromMap(Map<Object?, Object?> map) {
    bool flag(String key) => map[key] == true;
    final sdk = map['sdkInt'];
    return SystemCaptionStatus(
      supported: flag('supported'),
      running: flag('running'),
      overlayGranted: flag('overlayGranted'),
      micGranted: flag('micGranted'),
      notificationsGranted: flag('notificationsGranted'),
      sdkInt: sdk is int ? sdk : 0,
    );
  }

  static const unsupported = SystemCaptionStatus(
    supported: false,
    running: false,
    overlayGranted: false,
    micGranted: false,
    notificationsGranted: false,
  );

  /// Android 10 (API 29) is the first release that can capture playback audio.
  final bool supported;
  final bool running;

  /// "Display over other apps".
  final bool overlayGranted;

  /// RECORD_AUDIO. Android requires it for playback capture; the microphone is
  /// never opened.
  final bool micGranted;
  final bool notificationsGranted;
  final int sdkInt;

  /// Everything needed before the system consent dialog can be shown.
  /// Notifications are optional: the foreground service still runs without them.
  bool get readyToStart => supported && overlayGranted && micGranted;
}

/// Look of the caption box. Values are validated again on the native side.
@immutable
class CaptionStyle {
  const CaptionStyle({
    this.textSizeSp = 16,
    this.backgroundOpacity = 90,
    this.bottomOffsetDp = 96,
  });

  factory CaptionStyle.fromMap(Map<Object?, Object?> map) {
    final size = map['textSizeSp'];
    final opacity = map['backgroundOpacity'];
    final offset = map['bottomOffsetDp'];
    return CaptionStyle(
      textSizeSp: size is num ? size.toDouble().clamp(12.0, 32.0) : 16.0,
      backgroundOpacity: opacity is num ? opacity.toInt().clamp(30, 100) : 90,
      bottomOffsetDp: offset is num ? offset.toInt().clamp(0, 2000) : 96,
    );
  }

  final double textSizeSp;

  /// 30–100 (percent).
  final int backgroundOpacity;
  final int bottomOffsetDp;

  CaptionStyle copyWith({
    double? textSizeSp,
    int? backgroundOpacity,
    int? bottomOffsetDp,
  }) {
    return CaptionStyle(
      textSizeSp: textSizeSp ?? this.textSizeSp,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      bottomOffsetDp: bottomOffsetDp ?? this.bottomOffsetDp,
    );
  }

  Map<String, Object> toMap() => <String, Object>{
    'textSizeSp': textSizeSp,
    'backgroundOpacity': backgroundOpacity,
    'bottomOffsetDp': bottomOffsetDp,
  };

  @override
  bool operator ==(Object other) =>
      other is CaptionStyle &&
      other.textSizeSp == textSizeSp &&
      other.backgroundOpacity == backgroundOpacity &&
      other.bottomOffsetDp == bottomOffsetDp;

  @override
  int get hashCode =>
      Object.hash(textSizeSp, backgroundOpacity, bottomOffsetDp);
}

/// UI-facing control of the Android caption service. Mockable in tests.
abstract interface class SystemCaptionPlatform {
  Future<SystemCaptionStatus> status();

  /// Opens Android's "Display over other apps" screen for this app.
  Future<void> requestOverlayPermission();

  /// Shows the audio (and, on Android 13+, notification) permission prompts.
  /// Returns whether the audio permission is granted.
  Future<bool> requestRuntimePermissions();

  Future<void> openAppSettings();

  /// Shows Android's capture consent dialog and starts captions if accepted.
  Future<void> start();

  Future<void> stop();

  Future<CaptionStyle> style();

  Future<void> setStyle(CaptionStyle style);
}

class MethodChannelSystemCaptionPlatform implements SystemCaptionPlatform {
  MethodChannelSystemCaptionPlatform({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('live_caption_player/system_caption');

  final MethodChannel _channel;

  @override
  Future<SystemCaptionStatus> status() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('getStatus');
    return raw == null
        ? SystemCaptionStatus.unsupported
        : SystemCaptionStatus.fromMap(raw);
  }

  @override
  Future<void> requestOverlayPermission() =>
      _channel.invokeMethod<void>('requestOverlayPermission');

  @override
  Future<bool> requestRuntimePermissions() async =>
      await _channel.invokeMethod<bool>('requestRuntimePermissions') ?? false;

  @override
  Future<void> openAppSettings() =>
      _channel.invokeMethod<void>('openAppSettings');

  @override
  Future<void> start() => _channel.invokeMethod<void>('start');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  Future<CaptionStyle> style() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('getStyle');
    return raw == null ? const CaptionStyle() : CaptionStyle.fromMap(raw);
  }

  @override
  Future<void> setStyle(CaptionStyle style) =>
      _channel.invokeMethod<void>('setStyle', style.toMap());
}
