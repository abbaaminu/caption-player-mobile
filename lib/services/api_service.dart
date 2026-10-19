import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpException;

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<bool> verifyLicenseKey(String key) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return false;

    final response = await _client
        .post(
          Uri.parse(AppConfig.licenseVerificationUrl),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'license_key': normalizedKey}),
        )
        .timeout(AppConfig.licenseVerificationTimeout);

    if (response.statusCode != 200) {
      throw HttpException(
        'License server returned HTTP ${response.statusCode}.',
        uri: Uri.parse(AppConfig.licenseVerificationUrl),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['valid'] is! bool) {
      throw const FormatException(
        'License server returned an invalid response.',
      );
    }
    return decoded['valid'] as bool;
  }
}
