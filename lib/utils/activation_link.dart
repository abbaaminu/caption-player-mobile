import '../config/app_config.dart';

/// Result of parsing an activation URL such as
/// `captionplayer://activate?key=CLP-123`.
sealed class ActivationLinkResult {
  const ActivationLinkResult();
}

class ActivationLinkKey extends ActivationLinkResult {
  const ActivationLinkKey(this.key);

  final String key;
}

class ActivationLinkMissingKey extends ActivationLinkResult {
  const ActivationLinkMissingKey();
}

class ActivationLinkIgnored extends ActivationLinkResult {
  const ActivationLinkIgnored();
}

ActivationLinkResult parseActivationLink(String rawLink) {
  final trimmed = rawLink.trim();
  if (trimmed.isEmpty) {
    return const ActivationLinkIgnored();
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.toLowerCase() != AppConfig.activationScheme) {
    return const ActivationLinkIgnored();
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final isActivationTarget =
      host == AppConfig.activationHost ||
      (host.isEmpty && (path == '/activate' || path == 'activate'));
  if (!isActivationTarget) {
    return const ActivationLinkIgnored();
  }

  final key = uri.queryParameters['key']?.trim();
  if (key == null || key.isEmpty) {
    return const ActivationLinkMissingKey();
  }
  return ActivationLinkKey(key);
}
