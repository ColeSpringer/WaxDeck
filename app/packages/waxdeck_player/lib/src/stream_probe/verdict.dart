import 'dart:convert';

/// What a probe found at the other end of a stream URL. Three answers,
/// because a server can refuse the file itself (a 415 or 422) rather than
/// the way to it.
enum StreamProbe {
  /// The URL answered with bytes.
  answered,

  /// The server would not make audio out of the file: our sidecar's 415
  /// for `unsupported-format` or 422 for `malformed-input`. No number of
  /// retries makes this URL play.
  unplayable,

  /// Nothing usable came back: a status that is neither, a refused
  /// connection, a scheme this cannot ask, the deadline.
  unreachable;

  /// Whether this verdict puts a failure on the media rather than on the
  /// way to it.
  ///
  /// Written as the verdicts that say yes rather than as "not
  /// unreachable", because the module's rule is that only positive
  /// evidence answers `MediaFault.source` - the answer that moves a
  /// queue. A switch over the enum makes a verdict added later a compile
  /// error here rather than a silent skip.
  ///
  /// The two that can are different evidence for one conclusion. A server
  /// calling the file unplayable reached that verdict itself, so it is
  /// the file wherever it is read. An answered URL says the bytes were
  /// there and the player still could not finish, which is what garbage
  /// on disk looks like from out here - but only where the failure could
  /// not have been the way to them, which is what [strict] says it could.
  bool blames({required bool strict}) => switch (this) {
    StreamProbe.unplayable => true,
    StreamProbe.answered => !strict,
    StreamProbe.unreachable => false,
  };
}

/// A server's refusal of a stream fetch, in its own words: the status, and
/// the code, message and params of WaxDeck's error envelope.
///
/// Plain Dart, no API types, so the player package stays independent of the
/// client library; the app turns this into its own exception.
class StreamRefusal {
  const StreamRefusal({
    required this.status,
    this.code,
    this.message,
    this.params,
  });

  final int status;
  final String? code;
  final String? message;
  final Map<String, String>? params;

  /// The URL's credential lapsed or its source moved: a fresh mint is the
  /// cure, and nothing is wrong with the item.
  bool get stale => status == 401 || status == 410;

  /// The server could not reach its streaming engine: the 502 `internal`
  /// it answers a stream, a joined stream, or a rendering's playlist or
  /// segment with while the engine is away. A fresh mint may route around
  /// it (play-info hands out the original's bytes while the engine is
  /// down). A 502 in other words is a host behind the server, a podcast's
  /// or a station's, which another mint reaches no better.
  bool get engineDown => status == 502 && code == 'internal';

  @override
  String toString() =>
      'StreamRefusal($status ${code ?? '-'}: ${message ?? ''})';
}

/// One probe's reading: the verdict, plus the server's refusal when the
/// answer was one.
class ProbeAnswer {
  const ProbeAnswer(this.verdict, [this.refusal]);

  /// Nothing usable came back, and nothing said why.
  static const unreachable = ProbeAnswer(StreamProbe.unreachable);

  final StreamProbe verdict;
  final StreamRefusal? refusal;
}

/// Reads one answer to a probe the same way on every platform: its
/// status, the type of what came back, and its body where
/// [probeReadsBody] says one is worth reading.
///
/// A 2xx is the URL answering, unless what answered is a page (a captive
/// portal, a proxy's sign-in) where media was asked for. A 415 or 422 is
/// a server refusing the file itself, whoever answers it. The refusals are
/// the statuses a client acts on differently from a dead URL - an expired
/// token or a moved source (re-mint), the transcode cap (say so, never
/// skip), the engine away (re-mint around it) - and only when the body is
/// WaxDeck's own envelope (the spec's `Error`: a `code` and a `message`).
/// The same status on a proxy's or a portal's page explains nothing, so it
/// reads as a URL that did not answer.
ProbeAnswer interpretProbe(int status, {String? contentType, String? body}) {
  if (status >= 200 && status < 300) {
    return _pages.contains(_mediaType(contentType))
        ? ProbeAnswer.unreachable
        : const ProbeAnswer(StreamProbe.answered);
  }
  if (status == 415 || status == 422) {
    return const ProbeAnswer(StreamProbe.unplayable);
  }
  if (!probeReadsBody(status, contentType)) return ProbeAnswer.unreachable;
  final envelope = _envelope(body);
  if (envelope == null) return ProbeAnswer.unreachable;
  return ProbeAnswer(
    StreamProbe.unreachable,
    StreamRefusal(
      status: status,
      code: envelope.code,
      message: envelope.message,
      params: envelope.params,
    ),
  );
}

/// Whether [interpretProbe] reads the body of an answer: a refusal status
/// served as JSON, which is how the server sends its envelope. No other
/// body is worth the wait, so neither probe half reads one.
bool probeReadsBody(int status, String? contentType) {
  if (!_refusals.contains(status)) return false;
  final type = _mediaType(contentType);
  return type != null && (type == 'application/json' || type.endsWith('+json'));
}

/// The statuses whose envelope a client acts on: see [interpretProbe].
const Set<int> _refusals = <int>{401, 410, 429, 502, 503};

/// What a browser would draw rather than play.
const Set<String> _pages = <String>{'text/html', 'application/xhtml+xml'};

String? _mediaType(String? contentType) =>
    contentType?.split(';').first.trim().toLowerCase();

({String code, String message, Map<String, String>? params})? _envelope(
  String? body,
) {
  if (body == null || body.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  if (decoded case {
    'code': final String code,
    'message': final String message,
  }) {
    final params = switch (decoded['params']) {
      final Map<String, Object?> map => <String, String>{
        for (final entry in map.entries)
          if (entry.value case final String value) entry.key: value,
      },
      _ => null,
    };
    return (code: code, message: message, params: params);
  }
  return null;
}
