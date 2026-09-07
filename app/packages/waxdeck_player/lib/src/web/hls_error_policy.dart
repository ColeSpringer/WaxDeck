/// What an hls.js error means for the stream carrying it.
///
/// Pure, and kept apart from the engine on purpose: the engine is
/// browser-only, so the one decision in it worth a unit test - which
/// errors are the file's fault and which are the browser's - has to
/// live where the VM can run it.
enum HlsErrorKind {
  /// The server's session cap (429). Re-minting does not help: the
  /// ordinary path sits under the same limit.
  refused,

  /// The rendering is gone (401, 404, 410): the token aged out, the
  /// render was let go, the files moved. Mint again.
  gone,

  /// This browser cannot play this rendering - a codec question, which
  /// no retry answers and no other rendering of the same run will.
  unplayable,

  /// The browser's media pipeline hiccuped: a buffer that would not
  /// append, a fragment that would not parse once, a stall under load.
  /// Says nothing about the file; hls.js documents recovering these in
  /// place, and that is what happens before anything else is tried.
  media,

  /// Everything else fatal: the fetch, the network.
  transport,
}

/// The codec-shaped media errors, which are the only ones that mean
/// the rendering itself cannot be played here. hls.js's own names.
const Set<String> _unplayableDetails = <String>{
  'bufferAddCodecError',
  'bufferIncompatibleCodecsError',
  'manifestIncompatibleCodecsError',
};

/// Reads an hls.js error's meaning off the fields it sends: the HTTP
/// [status] a fetch answered, when there was one, then the error's
/// [type] and its [details].
///
/// The status wins over the type. A fetch that answered 404 is a
/// rendering that is gone however hls.js filed the consequence, and a
/// 429 is the cap whether it surfaced as a network error or, on the
/// way to the buffer, as a media one.
HlsErrorKind hlsErrorKind({
  int? status,
  required String type,
  String details = '',
}) {
  if (status == 429) return HlsErrorKind.refused;
  if (status == 401 || status == 404 || status == 410) {
    return HlsErrorKind.gone;
  }
  if (type == 'mediaError') {
    return _unplayableDetails.contains(details)
        ? HlsErrorKind.unplayable
        : HlsErrorKind.media;
  }
  return HlsErrorKind.transport;
}
