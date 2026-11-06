import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Takes a chunk's body the way [take] says, then answers the session.
class _ChunkAdapter implements HttpClientAdapter {
  _ChunkAdapter(this.take);

  final Future<void> Function(Stream<Uint8List> body) take;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await take(requestStream!);
    return ResponseBody.fromString(
      jsonEncode(const <String, Object?>{
        'id': 'up-01JZX5N8QW3F4V9T2B7KD3M9R6',
        'fileName': 'pace.flac',
        'sizeBytes': 1048576,
        'receivedBytes': 1048576,
        'idleMs': 0,
        'mediaType': 'music',
        'state': 'receiving',
        'createdAt': '2026-07-01T00:00:00Z',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

WaxDeckClient _client(_ChunkAdapter adapter) => WaxDeckClient(
  baseUrl: 'http://host:4420',
  dio: Dio()..httpClientAdapter = adapter,
  chunkStall: const Duration(milliseconds: 300),
);

const _session = <String, Object?>{
  'id': 'up-01JZX5N8QW3F4V9T2B7KD3M9R6',
  'fileName': 'pace.flac',
  'sizeBytes': 1048576,
  'receivedBytes': 1048576,
  'idleMs': 0,
  'mediaType': 'music',
  'state': 'receiving',
  'createdAt': '2026-07-01T00:00:00Z',
};

/// Sends a request the way a browser's transport does: the body is read
/// whole first, then goes out as upload progress events ([progress], the
/// wait before each and the bytes sent by then); the request as a whole is
/// cut at connect plus receive unless both are zero; a cancel aborts it.
class _BrowserLikeAdapter implements HttpClientAdapter {
  _BrowserLikeAdapter(this.progress, {this.answerAfter = Duration.zero});

  final List<(Duration, int)> Function(int total) progress;

  /// How long the answer takes once the body has gone.
  final Duration answerAfter;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final total =
        await requestStream?.fold<int>(0, (n, piece) => n + piece.length) ?? 0;
    final done = Completer<ResponseBody>();
    final budget =
        (options.connectTimeout ?? Duration.zero) +
        (options.receiveTimeout ?? Duration.zero);
    final cut = budget > Duration.zero
        ? Timer(budget, () {
            if (done.isCompleted) return;
            done.completeError(
              DioException.receiveTimeout(
                timeout: options.receiveTimeout ?? budget,
                requestOptions: options,
              ),
            );
          })
        : null;
    unawaited(
      cancelFuture?.then((_) {
        if (done.isCompleted) return;
        done.completeError(
          DioException.requestCancelled(
            requestOptions: options,
            reason: 'aborted',
          ),
        );
      }),
    );
    unawaited(() async {
      for (final (wait, sent)
          in total == 0 ? const <(Duration, int)>[] : progress(total)) {
        await Future<void>.delayed(wait);
        if (done.isCompleted) return;
        options.onSendProgress?.call(sent, total);
      }
      await Future<void>.delayed(answerAfter);
      if (done.isCompleted) return;
      done.complete(
        ResponseBody.fromString(
          jsonEncode(_session),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
    }());
    try {
      return await done.future;
    } finally {
      cut?.cancel();
    }
  }

  @override
  void close({bool force = false}) {}
}

/// Takes a chunk's body whole, reports one more progress event
/// [progressAfter] later (a browser's last, at the end of the body) and
/// answers [answerAfter] after that. A stall's check answers [checkIdleMs]
/// after [checkAfter].
class _LateProgressAdapter implements HttpClientAdapter {
  _LateProgressAdapter({
    required this.progressAfter,
    required this.answerAfter,
    required this.checkAfter,
    required this.checkIdleMs,
  });

  final Duration progressAfter;
  final Duration answerAfter;
  final Duration checkAfter;
  final int checkIdleMs;
  var checks = 0;

  static ResponseBody _answer(int idleMs) => ResponseBody.fromString(
    jsonEncode({..._session, 'idleMs': idleMs}),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET') {
      checks++;
      await Future<void>.delayed(checkAfter);
      return _answer(checkIdleMs);
    }
    final total = await requestStream!.fold<int>(
      0,
      (n, piece) => n + piece.length,
    );
    final done = Completer<ResponseBody>();
    unawaited(
      cancelFuture?.then((_) {
        if (done.isCompleted) return;
        done.completeError(
          DioException.requestCancelled(
            requestOptions: options,
            reason: 'aborted',
          ),
        );
      }),
    );
    unawaited(() async {
      await Future<void>.delayed(progressAfter);
      if (done.isCompleted) return;
      options.onSendProgress?.call(total, total);
      await Future<void>.delayed(answerAfter);
      if (done.isCompleted) return;
      done.complete(_answer(0));
    }());
    return done.future;
  }

  @override
  void close({bool force = false}) {}
}

/// A client sending through [adapter] as a browser does, its whole-request
/// budget brought down to 400 ms so a test can run past it.
WaxDeckClient _browserClient(_BrowserLikeAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final client = WaxDeckClient(
    baseUrl: 'http://host:4420',
    dio: dio,
    chunkStall: const Duration(milliseconds: 300),
    wholeRequestCut: true,
  );
  dio.options
    ..connectTimeout = const Duration(milliseconds: 100)
    ..receiveTimeout = const Duration(milliseconds: 300);
  return client;
}

void main() {
  final chunk = Uint8List(1048576);

  group('through a browser, which cuts a whole request at connect plus '
      'receive,', () {
    test('a chunk sent slowly but steadily finishes past that cut', () async {
      final watch = Stopwatch()..start();
      final client = _browserClient(
        _BrowserLikeAdapter(
          (total) => [
            for (var i = 1; i <= 20; i++)
              (const Duration(milliseconds: 50), total * i ~/ 20),
          ],
        ),
      );

      final session = await client.putUploadData(
        'up-01JZX5N8QW3F4V9T2B7KD3M9R6',
        offset: 0,
        bytes: chunk,
      );

      expect(session.receivedBytes, 1048576);
      expect(
        watch.elapsed,
        greaterThan(const Duration(milliseconds: 400)),
        reason: 'longer than the whole-request cut',
      );
    });

    test('a chunk whose send goes silent ends at the stall deadline', () async {
      final watch = Stopwatch()..start();
      final dio = Dio()
        ..httpClientAdapter = _BrowserLikeAdapter(
          (total) => [
            (const Duration(milliseconds: 20), total ~/ 8),
            // Then nothing more leaves.
            (const Duration(days: 1), total),
          ],
        );
      // The ordinary forty-second budget: only the stall can end it soon.
      final client = WaxDeckClient(
        baseUrl: 'http://host:4420',
        dio: dio,
        chunkStall: const Duration(milliseconds: 300),
        wholeRequestCut: true,
      );

      await expectLater(
        client
            .putUploadData(
              'up-01JZX5N8QW3F4V9T2B7KD3M9R6',
              offset: 0,
              bytes: chunk,
            )
            .timeout(const Duration(seconds: 10)),
        throwsA(
          isA<WaxDeckApiException>()
              .having((e) => e.code, 'code', 'transport-timeout')
              .having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('any other request keeps the whole-request cut', () async {
      final client = _browserClient(
        _BrowserLikeAdapter(
          (_) => const [],
          answerAfter: const Duration(seconds: 2),
        ),
      );

      await expectLater(
        client
            .getUpload('up-01JZX5N8QW3F4V9T2B7KD3M9R6')
            .timeout(const Duration(seconds: 10)),
        throwsA(
          isA<WaxDeckApiException>().having(
            (e) => e.code,
            'code',
            'transport-timeout',
          ),
        ),
      );
    });
  });

  test('a chunk whose send stops moving is given up as a timeout', () async {
    final client = _client(
      _ChunkAdapter((body) {
        // One piece goes, then the wire takes nothing more.
        late final StreamSubscription<Uint8List> taking;
        taking = body.listen((_) => taking.pause());
        return Completer<void>().future;
      }),
    );

    final sent = client.putUploadData(
      'up-01JZX5N8QW3F4V9T2B7KD3M9R6',
      offset: 0,
      bytes: chunk,
    );

    await expectLater(
      sent.timeout(const Duration(seconds: 10)),
      throwsA(
        isA<WaxDeckApiException>()
            .having((e) => e.code, 'code', 'transport-timeout')
            .having((e) => e.statusCode, 'statusCode', isNull),
      ),
    );
  });

  test('a body the transport took whole is not cut while the server still '
      'reads it', () async {
    // A real socket: its buffers take the whole body at once, as a slow
    // link's do, so no progress follows while the server reads.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var reading = false;
    var reads = 0;
    void answer(HttpRequest request, int idleMs) => request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({..._session, 'idleMs': idleMs}))
      ..close();
    server.listen((request) async {
      if (request.method != 'PUT') {
        reads++;
        answer(request, reading ? 0 : 5000);
        return;
      }
      reading = true;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await request.drain<void>();
      reading = false;
      answer(request, 0);
    });
    final client = WaxDeckClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      chunkStall: const Duration(milliseconds: 300),
    );

    final session = await client.putUploadData(
      'up-01JZX5N8QW3F4V9T2B7KD3M9R6',
      offset: 0,
      bytes: Uint8List(64 * 1024),
    );

    expect(session.receivedBytes, 1048576);
    expect(reads, greaterThan(0), reason: 'the stall asked the server');
  });

  // A stall falls due and asks the server; while it waits, the transport
  // reports progress and arms a fresh stall. The answer is about a moment
  // that progress has since replaced.
  group('a check that answers after fresh progress', () {
    test('does not cut the chunk', () async {
      // From the body taken: due at 300 ms and asked until 500 ms; the
      // progress at 400 ms sets the next deadline, and the answer at
      // 650 ms comes inside it.
      final client = WaxDeckClient(
        baseUrl: 'http://host:4420',
        dio: Dio()
          ..httpClientAdapter = _LateProgressAdapter(
            progressAfter: const Duration(milliseconds: 400),
            answerAfter: const Duration(milliseconds: 250),
            checkAfter: const Duration(milliseconds: 200),
            checkIdleMs: 5000,
          ),
        chunkStall: const Duration(milliseconds: 300),
      );

      final session = await client.putUploadData(
        'up-01JZX5N8QW3F4V9T2B7KD3M9R6',
        offset: 0,
        bytes: Uint8List(64 * 1024),
      );

      expect(session.receivedBytes, 1048576);
    });

    test('leaves the deadline that progress set', () async {
      // From the body taken: due at 1 s and asked until 1.9 s; the
      // progress at 1.1 s sets the next check for 2.1 s, 400 ms before the
      // answer at 2.5 s. Re-armed from the stale answer, it would wait to
      // 2.9 s, 400 ms after it.
      final adapter = _LateProgressAdapter(
        progressAfter: const Duration(milliseconds: 1100),
        answerAfter: const Duration(milliseconds: 1400),
        checkAfter: const Duration(milliseconds: 900),
        checkIdleMs: 0,
      );
      final client = WaxDeckClient(
        baseUrl: 'http://host:4420',
        dio: Dio()..httpClientAdapter = adapter,
        chunkStall: const Duration(seconds: 1),
      );

      await client.putUploadData(
        'up-01JZX5N8QW3F4V9T2B7KD3M9R6',
        offset: 0,
        bytes: Uint8List(64 * 1024),
      );

      expect(adapter.checks, 2);
    });
  });

  test('a chunk sent slowly but steadily is never cut', () async {
    var pieces = 0;
    final watch = Stopwatch()..start();
    final client = _client(
      _ChunkAdapter((body) async {
        await for (final _ in body) {
          pieces++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }),
    );

    final session = await client.putUploadData(
      'up-01JZX5N8QW3F4V9T2B7KD3M9R6',
      offset: 0,
      bytes: chunk,
    );

    expect(session.receivedBytes, 1048576);
    expect(pieces, greaterThan(1), reason: 'the body goes in pieces');
    expect(
      watch.elapsed,
      greaterThan(const Duration(milliseconds: 300)),
      reason: 'longer than the stall deadline in all, so it is per piece',
    );
  });
}
