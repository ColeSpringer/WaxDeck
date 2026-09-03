import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// The io half of the stream probe, against real sockets. What this
/// blames on the media is what the engine will call the file's own
/// fault and step a queue past, so the edges - a range ignored, a
/// stream that never ends, a server that refuses the file, a server
/// that never answers - are pinned rather than assumed.
void main() {
  Future<HttpServer> serve(void Function(HttpRequest) handler) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handler);
    addTearDown(() => server.close(force: true));
    return server;
  }

  String urlOf(HttpServer server, [String path = '/a.mp3']) =>
      'http://127.0.0.1:${server.port}$path';

  test('a server that honours the range answers', () async {
    final server = await serve((req) {
      expect(req.headers.value(HttpHeaders.rangeHeader), 'bytes=0-0');
      req.response.statusCode = HttpStatus.partialContent;
      req.response.add(const <int>[0x00]);
      req.response.close();
    });
    expect(await probeStream(urlOf(server)), StreamProbe.answered);
  });

  test('a range ignored costs headers, never the body', () async {
    // An Icecast-style live stream: a 200, headers, and a body that
    // never ends. An answer is only reachable by reading the status
    // and hanging up - a probe that drained would sit on this until
    // the deadline called it unreachable.
    final server = await serve((req) async {
      req.response.statusCode = HttpStatus.ok;
      req.response.add(List<int>.filled(1024, 0));
      await req.response.flush();
      // The body stays open, as a live stream's would.
    });
    expect(
      await probeStream(urlOf(server), deadline: const Duration(seconds: 5)),
      StreamProbe.answered,
    );
  });

  test('an error status short of a refusal reaches nothing', () async {
    // A 404 is a server working fine and an item not being there:
    // not proof the bytes are bad, so the engine's safe default has to
    // stand. Same for the server's own failures, for an expired media
    // token, and for a source that moved under a minted URL - each is
    // a state that changes, and none of them is a track to skip.
    final server = await serve((req) {
      req.response.statusCode = switch (req.uri.path) {
        '/gone.mp3' => HttpStatus.notFound,
        '/stale.mp3' => HttpStatus.unauthorized,
        '/moved.mp3' => HttpStatus.gone,
        _ => HttpStatus.internalServerError,
      };
      req.response.close();
    });
    for (final path in <String>[
      '/gone.mp3',
      '/stale.mp3',
      '/moved.mp3',
      '/broken.mp3',
    ]) {
      expect(
        await probeStream(urlOf(server, path)),
        StreamProbe.unreachable,
        reason: path,
      );
    }
  });

  test('a 415 is the server refusing the file itself', () async {
    // The one status that is a verdict about the bytes: the sidecar
    // answers `unsupported-format` when its decoder will not take the
    // file, and a load that died waiting on mpv for the same file is
    // the same file twice. Read as the media, so a queue steps past it
    // instead of standing on a retry that cannot come out differently.
    final server = await serve((req) {
      req.response.statusCode = HttpStatus.unsupportedMediaType;
      req.response.write('{"code":"unsupported-format"}');
      req.response.close();
    });
    expect(
      await probeStream(urlOf(server, '/garbage.flac')),
      StreamProbe.unplayable,
    );
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
    expect(
      await probeStream(urlOf(server, '/moved.mp3')),
      StreamProbe.answered,
    );
  });

  test('a refused connection reaches nothing', () async {
    // Bind-then-close, for a port with nothing behind it.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    expect(
      await probeStream('http://127.0.0.1:$port/a.mp3'),
      StreamProbe.unreachable,
    );
  });

  test('a server that never answers gives up at the deadline', () async {
    final server = await serve((req) {
      // Accept and say nothing.
    });
    final elapsed = Stopwatch()..start();
    expect(
      await probeStream(
        urlOf(server),
        deadline: const Duration(milliseconds: 400),
      ),
      StreamProbe.unreachable,
    );
    // The deadline bounds the whole probe, connect and answer together,
    // rather than each stage separately. Still generous against a
    // loaded machine: what would fail here is a probe that went back to
    // spending the deadline per stage, or a socket default measured in
    // minutes.
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a file answers whether it exists', () async {
    final dir = Directory.systemTemp.createTempSync('stream_probe');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/a.mp3')..writeAsBytesSync(const <int>[0]);
    expect(await probeStream(file.uri.toString()), StreamProbe.answered);
    expect(await probeStream('${dir.uri}absent.mp3'), StreamProbe.unreachable);
  });

  test('a scheme the probe cannot ask reaches nothing', () async {
    expect(await probeStream('asset:///tones/a.mp3'), StreamProbe.unreachable);
    expect(await probeStream('not a url at all'), StreamProbe.unreachable);
  });
}
