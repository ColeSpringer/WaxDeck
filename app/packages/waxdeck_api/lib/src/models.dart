/// The types feature code sees: the models generated from the API spec
/// that a public signature reaches, the few kept by hand, and the
/// client's exception.
library;

export 'gen/public.g.dart';
// The hand codec stays inside the package, as the generated one does.
export 'hand_models.dart'
    show
        M3uLineOutcome,
        M3uPreview,
        M3uPreviewLine,
        PlaybackSessionEntry,
        PlaybackSessionInfo,
        Playlist,
        RuleNode,
        SessionState;

/// Structured API error (the spec's `Error` schema), thrown by the client.
///
/// [code] is the server's own, from the spec's list, or one this package
/// mints where there is none to read: `transport` (the request did not
/// complete, or an answer came that is not the server's, a failed status
/// without an error of the server's or a body that is not JSON at all,
/// with that status), `transport-timeout` (no answer in time, deliberately
/// not the spec's `timeout`, which means a routed command whose endpoint
/// is still connected), `transport-empty` (an answer with no body) and
/// `transport-decode` (an answer that does not read, [message] naming the
/// field), both with the answer's status. Beside them,
/// `timeline-measuring` is the 202 `createQueueTimeline` answers while the
/// server still measures the queue, with the job to poll in
/// `params['job']`. Stable client vocabulary, absent from the spec's list,
/// so a caller wording errors by code covers them alongside it.
class WaxDeckApiException implements Exception {
  const WaxDeckApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.params,
  });

  /// Stable machine-readable code (`unauthenticated`, `not-found`, and so
  /// on), or one of this package's own transport codes.
  final String code;

  /// Human-readable explanation; not stable, never parse it.
  final String message;

  final int? statusCode;

  /// Machine-readable detail for the codes that cover more than one
  /// cause, keyed as the contract documents per code
  /// (`feature-unavailable` carries `feature` and `pid`). Best-effort:
  /// null covers a refusal that mints none and a server older than the
  /// field alike, so refine on it, never require it.
  final Map<String, String>? params;

  /// Whether this is the server out of reach rather than its answer: no
  /// response at all, a 503, or a gateway error without the server's own
  /// error (502 or 504, and a CDN's or tunnel's 521 to 524 and 530), which
  /// is something in front of the server answering for it while it is
  /// down. The one rule the offline outboxes queue on - a refusal is an
  /// answer, and a change the server refused must not wait to be refused
  /// again.
  bool get unreachable => switch (statusCode) {
    null || 503 => true,
    502 || 504 || 521 || 522 || 523 || 524 || 530 => _unworded,
    _ => false,
  };

  /// Whether the server said no: a 4xx in its own words, which no retry
  /// changes. A 4xx without them is something in front of the server
  /// answering (a proxy with no route for the path, a server too old to
  /// have it), which says nothing about what the next ask gets.
  bool get isRefusal {
    final status = statusCode;
    return status != null && status >= 400 && status < 500 && !_unworded;
  }

  /// Whether the server said the thing asked for is not there: its own
  /// `not-found`, however it arrived. A bare 404 is not one.
  bool get isNotFound => code == 'not-found';

  /// An answer that carried no error of the server's, which this package
  /// reports as `transport` with the status it came with.
  bool get _unworded => code == 'transport';

  @override
  String toString() => 'WaxDeckApiException($code, $statusCode): $message';
}

/// The spec's `Error` object as the exception, or null for anything that
/// is not one: an object whose `code` and `message` are both strings.
/// What is not one is the caller's to word, as the fallback it has.
///
/// Public because the shape arrives three ways - an HTTP error body, a
/// refusal inside an answer, a socket error frame - and a refusal that
/// read differently on each would explain itself differently depending
/// on how it got here.
WaxDeckApiException? apiErrorFromWire(Object? raw, {int? statusCode}) {
  if (raw is! Map) return null;
  final code = raw['code'];
  final message = raw['message'];
  if (code is! String || message is! String) return null;
  return WaxDeckApiException(
    code: code,
    message: message,
    statusCode: statusCode,
    params: _errorParams(raw['params']),
  );
}

/// An error's `params` as a plain string map, or null for anything that
/// is not one. A key or value of another type is dropped rather than
/// stringified, and an empty result reads as absent: a caller branches
/// on these, and branching on a guess is worse than taking the fallback.
Map<String, String>? _errorParams(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is String && value is String) out[key] = value;
  }
  return out.isEmpty ? null : out;
}

/// The most pids one item lookup takes, the contract's `maxItems`: a
/// longer list is looked up in pieces of it.
const itemLookupCap = 100;

/// One fully-addressed request a client can hand to the platform on
/// its way out.
///
/// Everything is resolved: the absolute URL, the method, the encoded
/// body, and the headers that authenticate it. Nothing about sending it
/// belongs to this package - a browser tab uses `fetch(keepalive: true)`
/// so the request outlives the document - so this is the shape that
/// crosses the line, not a call.
class ExitRequest {
  const ExitRequest({
    required this.path,
    required this.method,
    required this.body,
    required this.headers,
  });

  final String path;
  final String method;

  /// The already-encoded JSON body.
  final String body;

  /// Everything but `Content-Type`, which the sender adds.
  final Map<String, String> headers;
}
