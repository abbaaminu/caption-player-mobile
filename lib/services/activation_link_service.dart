import 'package:app_links/app_links.dart';

/// Abstraction over app_links so the player can be tested without plugins.
abstract interface class ActivationLinkSource {
  Stream<String> get links;

  Future<String?> getInitialLink();
}

class AppLinksActivationLinkSource implements ActivationLinkSource {
  AppLinksActivationLinkSource({AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Stream<String> get links => _appLinks.stringLinkStream;

  @override
  Future<String?> getInitialLink() => _appLinks.getInitialLinkString();
}
