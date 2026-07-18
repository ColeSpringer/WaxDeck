import 'package:web/web.dart' as web;

/// Hands the current tab to url. Deliberately not url_launcher: the
/// single sign-on redirect chain must ride this exact tab so the
/// session cookie lands back in the SPA, and a location assignment is
/// the one navigation primitive that cannot be popup-blocked or lost
/// to a plugin registration gap.
void navigateSameTab(String url) {
  web.window.location.href = url;
}
