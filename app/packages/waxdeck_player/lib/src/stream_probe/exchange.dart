/// One probe as both halves make it: which GETs go out, in what order,
/// and what each answer is read for. A half supplies only its transport,
/// `dart:io`'s client or the browser's fetch.
library;

import 'dart:async';

import 'verdict.dart';

/// How long one probe may take, every request in it together.
///
/// A whole-probe bound rather than a per-stage one: this is read on a
/// path that has already failed, and on desktop it is read *after* the
/// engine's load deadline and the stop that follows, so every second
/// here is one more the listener spends in silence before the pane or
/// the skip.
const Duration probeDeadline = Duration(seconds: 3);

/// The range every probe GET asks for: the whole entity, from the top.
///
/// The one request that reaches every answer the streaming engine gives.
/// It answers a HEAD from the plan and any other range with a 416, both
/// before it admits a live encode, so neither can meet its overload, the
/// refusal a busy engine gives a failed load. The price is that an
/// uncached encode the probe reaches runs on after the probe hangs up,
/// as every read-behind encode does (asked of the engine upstream).
const String probeRange = 'bytes=0-';

/// What the engine asks about media that failed: [url] itself, or, given
/// [segmentAt], the segment holding that position in the HLS presentation
/// [url] names (see [askThrough]).
typedef StreamAsk =
    Future<ProbeAnswer> Function(String url, {Duration? segmentAt});

/// One answer to a probe GET, as a half's transport reads it.
abstract interface class ProbeReply {
  int get status;
  String? get contentType;

  /// The body a line at a time, fetched only as far as it is read.
  Stream<String> get lines;
}

/// One probe GET of a URL, asking for [probeRange].
typedef ProbeGet = Future<ProbeReply> Function(Uri uri);

/// Asks [uri] through [get] and reads the answer (see `interpretProbe`).
///
/// Given [segmentAt], [uri] is an HLS presentation, and what is asked is
/// the segment holding that position. Its playlists are a string build the
/// engine answers whatever its slots are doing, while every refusal that
/// is the engine's own (the busy one above all) is met on a segment: so
/// the master, its first variant, and then the segment, three requests
/// under the one deadline. A playlist that refuses is the answer, and one
/// this cannot read leaves its own answer standing.
Future<ProbeAnswer> askThrough(
  ProbeGet get,
  Uri uri, {
  Duration? segmentAt,
}) async {
  var at = uri;
  var reply = await get(at);
  if (segmentAt != null) {
    for (var hop = 0; hop < 2 && _answered(reply); hop++) {
      final next = await _next(at, reply.lines, segmentAt);
      if (next == null) break;
      at = next;
      reply = await get(at);
    }
  }
  final body = probeReadsBody(reply.status, reply.contentType)
      ? await _envelope(reply.lines)
      : null;
  return interpretProbe(
    reply.status,
    contentType: reply.contentType,
    body: body,
  );
}

bool _answered(ProbeReply reply) =>
    interpretProbe(reply.status, contentType: reply.contentType).verdict ==
    StreamProbe.answered;

/// Where a playlist leads for a position [at]: a master's first variant,
/// or the segment of a media playlist that holds [at] (its last, for a
/// position past the end). Null for anything else. Reads only as far as
/// the answer.
Future<Uri?> _next(Uri playlist, Stream<String> lines, Duration at) async {
  var variant = false;
  Duration? length;
  var end = Duration.zero;
  Uri? last;
  await for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXT-X-STREAM-INF')) {
      variant = true;
    } else if (line.startsWith('#EXTINF:')) {
      final seconds = double.tryParse(
        line.substring('#EXTINF:'.length).split(',').first,
      );
      length = seconds == null
          ? null
          : Duration(microseconds: (seconds * 1e6).round());
    } else if (!line.startsWith('#')) {
      final uri = playlist.resolve(line);
      if (variant) return uri;
      final segment = length;
      if (segment == null) continue;
      length = null;
      last = uri;
      end += segment;
      if (end > at) return uri;
    }
  }
  return last;
}

/// An error envelope is a few hundred bytes; never more than this.
Future<String> _envelope(Stream<String> lines) async {
  final text = StringBuffer();
  await for (final line in lines) {
    text.writeln(line);
    if (text.length >= 4096) break;
  }
  return text.toString();
}
