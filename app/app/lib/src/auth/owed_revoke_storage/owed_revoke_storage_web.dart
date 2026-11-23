import '../../settings/client_settings/browser_settings_store.dart';
import '../../settings/client_settings/client_settings_web.dart';

/// The page's `localStorage`, which every tab of the origin reads.
BrowserStorage? owedRevokeStorage() => const BrowserLocalStorage();
