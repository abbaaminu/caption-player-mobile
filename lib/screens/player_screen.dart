import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:app_links/app_links.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/license_state.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../services/speech_service.dart';
import '../services/video_controller_factory.dart';
import 'paywall_overlay.dart';
import '../widgets/custom_slider.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final StorageService _storageService = StorageService();
  final ApiService _apiService = ApiService();
  final SpeechService _speechService = SpeechService();

  VideoPlayerController? _videoController;
  final TextEditingController _keyController = TextEditingController();

  int _watchTimeMs = 0;
  final int _maxFreeTimeMs = AppConfig.freeTrialDuration.inMilliseconds;
  bool _isSubscribed = false;

  String _captionsText = "Open a video file to begin...";
  String _paywallStatus = "";
  bool _showPaywall = false;
  bool _isActivating = false;
  bool _isUpdatingSlider = false;
  bool _isLoadingVideo = false;
  bool _speechAvailable = false;
  bool _isRequestingSpeech = false;
  bool _microphonePermissionDenied = false;
  bool _showSpeechRecoveryActions = false;
  bool _isSavingTrial = false;
  String? _playerError;

  Timer? _trialTrackerTimer;
  StreamSubscription? _subLink;

  @override
  void initState() {
    super.initState();
    _initAppAndCheckLicense();
    _initDeepLinking();
    _initSpeechRecognizer();
  }

  Future<void> _initAppAndCheckLicense() async {
    late final LicenseState? cachedState;
    try {
      _watchTimeMs = await _storageService.loadSavedTime();
      cachedState = await _storageService.loadLicense();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _watchTimeMs = _maxFreeTimeMs;
        _showPaywall = true;
        _showSpeechRecoveryActions = false;
        _playerError = kIsWeb
            ? 'Browser storage is unavailable. Allow site data for this '
                  'website in your browser settings, then reload.'
            : 'Could not read saved trial or license data: $error';
      });
      return;
    }

    if (!mounted) return;

    if (cachedState != null && cachedState.isSubscribed) {
      setState(() {
        _isSubscribed = true;
      });
      // Silently check in background
      _verifyLicense(cachedState.key ?? "", silent: true);
    } else if (!_isSubscribed && _watchTimeMs >= _maxFreeTimeMs) {
      setState(() => _showPaywall = true);
    }
  }

  Future<void> _initSpeechRecognizer() async {
    if (_isRequestingSpeech) return;
    setState(() {
      _isRequestingSpeech = true;
      _playerError = null;
      _microphonePermissionDenied = false;
      _showSpeechRecoveryActions = false;
    });

    try {
      if (kIsWeb && !_isSecureWebOrigin(Uri.base)) {
        _setSpeechError(
          'Microphone access requires a secure website. Open this app using '
          'HTTPS or localhost, then allow microphone access in your browser.',
        );
        return;
      }

      if (kIsWeb && !await _speechService.isSupported()) {
        _setSpeechError(
          'This browser does not support live speech recognition. Try a '
          'current version of Chrome or Edge.',
        );
        return;
      }

      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _setSpeechError(
          kIsWeb
              ? 'Microphone access was blocked. Allow it in this site’s browser '
                    'permissions, then retry. Use HTTPS or localhost in Chrome or Edge.'
              : 'Microphone access was denied. Allow it in your device app '
                    'settings, then retry.',
          permissionDenied: true,
        );
        return;
      }

      final available = await _speechService.initSpeech(
        onError: (message) {
          _setSpeechError(
            SpeechService.userFriendlyError(message, isWeb: kIsWeb),
          );
        },
      );
      if (!mounted) return;

      setState(() {
        _speechAvailable = available;
        _showSpeechRecoveryActions = !available;
        if (!available) {
          _playerError = kIsWeb
              ? 'Live speech recognition is unavailable. Use a supported '
                    'browser such as current Chrome or Edge, allow microphone '
                    'access, and open the app using HTTPS or localhost.'
              : 'Live speech recognition is unavailable on this device.';
        } else {
          _playerError = null;
        }
      });
    } catch (error) {
      _setSpeechError(
        SpeechService.userFriendlyError(error.toString(), isWeb: kIsWeb),
      );
    } finally {
      if (mounted) setState(() => _isRequestingSpeech = false);
    }
  }

  bool _isSecureWebOrigin(Uri uri) {
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;

    final host = uri.host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
    return host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == '127.0.0.1' ||
        host == '::1';
  }

  void _setSpeechError(String message, {bool permissionDenied = false}) {
    if (!mounted) return;
    setState(() {
      _speechAvailable = false;
      _microphonePermissionDenied = permissionDenied;
      _showSpeechRecoveryActions = true;
      _playerError = message;
    });
  }

  Future<void> _openMicrophoneSettings() async {
    try {
      if (!await openAppSettings() && mounted) {
        _setSpeechError(
          'Could not open app settings. Enable microphone access in your '
          'device settings, then retry.',
          permissionDenied: true,
        );
      }
    } catch (error) {
      _setSpeechError(
        'Could not open app settings: $error. Enable microphone access in '
        'your device settings, then retry.',
        permissionDenied: true,
      );
    }
  }

  // --- Deep Link Integration (captionplayer://activate?key=XXX) ---
  final _appLinks = AppLinks();

  void _initDeepLinking() {
    _subLink = _appLinks.stringLinkStream.listen(
      _handleDeepLink,
      onError: (Object error) {
        if (mounted) {
          setState(
            () => _paywallStatus = 'Could not read activation link: $error',
          );
        }
      },
    );
    if (!kIsWeb) unawaited(_handleInitialDeepLink());
  }

  Future<void> _handleInitialDeepLink() async {
    try {
      final link = await _appLinks.getInitialLinkString();
      if (link != null) _handleDeepLink(link);
    } catch (error) {
      if (mounted) {
        setState(
          () => _paywallStatus = 'Could not read activation link: $error',
        );
      }
    }
  }

  void _handleDeepLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'captionplayer') return;

    final key = uri.queryParameters['key'];
    if (key != null) {
      _keyController.text = key;
      _verifyLicense(key);
    } else if (mounted) {
      setState(
        () => _paywallStatus = 'Activation link is missing its license key.',
      );
    }
  }

  Future<void> _openPricingPage() async {
    final uri = Uri.parse(AppConfig.pricingUrl);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No browser could open the pricing page.');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _paywallStatus = 'Could not open the pricing page: $error',
        );
      }
    }
  }

  Future<void> _verifyLicense(String key, {bool silent = false}) async {
    if (key.trim().isEmpty) {
      if (!silent && mounted) {
        setState(() => _paywallStatus = "Please paste your license key first.");
      }
      return;
    }

    if (!silent && mounted) setState(() => _isActivating = true);

    try {
      final isValid = await _apiService.verifyLicenseKey(key);
      if (isValid) {
        String? storageMessage;
        try {
          await _storageService.saveLicense(key);
        } catch (error) {
          storageMessage = kIsWeb
              ? 'License verified for this session, but browser storage could '
                    'not save it. Allow site data to keep the activation after reload.'
              : 'License verified, but could not save it on this device: $error';
        }
        if (!mounted) return;
        setState(() {
          _isSubscribed = true;
          _showPaywall = false;
          _paywallStatus = storageMessage ?? '';
          _captionsText = "License verified. Enjoy unlimited captions!";
        });
      } else {
        if (silent) {
          await _storageService.clearLicense();
          if (!mounted) return;
          setState(() {
            _isSubscribed = false;
            if (_watchTimeMs >= _maxFreeTimeMs) _showPaywall = true;
          });
        } else if (mounted) {
          _keyController.clear();
          setState(() => _paywallStatus = "Invalid Activation Key. Try again.");
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _paywallStatus = 'Could not verify the license: $error');
      }
    } finally {
      if (!silent && mounted) setState(() => _isActivating = false);
    }
  }

  Future<void> _loadLocalVideo() async {
    if (_isLoadingVideo) return;
    setState(() {
      _isLoadingVideo = true;
      _playerError = null;
      _showSpeechRecoveryActions = false;
    });

    VideoPlayerController? controller;
    try {
      final pickedFile = await FilePicker.pickFile(type: FileType.video);
      if (!mounted || pickedFile == null) return;

      controller = await createVideoController(pickedFile);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      await controller.play();
      final previousController = _videoController;
      setState(() {
        _videoController = controller;
        _captionsText = _speechAvailable
            ? 'Listening for nearby speech...'
            : 'Video is playing. Enable speech recognition to see live captions.';
      });
      controller.addListener(_handleVideoChanged);
      await previousController?.dispose();
      _startTrialTracking();
      if (_speechAvailable) _startCaptioning();
    } catch (error) {
      await controller?.dispose();
      if (mounted) {
        setState(() {
          _playerError = 'Could not open this video: $error';
          _showSpeechRecoveryActions = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingVideo = false);
    }
  }

  void _handleVideoChanged() {
    if (mounted && !_isUpdatingSlider) setState(() {});
  }

  Future<void> _startCaptioning() {
    return _speechService.startListening(
      onResult: _handleSpeechResult,
      onError: (message) {
        _setSpeechError(
          SpeechService.userFriendlyError(message, isWeb: kIsWeb),
          permissionDenied:
              message.toLowerCase().contains('permission') ||
              message.toLowerCase().contains('not-allowed'),
        );
      },
    );
  }

  void _handleSpeechResult(String text) {
    if (mounted && !_showPaywall) {
      setState(() => _captionsText = text);
    }
  }

  void _startTrialTracking() {
    _trialTrackerTimer?.cancel();
    _trialTrackerTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (_isSubscribed ||
          _videoController == null ||
          !_videoController!.value.isPlaying ||
          _isSavingTrial) {
        return;
      }

      _watchTimeMs += 1000;
      _isSavingTrial = true;
      try {
        await _storageService.saveCurrentTime(_watchTimeMs);
      } catch (error) {
        timer.cancel();
        await _videoController?.pause();
        await _speechService.stopListening();
        if (mounted) {
          setState(() {
            _showPaywall = true;
            _showSpeechRecoveryActions = false;
            _playerError = kIsWeb
                ? 'Could not save trial time in browser storage. Allow site '
                      'data for this website before continuing.'
                : 'Could not save trial time: $error';
          });
        }
        return;
      } finally {
        _isSavingTrial = false;
      }

      if (_watchTimeMs >= _maxFreeTimeMs) {
        _videoController?.pause();
        await _speechService.stopListening();
        if (mounted) setState(() => _showPaywall = true);
        _trialTrackerTimer?.cancel();
      }
    });
  }

  Future<void> _togglePlay() async {
    if (_showPaywall) return;
    if (_videoController == null) return;

    if (_videoController!.value.isPlaying) {
      await _videoController!.pause();
      await _speechService.stopListening();
    } else {
      await _videoController!.play();
      if (_speechAvailable) {
        await _startCaptioning();
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _keyController.dispose();
    _apiService.close();
    _trialTrackerTimer?.cancel();
    _subLink?.cancel();
    unawaited(_speechService.stopListening());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = _videoController?.value.position ?? Duration.zero;
    final duration = _videoController?.value.duration ?? Duration.zero;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Live Caption Player'),
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        color: Colors.black,
                        child: Center(
                          child:
                              _videoController != null &&
                                  _videoController!.value.isInitialized
                              ? AspectRatio(
                                  aspectRatio:
                                      _videoController!.value.aspectRatio,
                                  child: VideoPlayer(_videoController!),
                                )
                              : const Text(
                                  'Choose a video to start',
                                  style: TextStyle(color: Colors.white70),
                                ),
                        ),
                      ),
                      if (!_showPaywall)
                        Positioned(
                          bottom: 20,
                          left: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _captionsText,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.yellow,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      if (_isLoadingVideo)
                        const Center(child: CircularProgressIndicator()),
                      if (_showPaywall)
                        PaywallOverlay(
                          controller: _keyController,
                          statusMessage: _paywallStatus,
                          isLoading: _isActivating,
                          onOpenPricing: _openPricingPage,
                          onActivate: () => _verifyLicense(_keyController.text),
                        ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.lightBlueAccent,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Live captions use sound picked up by your device '
                          'microphone; they do not directly transcribe the '
                          'video’s internal audio. Keep playback audible and '
                          'use speakers close to the microphone.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_playerError != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _playerError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        if (_showSpeechRecoveryActions)
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: _isRequestingSpeech
                                    ? null
                                    : _initSpeechRecognizer,
                                child: Text(
                                  _isRequestingSpeech
                                      ? 'Requesting microphone...'
                                      : 'Allow microphone / retry',
                                ),
                              ),
                              if (_microphonePermissionDenied && !kIsWeb)
                                TextButton(
                                  onPressed: _openMicrophoneSettings,
                                  child: const Text('Open app settings'),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                CustomSlider(
                  value: position.inMilliseconds.toDouble(),
                  max: duration.inMilliseconds.toDouble(),
                  onChanged: (val) {
                    _isUpdatingSlider = true;
                    setState(() {});
                  },
                  onChangeEnd: (val) {
                    _isUpdatingSlider = false;
                    _videoController?.seekTo(
                      Duration(milliseconds: val.toInt()),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      IconButton(
                        tooltip: 'Choose a video',
                        icon: const Icon(Icons.video_file, color: Colors.white),
                        onPressed: _isLoadingVideo ? null : _loadLocalVideo,
                      ),
                      IconButton(
                        tooltip: 'Back 10 seconds',
                        icon: const Icon(Icons.replay_10, color: Colors.white),
                        onPressed: _videoController == null
                            ? null
                            : () {
                                final target =
                                    position - const Duration(seconds: 10);
                                _videoController?.seekTo(
                                  target < Duration.zero
                                      ? Duration.zero
                                      : target,
                                );
                              },
                      ),
                      IconButton(
                        tooltip: 'Play or pause',
                        icon: Icon(
                          _videoController?.value.isPlaying == true
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: _videoController == null
                            ? null
                            : _togglePlay,
                      ),
                      IconButton(
                        tooltip: 'Forward 10 seconds',
                        icon: const Icon(Icons.forward_10, color: Colors.white),
                        onPressed: _videoController == null
                            ? null
                            : () {
                                final target =
                                    position + const Duration(seconds: 10);
                                _videoController?.seekTo(
                                  target > duration ? duration : target,
                                );
                              },
                      ),
                      Text(
                        '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')} / ${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
