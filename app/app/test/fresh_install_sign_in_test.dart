import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/auth/server_address.dart';
import 'package:waxdeck/src/auto/media_session_init.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'app_host.dart';

/// The first launch of a native install: no stored address, so the real
/// client cannot be built until the connect screen adopts one, while
/// `main()` registers the OS media session before the first frame.
void main() {
  testWidgets('the first sign-in after connecting lands on home', (
    tester,
  ) async {
    final store = InMemoryCredentialStore();
    final container = appContainer(
      server: _Server(),
      credentials: store,
      extra: [
        bootServerAddressProvider.overrideWithValue(null),
        serverProbeProvider.overrideWithValue(
          (_) async =>
              const ServerHealth(status: 'ok', version: 'test', apiVersion: 1),
        ),
      ],
    );
    // The platform half of the media session, answering as a device does.
    // Registration is once per isolate, so only this test makes it.
    const channel = MethodChannel('com.ryanheise.audio_service.client.methods');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await initMediaSession(container);

    await pumpWholeApp(tester, container: container);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.connectServerAddress),
      'http://server.test',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.connectServerSubmit),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.loginUsername),
      'listener',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.loginPassword),
      'wax-listen-pass',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.loginSubmit));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsIdentifier(SemanticsIds.homeScreen), findsOneWidget);
    // What the next launch signs in with.
    expect(store.serverAddress, 'http://server.test');
    expect(store.token, 'token');
  });

  test('a rebuilt client leaves the adapter a test injected open', () {
    final server = _Server();
    final container = appContainer(server: server);
    container.read(repositoryProvider);

    // What adopting an address does: the client is built again.
    container.invalidate(repositoryProvider);
    container.read(repositoryProvider);

    expect(server.closed, 0);
  });
}

/// A server with one account and nothing in its library: the session, the
/// sign-in and the empty session history answer, everything else is not
/// found.
class _Server implements HttpClientAdapter {
  static const _user = <String, Object?>{
    'id': 'us-1',
    'username': 'listener',
    'roles': ['user'],
    'uploadEnabled': false,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    final bearer = options.headers['Authorization'] != null;
    final (status, body) = switch ((options.method, path)) {
      ('GET', '/auth/bootstrap') => (200, {'required': false}),
      ('GET', '/auth/session') when bearer => (
        200,
        {'authenticated': true, 'user': _user, 'csrfToken': 'csrf'},
      ),
      ('GET', '/auth/session') => (200, {'authenticated': false}),
      ('POST', '/auth/login') => (
        200,
        {
          'user': _user,
          'token': 'token',
          'csrfToken': 'csrf',
          'sessionId': 'se-1',
        },
      ),
      ('GET', '/player/sessions/history') => (200, {'sessions': <Object?>[]}),
      _ => (404, {'code': 'not-found', 'message': 'not found'}),
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  /// How many times the transport was closed.
  var closed = 0;

  @override
  void close({bool force = false}) => closed++;
}
