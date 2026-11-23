import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/client_settings/browser_settings_store.dart';
import 'owed_revoke_storage/owed_revoke_storage.dart';

/// What a browser keeps of its session beside the cookie: which session the
/// cookie holds, by the id the server gives it, and a sign-out its server
/// has yet to hear.
///
/// A browser's session is the server's cookie, which the page cannot
/// remove: a sign-out whose request never arrived leaves it live, and the
/// next read of the session would sign the browser back in. So the revoke
/// is owed until the server answers it, as a mark in browser storage: it
/// outlasts a reload, and every tab of the origin reads the same one. The
/// mark names the session the cookie held at the sign-out when that was
/// known, so that its delivery ends that session and no other; one that
/// names none is delivered as a plain sign-out. Each mark is its own, so a
/// road that took one settles that one and never another owed since.
/// Neither names an account or holds a credential.
///
/// Storage that will not hold either leaves it held here, for as long as
/// the page lives. Native keeps none: its sign-out drops the token, and
/// nothing presents that session again.
class OwedRevoke {
  OwedRevoke(this._storage);

  static const storageKey = 'waxdeck.auth.owedRevoke';
  static const heldKey = 'waxdeck.auth.heldSession';

  /// What a mark that names no session starts with. No session id does.
  static const _unnamed = '1';

  static final _random = Random();

  final BrowserStorage? _storage;

  /// What the storage would not take, by key: the value, or null for none.
  final _kept = <String, String?>{};

  /// Whether anything is kept here at all: a browser's storage.
  bool get keeps => _storage != null;

  /// The revoke owed, null for none. Read from the storage each time:
  /// another tab may have settled it, or owed another since.
  String? get mark => _read(storageKey);

  bool get owed => mark != null;

  /// The id of the session owed, null when none is owed or none named.
  String? get session => switch (mark) {
    final mark? when !mark.startsWith(_unnamed) => mark,
    _ => null,
  };

  /// A sign-out of [session], or of a session not known, was asked of the
  /// server: answers the mark it owes.
  String owe([String? session]) {
    final mark =
        session ??
        '$_unnamed:${DateTime.now().microsecondsSinceEpoch}:'
            '${_random.nextInt(1 << 30)}';
    _write(storageKey, mark);
    return mark;
  }

  /// The server heard the revoke [mark] owes, or no session is left for it
  /// to end. A revoke owed since, in this tab or another, stays owed.
  void settle(String mark) {
    if (_read(storageKey) == mark) _write(storageKey, null);
  }

  /// The session the browser's cookie holds, as last said by a response
  /// that says which; null when that is not known.
  String? get held => _read(heldKey);

  /// The cookie holds [session], or, with none given, one not known.
  void hold([String? session]) => _write(heldKey, session);

  /// The cookie no longer holds [session], or, with none given, holds one
  /// not known.
  void release([String? session]) {
    if (session == null || _read(heldKey) == session) _write(heldKey, null);
  }

  String? _read(String key) {
    final storage = _storage;
    if (storage == null) return null;
    if (_kept.containsKey(key)) return _kept[key];
    try {
      return storage.getItem(key);
    } catch (_) {
      // Unreadable, and nothing was asked of it here: nothing is known.
      return null;
    }
  }

  void _write(String key, String? value) {
    final storage = _storage;
    if (storage == null) return;
    try {
      if (value != null) {
        storage.setItem(key, value);
      } else {
        storage.removeItem(key);
      }
      // Read back: some contexts take a write and keep nothing.
      if (storage.getItem(key) == value) {
        _kept.remove(key);
      } else {
        _kept[key] = value;
      }
    } catch (_) {
      // A private window, a denied store.
      _kept[key] = value;
    }
  }
}

/// Over the page's storage on the web; over none elsewhere, where nothing
/// is ever owed.
final owedRevokeProvider = Provider<OwedRevoke>(
  (ref) => OwedRevoke(owedRevokeStorage()),
);
