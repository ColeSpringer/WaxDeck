import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_data/src/ws_connect/ws_connect.dart';

void main() {
  test('a socket that accepts and never upgrades times out', () async {
    // The half-open case, which is the one a deadline exists for: the TCP
    // connection completes, so nothing fails, and without a budget the
    // future never settles and the reconnect ladder above never learns
    // the channel is down.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final held = <Socket>[];
    server.listen(held.add);
    addTearDown(() {
      for (final s in held) {
        s.destroy();
      }
    });

    await expectLater(
      connectWebSocket(
        'ws://127.0.0.1:${server.port}/api/v1/sync/live',
        connectDeadline: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('an attempt past its deadline is aborted, not left open', () async {
    // Left in flight, the attempt finishes its upgrade whenever the
    // server gets round to it, and is a second sync socket until closed.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final held = <Socket>[];
    final ended = Completer<void>();
    // Once: a reset reports an error and then done.
    void end() {
      if (!ended.isCompleted) ended.complete();
    }

    server.listen((socket) {
      held.add(socket);
      socket.listen((_) {}, onDone: end, onError: (Object _) => end());
    });
    addTearDown(() {
      for (final s in held) {
        s.destroy();
      }
    });

    await expectLater(
      connectWebSocket(
        'ws://127.0.0.1:${server.port}/api/v1/sync/live',
        connectDeadline: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(held, hasLength(1));
    await expectLater(
      ended.future.timeout(const Duration(seconds: 2)),
      completes,
      reason: 'the server still holds the connection open',
    );
  });

  test('an upgraded socket outlives the client that opened it', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      // Slow to answer, so the client holds an unanswered upgrade a while.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen(socket.add);
    });

    final channel = await connectWebSocket(
      'ws://127.0.0.1:${server.port}/api/v1/sync/live',
    );
    addTearDown(channel.sink.close);
    final replies = StreamIterator<dynamic>(channel.stream);
    for (final frame in <String>['one', 'two']) {
      channel.sink.add(frame);
      expect(
        await replies.moveNext().timeout(const Duration(seconds: 2)),
        true,
      );
      expect(replies.current, frame);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });

  test('a refused connection fails rather than hanging', () async {
    // Nothing is listening: the platform refuses immediately, and the
    // deadline is not what reports it.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    await expectLater(
      connectWebSocket(
        'ws://127.0.0.1:$port/api/v1/sync/live',
        connectDeadline: const Duration(seconds: 5),
      ),
      throwsA(isA<Exception>()),
    );
  });

  group('an upgrade the server answers with a status', () {
    Future<int> answering(int status) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response
          ..statusCode = status
          ..close();
      });
      return server.port;
    }

    test('says which status, so a refusal for want of a session is seen as '
        'one', () async {
      final port = await answering(HttpStatus.unauthorized);

      await expectLater(
        connectWebSocket('ws://127.0.0.1:$port/api/v1/ws'),
        throwsA(isA<UpgradeRefused>().having((e) => e.status, 'status', 401)),
      );
    });

    test('says so for any other status too', () async {
      final port = await answering(HttpStatus.serviceUnavailable);

      await expectLater(
        connectWebSocket('ws://127.0.0.1:$port/api/v1/ws'),
        throwsA(isA<UpgradeRefused>().having((e) => e.status, 'status', 503)),
      );
    });
  });
}
