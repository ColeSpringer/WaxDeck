/// Client-minted identifiers, listen-session keys and ULIDs, and the ULID
/// a pid carries.
library;

import 'dart:math';

const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

Random _newRandom() {
  try {
    return Random.secure();
  } on UnsupportedError {
    // Some embedders have no entropy source; a time-seeded generator is
    // acceptable for idempotency IDs, which only need to avoid collisions.
    return Random(DateTime.now().microsecondsSinceEpoch);
  }
}

final Random _random = _newRandom();

/// Returns a fresh 26-character Crockford base32 identifier.
///
/// Clients mint one per playback session and reuse it only when retrying a
/// failed report; the server deduplicates on it, so a replay never
/// double-counts.
String newListenSessionId() {
  final buffer = StringBuffer();
  for (var i = 0; i < 26; i++) {
    buffer.write(_crockford[_random.nextInt(_crockford.length)]);
  }
  return buffer.toString();
}

/// [pid] without its type prefix: the item's ULID, which a kind change
/// keeps while the prefix follows the kind. Whatever matches items across
/// a kind change keys them by this. A pid with no prefix is its own ULID.
String ulidOf(String pid) => pid.substring(pid.indexOf('-') + 1);

/// Returns a fresh ULID: a millisecond timestamp and 80 random bits in
/// Crockford base32, so it sorts by when it was minted and the server's
/// strict parse takes it (the first character is at most 7).
String newUlid() {
  var time = DateTime.now().millisecondsSinceEpoch;
  final chars = List<String>.filled(26, '0');
  for (var i = 9; i >= 0; i--) {
    chars[i] = _crockford[time % 32];
    time ~/= 32;
  }
  for (var i = 10; i < 26; i++) {
    chars[i] = _crockford[_random.nextInt(32)];
  }
  return chars.join();
}
