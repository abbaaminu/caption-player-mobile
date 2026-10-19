import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/license_state.dart';

class StorageService {
  final _secureStorage = const FlutterSecureStorage();
  final _browserStorage = SharedPreferencesAsync();

  static const _keyTrialTime = 'trial_state_ms';
  static const _keyLicense = 'license_state';

  // --- Trial Watch Time (Encrypted) ---
  Future<int> loadSavedTime() async {
    final raw = await _read(key: _keyTrialTime);
    if (raw == null) return 0;
    final savedTime = int.tryParse(raw);
    if (savedTime == null || savedTime < 0) {
      return AppConfig.freeTrialDuration.inMilliseconds;
    }
    return savedTime;
  }

  Future<void> saveCurrentTime(int watchTimeMs) async {
    await _write(key: _keyTrialTime, value: watchTimeMs.toString());
  }

  // --- Subscription / License state persistence ---
  Future<void> saveLicense(String licenseKey) async {
    final state = LicenseState(key: licenseKey, isSubscribed: true);
    await _write(key: _keyLicense, value: jsonEncode(state.toJson()));
  }

  Future<LicenseState?> loadLicense() async {
    final raw = await _read(key: _keyLicense);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return LicenseState.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearLicense() async {
    if (kIsWeb) {
      await _browserStorage.remove(_keyLicense);
    } else {
      await _secureStorage.delete(key: _keyLicense);
    }
  }

  Future<String?> _read({required String key}) {
    if (kIsWeb) return _browserStorage.getString(key);
    return _secureStorage.read(key: key);
  }

  Future<void> _write({required String key, required String value}) async {
    if (kIsWeb) {
      await _browserStorage.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }
}
