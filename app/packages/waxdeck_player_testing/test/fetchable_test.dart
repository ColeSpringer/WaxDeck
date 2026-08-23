import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// The io half of the reachability probe, against real sockets. What
/// this calls fetchable is what the engine will call the file's own
/// fault, so the edges - a range ignored, a stream that never ends, a
/// server that never answers - are pinned rather than assumed.
void main() {
  Future<HttpServer> serve(void Function(HttpRequest) handler) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handler);
    addTearDown(() => server.close(force: true));
    return server;
  }

  String urlOf(HttpServer server, [String path = '/a.mp3']) =>
      'http://127.0.0.1:${server.port}$path';

  test('a server that honours the range answers true', () async {
    final server = await serve((req) {
      expect(req.headers.value(HttpHeaders.rangeHeader), 'bytes=0-0');
      req.response.statusCode = HttpStatus.partialContent;
      req.response.add(const <int>[0x00]);
      req.response.close();
    });
    expect(await fetchable(urlOf(server)), isTrue);
  });

  test('a range ignored costs headers, never the body', () async {
    // An Icecast-style live stream: a 200, headers, and a body that
    // never ends. True is only reachable by reading the status and
    // hanging up - a probe that drained would sit on this until the
    // deadline turned it false.
    final server = await serve((req) async {
      req.response.statusCode = HttpStatus.ok;
      req.response.add(List<int>.filled(1024, 0));
      await req.response.flush();
      // The body stays open, as a live stream's would.
    });
    expect(
      await fetchable(urlOf(server), deadline: const Duration(seconds: 5)),
      isTrue,
    );
  });

  test('an error status is not fetchable', () async {
    // A 404 is a server working fine and an item not being there:
    // not proof the bytes are bad, so the engine's safe default has to
    // stand. Same for the server's own failures.
    final server = await serve((req) {
      req.response.statusCode = req.uri.path.contains('gone')
          ? HttpStatus.notFound
          : HttpStatus.internalServerError;
      req.response.close();
    });
    expect(await fetchable(urlOf(server, '/gone.mp3')), isFalse);
    expect(await fetchable(urlOf(server, '/broken.mp3')), isFalse);
  });

  test('a redirect is followed to its answer', () async {
    late HttpServer server;
    server = await serve((req) {
      if (req.uri.path == '/moved.mp3') {
        req.response.statusCode = HttpStatus.found;
        req.response.headers.set(
          HttpHeaders.locationHeader,
          urlOf(server, '/here.mp3'),
        );
      } else {
        req.response.statusCode = HttpStatus.partialContent;
      }
      req.response.close();
    });
    expect(await fetchable(urlOf(server, '/moved.mp3')), isTrue);
  });

  test('a refused connection is not fetchable', () async {
    // Bind-then-close, for a port with nothing behind it.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    expect(await fetchable('http://127.0.0.1:$port/a.mp3'), isFalse);
  });

  test('a server that never answers is false at the deadline', () async {
    final server = await serve((req) {
      // Accept and say nothing.
    });
    final elapsed = Stopwatch()..start();
    expect(
      await fetchable(
        urlOf(server),
        deadline: const Duration(milliseconds: 400),
      ),
      isFalse,
    );
    // Generous: the point is that the deadline cut it loose, not a
    // socket default measured in minutes.
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('a file answers whether it exists', () async {
    final dir = Directory.systemTemp.createTempSync('fetchable');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/a.mp3')..writeAsBytesSync(const <int>[0]);
    expect(await fetchable(file.uri.toString()), isTrue);
    expect(await fetchable('${dir.uri}absent.mp3'), isFalse);
  });

  test('a scheme the probe cannot ask is not fetchable', () async {
    expect(await fetchable('asset:///tones/a.mp3'), isFalse);
    expect(await fetchable('not a url at all'), isFalse);
  });
}
