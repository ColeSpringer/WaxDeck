@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:web/web.dart' as web;

/// The browser's stream probe: a same-origin fetch of the URL the media
/// element failed on, read for the server's refusal. `window.fetch` is
/// stubbed to answer the way WaxDeck's stream endpoint does; what is under
/// test is what is asked and what is read back.
void main() {
  late JSAny? original;
  late List<({String url, String? range, web.AbortSignal? signal})> asked;

  setUp(() {
    original = web.window.getProperty<JSAny?>('fetch'.toJS);
    asked = [];
  });

  tearDown(() => web.window.setProperty('fetch'.toJS, original));

  /// Answers each fetch with what [reply] says for its URL: a status, a
  /// body, and the type the body is served as.
  void answerBy(
    ({int status, String body, String type}) Function(Uri url) reply,
  ) {
    web.window.setProperty(
      'fetch'.toJS,
      ((JSString input, web.RequestInit init) {
        asked.add((
          url: input.toDart,
          range: (init.headers as web.Headers).get('Range'),
          signal: init.signal,
        ));
        final answer = reply(Uri.parse(input.toDart));
        return Future<web.Response>.value(
          web.Response(
            answer.body.toJS,
            web.ResponseInit(
              status: answer.status,
              headers: web.Headers()..append('content-type', answer.type),
            ),
          ),
        ).toJS;
      }).toJS,
    );
  }

  /// Answers every fetch with [status] and [body], served as JSON, which
  /// is how the server sends its refusals.
  void answer(
    int status, [
    String body = '',
    String type = 'application/json',
  ]) => answerBy((_) => (status: status, body: body, type: type));

  test(
    'a same-origin URL is asked from the top and its refusal read',
    () async {
      answer(429, '{"code":"transcode-limited","message":"too many streams"}');
      final read = await askStream('/media/stream?pid=tr-a&mt=x');
      expect(read.verdict, StreamProbe.unreachable);
      expect(read.refusal?.status, 429);
      expect(read.refusal?.code, 'transcode-limited');
      expect(asked.single.range, 'bytes=0-');
      expect(Uri.parse(asked.single.url).path, '/media/stream');
    },
  );

  test('a URL that answers is let go once the headers are read', () async {
    answer(200, 'audio');
    final read = await askStream('/media/stream?pid=tr-a&mt=x');
    expect(read.verdict, StreamProbe.answered);
    expect(
      asked.single.signal?.aborted,
      isTrue,
      reason: 'a live transcode never ends its body, and holds a slot',
    );
  });

  test('an expired token reads as stale', () async {
    answer(401, '{"code":"unauthenticated","message":"expired"}');
    final read = await askStream('/media/stream?pid=tr-a&mt=x');
    expect(read.refusal?.stale, isTrue);
  });

  test('a page in the server\'s place is no refusal', () async {
    answer(429, '<html>Too Many Requests</html>', 'text/html');
    final read = await askStream('/media/stream?pid=tr-a&mt=x');
    expect(read.verdict, StreamProbe.unreachable);
    expect(read.refusal, isNull);
  });

  test('a presentation is asked at the segment holding the position', () async {
    answerBy((url) {
      final path = url.path;
      if (path.endsWith('/master.m3u8')) {
        return (
          status: 200,
          body: '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nmedia.m3u8?c=v\n',
          type: 'application/vnd.apple.mpegurl',
        );
      }
      if (path.endsWith('/media.m3u8')) {
        return (
          status: 200,
          body:
              '#EXTM3U\n#EXTINF:4.0,\nseg/0.m4s?c=s\n'
              '#EXTINF:4.0,\nseg/1.m4s?c=s\n#EXTINF:4.0,\nseg/2.m4s?c=s\n',
          type: 'application/vnd.apple.mpegurl',
        );
      }
      return (
        status: 429,
        body: '{"code":"transcode-limited","message":"busy"}',
        type: 'application/json',
      );
    });
    final read = await askStream(
      '/media/hls/master.m3u8?it=k&mt=t',
      segmentAt: const Duration(seconds: 5),
    );
    expect(read.refusal?.code, 'transcode-limited');
    expect(Uri.parse(asked.last.url).path, '/media/hls/seg/1.m4s');
  });

  test('another origin is never asked', () async {
    answer(200);
    final read = await askStream('https://elsewhere.invalid/a.mp3');
    expect(read.verdict, StreamProbe.unreachable);
    expect(asked, isEmpty);
  });

  test('a fetch that fails reaches nothing', () async {
    web.window.setProperty(
      'fetch'.toJS,
      ((JSString input, web.RequestInit init) => Future<web.Response>.error(
        StateError('offline'),
      ).toJS).toJS,
    );
    final read = await askStream('/media/stream?pid=tr-a&mt=x');
    expect(read.verdict, StreamProbe.unreachable);
    expect(read.refusal, isNull);
  });
}
