import 'package:flutter_web_plugins/url_strategy.dart';

/// Puts WaxDeck's locations in the path rather than the fragment.
///
/// The fragment never reaches the server, so under the default strategy
/// every location was one origin as far as a proxy, a crawler, or a
/// share preview was concerned. The server's SPA fallback answers a
/// document navigation for any unknown path with the shell
/// (`server/internal/web`), which is the whole requirement; the hash
/// links minted before this flip are rewritten by the shim in
/// `web/index.html` before the engine boots.
void useWaxUrlStrategy() {
  usePathUrlStrategy();
}
