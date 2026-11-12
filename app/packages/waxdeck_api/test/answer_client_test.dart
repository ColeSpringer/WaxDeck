import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

/// Answers every request with [text] at [status], under [contentType] when
/// one is given and with no Content-Type header otherwise. [declareLength]
/// adds the Content-Length header a server that knows the size sends.
class _TextAdapter implements HttpClientAdapter {
  _TextAdapter(
    this.text, {
    this.contentType,
    this.status = 200,
    this.declareLength = false,
  });

  final String text;
  final String? contentType;
  final int status;
  final bool declareLength;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    text,
    status,
    headers: {
      if (contentType case final type?) Headers.contentTypeHeader: [type],
      if (declareLength)
        Headers.contentLengthHeader: ['${utf8.encode(text).length}'],
    },
  );

  @override
  void close({bool force = false}) {}
}

const _health = '{"status":"ok","version":"1.0.0","apiVersion":1}';

/// Dio decodes an answer this size or larger off the calling isolate.
const _isolateThreshold = 50 * 1024;

/// A health answer padded past the isolate threshold.
final _largeHealth =
    '{"status":"ok","version":"1.0.0","apiVersion":1,'
    '"padding":"${'x' * (_isolateThreshold + 1024)}"}';

/// A timer that has already fired.
class _SpentTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 1;
}

/// Runs [body] with each timer armed for exactly [budget] expiring in a
/// microtask instead of by the clock, and adds the ones it saw to [armed].
/// A microtask runs before the next event, so the expiry comes ahead of an
/// isolate's answer however long that has been ready.
Future<T> _expireBudget<T>(
  Duration budget,
  List<Duration> armed,
  Future<T> Function() body,
) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, f) {
      if (duration != budget) return parent.createTimer(zone, duration, f);
      armed.add(duration);
      zone.scheduleMicrotask(f);
      return _SpentTimer();
    },
  ),
);

/// What the message says of an answer that is not JSON: its type and size,
/// never its content.
String _notJson(String? type, [int? bytes]) =>
    'the answer is not JSON (${type ?? 'no content type'}'
    '${bytes == null ? '' : ', $bytes bytes'})';

Matcher _failed(
  String code, {
  Object? message = anything,
  int status = 200,
  bool unreachable = false,
}) => throwsA(
  isA<WaxDeckApiException>()
      .having((e) => e.code, 'code', code)
      .having((e) => e.statusCode, 'statusCode', status)
      .having((e) => e.message, 'message', message)
      // A 2xx was an answer: the outboxes must not queue a write the
      // server may have applied.
      .having((e) => e.unreachable, 'unreachable', unreachable),
);

void main() {
  group('a 2xx answer', () {
    test('with no body keeps its status', () async {
      final client = clientOn(
        _TextAdapter('', contentType: Headers.jsonContentType),
      );
      await expectLater(client.health(), _failed('transport-empty'));
    });

    test('with no body and no JSON type reads as empty too', () async {
      await expectLater(
        clientOn(_TextAdapter('')).health(),
        _failed('transport-empty'),
      );
    });

    test('that does not decode names the field that failed', () async {
      final client = clientOn(
        RecordingAdapter(body: {'version': '1.0.0', 'apiVersion': 1}),
      );
      await expectLater(
        client.health(),
        _failed('transport-decode', message: 'ServerHealth.status: missing'),
      );
    });

    test('of the wrong shape names it too', () async {
      final client = clientOn(
        RecordingAdapter(body: {'status': 'ok', 'version': 1, 'apiVersion': 1}),
      );
      await expectLater(
        client.health(),
        _failed(
          'transport-decode',
          message: 'ServerHealth.version: expected a string, got int',
        ),
      );
    });

    test(
      'shaped like an error is still an answer that does not read',
      () async {
        // Only a failed status carries the server's error; a 2xx body is the
        // operation's answer, whatever its fields are called.
        final client = clientOn(
          RecordingAdapter(body: {'code': 'not-found', 'message': 'no'}),
        );
        await expectLater(client.health(), _failed('transport-decode'));
      },
    );

    for (final type in <String?>['text/plain', null]) {
      test('of JSON under ${type ?? 'no'} content type reads', () async {
        final health = await clientOn(
          _TextAdapter(_health, contentType: type),
        ).health();
        expect(health.status, 'ok');
        expect(health.apiVersion, 1);
      });
    }

    // Something other than the server answered: a captive portal, a proxy's
    // page, a body cut short. Whatever the content type says.
    for (final (type, text) in <(String?, String)>[
      (Headers.jsonContentType, '<html>sign in</html>'),
      (Headers.jsonContentType, '{"status":"ok","vers'),
      ('text/html', '<html>sign in</html>'),
      ('text/plain', '{"status":"ok","vers'),
      (null, 'garbled'),
    ]) {
      test('of ${type ?? 'no type'} holding $text is not the server\'s', () {
        return expectLater(
          clientOn(_TextAdapter(text, contentType: type)).health(),
          _failed('transport', message: _notJson(type)),
        );
      });
    }

    test('that is not JSON says its size when the server declared it', () {
      const text = '<html>sign in</html>';
      return expectLater(
        clientOn(
          _TextAdapter(text, contentType: 'text/html', declareLength: true),
        ).health(),
        _failed('transport', message: _notJson('text/html', text.length)),
      );
    });

    test('that is not JSON names its type without the parameters', () {
      return expectLater(
        clientOn(
          _TextAdapter('<html/>', contentType: 'text/html; charset=utf-8'),
        ).health(),
        _failed('transport', message: _notJson('text/html')),
      );
    });

    test(
      'that is not JSON leaves its content out of what is reported',
      () async {
        // A login answer cut short still carries the token it began with.
        final client = clientOn(
          _TextAdapter(
            '{"token":"s3cret-token","csrfToken":"c5rf-token","user":{"na',
            contentType: Headers.jsonContentType,
          ),
        );
        final error = await client.health().then<Object>(
          (_) => fail('the answer should not read'),
          onError: (Object e) => e,
        );
        expect(error, isA<WaxDeckApiException>());
        expect(error.toString(), isNot(contains('s3cret-token')));
        expect(error.toString(), isNot(contains('c5rf-token')));
        expect(error.toString(), isNot(contains('"user"')));
      },
    );

    for (final type in <String?>[Headers.jsonContentType, 'text/plain', null]) {
      test(
        'of a JSON string under ${type ?? 'no type'} is the wrong shape',
        () {
          return expectLater(
            clientOn(_TextAdapter('"sign in"', contentType: type)).health(),
            _failed(
              'transport-decode',
              message: 'getHealth: expected an object, got String',
            ),
          );
        },
      );
    }

    for (final type in ['text/x-opml', Headers.jsonContentType]) {
      test('of text stays text under $type', () async {
        final opml = await clientOn(
          _TextAdapter('{"not": "parsed"}', contentType: type),
        ).exportOpml();
        expect(opml, '{"not": "parsed"}');
      });
    }

    test('of text that is empty is empty text', () async {
      expect(
        await clientOn(
          _TextAdapter('', contentType: 'text/x-opml'),
        ).exportOpml(),
        isEmpty,
      );
    });
  });

  // A call that returns nothing never reads its body, so the answer being
  // the server's at all is checked where the response arrives.
  group('a call that returns nothing', () {
    for (final (type, text) in <(String?, String)>[
      (Headers.jsonContentType, '<html>sign in</html>'),
      ('text/html', '<html>sign in</html>'),
      (null, 'garbled'),
    ]) {
      test('under a 2xx ${type ?? 'with no type'} page is not delivered', () {
        final client = clientOn(_TextAdapter(text, contentType: type));
        return expectLater(
          client.putPlayState('tr-1', 1000),
          _failed('transport', message: _notJson(type)),
        );
      });
    }

    test('under a 2xx page fails for a delete as well', () {
      final client = clientOn(
        _TextAdapter('<html>sign in</html>', contentType: 'text/html'),
      );
      return expectLater(client.logout(), _failed('transport'));
    });

    for (final (status, text, type) in <(int, String, String?)>[
      (204, '', null),
      (200, '', Headers.jsonContentType),
      (200, '{}', Headers.jsonContentType),
      (200, '{"ok":true}', 'text/plain'),
    ]) {
      test('is delivered by a $status answer holding "$text" '
          'under ${type ?? 'no type'}', () async {
        final client = clientOn(
          _TextAdapter(text, contentType: type, status: status),
        );
        await client.putPlayState('tr-1', 1000);
      });
    }

    test('keeps the server\'s refusal under a 4xx', () {
      final client = clientOn(
        _TextAdapter(
          '{"code":"not-found","message":"no"}',
          contentType: Headers.jsonContentType,
          status: 404,
        ),
      );
      return expectLater(
        client.putPlayState('tr-1', 1000),
        _failed('not-found', status: 404, message: 'no'),
      );
    });
  });

  // Dio's own default transformer decodes an answer of 50 KB or more in a
  // background isolate; a catalog page is several times that, so the calling
  // isolate must not do it.
  group('a large answer', () {
    test('switches to an isolate at the size Dio\'s default does', () {
      final dio = Dio();
      WaxDeckClient(baseUrl: 'http://host:4420', dio: dio);
      expect(
        dio.transformer,
        isA<FusedTransformer>().having(
          (t) => t.contentLengthIsolateThreshold,
          'contentLengthIsolateThreshold',
          _isolateThreshold,
        ),
      );
      expect(
        (Dio().transformer as FusedTransformer).contentLengthIsolateThreshold,
        _isolateThreshold,
        reason: 'Dio\'s default moved; follow it',
      );
    });

    for (final declareLength in [false, true]) {
      for (final type in <String?>[Headers.jsonContentType, 'text/plain']) {
        final how =
            '${declareLength ? 'declared' : 'undeclared'} length, '
            'under $type';
        test('reads ($how)', () async {
          final health = await clientOn(
            _TextAdapter(
              _largeHealth,
              contentType: type,
              declareLength: declareLength,
            ),
          ).health();
          expect(health.status, 'ok');
        });

        test('that is not JSON is not the server\'s ($how)', () {
          final text = '<html>${'x' * (_isolateThreshold + 1024)}</html>';
          return expectLater(
            clientOn(
              _TextAdapter(
                text,
                contentType: type,
                declareLength: declareLength,
              ),
            ).health(),
            _failed(
              'transport',
              message: _notJson(type, declareLength ? text.length : null),
            ),
          );
        });

        test('cut short is not the server\'s ($how)', () {
          final text = _largeHealth.substring(0, _largeHealth.length - 100);
          return expectLater(
            clientOn(
              _TextAdapter(
                text,
                contentType: type,
                declareLength: declareLength,
              ),
            ).health(),
            _failed(
              'transport',
              message: _notJson(type, declareLength ? text.length : null),
            ),
          );
        });
      }
    }

    test('that is not JSON keeps the failed status it came with', () {
      return expectLater(
        clientOn(
          _TextAdapter(
            '<html>${'x' * (_isolateThreshold + 1024)}</html>',
            contentType: 'text/html',
            status: 502,
          ),
        ).health(),
        _failed('transport', status: 502, unreachable: true),
      );
    });

    test('is decoded under the request\'s transform timeout', () async {
      final dio = Dio()
        ..httpClientAdapter = _TextAdapter(
          _largeHealth,
          contentType: Headers.jsonContentType,
        );
      WaxDeckClient(baseUrl: 'http://host:4420', dio: dio);
      const url = 'http://host:4420/api/v1/health';
      // Dio arms the budget as a timer once the decode isolate is running,
      // and the timer and the isolate's answer then race on one event loop.
      // So the budget is only a label here and its timer is expired by hand
      // (_expireBudget), ahead of whichever answer is ready. It matches no
      // timeout the client sets, whose timers must keep running.
      const budget = Duration(minutes: 7);
      final armed = <Duration>[];
      await _expireBudget(
        budget,
        armed,
        () => expectLater(
          dio.get<Object?>(url, options: Options(transformTimeout: budget)),
          throwsA(
            isA<DioException>().having(
              (e) => e.type,
              'type',
              DioExceptionType.transformTimeout,
            ),
          ),
        ),
      );
      expect(armed, [budget], reason: 'the large answer\'s decode is timed');

      // The budget is for the isolate's work only, so it is spent on an
      // answer that went to one and never on one that did not.
      armed.clear();
      dio.httpClientAdapter = _TextAdapter(
        _health,
        contentType: Headers.jsonContentType,
      );
      final small = await _expireBudget(
        budget,
        armed,
        () => dio.get<Object?>(url, options: Options(transformTimeout: budget)),
      );
      expect((small.data! as Map)['status'], 'ok');
      expect(armed, isEmpty, reason: 'the small answer\'s decode is not timed');
    });
  });

  group('a failed status', () {
    for (final type in <String?>[Headers.jsonContentType, 'text/html', null]) {
      test('with a page that is not JSON under ${type ?? 'no type'} '
          'keeps its status', () async {
        final client = clientOn(
          _TextAdapter(
            '<html>bad gateway</html>',
            contentType: type,
            status: 502,
          ),
        );
        // An unworded 502 is a proxy answering for a server that is down.
        await expectLater(
          client.health(),
          _failed('transport', status: 502, unreachable: true),
        );
      });
    }

    test('with a 404 page that is not JSON is not a refusal', () async {
      final client = clientOn(
        _TextAdapter(
          '<html>not found</html>',
          contentType: Headers.jsonContentType,
          status: 404,
        ),
      );
      await expectLater(
        client.health(),
        throwsA(
          isA<WaxDeckApiException>()
              .having((e) => e.code, 'code', 'transport')
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.isRefusal, 'isRefusal', isFalse),
        ),
      );
    });

    test('with the server\'s own error is its answer', () async {
      final client = clientOn(
        _TextAdapter(
          '{"code":"not-found","message":"no"}',
          contentType: 'text/plain',
          status: 404,
        ),
      );
      await expectLater(
        client.health(),
        _failed('not-found', status: 404, message: 'no'),
      );
    });
  });
}
