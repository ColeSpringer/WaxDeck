import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/client_settings/browser_settings_store.dart';
import 'cursor_storage/cursor_storage.dart';

/// The newest catalog position a listener with no mirror has heard, for
/// the server and account it heard it for.
///
/// Presented when the listener subscribes, so a browser that comes back
/// (a reload, a return after a while) is told which entities changed
/// while it was away. Kept in browser storage across reloads as one
/// record; a position heard for another server or account is never
/// presented, and the next one this account hears replaces it. Storage
/// that cannot be read or written leaves the position held for the
/// session.
class CatalogCursor {
  CatalogCursor({this._storage, required this.server, required this.account});

  /// Where the record is kept: a JSON object of `server`, `account` and
  /// `since`.
  static const storageKey = 'waxdeck.live.catalogSince';

  final BrowserStorage? _storage;

  /// The server's base URL, as the client addresses it.
  final String server;

  /// The account the session is for. Null keeps nothing.
  final String? account;

  String? _since;
  var _loaded = false;

  /// The position to present, null when none was heard for this server
  /// and account.
  String? get since {
    if (!_loaded) {
      _loaded = true;
      _since = _load();
    }
    return _since;
  }

  /// A catalog invalidation said [since]: the newest position heard.
  void heard(String since) {
    _loaded = true;
    _since = since;
    if (account == null) return;
    try {
      _storage?.setItem(
        storageKey,
        jsonEncode({'server': server, 'account': account, 'since': since}),
      );
    } catch (_) {
      // A private window, a full quota: held for the session.
    }
  }

  String? _load() {
    if (account == null) return null;
    try {
      final raw = _storage?.getItem(storageKey);
      if (raw == null) return null;
      final record = jsonDecode(raw);
      if (record is! Map<String, Object?>) return null;
      if (record['server'] != server || record['account'] != account) {
        return null;
      }
      final since = record['since'];
      return since is String && since.isNotEmpty ? since : null;
    } catch (_) {
      // Unreadable, or not a record this wrote: nothing to present.
      return null;
    }
  }
}

/// The browser's storage on the web, where the listener holds no mirror;
/// null elsewhere.
final catalogCursorStorageProvider = Provider<BrowserStorage?>(
  (ref) => cursorStorage(),
);
