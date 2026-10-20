import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/license_state.dart';

/// Small storage port so trial and license logic can be tested without
/// platform plugins.
abstract interface class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Keeps license keys and trial progress in the platform keychain/keystore.
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Web browsers do not expose the keychain, so local storage is used instead.
class PreferencesKeyValueStore implements KeyValueStore {
  PreferencesKeyValueStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) {
    return _preferences.setString(key, value);
  }

  @override
  Future<void> delete(String key) => _preferences.remove(key);
}

/// Persists the local free-trial counter and the verified license.
class StorageService {
  StorageService({KeyValueStore? store})
    : _store =
          store ??
          (kIsWeb ? PreferencesKeyValueStore() : SecureKeyValueStore());

  static const trialTimeKey = 'trial_state_ms';
  static const licenseStateKey = 'license_state';

  final KeyValueStore _store;

  /// Returns a sane value even if the stored data was truncated or tampered
  /// with. Values are clamped to the configured trial length.
  Future<int> loadSavedTime() async {
    final rawValue = await _store.read(trialTimeKey);
    if (rawValue == null) {
      return 0;
    }

    final parsed = int.tryParse(rawValue);
    if (parsed == null || parsed <= 0) {
      return 0;
    }
    return parsed.clamp(0, AppConfig.freeTrialDuration.inMilliseconds);
  }

  Future<void> saveCurrentTime(int watchTimeMs) async {
    final clamped = watchTimeMs.clamp(
      0,
      AppConfig.freeTrialDuration.inMilliseconds,
    );
    await _store.write(trialTimeKey, clamped.toString());
  }

  Future<LicenseState?> loadLicense() async {
    final rawValue = await _store.read(licenseStateKey);
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final license = LicenseState.fromJson(decoded);
      return license.isValid ? license : null;
    } on FormatException {
      // A malformed value must not block the app; treat it as unlicensed.
      return null;
    }
  }

  Future<void> saveLicense(String licenseKey) async {
    final normalizedKey = licenseKey.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(licenseKey, 'licenseKey', 'Must not be empty');
    }

    final license = LicenseState(key: normalizedKey, isSubscribed: true);
    await _store.write(licenseStateKey, jsonEncode(license.toJson()));
  }

  Future<void> clearLicense() => _store.delete(licenseStateKey);
}
