import '../../settings/client_settings/browser_settings_store.dart';
import '../../settings/client_settings/client_settings_web.dart';

/// The page's `localStorage`, scoped to the origin the app is served from.
BrowserStorage? cursorStorage() => const BrowserLocalStorage();
