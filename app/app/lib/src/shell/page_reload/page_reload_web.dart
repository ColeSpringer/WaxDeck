import 'package:web/web.dart' as web;

const bool canReloadPage = true;

/// Fetches the client again. The server serves the SPA entry with
/// `Cache-Control: no-cache`, so this always lands on the new build
/// rather than on whatever the browser kept.
void reloadPage() {
  web.window.location.reload();
}
