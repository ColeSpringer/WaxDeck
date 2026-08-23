import 'dart:async';
import 'dart:io';

/// How long [fetchable] spends before answering false. The answer is
/// read on a path that has already failed, where every second is one
/// the listener waits in silence for the pane or the skip.
const Duration _fetchableDeadline = Duration(seconds: 3);

/// Whether [url] answers at all, asked with one ranged GET.
///
/// This is the reachability probe behind the engine's fault refinement
/// (`probedMediaFaultOf`), not a download: the response's status is
/// read and the connection dropped, so a server that ignores the range
/// - a live stream, whose body never ends - costs headers, never a
/// body. A ranged GET rather than HEAD, which media servers refuse
/// often enough to make its no an answer about the method instead of
/// the URL.
///
/// `file:` URLs answer whether the file exists. Everything else - a
/// scheme this cannot ask, a status outside 2xx, a TLS refusal, the
/// [deadline] - answers false, and false never throws: the caller is
/// inside an error path already.
Future<bool> fetchable(
  String url, {
  Duration deadline = _fetchableDeadline,
}) async {
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    return false;
  }
  if (uri.isScheme('file')) {
    try {
      return File.fromUri(uri).existsSync();
    } on Object {
      return false;
    }
  }
  if (!uri.isScheme('http') && !uri.isScheme('https')) return false;
  final client = HttpClient()..connectionTimeout = deadline;
  try {
    final request = await client.getUrl(uri).timeout(deadline);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final response = await request.close().timeout(deadline);
    return response.statusCode >= 200 && response.statusCode < 300;
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}
