import 'dart:async';
import 'dart:io';

import '../oidc_flow.dart';

/// Binds a real localhost listener on an ephemeral port for the desktop
/// OIDC flow.
Future<LoopbackReceiverPort> bindLoopbackReceiver() =>
    IoLoopbackReceiver.bind();

/// dart:io implementation of [LoopbackReceiverPort]: serves the tiny
/// "you can close this tab" page on /callback and hands over the code.
class IoLoopbackReceiver implements LoopbackReceiverPort {
  IoLoopbackReceiver._(this._server) {
    _sub = _server.listen(_handle);
  }

  static Future<IoLoopbackReceiver> bind() async {
    // Loopback only: the code must never be reachable off this machine.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return IoLoopbackReceiver._(server);
  }

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _sub;
  final _code = Completer<String>();

  @override
  int get port => _server.port;

  @override
  Future<String> get code => _code.future;

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final delivered = request.uri.queryParameters['code'];
    if (request.uri.path == '/callback' && delivered != null) {
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.html;
      response.write(
        '<!doctype html><meta charset="utf-8"><title>WaxDeck</title>'
        '<body style="font-family: sans-serif; text-align: center; '
        'padding-top: 4em;">'
        '<h1>Signed in</h1>'
        '<p>You can close this tab and return to WaxDeck.</p></body>',
      );
      if (!_code.isCompleted) _code.complete(delivered);
    } else {
      response.statusCode = HttpStatus.notFound;
      response.write('not found');
    }
    await response.close();
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _server.close(force: true);
  }
}
