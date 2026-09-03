import 'verdict.dart';

/// Web build of the stream probe: nothing is ever reached.
///
/// Not because a browser could not ask, but because the answer would
/// say less there: the web classifier already carries a verdict per
/// `MediaError` code (2 is the network saying so itself), and a
/// cross-origin GET is CORS-gated in ways the media element is not, so
/// an unreachable from here would read as unreachable when it means
/// unaskable. Answering unreachable keeps the code's own verdict
/// standing.
Future<StreamProbe> probeStream(
  String url, {
  Duration deadline = const Duration(seconds: 3),
}) async => StreamProbe.unreachable;
