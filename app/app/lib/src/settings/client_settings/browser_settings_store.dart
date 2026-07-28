import 'package:waxdeck_data/waxdeck_data.dart';

/// The slice of a browser's key/value storage this store uses.
///
/// Declared here rather than taken as `web.Storage` so the store is a
/// plain Dart object: the probe, the degradation, and the key semantics
/// are then exercised on the VM with a fake — a throwing one included —
/// and the only thing left unexercised is the handful of lines that hand
/// over the real `localStorage`.
abstract interface class BrowserStorage {
  String? getItem(String key);
  void setItem(String key, String value);
  void removeItem(String key);
}

/// Per-device settings in browser storage.
///
/// `localStorage` is not a guarantee. Private and incognito contexts
/// have thrown on write, a partitioned third-party context can refuse it
/// outright, and a visitor can turn it off. So the store probes once at
/// construction and guards every call after that, and a browser that
/// will not hold a value gets an in-memory one instead: a preference set
/// in a private window then lasts the session rather than taking down
/// the shell that reads it at startup. Same house rule the credential
/// store follows for the same reason.
///
/// Whatever this session changed is answered from memory first —
/// a removal as much as a write. That is what makes a change storage
/// refused still hold: it is in the shadow whether or not the browser
/// took it. It also means a second tab's writes are not picked up
/// mid-session, which is deliberate — these are per-device preferences
/// read at startup, not a cross-tab channel, and the native store does
/// not offer one either.
class BrowserClientSettingsStore implements ClientSettingsStore {
  /// Probes [storage] and falls back to memory if it will not hold a
  /// value. The probe is a full round trip: some contexts accept a write
  /// and then answer null, which a write-only probe would call success.
  BrowserClientSettingsStore(BrowserStorage storage)
    : _storage = _probe(storage) ? storage : null;

  static const _probeKey = 'waxdeck.storageProbe';

  final BrowserStorage? _storage;

  /// Every key this session touched, whether or not [_storage] took the
  /// change — a removal included, which is why the values are nullable
  /// and why membership rather than a non-null value is what makes the
  /// shadow authoritative. A `remove` the browser refuses would
  /// otherwise read back out of storage as the value that was just
  /// deleted.
  final Map<String, String?> _shadow = {};

  /// True when the store is answering out of memory alone.
  bool get degraded => _storage == null;

  static bool _probe(BrowserStorage storage) {
    try {
      storage.setItem(_probeKey, '1');
      final read = storage.getItem(_probeKey);
      storage.removeItem(_probeKey);
      return read == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> read(String key) async {
    if (_shadow.containsKey(key)) return _shadow[key];
    try {
      return _storage?.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _shadow[key] = value;
    try {
      _storage?.setItem(key, value);
    } catch (_) {
      // Out of quota, or a context that refuses to hold anything: the
      // shadow above already answered for the session.
    }
  }

  @override
  Future<void> remove(String key) async {
    _shadow[key] = null;
    try {
      _storage?.removeItem(key);
    } catch (_) {
      // A key that cannot be deleted comes back at the next launch,
      // which is a stale preference and not a reason to throw.
    }
  }
}
