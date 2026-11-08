import 'package:flutter/foundation.dart';

/// Web speech recognition requires a secure context. `localhost` also counts
/// as secure in browsers, which keeps local development usable over HTTP.
///
/// [isWeb] exists for tests; production callers should use the default.
bool isSecureWebOrigin(Uri uri, {bool? isWeb}) {
  if (!(isWeb ?? kIsWeb)) {
    return true;
  }

  if (uri.scheme == 'https') {
    return true;
  }
  if (uri.scheme != 'http') {
    return false;
  }

  final host = uri.host.toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]';
}
