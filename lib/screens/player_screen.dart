import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../config/app_config.dart';
import '../services/activation_link_service.dart';
import '../services/api_service.dart';
import '../services/media_picker_service.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../services/video_controller_factory.dart';
import '../theme/app_theme.dart';
import '../utils/activation_link.dart';
import '../utils/media_format.dart';
import '../widgets/audio_player_card.dart';
import '../widgets/caption_audio_guide.dart';
import '../widgets/caption_overlay.dart';
import '../widgets/empty_player_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_error_banner.dart';
import '../widgets/startup_error_view.dart';
import 'paywall_overlay.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    this.storageService,
    this.apiService,
    this.speechService,
    this.activationLinkSource,
    this.mediaPicker,
    this.videoControllerFactory,
  });

  final StorageService? storageService;
  final ApiService? apiService;
  final SpeechService? speechService;
  final ActivationLinkSource? activationLinkSource;
  final MediaPickerService? mediaPicker;
  final VideoControllerFactory? videoControllerFactory;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final StorageService _storageService;
  late final ApiService _apiService;
  late final SpeechService _speechService;
  late final ActivationLinkSource _activationLinkSource;
  late final MediaPickerService _mediaPicker;
  late final VideoControllerFactory _videoControllerFactory;
  late final bool _ownsApiService;
  late final bool _ownsSpeechService;
  late final TextEditingController _licenseKeyController;

  StreamSubscription<String>? _activationLinkSubscription;
  Timer? _trialTimer;
  VideoPlayerController? _videoController;

  bool _isInitializing = true;
  String? _startupError;
  String? _startupErrorDetails;

  bool _isSubscribed = false;
  bool _showPaywall = false;
  bool _isActivating = false;
  String _paywallStatus = '';

  double _watchTimeMs = 0;
  int _lastSavedTrialMs = 0;
  bool _isSavingTrial = false;

  bool _isLoadingMedia = false;
  bool _isAudioTrack = false;
  String? _mediaTitle;
  String? _playerError;
  bool _showCaptionRecoveryActions = false;
  String? _lastVideoError;
  bool _wasCompleted = false;

  bool _captionsEnabled = false;
  bool _captionsReady = false;
  bool _isTranscribing = false;
  bool _isPreparingCaptions = false;
  bool _showCaptionGuide = true;
  String _captionStatus = '';
  String _captionsText = '';

  double? _dragPositionMs;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageService ?? StorageService();
    _apiService = widget.apiService ?? ApiService();
    _ownsApiService = widget.apiService == null;
    _speechService = widget.speechService ?? SpeechService();
    _ownsSpeechService = widget.speechService == null;
    _activationLinkSource =
        widget.activationLinkSource ?? AppLinksActivationLinkSource();
    _mediaPicker = widget.mediaPicker ?? FilePickerMediaPickerService();
    _videoControllerFactory =
        widget.videoControllerFactory ?? createVideoController;
    _licenseKeyController = TextEditingController();

    unawaited(_initializeApp());
    _startTrialTracking();
    _initializeDeepLinking();
  }

  @override
  void dispose() {
    _trialTimer?.cancel();
    unawaited(_activationLinkSubscription?.cancel());
    _videoController?.removeListener(_handleVideoChanged);
    unawaited(_videoController?.dispose());
    unawaited(_disposeSpeechService());
    if (_ownsApiService) {
      _apiService.close();
    }
    _licenseKeyController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      final savedTime = await _storageService.loadSavedTime();
      final cachedLicense = await _storageService.loadLicense();
      if (!mounted) {
        return;
      }
      _lastSavedTrialMs = savedTime;
      setState(() {
        _isInitializing = false;
        _startupError = null;
        _startupErrorDetails = null;
        _watchTimeMs = savedTime.toDouble();
        if (cachedLicense != null && cachedLicense.isValid) {
          _isSubscribed = true;
          final key = cachedLicense.key;
          if (key != null && key.isNotEmpty) {
            _licenseKeyController.text = key;
          }
        } else if (savedTime >= AppConfig.maxFreeTrialMs) {
          _showPaywall = true;
        }
      });

      final cachedKey = cachedLicense?.key;
      if (cachedLicense != null &&
          cachedLicense.isValid &&
          cachedKey != null &&
          cachedKey.isNotEmpty) {
        unawaited(_verifyLicense(cachedKey, silent: true));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _startupError = kIsWeb
            ? 'Could not load your saved session. The browser may be '
                  'blocking site storage for this app.'
            : 'Could not load your saved session. Check that the app has '
                  'free storage space, then try again.';
        _startupErrorDetails = kDebugMode ? error.toString() : null;
      });
    }
  }

  void _retryStartup() {
    setState(() {
      _isInitializing = true;
      _startupError = null;
      _startupErrorDetails = null;
    });
    unawaited(_initializeApp());
  }

  void _initializeDeepLinking() {
    try {
      _activationLinkSubscription = _activationLinkSource.links.listen(
        _handleActivationLink,
        onError: (Object error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _showPaywall = true;
            _paywallStatus =
                'Could not read that activation link. Open the link again.';
          });
          unawaited(_pausePlaybackForPaywall());
          if (kDebugMode) {
            debugPrint('Activation link stream error: $error');
          }
        },
      );
      if (!kIsWeb) {
        unawaited(_handleInitialActivationLink());
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Activation link initialization failed: $error');
      }
    }
  }

  Future<void> _handleInitialActivationLink() async {
    try {
      final link = await _activationLinkSource.getInitialLink();
      if (link != null && link.isNotEmpty) {
        _handleActivationLink(link);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Initial activation link failed: $error');
      }
    }
  }

  void _handleActivationLink(String rawLink) {
    final parsed = parseActivationLink(rawLink);
    switch (parsed) {
      case ActivationLinkKey(:final key):
        setState(() {
          _licenseKeyController.text = key;
          _showPaywall = true;
          _paywallStatus = 'Checking activation key…';
        });
        unawaited(_pausePlaybackForPaywall());
        unawaited(_verifyLicense(key));
      case ActivationLinkMissingKey():
        setState(() {
          _showPaywall = true;
          _paywallStatus =
              'That activation link is missing its license key. Paste the '
              'key from your purchase email instead.';
        });
        unawaited(_pausePlaybackForPaywall());
      case ActivationLinkIgnored():
        break;
    }
  }

  Future<void> _verifyLicense(String key, {bool silent = false}) async {
    final normalized = key.trim();
    if (normalized.isEmpty) {
      if (!silent) {
        setState(() => _paywallStatus = 'Paste your license key first.');
      }
      return;
    }
    if (!silent) {
      setState(() => _isActivating = true);
    }

    try {
      final isValid = await _apiService.verifyLicenseKey(normalized);
      if (!mounted) {
        return;
      }
      if (isValid) {
        if (silent) {
          setState(() => _isSubscribed = true);
          return;
        }
        String? storageWarning;
        try {
          await _storageService.saveLicense(normalized);
        } catch (error) {
          storageWarning = kIsWeb
              ? 'Activated for this session, but the license could not be '
                    'saved. Allow site storage before your next launch.'
              : 'Activated for this session, but the license could not be '
                    'saved. Free some storage before your next launch.';
          if (kDebugMode) {
            debugPrint('License persistence failed: $error');
          }
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _isSubscribed = true;
          _showPaywall = false;
          _paywallStatus = '';
          _licenseKeyController.clear();
          _playerError = storageWarning;
          _showCaptionRecoveryActions = false;
        });
      } else if (silent) {
        try {
          await _storageService.clearLicense();
        } catch (error) {
          if (kDebugMode) {
            debugPrint('License cache cleanup failed: $error');
          }
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _isSubscribed = false;
          _showPaywall = _watchTimeMs >= AppConfig.maxFreeTrialMs;
        });
      } else {
        _licenseKeyController.clear();
        setState(() {
          _paywallStatus =
              'That activation key is not valid. Check the key and try again.';
        });
      }
    } on LicenseVerificationException catch (error) {
      if (mounted && !silent) {
        setState(() => _paywallStatus = error.message);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('License verification failed: $error');
      }
      if (mounted && !silent) {
        setState(() {
          _paywallStatus =
              'Could not verify the license right now. Check your connection '
              'and try again.';
        });
      }
    } finally {
      if (!silent && mounted) {
        setState(() => _isActivating = false);
      }
    }
  }

  Future<void> _openPricingPage() async {
    final uri = Uri.tryParse(AppConfig.pricingUrl);
    if (uri == null) {
      setState(() {
        _paywallStatus =
            'The pricing page address is not valid. Contact support at '
            '${AppConfig.supportEmail}.';
      });
      return;
    }
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('Pricing page did not open.');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Pricing page launch failed: $error');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _paywallStatus =
            'Could not open the pricing page. Check your connection or '
            'browser, then try again.';
      });
    }
  }

  Future<void> _pausePlaybackForPaywall() async {
    try {
      await _videoController?.pause();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Could not pause for paywall: $error');
      }
    }
    await _stopCaptioning();
    if (mounted) {
      setState(() => _isTranscribing = false);
    }
  }

  Future<void> _lockForPaywall() async {
    await _pausePlaybackForPaywall();
    if (!mounted) {
      return;
    }
    setState(() {
      _showPaywall = true;
      _paywallStatus = '';
      _captionsText = '';
    });
  }

  void _startTrialTracking() {
    _trialTimer?.cancel();
    _trialTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => unawaited(_onTrialTick(timer)),
    );
  }

  Future<void> _onTrialTick(Timer timer) async {
    if (!mounted) {
      timer.cancel();
      return;
    }
    final controller = _videoController;
    if (_isSubscribed ||
        _showPaywall ||
        _isSavingTrial ||
        controller == null ||
        !controller.value.isPlaying) {
      return;
    }
    if (_watchTimeMs >= AppConfig.maxFreeTrialMs) {
      await _lockForPaywall();
      return;
    }

    setState(() {
      _watchTimeMs = (_watchTimeMs + Duration.millisecondsPerSecond).clamp(
        0,
        AppConfig.maxFreeTrialMs.toDouble(),
      );
    });

    final shouldPersist =
        _watchTimeMs - _lastSavedTrialMs >=
            AppConfig.trialSaveInterval.inMilliseconds ||
        _watchTimeMs >= AppConfig.maxFreeTrialMs;
    if (!shouldPersist) {
      return;
    }

    _isSavingTrial = true;
    try {
      await _storageService.saveCurrentTime(_watchTimeMs.round());
      _lastSavedTrialMs = _watchTimeMs.round();
    } catch (error) {
      timer.cancel();
      if (kDebugMode) {
        debugPrint('Trial progress persistence failed: $error');
      }
      await _videoController?.pause();
      await _stopCaptioning();
      if (!mounted) {
        return;
      }
      setState(() {
        _showPaywall = true;
        _playerError =
            'Your trial progress could not be saved, so playback was paused. '
            'Free some storage and restart the app to continue.';
        _showCaptionRecoveryActions = false;
        _isTranscribing = false;
      });
      return;
    } finally {
      _isSavingTrial = false;
    }

    if (_watchTimeMs >= AppConfig.maxFreeTrialMs) {
      await _lockForPaywall();
    }
  }

  String get _trialLabel {
    if (_startupError != null) {
      return 'Storage unavailable';
    }
    if (_isSubscribed) {
      return 'Activated · unlimited captions';
    }
    if (_isInitializing) {
      return 'Starting up…';
    }
    final remainingMs = AppConfig.maxFreeTrialMs - _watchTimeMs;
    final minutes = (remainingMs / Duration.millisecondsPerMinute).ceil();
    final bounded = minutes.clamp(0, AppConfig.freeTrialDuration.inMinutes);
    return 'Free trial · $bounded min left';
  }

  /// Web speech recognition only works in a secure context.
  bool get _canUseMicrophone =>
      !kIsWeb ||
      Uri.base.scheme == 'https' ||
      Uri.base.host == 'localhost' ||
      Uri.base.host == '127.0.0.1';

  Future<void> _enableCaptions() async {
    if (_isPreparingCaptions || _showPaywall) {
      return;
    }
    if (!_canUseMicrophone) {
      _setCaptionError(
        'Live captions need HTTPS or localhost. Open this app over a secure '
        'connection, then retry captions.',
        canRetry: false,
      );
      return;
    }
    if (!_speechService.isSupported) {
      _setCaptionError(
        const UnsupportedSpeechPlatformException().userMessage,
        canRetry: false,
      );
      return;
    }

    setState(() {
      _isPreparingCaptions = true;
      _showCaptionRecoveryActions = false;
      _playerError = null;
    });

    try {
      final available = await _speechService.initialize(
        onError: _handleCaptionError,
        onStatus: _handleSpeechStatus,
      );
      if (!mounted) {
        return;
      }
      if (!available) {
        if (_playerError == null) {
          _setCaptionError(const SpeechUnavailableException().userMessage);
        }
        return;
      }

      setState(() {
        _captionsReady = true;
        _captionsEnabled = true;
        _showCaptionGuide = true;
        _playerError = null;
        _showCaptionRecoveryActions = false;
      });

      final controller = _videoController;
      if (controller != null && controller.value.isInitialized) {
        if (controller.value.isPlaying) {
          await _startCaptioning();
        } else {
          setState(() => _captionStatus = 'Captions start with playback');
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Enabling live captions failed: $error');
      }
      _setCaptionError(
        error is SpeechException
            ? error.userMessage
            : SpeechRecognitionException(cause: error).userMessage,
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparingCaptions = false);
      }
    }
  }

  Future<void> _startCaptioning() async {
    final controller = _videoController;
    if (!_captionsReady ||
        !_captionsEnabled ||
        _showPaywall ||
        controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isPlaying ||
        _speechService.isActive) {
      return;
    }

    setState(() {
      _isTranscribing = true;
      _captionStatus = SpeechService.statusMessage(SpeechStatus.preparing);
    });
    await _speechService.startListening(
      onResult: _handleCaptionText,
      onError: _handleCaptionError,
      onStatus: _handleSpeechStatus,
    );
  }

  /// Stops the microphone while preserving the last caption line. Called when
  /// playback pauses so captions resume with the video.
  Future<void> _pauseCaptioning() async {
    if (!_captionsEnabled) {
      return;
    }
    try {
      await _speechService.pause();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Pausing live captions failed: $error');
      }
    }
    if (mounted) {
      setState(() => _isTranscribing = false);
    }
  }

  Future<void> _stopCaptioning() async {
    try {
      await _speechService.stop();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Stopping live captions failed: $error');
      }
    }
    if (mounted) {
      setState(() {
        _isTranscribing = false;
        _captionStatus = '';
      });
    }
  }

  Future<void> _disposeSpeechService() async {
    try {
      if (_ownsSpeechService) {
        await _speechService.dispose();
      } else {
        await _speechService.stop();
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Disposing the speech service failed: $error');
      }
    }
  }

  void _handleCaptionText(String text) {
    if (!mounted || !_captionsEnabled || _showPaywall) {
      return;
    }
    setState(() => _captionsText = text.trim());
  }

  void _handleSpeechStatus(SpeechStatus status) {
    if (!mounted) {
      return;
    }
    setState(() {
      _captionStatus = SpeechService.statusMessage(status);
      if (status == SpeechStatus.listening) {
        _isTranscribing = true;
      } else if (status == SpeechStatus.paused) {
        _isTranscribing = false;
      }
    });
  }

  void _handleCaptionError(String message) {
    if (kDebugMode) {
      debugPrint('Live caption error: $message');
    }
    _setCaptionError(message);
  }

  void _setCaptionError(String message, {bool canRetry = true}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _captionsReady = false;
      _captionsEnabled = false;
      _isTranscribing = false;
      _captionStatus = '';
      _showCaptionGuide = false;
      _showCaptionRecoveryActions = canRetry;
      _playerError = message;
    });
    unawaited(_speechService.stop());
  }

  void _dismissCaptionGuide() {
    setState(() => _showCaptionGuide = false);
  }

  void _dismissPlayerError() {
    setState(() {
      _playerError = null;
      _showCaptionRecoveryActions = false;
    });
  }

  Future<void> _pickMedia() async {
    if (_isLoadingMedia || _showPaywall) {
      return;
    }
    setState(() {
      _isLoadingMedia = true;
      _playerError = null;
      _showCaptionRecoveryActions = false;
      _lastVideoError = null;
    });

    VideoPlayerController? newController;
    try {
      final file = await _mediaPicker.pickMedia();
      if (file == null || !mounted) {
        return;
      }
      await _stopCaptioning();
      newController = await _videoControllerFactory(file);
      await newController.initialize();
      if (!mounted) {
        await newController.dispose();
        return;
      }
      newController.addListener(_handleVideoChanged);
      await newController.play();

      final previousController = _videoController;
      setState(() {
        _videoController = newController;
        _isAudioTrack = isAudioMediaExtension(file.extension);
        _mediaTitle = file.name;
        _captionsText = '';
        _captionStatus = '';
        _wasCompleted = false;
        _lastVideoError = null;
      });
      previousController?.removeListener(_handleVideoChanged);
      await previousController?.dispose();

      if (_captionsEnabled && _captionsReady) {
        await _startCaptioning();
      } else {
        await _enableCaptions();
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Opening media failed: $error');
      }
      await newController?.dispose();
      if (!mounted) {
        return;
      }
      setState(() => _playerError = _mediaErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _isLoadingMedia = false);
      }
    }
  }

  String _mediaErrorMessage(Object error) {
    const fallback =
        'Could not open that media file. Try a standard MP4 or WebM video, '
        'or an MP3, M4A, WAV, or OGG audio file.';
    if (error is UnsupportedError) {
      return error.message ?? fallback;
    }
    if (error is StateError) {
      return error.message;
    }
    return fallback;
  }

  void _handleVideoChanged() {
    if (!mounted) {
      return;
    }
    final controller = _videoController;
    if (controller == null) {
      return;
    }
    final value = controller.value;
    final error = value.errorDescription;
    if (error != null && error.isNotEmpty) {
      if (error != _lastVideoError) {
        _lastVideoError = error;
        if (kDebugMode) {
          debugPrint('Video playback error: $error');
        }
        unawaited(_stopCaptioning());
        setState(() {
          _playerError =
              'Playback stopped unexpectedly. Reopen the file or choose a '
              'different format.';
          _captionsText = '';
          _isTranscribing = false;
          _showCaptionRecoveryActions = false;
        });
      }
      return;
    }
    _lastVideoError = null;

    if (value.isCompleted && !_wasCompleted) {
      _wasCompleted = true;
      unawaited(_pauseCaptioning());
      setState(() => _isTranscribing = false);
      return;
    }
    if (!value.isCompleted) {
      _wasCompleted = false;
    }
    if (_dragPositionMs == null) {
      setState(() {});
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _videoController;
    if (controller == null || _showPaywall) {
      return;
    }
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
        await _pauseCaptioning();
      } else {
        if (controller.value.isCompleted) {
          await controller.seekTo(Duration.zero);
          _wasCompleted = false;
        }
        await controller.play();
        if (_captionsEnabled && _captionsReady) {
          await _startCaptioning();
        } else {
          await _enableCaptions();
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Playback control failed: $error');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _playerError =
            'Playback could not be controlled. Try reopening the '
            'media file.';
      });
    }
  }

  void _handleSeekChanged(double value) {
    setState(() => _dragPositionMs = value);
  }

  Future<void> _finishSeek(double value) async {
    await _seekTo(Duration(milliseconds: value.round()));
    if (mounted) {
      setState(() => _dragPositionMs = null);
    }
  }

  Future<void> _seekBy(Duration offset) async {
    final position = _videoController?.value.position ?? Duration.zero;
    await _seekTo(position + offset);
  }

  Future<void> _seekTo(Duration target) async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final duration = controller.value.duration;
    var clamped = target;
    if (clamped < Duration.zero) {
      clamped = Duration.zero;
    } else if (duration > Duration.zero && clamped > duration) {
      clamped = duration;
    }
    try {
      await controller.seekTo(clamped);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Seek failed: $error');
      }
    }
  }

  Future<void> _setVolume(double volume) async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.setVolume(volume.clamp(0.0, 1.0));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Volume control failed: $error');
      }
      if (mounted) {
        setState(() => _playerError = 'Volume could not be changed.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = _videoController?.value;
    final hasMedia = value?.isInitialized ?? false;
    final duration = value?.duration ?? Duration.zero;
    final displayMs =
        _dragPositionMs ?? value?.position.inMilliseconds.toDouble() ?? 0;
    final positionMs = displayMs < 0 ? 0.0 : displayMs;

    return Scaffold(
      appBar: _buildAppBar(theme),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  children: [
                    Expanded(child: _buildMediaArea()),
                    if (_captionsEnabled &&
                        _showCaptionGuide &&
                        !_showPaywall &&
                        !_isInitializing &&
                        _startupError == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: CaptionAudioGuide(
                              isWeb: kIsWeb,
                              onDismiss: _dismissCaptionGuide,
                            ),
                          ),
                        ),
                      ),
                    if (!_isInitializing && _startupError == null)
                      PlayerControls(
                        position: Duration(milliseconds: positionMs.round()),
                        duration: duration,
                        volume: value?.volume ?? 1,
                        hasMedia: hasMedia,
                        isPlaying: value?.isPlaying ?? false,
                        isLoading: _isLoadingMedia,
                        enabled: !_showPaywall,
                        onPickMedia: () => unawaited(_pickMedia()),
                        onBack10: () =>
                            unawaited(_seekBy(const Duration(seconds: -10))),
                        onForward10: () =>
                            unawaited(_seekBy(const Duration(seconds: 10))),
                        onTogglePlay: () => unawaited(_togglePlayback()),
                        onVolumeChanged: (volume) =>
                            unawaited(_setVolume(volume)),
                        onSeekChanged: _handleSeekChanged,
                        onSeekEnd: (seekValue) =>
                            unawaited(_finishSeek(seekValue)),
                      ),
                  ],
                ),
              ),
            ),
            if (_showPaywall)
              Positioned.fill(
                child: PaywallOverlay(
                  controller: _licenseKeyController,
                  statusMessage: _paywallStatus,
                  isLoading: _isActivating,
                  onActivate: () =>
                      unawaited(_verifyLicense(_licenseKeyController.text)),
                  onOpenPricing: () => unawaited(_openPricingPage()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    final trialColor = _startupError != null
        ? theme.colorScheme.error
        : _isSubscribed
        ? AppTheme.accent
        : Colors.white60;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppConfig.appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _trialLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: trialColor),
          ),
        ],
      ),
      actions: [
        if (_isTranscribing || _isPreparingCaptions)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Semantics(
                liveRegion: true,
                label: _captionStatus.isEmpty
                    ? (_isTranscribing
                          ? 'Live captions are active'
                          : 'Preparing live captions')
                    : _captionStatus,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isTranscribing ? 'LIVE' : 'PREPARING',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMediaArea() {
    final controller = _videoController;
    final value = controller?.value;
    final isReady = controller != null && value != null && value.isInitialized;
    final Widget content;

    if (_isInitializing) {
      content = const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading player'),
      );
    } else if (_startupError != null) {
      content = StartupErrorView(
        message: _startupError!,
        details: _startupErrorDetails,
        onRetry: _retryStartup,
      );
    } else if (controller != null && value != null && value.isInitialized) {
      if (_isAudioTrack) {
        final title = _mediaTitle;
        content = SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: AudioPlayerCard(
              title: title == null || title.isEmpty ? 'Audio track' : title,
              isPlaying: value.isPlaying,
              duration: value.duration,
            ),
          ),
        );
      } else {
        final aspectRatio = value.aspectRatio;
        final safeAspectRatio = aspectRatio.isFinite && aspectRatio > 0
            ? aspectRatio
            : 16 / 9;
        content = Center(
          child: AspectRatio(
            aspectRatio: safeAspectRatio,
            child: VideoPlayer(controller),
          ),
        );
      }
    } else {
      content = EmptyPlayerView(
        onChooseMedia: () => unawaited(_pickMedia()),
        isLoading: _isLoadingMedia,
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (_isLoadingMedia && isReady)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Opening media',
                  ),
                ),
              ),
            ),
          if (_playerError != null && _startupError == null && !_showPaywall)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: PlayerErrorBanner(
                    message: _playerError!,
                    isBusy: _isPreparingCaptions,
                    onRetry: _showCaptionRecoveryActions
                        ? () => unawaited(_enableCaptions())
                        : null,
                    onDismiss: _dismissPlayerError,
                  ),
                ),
              ),
            ),
          if (isReady &&
              !_showPaywall &&
              !_isLoadingMedia &&
              _captionsText.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Center(child: CaptionOverlay(text: _captionsText)),
            ),
        ],
      ),
    );
  }
}
