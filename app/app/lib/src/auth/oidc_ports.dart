import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'oidc_flow.dart';
import 'web_nav/web_nav.dart';

/// The url-opening port. On web the start URL is origin-relative and
/// must navigate the current tab (the OIDC redirect chain sets the
/// session cookie and lands back in the SPA), which is a direct
/// location assignment rather than url_launcher; on native the port
/// opens the system browser at the absolute URL via url_launcher.
class LauncherUrlOpener implements UrlOpenerPort {
  const LauncherUrlOpener();

  @override
  Future<void> open(String url) async {
    var uri = Uri.parse(url);
    if (!uri.hasScheme) {
      // Origin-relative (web builds): resolve against the page URL.
      uri = Uri.base.resolveUri(uri);
    }
    if (kIsWeb) {
      navigateSameTab(uri.toString());
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// app_links behind the WaxDeck-owned port.
class AppLinksDeepLinks implements DeepLinkPort {
  AppLinksDeepLinks() : _appLinks = AppLinks();

  final AppLinks _appLinks;

  @override
  Stream<Uri> get uriLinkStream => _appLinks.uriLinkStream;
}
