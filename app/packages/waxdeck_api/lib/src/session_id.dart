/// Listen-session idempotency IDs.
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
