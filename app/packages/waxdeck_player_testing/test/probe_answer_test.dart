import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// What one look at a stream URL reads off the answer, shared by the
/// native and the browser probe so it is pinned once, here, on the VM.
///
/// The bodies are the server's own: `writeJSONError` in the streaming
/// bridge, which every stream route answers a refusal with.
void main() {
  ProbeAnswer read(int status, [String? body]) =>
      interpretProbe(status, contentType: 'application/json', body: body);

  test('a 2xx is the URL answering', () {
    for (final status in <int>[200, 206]) {
      final answer = interpretProbe(status, contentType: 'audio/flac');
      expect(answer.verdict, StreamProbe.answered, reason: '$status');
      expect(answer.refusal, isNull);
    }
    expect(
      interpretProbe(200).verdict,
      StreamProbe.answered,
      reason: 'a host that names no type still answered',
    );
  });

  test('a page where media was asked for is not the URL answering', () {
    // A captive portal or a proxy's sign-in answers 200 with a page, and
    // reading that as the URL answering blames the file for a network
    // that never reached the server.
    for (final type in <String>['text/html; charset=utf-8', 'text/HTML']) {
      final answer = interpretProbe(200, contentType: type);
      expect(answer.verdict, StreamProbe.unreachable, reason: type);
      expect(answer.refusal, isNull);
    }
  });

  test('415 and 422 are the server refusing the file itself', () {
    for (final status in <int>[415, 422]) {
      final answer = read(
        status,
        '{"code":"unsupported-format","message":"no"}',
      );
      expect(answer.verdict, StreamProbe.unplayable, reason: '$status');
      expect(answer.refusal, isNull);
    }
  });

  test('an expired token is a refusal a fresh mint cures', () {
    final answer = read(
      401,
      '{"code":"unauthenticated","message":"invalid or expired media token"}',
    );
    expect(answer.verdict, StreamProbe.unreachable);
    final refusal = answer.refusal!;
    expect(refusal.status, 401);
    expect(refusal.code, 'unauthenticated');
    expect(refusal.message, 'invalid or expired media token');
    expect(refusal.stale, isTrue);
    expect(refusal.engineDown, isFalse);
  });

  test('a source that moved is stale too', () {
    final refusal = read(
      410,
      '{"code":"stream-stale","message":"moved"}',
    ).refusal!;
    expect(refusal.stale, isTrue);
  });

  test('the transcode cap is a refusal in the server\'s words', () {
    final answer = read(
      429,
      '{"code":"transcode-limited","message":"too many streams"}',
    );
    expect(answer.verdict, StreamProbe.unreachable);
    final refusal = answer.refusal!;
    expect(refusal.code, 'transcode-limited');
    expect(refusal.stale, isFalse);
    expect(refusal.engineDown, isFalse);
  });

  test('the streaming engine being away is worth another mint', () {
    final bridge = read(
      502,
      '{"code":"internal","message":"stream backend unavailable"}',
    ).refusal!;
    expect(bridge.engineDown, isTrue);
    expect(bridge.stale, isFalse);
  });

  test('only the server\'s word that its engine is away is engine down', () {
    // The podcast and station proxies answer a host behind the server
    // being away with a 502 of their own, which no mint reaches past.
    final host = read(
      502,
      '{"code":"service-unreachable",'
      '"message":"the podcast host could not be reached"}',
    ).refusal!;
    expect(host.engineDown, isFalse);
  });

  test('the catalog in maintenance is a refusal, not an outage', () {
    final refusal = read(
      503,
      '{"code":"catalog-maintenance",'
      '"message":"the catalog is in maintenance; retry shortly"}',
    ).refusal!;
    expect(refusal.engineDown, isFalse);
    expect(refusal.stale, isFalse);
  });

  test('the envelope\'s params ride along as strings', () {
    final refusal = read(
      429,
      '{"code":"transcode-limited","message":"busy",'
      '"params":{"limit":"2","n":3}}',
    ).refusal!;
    expect(refusal.params, <String, String>{'limit': '2'});
  });

  test('a proxy\'s page is no refusal, whatever its status', () {
    for (final status in <int>[401, 410, 429, 502, 503]) {
      expect(
        interpretProbe(
          status,
          contentType: 'text/html',
          body: '<html>Bad Gateway</html>',
        ).refusal,
        isNull,
        reason: '$status',
      );
      expect(
        read(status, '<html>Bad Gateway</html>').refusal,
        isNull,
        reason: '$status mislabelled as JSON',
      );
    }
  });

  test('a body in the sidecar\'s own words is no refusal', () {
    // The server answers every refusal in its own envelope; the engine's
    // body, or JSON that lacks the envelope's code and message, is not
    // one.
    expect(
      read(
        429,
        '{"error":"live transcode slots are full","code":"overloaded",'
        '"schemaVersion":1}',
      ).refusal,
      isNull,
    );
    expect(read(429, '{"code": 7, "message": "x"}').refusal, isNull);
    expect(read(429, '["transcode-limited"]').refusal, isNull);
  });

  test('anything else reaches nothing', () {
    for (final status in <int>[0, 302, 403, 404, 500, 504]) {
      final answer = read(status, '{"code":"not-found","message":"gone"}');
      expect(answer.verdict, StreamProbe.unreachable, reason: '$status');
      expect(answer.refusal, isNull, reason: '$status');
    }
  });
}
