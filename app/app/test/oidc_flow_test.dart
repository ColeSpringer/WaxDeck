import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/loopback/loopback_io.dart';
import 'package:waxdeck/src/auth/oidc_flow.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _provider = OidcProvider(
  id: 'corp',
  displayName: 'Corp SSO',
  startUrl: 'http://host:4420/api/v1/auth/oidc/start?provider=corp',
);

class _FakeOpener implements UrlOpenerPort {
  final List<String> opened = [];

  @override
  Future<void> open(String url) async => opened.add(url);
}

class _FakeDeepLinks implements DeepLinkPort {
  final controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get uriLinkStream => controller.stream;
}

class _FakeReceiver implements LoopbackReceiverPort {
  final codeController = Completer<String>();
  bool closed = false;

  @override
  int get port => 41234;

  @override
  Future<String> get code => codeController.future;

  @override
  Future<void> close() async => closed = true;
}

void main() {
  group('verifier and challenge derivation', () {
    test('the challenge is the base64url SHA-256 without padding', () {
      // Pinned against an external vector: sha256("test") is
      // 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08.
      expect(
        OidcLoginFlow.deriveChallenge('test'),
        'n4bQgYhMfWWaL-qgxVrQFaO_TxsrC4Is0V1sFbDwCgg',
      );
    });

    test('verifiers are 43 chars of base64url alphabet and unique', () {
      final flow = OidcLoginFlow(
        repository: FakeRepository(),
        urlOpener: _FakeOpener(),
      );
      final seen = <String>{};
      for (var i = 0; i < 100; i++) {
        final verifier = flow.newVerifier();
        expect(verifier, hasLength(43));
        expect(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(verifier), isTrue);
        expect(seen.add(verifier), isTrue);
      }
    });

    test('start URLs keep the provider query and add flow parameters', () {
      final url = Uri.parse(
        OidcLoginFlow.startUrlFor(
          _provider,
          mode: 'loopback',
          challenge: 'abc',
          port: 9999,
        ),
      );
      expect(url.queryParameters['provider'], 'corp');
      expect(url.queryParameters['mode'], 'loopback');
      expect(url.queryParameters['challenge'], 'abc');
      expect(url.queryParameters['port'], '9999');
    });
  });

  group('deep link flow', () {
    test(
      'opens the browser, exchanges the linked code with the verifier',
      () async {
        final repo = FakeRepository();
        final opener = _FakeOpener();
        final links = _FakeDeepLinks();
        final flow = OidcLoginFlow(
          repository: repo,
          urlOpener: opener,
          deepLinks: links,
        );

        final login = flow.loginWithDeepLink(_provider, deviceName: 'Pixel 9');
        await pumpEventQueue();
        expect(opener.opened, hasLength(1));

        // Unrelated links must be ignored, not treated as the code.
        links.controller.add(Uri.parse('waxdeck://share?item=tr-x'));
        links.controller.add(Uri.parse('waxdeck://auth?code=one-time-code'));
        final result = await login;

        expect(result.token, 'oidc-token');
        final call = repo.oidcExchangeCalls.single;
        expect(call.code, 'one-time-code');
        expect(call.deviceName, 'Pixel 9');

        final opened = Uri.parse(opener.opened.single);
        expect(opened.queryParameters['mode'], 'app');
        expect(
          opened.queryParameters['challenge'],
          OidcLoginFlow.deriveChallenge(call.verifier!),
        );
      },
    );

    test('times out when no link ever arrives', () async {
      final flow = OidcLoginFlow(
        repository: FakeRepository(),
        urlOpener: _FakeOpener(),
        deepLinks: _FakeDeepLinks(),
      );
      await expectLater(
        flow.loginWithDeepLink(
          _provider,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('loopback flow', () {
    test(
      'binds, opens the browser with the port, exchanges, and closes',
      () async {
        final repo = FakeRepository();
        final opener = _FakeOpener();
        final receiver = _FakeReceiver();
        final flow = OidcLoginFlow(
          repository: repo,
          urlOpener: opener,
          bindLoopbackReceiver: () async => receiver,
        );

        final login = flow.loginWithLoopback(_provider, deviceName: 'Study');
        await pumpEventQueue();
        expect(opener.opened, hasLength(1));
        receiver.codeController.complete('one-time-code');
        final result = await login;

        expect(result.token, 'oidc-token');
        final call = repo.oidcExchangeCalls.single;
        expect(call.code, 'one-time-code');
        expect(call.deviceName, 'Study');

        final opened = Uri.parse(opener.opened.single);
        expect(opened.queryParameters['mode'], 'loopback');
        expect(opened.queryParameters['port'], '41234');
        expect(
          opened.queryParameters['challenge'],
          OidcLoginFlow.deriveChallenge(call.verifier!),
        );
        expect(receiver.closed, isTrue);
      },
    );

    test('closes the receiver when the exchange never happens', () async {
      final receiver = _FakeReceiver();
      final flow = OidcLoginFlow(
        repository: FakeRepository(),
        urlOpener: _FakeOpener(),
        bindLoopbackReceiver: () async => receiver,
      );
      await expectLater(
        flow.loginWithLoopback(
          _provider,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(receiver.closed, isTrue);
    });
  });

  group('io loopback receiver', () {
    test(
      'serves the close page on /callback and hands over the code',
      () async {
        final receiver = await IoLoopbackReceiver.bind();
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final missReq = await client.getUrl(
          Uri.parse('http://127.0.0.1:${receiver.port}/other'),
        );
        final miss = await missReq.close();
        expect(miss.statusCode, HttpStatus.notFound);
        await miss.drain<void>();

        final hitReq = await client.getUrl(
          Uri.parse(
            'http://127.0.0.1:${receiver.port}/callback?code=one-time-code',
          ),
        );
        final hit = await hitReq.close();
        expect(hit.statusCode, HttpStatus.ok);
        final body = await utf8.decodeStream(hit);
        expect(body, contains('close this tab'));

        expect(await receiver.code, 'one-time-code');
        await receiver.close();
      },
    );
  });
}
