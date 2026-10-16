import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'exchange.dart';
import 'verdict.dart';

/// What [url] says about itself, asked with a GET from the top (see
/// [probeRange]) and read the way `interpretProbe` reads every answer.
///
/// The probe behind the engine's fault classification, not a download:
/// the status is read and the connection dropped, so a server that
/// ignores the range - a live stream, whose body never ends - costs
/// headers, never a body. A body is read only where `probeReadsBody`
/// says it can carry the server's refusal. A GET rather than HEAD, which
/// media servers refuse often enough to make its no an answer about the
/// method instead of the URL. Given [segmentAt], [url] is an HLS
/// presentation and the segment holding that position is what is asked
/// (see `askThrough`).
///
/// A 2xx is [StreamProbe.answered] and a 415 or 422 is
/// [StreamProbe.unplayable] - the statuses whose meaning is the entity
/// rather than the exchange, so a host answering one is saying it will
/// not serve this as audio however often it is asked. Read from any host,
/// not only ours: the engine is handed radio URLs and podcast enclosures
/// on the same call, and a 415 says the same thing wherever it comes
/// from. Our own sidecar is where it comes from most
/// (`unsupported-format`), and there it can be the file or the shape
/// asked for - a distinction the caller cannot act on differently. Where
/// that refusal is true of a whole library rather than one file, the
/// consecutive-skip cap in the session is what stops the queue and says
/// so, rather than this reading a misconfiguration as one bad rip.
///
/// Every other status is [StreamProbe.unreachable] on purpose: a 404 is
/// an item that moved mid-scan, a 5xx the server's own trouble, and
/// neither is the file's fault to skip for. The server's refusals - a
/// media token to re-mint, a source to re-resolve, the transcode cap, the
/// engine away - ride along in its own words.
///
/// `file:` URLs answer whether the file exists. Everything else - a
/// scheme this cannot ask, a TLS refusal, the [deadline] - answers
/// unreachable, and nothing here throws: the caller is inside an error
/// path already.
Future<ProbeAnswer> askStream(
  String url, {
  Duration deadline = probeDeadline,
  Duration? segmentAt,
}) async {
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    return ProbeAnswer.unreachable;
  }
  if (uri.isScheme('file')) {
    try {
      return File.fromUri(uri).existsSync()
          ? const ProbeAnswer(StreamProbe.answered)
          : ProbeAnswer.unreachable;
    } on Object {
      return ProbeAnswer.unreachable;
    }
  }
  if (!uri.isScheme('http') && !uri.isScheme('https')) {
    return ProbeAnswer.unreachable;
  }
  final client = HttpClient()..connectionTimeout = deadline;
  try {
    // One timeout around the whole exchange rather than one per request,
    // so the deadline is the answer's bound and not a multiple of it.
    // Nothing cancels an HTTP request mid-flight, so the close below is
    // what actually drops a socket the deadline gave up on.
    return await askThrough(
      (uri) => _get(client, uri),
      uri,
      segmentAt: segmentAt,
    ).timeout(deadline);
  } on Object {
    return ProbeAnswer.unreachable;
  } finally {
    client.close(force: true);
  }
}

Future<ProbeReply> _get(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.rangeHeader, probeRange);
  return _Reply(await request.close());
}

class _Reply implements ProbeReply {
  _Reply(this._response);

  final HttpClientResponse _response;

  @override
  int get status => _response.statusCode;

  @override
  String? get contentType =>
      _response.headers.value(HttpHeaders.contentTypeHeader);

  @override
  Stream<String> get lines => _response
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());
}
