import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../system_caption/system_caption_platform.dart';
import '../theme/app_theme.dart';

/// Home of the system-wide caption feature (the Infinix / Pixel style
/// "Live Caption"): permission setup, start/stop, caption look, and the
/// trial / activation state shared with the player.
class SystemCaptionsScreen extends StatefulWidget {
  const SystemCaptionsScreen({
    super.key,
    this.isActive = true,
    this.platform,
    this.storageService,
    this.apiService,
  });

  /// Whether this tab is currently visible. Status is polled only then.
  final bool isActive;
  final SystemCaptionPlatform? platform;
  final StorageService? storageService;
  final ApiService? apiService;

  @override
  State<SystemCaptionsScreen> createState() => _SystemCaptionsScreenState();
}

class _SystemCaptionsScreenState extends State<SystemCaptionsScreen> {
  static const _disclosureKey = 'system_caption_disclosure_v1';

  late final SystemCaptionPlatform _platform;
  late final StorageService _storage;
  late final ApiService _api;
  late final bool _ownsApi;
  late final AppLifecycleListener _lifecycle;
  final TextEditingController _keyController = TextEditingController();

  Timer? _poller;
  SystemCaptionStatus _status = SystemCaptionStatus.unsupported;
  bool _statusLoaded = false;
  CaptionStyle _style = const CaptionStyle();
  int _usedMs = 0;
  bool _licensed = false;
  bool _busy = false;
  bool _activating = false;
  String _message = '';

  bool get _trialExhausted => !_licensed && _usedMs >= AppConfig.maxFreeTrialMs;

  @override
  void initState() {
    super.initState();
    _platform = widget.platform ?? MethodChannelSystemCaptionPlatform();
    _storage = widget.storageService ?? StorageService();
    _api = widget.apiService ?? ApiService();
    _ownsApi = widget.apiService == null;
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_refresh()));
    unawaited(_loadStyle());
    unawaited(_refresh());
    _syncPolling();
  }

  @override
  void didUpdateWidget(SystemCaptionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncPolling();
      if (widget.isActive) {
        unawaited(_refresh());
      }
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    _lifecycle.dispose();
    _keyController.dispose();
    if (_ownsApi) {
      _api.close();
    }
    super.dispose();
  }

  void _syncPolling() {
    _poller?.cancel();
    _poller = null;
    if (widget.isActive) {
      _poller = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_refresh()),
      );
    }
  }

  Future<void> _refresh() async {
    try {
      final status = await _platform.status();
      final used = await _storage.loadSavedTime();
      final license = await _storage.loadLicense();
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusLoaded = true;
        _usedMs = used;
        _licensed = license?.isValid ?? false;
      });
    } catch (error) {
      if (kDebugMode) debugPrint('Refreshing caption status failed: $error');
      if (!mounted) return;
      setState(() => _statusLoaded = true);
    }
  }

  Future<void> _loadStyle() async {
    try {
      final style = await _platform.style();
      if (mounted) setState(() => _style = style);
    } catch (_) {
      // Defaults are fine.
    }
  }

  // ---------------------------------------------------------------------
  // Start / stop
  // ---------------------------------------------------------------------

  Future<void> _onPrimaryPressed() async {
    if (_busy) return;
    if (_status.running) {
      await _run(() => _platform.stop());
      return;
    }
    if (_trialExhausted) {
      await _openPricing();
      return;
    }
    if (!await _ensureDisclosureAccepted()) return;

    await _run(() async {
      if (!_status.micGranted || !_status.notificationsGranted) {
        final audioGranted = await _platform.requestRuntimePermissions();
        await _refresh();
        if (!audioGranted) {
          _say(
            'Audio permission is needed so Android lets this app hear sound '
            'playing on the phone. The microphone is never recorded.',
          );
          return;
        }
      }
      if (!_status.overlayGranted) {
        _say(
          'Turn on “Display over other apps” for Live Caption Player, then '
          'come back and press Start.',
        );
        await _platform.requestOverlayPermission();
        return;
      }
      _say('');
      await _platform.start();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (kDebugMode) debugPrint('Caption action failed: $error');
      _say('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Give the service a moment to come up before re-reading its state.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _refresh();
  }

  void _say(String message) {
    if (mounted) setState(() => _message = message);
  }

  Future<bool> _ensureDisclosureAccepted() async {
    final preferences = SharedPreferencesAsync();
    try {
      if (await preferences.getBool(_disclosureKey) == true) return true;
    } catch (_) {
      // Fall through and ask again; the answer simply is not remembered.
    }
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Caption audio on this phone'),
        content: const SingleChildScrollView(
          child: Text(
            'Live Caption listens to the sound your phone is playing (videos, '
            'music, games, social media) and turns speech into on-screen '
            'text.\n\n'
            '• Audio is processed on your device by an offline speech model. '
            'It is never uploaded or stored.\n'
            '• The microphone is not recorded. Android names this permission '
            '“audio” because it also covers capturing playback.\n'
            '• Android will ask you to confirm each time captions start.\n'
            '• Calls and apps that block capture cannot be captioned.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agree and continue'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    try {
      await preferences.setBool(_disclosureKey, true);
    } catch (_) {
      // Not remembered; the dialog will show again next time.
    }
    return true;
  }

  // ---------------------------------------------------------------------
  // Pricing and activation (same backend and prices as the player)
  // ---------------------------------------------------------------------

  Future<void> _openPricing() async {
    final uri = Uri.tryParse(AppConfig.pricingUrl);
    try {
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open pricing page');
      }
    } catch (_) {
      _say(
        'Could not open the pricing page. Check your connection, then try '
        'again.',
      );
    }
  }

  Future<void> _activate() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _say('Paste your license key first.');
      return;
    }
    setState(() {
      _activating = true;
      _message = 'Checking activation key…';
    });
    try {
      final valid = await _api.verifyLicenseKey(key);
      if (!mounted) return;
      if (valid) {
        await _storage.saveLicense(key);
        _keyController.clear();
        _say('Activated. Unlimited live captions are unlocked.');
        await _refresh();
      } else {
        _say('That activation key is not valid. Check the key and try again.');
      }
    } on LicenseVerificationException catch (error) {
      _say(error.message);
    } catch (_) {
      _say('Could not save the activation. Free some storage and try again.');
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  // ---------------------------------------------------------------------
  // Style
  // ---------------------------------------------------------------------

  Future<void> _commitStyle(CaptionStyle style) async {
    setState(() => _style = style);
    try {
      await _platform.setStyle(style);
    } catch (_) {
      // The box keeps its previous look; nothing the user can act on.
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConfig.appName,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _trialLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: _licensed ? AppTheme.accent : Colors.white60,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: !_statusLoaded
            ? const Center(child: CircularProgressIndicator())
            : (!_status.supported
                  ? _buildUnsupported(theme)
                  : _buildBody(theme)),
      ),
    );
  }

  String get _trialLabel {
    if (_licensed) return 'Unlimited captions activated';
    final remaining = (AppConfig.maxFreeTrialMs - _usedMs).clamp(
      0,
      AppConfig.maxFreeTrialMs,
    );
    if (remaining == 0) return 'Free trial ended';
    return 'Free trial · ${(remaining / 60000).ceil()} min left';
  }

  Widget _buildUnsupported(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_android, size: 48, color: Colors.white38),
            const SizedBox(height: 16),
            Text(
              'System-wide captions need Android 10 or newer.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'You can still caption a video or audio file from the Player '
              'tab.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final running = _status.running;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _heroCard(theme, running),
        if (_message.isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.accent,
                height: 1.4,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (_trialExhausted) ...[
          _unlockCard(theme),
          const SizedBox(height: 20),
        ],
        _sectionTitle(theme, 'Setup'),
        _permissionTile(
          icon: Icons.layers_outlined,
          title: 'Display over other apps',
          subtitle: 'Shows the caption box on top of the app you are using.',
          granted: _status.overlayGranted,
          onGrant: () => _platform.requestOverlayPermission(),
        ),
        _permissionTile(
          icon: Icons.graphic_eq,
          title: 'Capture phone audio',
          subtitle:
              'Android calls this the audio permission. It lets captions hear '
              'what the phone plays. The microphone is not recorded.',
          granted: _status.micGranted,
          onGrant: () async {
            final granted = await _platform.requestRuntimePermissions();
            if (!granted) await _platform.openAppSettings();
            await _refresh();
          },
        ),
        _permissionTile(
          icon: Icons.notifications_none,
          title: 'Notifications',
          subtitle:
              'Lets you stop captions from the notification shade. Optional.',
          granted: _status.notificationsGranted,
          onGrant: () async {
            await _platform.requestRuntimePermissions();
            await _refresh();
          },
        ),
        const SizedBox(height: 20),
        _sectionTitle(theme, 'Caption style'),
        _styleCard(theme),
        const SizedBox(height: 20),
        _sectionTitle(theme, 'Good to know'),
        _tips(theme),
        if (!_licensed && !_trialExhausted) ...[
          const SizedBox(height: 20),
          _unlockCard(theme),
        ],
      ],
    );
  }

  Widget _heroCard(ThemeData theme, bool running) {
    final label = running
        ? 'Stop live captions'
        : (_trialExhausted
              ? 'Unlock live captions'
              : (_status.readyToStart
                    ? 'Start live captions'
                    : 'Set up live captions'));
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: running
              ? AppTheme.accent.withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                running ? Icons.closed_caption : Icons.closed_caption_outlined,
                color: running ? AppTheme.accent : Colors.white70,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      running ? 'Live captions are on' : 'Live Caption',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      running
                          ? 'Switch to any app. Tap the caption box to expand '
                                'it, drag it to move it.'
                          : 'Captions for any video, call recording, podcast '
                                'or song playing on this phone.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _onPrimaryPressed,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: Colors.white54,
          letterSpacing: 1.1,
        ),
      ),
    ),
  );

  Widget _permissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required Future<void> Function() onGrant,
  }) {
    return Card(
      color: AppTheme.surfaceRaised,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: granted
            ? Semantics(
                label: 'Allowed',
                child: const Icon(Icons.check_circle, color: Color(0xFF4CD08A)),
              )
            : TextButton(
                onPressed: () => unawaited(onGrant()),
                child: const Text('Allow'),
              ),
      ),
    );
  }

  Widget _styleCard(ThemeData theme) {
    final alpha = (_style.backgroundOpacity * 255 / 100).round();
    return Card(
      color: AppTheme.surfaceRaised,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(alpha),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                'This is how live captions will look.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _style.textSizeSp,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _labeledSlider(
              label: 'Text size',
              value: _style.textSizeSp,
              min: 12,
              max: 32,
              divisions: 20,
              display: '${_style.textSizeSp.round()} sp',
              onChanged: (value) =>
                  setState(() => _style = _style.copyWith(textSizeSp: value)),
              onChangeEnd: (value) =>
                  _commitStyle(_style.copyWith(textSizeSp: value)),
            ),
            _labeledSlider(
              label: 'Background',
              value: _style.backgroundOpacity.toDouble(),
              min: 30,
              max: 100,
              divisions: 14,
              display: '${_style.backgroundOpacity}%',
              onChanged: (value) => setState(
                () =>
                    _style = _style.copyWith(backgroundOpacity: value.round()),
              ),
              onChangeEnd: (value) => _commitStyle(
                _style.copyWith(backgroundOpacity: value.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeledSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _tips(ThemeData theme) {
    const tips = <(IconData, String)>[
      (
        Icons.toggle_on_outlined,
        'Add the “Live Caption” tile to Quick Settings (swipe down twice, tap '
            'the pencil) to start captions from any screen.',
      ),
      (
        Icons.lock_outline,
        'Some apps block audio capture (certain streaming apps, and phone or '
            'voice calls). Their captions will not appear.',
      ),
      (
        Icons.offline_bolt_outlined,
        'Captions are created on your phone by an offline model. The first '
            'start downloads it once (about 31 MB); after that no internet is '
            'needed.',
      ),
      (
        Icons.battery_5_bar,
        'Captioning uses the processor continuously. Stop it when you are not '
            'watching to save battery.',
      ),
    ];
    return Card(
      color: AppTheme.surfaceRaised,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final tip in tips)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(tip.$1, size: 20, color: Colors.white54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tip.$2,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _unlockCard(ThemeData theme) {
    return Card(
      color: AppTheme.surfaceRaised,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _trialExhausted
                  ? 'Your ${AppConfig.freeTrialDuration.inMinutes}-minute free '
                        'trial has ended.'
                  : 'Unlock unlimited live captions',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The same plan unlocks system-wide captions and the player.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _activating ? null : _openPricing,
              child: const Text(AppConfig.monthlyPlanLabel),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _activating ? null : _openPricing,
              child: const Text(AppConfig.lifetimePlanLabel),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              enabled: !_activating,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: AppConfig.maxLicenseKeyLength,
              keyboardType: TextInputType.visiblePassword,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Already purchased? Paste license key',
                counterText: '',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
              onSubmitted: (_) => _activating ? null : _activate(),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _activating ? null : _activate,
              child: _activating
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Activate'),
            ),
            const SizedBox(height: 8),
            Text(
              'Need help? ${AppConfig.supportEmail}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}
