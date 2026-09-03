import 'dart:async';
import 'dart:io';

import 'verdict.dart';

/// How long one call to [probeStream] may take, connect and answer
/// together.
///
/// A whole-probe bound rather than a per-stage one: this is read on a
/// path that has already failed, and on desktop it is read *after* the
/// engine's load deadline and the stop that follows, so every second
/// here is one more the listener spends in silence before the pane or
/// the skip.
const Duration _probeDeadline = Duration(seconds: 3);

/// What [url] says about itself, asked with one ranged GET.
///
/// This is the probe behind the engine's fault refinement
/// (`probedMediaFaultOf`), not a download: the status is read and the
/// connection dropped, so a server that ignores the range - a live
/// stream, whose body never ends - costs headers, never a body. A
/// ranged GET rather than HEAD, which media servers refuse often enough
/// to make its no an answer about the method instead of the URL.
///
/// A 2xx is [StreamProbe.answered] and a 415 is
/// [StreamProbe.unplayable] - the one status whose meaning is the
/// entity rather than the exchange, so a host answering it is saying it
/// will not serve this as audio however often it is asked. Read from
/// any host, not only ours: the engine is handed radio URLs and podcast
/// enclosures on the same call, and a 415 says the same thing wherever
/// it comes from. Our own sidecar is where it comes from most
/// (`unsupported-format`), and there it can be the file or the shape
/// asked for - a distinction the caller cannot act on differently. Where
/// that refusal is true of a whole library rather than one file, the
/// consecutive-skip cap in the session is what stops the queue and says
/// so, rather than this reading a misconfiguration as one bad rip.
///
/// Every other status stays [StreamProbe.unreachable] on purpose: a 404
/// is an item that moved mid-scan, a 401 is a media token to re-mint, a
/// 410 is a source to re-resolve, a 5xx is the server's own trouble, and
/// none of those is the file's fault to skip for.
///
/// `file:` URLs answer whether the file exists. Everything else - a
/// scheme this cannot ask, a TLS refusal, the [deadline] - answers
/// unreachable, and nothing here throws: the caller is inside an error
/// path already.
Future<StreamProbe> probeStream(
  String url, {
  Duration deadline = _probeDeadline,
}) async {
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    return StreamProbe.unreachable;
  }
  if (uri.isScheme('file')) {
    try {
      return File.fromUri(uri).existsSync()
          ? StreamProbe.answered
          : StreamProbe.unreachable;
    } on Object {
      return StreamProbe.unreachable;
    }
  }
  if (!uri.isScheme('http') && !uri.isScheme('https')) {
    return StreamProbe.unreachable;
  }
  final client = HttpClient()..connectionTimeout = deadline;
  try {
    // One timeout around the whole exchange rather than one per stage,
    // so the deadline is the answer's bound and not a multiple of it.
    // Nothing cancels an HTTP request mid-flight, so the close below is
    // what actually drops a socket the deadline gave up on.
    return await _ask(client, uri).timeout(deadline);
  } on Object {
    return StreamProbe.unreachable;
  } finally {
    client.close(force: true);
  }
}

/// The exchange itself: a ranged GET, and the verdict its status
/// carries.
Future<StreamProbe> _ask(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
  final response = await request.close();
  return switch (response.statusCode) {
    >= 200 && < 300 => StreamProbe.answered,
    HttpStatus.unsupportedMediaType => StreamProbe.unplayable,
    _ => StreamProbe.unreachable,
  };
}
