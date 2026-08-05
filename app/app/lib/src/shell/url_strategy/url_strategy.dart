/// Platform switch for the web build's address-bar strategy.
///
/// WaxDeck's locations are real paths (`/music/albums/al-...`), not
/// fragments: the server answers unknown paths with the app shell
/// (`server/internal/web`), so a typed URL, a shared link, and a reload
/// all land on the screen they name. Native builds have no address bar
/// and no strategy to set.
library;

export 'url_strategy_stub.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart';
