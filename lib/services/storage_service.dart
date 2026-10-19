import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import '../models/license_state.dart';

class StorageService {
  final _storage = const FlutterSecureStorage();

  static const _keyTrialTime = 'trial_state_ms';
  static const _keyLicense = 'license_state';

  // --- Trial Watch Time (Encrypted) ---
  Future<int> loadSavedTime() async {
    final raw = await _storage.read(key: _keyTrialTime);
    if (raw == null) return 0;
    final savedTime = int.tryParse(raw);
    if (savedTime == null || savedTime < 0) {
      return AppConfig.freeTrialDuration.inMilliseconds;
    }
    return savedTime;
  }

  Future<void> saveCurrentTime(int watchTimeMs) async {
    await _storage.write(key: _keyTrialTime, value: watchTimeMs.toString());
  }

  // --- Subscription / License state persistence ---
  Future<void> saveLicense(String licenseKey) async {
    final state = LicenseState(key: licenseKey, isSubscribed: true);
    await _storage.write(key: _keyLicense, value: jsonEncode(state.toJson()));
  }

  Future<LicenseState?> loadLicense() async {
    final raw = await _storage.read(key: _keyLicense);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return LicenseState.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearLicense() async {
    await _storage.delete(key: _keyLicense);
  }
}
