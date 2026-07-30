import 'package:web/web.dart' as web;
import 'package:waxdeck_data/waxdeck_data.dart';

import 'browser_settings_store.dart';

/// The real binding: `window.localStorage`, which survives a reload and
/// is scoped to the origin the app is served from.
///
/// Not `sessionStorage` - a preference that forgets itself when the tab
/// closes is the in-memory notifier this store replaced.
class _LocalStorage implements BrowserStorage {
  const _LocalStorage();

  @override
  String? getItem(String key) => web.window.localStorage.getItem(key);

  @override
  void setItem(String key, String value) =>
      web.window.localStorage.setItem(key, value);

  @override
  void removeItem(String key) => web.window.localStorage.removeItem(key);
}

/// The web build's per-device settings store. There is no mirror
/// database here (drift does not run on web), so [db] is always null and
/// the browser holds the values instead - which is the point: the
/// desktop-shaped surface that most wants a collapsed sidebar is the one
/// running in a browser.
ClientSettingsStore createClientSettingsStore(MirrorDatabase? db) =>
    BrowserClientSettingsStore(const _LocalStorage());
