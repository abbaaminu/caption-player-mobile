import 'dart:async';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// Applies the existing free-trial and license rules to system-wide captions.
///
/// The same 30-minute trial and the same license key unlock both the file
/// player and system captions. Trial time is spent only while audio is
/// actually being captioned (silent steps are free), and is written to the
/// same secure storage the player uses.
class SystemCaptionGate {
  SystemCaptionGate({
    required this._storage,
    required this._api,
    this.saveInterval = AppConfig.trialSaveInterval,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final StorageService _storage;
  final ApiService _api;
  final Duration saveInterval;
  final DateTime Function() _now;

  bool _unlimited = false;
  int _usedMs = 0;
  int _unsavedMs = 0;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// True when a valid activation is stored on this device.
  bool get isUnlimited => _unlimited;

  int get usedMs => _usedMs;

  int get remainingMs => _unlimited
      ? AppConfig.maxFreeTrialMs
      : (AppConfig.maxFreeTrialMs - _usedMs).clamp(0, AppConfig.maxFreeTrialMs);

  /// No trial time left and no license.
  bool get isExhausted => !_unlimited && _usedMs >= AppConfig.maxFreeTrialMs;

  Future<void> load() async {
    _usedMs = await _storage.loadSavedTime();
    final license = await _storage.loadLicense();
    final key = license?.key;
    if (license != null && license.isValid && key != null) {
      _unlimited = true;
      // Confirm in the background. Only an explicit "not valid" from the
      // server revokes access; being offline never locks a paying user out.
      unawaited(_recheck(key));
    }
  }

  Future<void> _recheck(String key) async {
    try {
      final valid = await _api.verifyLicenseKey(key);
      if (!valid) {
        _unlimited = false;
      }
    } on LicenseVerificationException {
      // Keep the cached license until the server can be reached.
    } catch (_) {
      // Same: transient failures must not lock the user out.
    }
  }

  /// Spends [ms] of trial time for audible captioning. Returns `false` once
  /// the trial is used up. Does nothing for licensed users.
  Future<bool> spend(int ms) async {
    if (_unlimited) {
      return true;
    }
    if (ms > 0) {
      _unsavedMs += ms;
      _usedMs = (_usedMs + ms).clamp(0, AppConfig.maxFreeTrialMs);
    }
    if (_unsavedMs > 0 && _now().difference(_lastSave) >= saveInterval) {
      await flush();
    }
    return !isExhausted;
  }

  /// Writes any trial time not yet saved.
  Future<void> flush() async {
    if (_unsavedMs <= 0) {
      return;
    }
    final pending = _unsavedMs;
    _unsavedMs = 0;
    _lastSave = _now();
    try {
      final total = await _storage.addTrialTime(pending);
      // Another process (the player) may also have spent time.
      if (total > _usedMs) {
        _usedMs = total;
      }
    } catch (_) {
      // Keep the time so the next flush retries it.
      _unsavedMs += pending;
    }
  }
}
