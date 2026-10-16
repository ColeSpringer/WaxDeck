import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'exchange.dart';
import 'verdict.dart';

/// Web build of the stream probe: a same-origin fetch of the URL that
/// failed, read the way `interpretProbe` reads every answer.
///
/// The media element hides why a fetch failed (a 401, a 429 and a codec
/// it lacks are all `MediaError` 4), so this asks the URL directly. Only
/// this origin: a cross-origin GET is CORS-gated where the element is
/// not, so there an unreachable would mean unaskable. The deployed web
/// build is always same-origin. A dev server on another port asks nothing
/// and answers unreachable, so only the element's own code decides there:
/// a decode error is still the file, while a failed first fetch stays on
/// the retry pane rather than stepping past the item, and no refusal - an
/// expired token, the transcode cap - is ever read.
Future<ProbeAnswer> askStream(
  String url, {
  Duration deadline = probeDeadline,
  Duration? segmentAt,
}) async {
  final Uri target;
  try {
    target = Uri.base.resolve(url);
    if (!target.isScheme('http') && !target.isScheme('https')) {
      return ProbeAnswer.unreachable;
    }
    if (target.origin != Uri.base.origin) return ProbeAnswer.unreachable;
  } on Object {
    return ProbeAnswer.unreachable;
  }
  final abort = web.AbortController();
  // A closure, not a tear-off: interop members cannot be torn off.
  final timer = Timer(deadline, () => abort.abort());
  try {
    return await askThrough(
      (uri) => _get(uri, abort.signal),
      target,
      segmentAt: segmentAt,
    );
  } on Object {
    return ProbeAnswer.unreachable;
  } finally {
    timer.cancel();
    // Hangs up on a body nobody reads: a live transcode's never ends, and
    // the listener's slot on the server is released when the connection
    // goes (the engine's own encode runs on; see [probeRange]).
    abort.abort();
  }
}

Future<ProbeReply> _get(Uri uri, web.AbortSignal signal) async {
  final headers = web.Headers()..append('Range', probeRange);
  final response = await web.window
      .fetch(
        uri.toString().toJS,
        web.RequestInit(
          headers: headers,
          cache: 'no-store',
          credentials: 'same-origin',
          signal: signal,
        ),
      )
      .toDart;
  return _Reply(response);
}

class _Reply implements ProbeReply {
  _Reply(this._response);

  final web.Response _response;

  @override
  int get status => _response.status;

  @override
  String? get contentType => _response.headers.get('content-type');

  @override
  Stream<String> get lines => Stream.fromFuture(
    _response.text().toDart,
  ).expand((text) => LineSplitter.split(text.toDart));
}
