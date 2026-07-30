import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../sync/sync_providers.dart';
import 'client_settings/client_settings.dart';

/// Where per-device preferences persist: the local mirror on native, the
/// browser's own storage on web. The sibling of [prefsControllerProvider]
/// (`prefs_controller.dart`), which holds the account's synced document;
/// what belongs in which is ADR-0027's subject.
final clientSettingsStoreProvider = Provider<ClientSettingsStore>(
  (ref) => createClientSettingsStore(ref.watch(mirrorDatabaseProvider)),
);

/// A notifier whose state is one per-device preference.
///
/// The state stays synchronous. Everything reading a preference reads a
/// value, not an `AsyncValue` of one - a shell that cannot lay itself
/// out until the disk answers would be a worse trade than a first frame
/// drawn at the default. So the notifier starts at [defaultValue],
/// replaces it once the stored value arrives, and writes every change
/// back.
///
/// Nothing here throws, and it does not rely on being lucky about that.
/// Both stores promise never to, but these are unawaited futures on a
/// startup path: anything escaping one is an unhandled zone error rather
/// than a caught failure, and the whole cost of losing is a preference
/// read at its default. So the store's promise is enforced here rather
/// than trusted, which also covers a [decode] a later setting writes.
mixin StoredSetting<T> on Notifier<T> {
  /// The key this preference is filed under; see [ClientSettingKeys].
  String get settingKey;

  /// What the preference reads as before anything is stored.
  T get defaultValue;

  /// Reads a stored string back, or null when it does not parse. A value
  /// written by an older build (or hand-edited in a browser's storage
  /// inspector) must read as "nothing stored", not as a crash at launch.
  T? decode(String raw);

  String encode(T value);

  /// Combines a value this session set with one the store answered with
  /// afterwards. Called only when the two race - a preference changed
  /// before its own read came back.
  ///
  /// Keeping the session's value and dropping the stored one is right
  /// for a preference that names a single thing: a listener who
  /// collapsed the sidebar before the read landed must not have it
  /// opened again by their own last launch. It is wrong for a preference
  /// that accumulates, where it would throw away everything stored on
  /// the strength of one new entry, so those override it.
  @protected
  T merge(T mine, T stored) => mine;

  /// True once this session set the value itself.
  bool _touched = false;

  /// The value this notifier knows, kept across rebuilds.
  ///
  /// Riverpod re-runs `build` on the same notifier instance when a
  /// dependency changes, and whatever `build` returns replaces the
  /// state. Without this the rebuild would hand back [defaultValue] and
  /// silently discard the listener's preference.
  bool _known = false;
  late T _value;

  /// Which read is still the current one. A read in flight when the
  /// preference is cleared must not land afterwards and put it back.
  int _generation = 0;

  /// Called from [build].
  @protected
  T hydrate() {
    if (_known) return _value;
    // Read, not watch. Which store this is cannot meaningfully change
    // under a running app - it is chosen by the platform at startup -
    // and watching it would make every preference vulnerable to the
    // rebuild this notifier has to survive rather than merely tolerate.
    unawaited(_load(ref.read(clientSettingsStoreProvider), ++_generation));
    return defaultValue;
  }

  Future<void> _load(ClientSettingsStore store, int generation) async {
    try {
      final raw = await store.read(settingKey);
      if (raw == null || !ref.mounted || generation != _generation) return;
      final stored = decode(raw);
      if (stored == null) return;
      if (!_touched) {
        _remember(stored);
        return;
      }
      // The read lost a race with the listener. [merge] decides what
      // that costs, and the result is written back, because what is on
      // disk is the half of it this session already persisted.
      final merged = merge(_value, stored);
      _remember(merged);
      await _persist(store, encode(merged));
    } catch (error) {
      _failed('reading', error);
    }
  }

  void _remember(T value) {
    _known = true;
    _value = value;
    state = value;
  }

  /// Sets the preference and remembers it for the next launch.
  ///
  /// The store and the encoding are resolved before the write is handed
  /// off, not inside it: `ref.read` past a disposal throws, and a
  /// preference set by the last tap before a screen goes away is exactly
  /// when that would happen.
  @protected
  void put(T value) {
    _touched = true;
    _remember(value);
    final store = ref.read(clientSettingsStoreProvider);
    unawaited(_persist(store, encode(value)));
  }

  /// Drops the preference from the store and from memory, so it reads as
  /// its default again.
  ///
  /// For a key that turns out to be an account's content rather than a
  /// device's - the recent searches on sign-out. Public where [put] is
  /// protected, because the caller is the session ending rather than the
  /// setting's own screen.
  ///
  /// Retires any read still in flight: invalidating the provider does
  /// not help, since Riverpod keeps the notifier across a rebuild, and a
  /// read that landed after this would put the cleared value straight
  /// back.
  Future<void> clearStored() async {
    _generation++;
    _touched = false;
    _known = false;
    state = defaultValue;
    try {
      await ref.read(clientSettingsStoreProvider).remove(settingKey);
    } catch (error) {
      _failed('clearing', error);
    }
  }

  Future<void> _persist(ClientSettingsStore store, String encoded) async {
    try {
      await store.write(settingKey, encoded);
    } catch (error) {
      _failed('writing', error);
    }
  }

  /// A preference that cannot be read or written has no symptom of its
  /// own - it simply reads as the default next launch - so the console
  /// gets the reason rather than nothing. Same treatment, and the same
  /// reasoning, as a queue that will not write.
  void _failed(String verb, Object error) {
    debugPrint('client setting $settingKey: $verb failed: $error');
  }
}
