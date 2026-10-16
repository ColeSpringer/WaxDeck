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

  Future<StreamProbe> verdictOf(String url, {Duration? deadline}) async =>
      (await (deadline == null
              ? askStream(url)
              : askStream(url, deadline: deadline)))
          .verdict;

  test('a server that honours the range answers', () async {
    final server = await serve((req) {
      expect(req.headers.value(HttpHeaders.rangeHeader), 'bytes=0-');
      req.response.statusCode = HttpStatus.partialContent;
      req.response.add(const <int>[0x00]);
      req.response.close();
    });
    expect(await verdictOf(urlOf(server)), StreamProbe.answered);
  });

  test('a live transcode, which takes no other range, answers', () async {
    // The sidecar answers 416 to any range but the whole stream from the
    // top, so a one-byte range read every healthy transcode as dead.
    final server = await serve((req) async {
      final whole = req.headers.value(HttpHeaders.rangeHeader) == 'bytes=0-';
      req.response.statusCode = whole
          ? HttpStatus.ok
          : HttpStatus.requestedRangeNotSatisfiable;
      if (whole) {
        req.response.add(List<int>.filled(1024, 0));
        await req.response.flush();
      } else {
        await req.response.close();
      }
    });
    expect(
      await verdictOf(urlOf(server), deadline: const Duration(seconds: 5)),
      StreamProbe.answered,
    );
  });

  test('a refusal comes back in the server\'s own words', () async {
    final server = await serve((req) {
      req.response.statusCode = HttpStatus.tooManyRequests;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        '{"code":"transcode-limited","message":"too many streams"}',
      );
      req.response.close();
    });
    final answer = await askStream(urlOf(server));
    expect(answer.verdict, StreamProbe.unreachable);
    expect(answer.refusal?.status, 429);
    expect(answer.refusal?.code, 'transcode-limited');
    expect(answer.refusal?.message, 'too many streams');
  });

  test('a body the probe has no use for is never waited on', () async {
    // A proxy's error page, a 404's: nothing in either changes the answer,
    // so a body that never ends costs the status line and no more.
    final server = await serve((req) async {
      req.response.statusCode = req.uri.path == '/page.mp3'
          ? HttpStatus.badGateway
          : HttpStatus.notFound;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<html>');
      await req.response.flush();
      // The body stays open.
    });
    for (final path in <String>['/page.mp3', '/gone.mp3']) {
      final elapsed = Stopwatch()..start();
      final answer = await askStream(
        urlOf(server, path),
        deadline: const Duration(seconds: 5),
      );
      expect(answer.verdict, StreamProbe.unreachable, reason: path);
      expect(answer.refusal, isNull, reason: path);
      expect(
        elapsed.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: path,
      );
    }
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
      await verdictOf(urlOf(server), deadline: const Duration(seconds: 5)),
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
        await verdictOf(urlOf(server, path)),
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
      await verdictOf(urlOf(server, '/garbage.flac')),
      StreamProbe.unplayable,
    );
  });

  test('a 422 is the server finding the file damaged', () async {
    final server = await serve((req) {
      req.response.statusCode = HttpStatus.unprocessableEntity;
      req.response.write('{"code":"malformed-input"}');
      req.response.close();
    });
    expect(
      await verdictOf(urlOf(server, '/damaged.flac')),
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
    expect(await verdictOf(urlOf(server, '/moved.mp3')), StreamProbe.answered);
  });

  test('a refused connection reaches nothing', () async {
    // Bind-then-close, for a port with nothing behind it.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    expect(
      await verdictOf('http://127.0.0.1:$port/a.mp3'),
      StreamProbe.unreachable,
    );
  });

  test('a server that never answers gives up at the deadline', () async {
    final server = await serve((req) {
      // Accept and say nothing.
    });
    final elapsed = Stopwatch()..start();
    expect(
      await verdictOf(
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

  group('an HLS presentation', () {
    // Served the way the server hands an item's rendering out: a master
    // naming one variant, the variant listing four-second segments, and a
    // busy engine refusing segments while both playlists, a string build,
    // still answer.
    Future<({String url, List<String> asked})> presentation({
      int masterStatus = HttpStatus.ok,
      String? master,
      int refuseFrom = 1 << 30,
    }) async {
      final asked = <String>[];
      final server = await serve((req) async {
        final path = req.uri.path;
        asked.add(path);
        final response = req.response;
        final segment = RegExp(r'/seg/(\d+)\.m4s$').firstMatch(path);
        if (path.endsWith('/master.m3u8')) {
          response.statusCode = masterStatus;
          if (masterStatus != HttpStatus.ok) {
            response.headers.contentType = ContentType.json;
            response.write(
              '{"code":"unauthenticated",'
              '"message":"invalid or expired media token"}',
            );
          } else {
            response.write(
              master ??
                  '#EXTM3U\n'
                      '#EXT-X-STREAM-INF:BANDWIDTH=160000,CODECS="opus"\n'
                      'media.m3u8?c=v&mt=t\n',
            );
          }
        } else if (path.endsWith('/media.m3u8')) {
          response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:4\n'
            '#EXT-X-MAP:URI="init.mp4?c=i&mt=t"\n'
            '${[for (var n = 0; n < 5; n++) '#EXTINF:4.000,\nseg/$n.m4s?c=s&mt=t\n'].join()}'
            '#EXT-X-ENDLIST\n',
          );
        } else if (segment != null && int.parse(segment[1]!) >= refuseFrom) {
          response.statusCode = HttpStatus.tooManyRequests;
          response.headers.contentType = ContentType.json;
          response.write(
            '{"code":"transcode-limited",'
            '"message":"the streaming engine is busy; retry shortly"}',
          );
        } else {
          expect(req.headers.value(HttpHeaders.rangeHeader), 'bytes=0-');
          response.add(List<int>.filled(64, 0));
        }
        await response.close();
      });
      return (
        url: '${urlOf(server, '/media/hls/master.m3u8')}?it=k&mt=t',
        asked: asked,
      );
    }

    test('is asked at the segment holding the position', () async {
      final served = await presentation(refuseFrom: 2);
      final answer = await askStream(
        served.url,
        segmentAt: const Duration(seconds: 9),
      );
      expect(answer.refusal?.code, 'transcode-limited');
      expect(served.asked, <String>[
        '/media/hls/master.m3u8',
        '/media/hls/media.m3u8',
        '/media/hls/seg/2.m4s',
      ]);
    });

    test('answers when the segment does', () async {
      final served = await presentation(refuseFrom: 3);
      final answer = await askStream(
        served.url,
        segmentAt: const Duration(seconds: 9),
      );
      expect(answer.verdict, StreamProbe.answered);
      expect(answer.refusal, isNull);
    });

    test('past its end, asks the last segment', () async {
      final served = await presentation();
      await askStream(served.url, segmentAt: const Duration(hours: 1));
      expect(served.asked.last, '/media/hls/seg/4.m4s');
    });

    test('a playlist that refuses is the answer', () async {
      final served = await presentation(masterStatus: HttpStatus.unauthorized);
      final answer = await askStream(
        served.url,
        segmentAt: const Duration(seconds: 9),
      );
      expect(answer.refusal?.stale, isTrue);
      expect(served.asked, <String>['/media/hls/master.m3u8']);
    });

    test('a playlist it cannot read leaves its own answer standing', () async {
      final served = await presentation(master: 'not a playlist\n');
      final answer = await askStream(
        served.url,
        segmentAt: const Duration(seconds: 9),
      );
      expect(answer.verdict, StreamProbe.answered);
      expect(served.asked, <String>['/media/hls/master.m3u8']);
    });

    test('is asked as itself without a position', () async {
      final served = await presentation(refuseFrom: 0);
      final answer = await askStream(served.url);
      expect(answer.verdict, StreamProbe.answered);
      expect(served.asked, <String>['/media/hls/master.m3u8']);
    });
  });

  test('a file answers whether it exists', () async {
    final dir = Directory.systemTemp.createTempSync('stream_probe');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/a.mp3')..writeAsBytesSync(const <int>[0]);
    expect(await verdictOf(file.uri.toString()), StreamProbe.answered);
    expect(await verdictOf('${dir.uri}absent.mp3'), StreamProbe.unreachable);
  });

  test('a scheme the probe cannot ask reaches nothing', () async {
    expect(await verdictOf('asset:///tones/a.mp3'), StreamProbe.unreachable);
    expect(await verdictOf('not a url at all'), StreamProbe.unreachable);
  });
}
