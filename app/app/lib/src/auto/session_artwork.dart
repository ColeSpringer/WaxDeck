/// Where an OS media surface fetches the cover of what is playing.
///
/// The whole problem in one line: those surfaces fetch artwork
/// themselves, in another process, carrying none of this app's
/// credentials - and every WaxDeck art URL wants a bearer token. So
/// native builds hand the OS a file they have already fetched, and the
/// web build hands over the server URL, where the browser attaches the
/// session cookie it holds anyway.
library;

export 'session_artwork_io.dart'
    if (dart.library.js_interop) 'session_artwork_web.dart';

/// The rung an OS surface's cover is asked for at.
///
/// One size for every surface that shows it: a lock screen at three
/// inches, a car display at seven, and a desktop notification at two.
/// The largest of those decides it, and 512 covers all of them without
/// making a phone hold a megabyte per track change.
///
/// Declared here rather than in each half of the conditional import,
/// which is where it started: the native half bakes it into the cache
/// file's name, so two declarations would let a change on one side leave
/// the other asking for a different size with nothing to catch it.
const int kMediaSessionArtRung = 512;
