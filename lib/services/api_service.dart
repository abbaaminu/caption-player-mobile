import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// A verification failure that is safe to show to the user.
class LicenseVerificationException implements Exception {
  const LicenseVerificationException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Talks to the activation backend. The service never logs or persists the
/// key itself; [StorageService] owns persistence after verification.
class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  /// Returns `true` only when the server confirms the key is valid.
  ///
  /// Throws [LicenseVerificationException] for network, timeout, HTTP, and
  /// malformed-response failures so the paywall can show an actionable message.
  Future<bool> verifyLicenseKey(String key) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return false;
    }
    if (normalizedKey.length > AppConfig.maxLicenseKeyLength) {
      throw const LicenseVerificationException(
        'That activation key is too long. Check the key and try again.',
      );
    }

    final uri = Uri.parse(AppConfig.licenseVerificationUrl);
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, String>{'license_key': normalizedKey}),
          )
          .timeout(AppConfig.licenseVerificationTimeout);
    } on TimeoutException {
      throw const LicenseVerificationException(
        'The license server took too long to respond. Check your connection '
        'and try again.',
      );
    } on http.ClientException {
      throw const LicenseVerificationException(
        'Could not reach the license server. Check your internet connection '
        'and try again.',
      );
    }

    if (response.statusCode != 200) {
      throw LicenseVerificationException(
        'The license server returned HTTP ${response.statusCode}. Try again '
        'in a moment.',
        statusCode: response.statusCode,
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const LicenseVerificationException(
        'The license server returned an unreadable response. Try again in a '
        'moment.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const LicenseVerificationException(
        'The license server returned an invalid response. Try again in a '
        'moment.',
      );
    }

    final valid = decoded['valid'];
    if (valid is! bool) {
      throw const LicenseVerificationException(
        'The license server returned an invalid response. Try again in a '
        'moment.',
      );
    }
    return valid;
  }
}
