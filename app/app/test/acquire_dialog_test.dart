import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/uploads/add_to_library.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// The add-from-URL dialog while the server checks the link: it stays
/// open and says so, a refusal is worded inline, and what was queued is
/// named.

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

const _video = 'https://tube.example/watch?v=one';
const _both = 'https://tube.example/watch?v=one&list=PL1';

WaxDeckApiException _refused(String? reason) => WaxDeckApiException(
  code: 'source-refused',
  statusCode: 422,
  message: 'the server says no, in English',
  params: reason == null ? null : <String, String>{'reason': reason},
);

FakeRepository _repo() =>
    FakeRepository()
      ..sessionState = const SessionState(authenticated: true, user: _user);

Finder _url() => find.bySemanticsIdentifier(SemanticsIds.acquireUrl);

Finder _playlistSwitch() => find.ancestor(
  of: find.bySemanticsIdentifier(SemanticsIds.acquirePlaylist),
  matching: find.byType(WaxSwitch),
);

Finder _submit() => find.ancestor(
  of: find.bySemanticsIdentifier(SemanticsIds.acquireSubmit),
  matching: find.byType(WaxButton),
);

Future<void> _open(
  WidgetTester tester,
  ProviderContainer container,
  Locale locale,
) async {
  await mountApp(
    tester,
    Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Center(
          child: WaxButton(
            label: 'Open',
            onPressed: () => acquireFromUrl(context, ref),
          ),
        ),
      ),
    ),
    container: container,
    locale: locale,
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String url) async {
  await tester.enterText(_url(), url);
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in const [Locale('en'), Locale('es')]) {
    group('the acquire dialog in ${locale.languageCode}', () {
      late AppLocalizations l10n;

      setUpAll(() async {
        l10n = await AppLocalizations.delegate.load(locale);
      });

      String? message(ProviderContainer container) =>
          container.read(shellMessagesProvider)?.resolve(l10n);

      testWidgets('stays open and says it is checking while it waits', (
        tester,
      ) async {
        final gate = Completer<void>();
        final repo = _repo()..createAcquisitionGate = gate;
        final container = appContainer(repo: repo);
        await _open(tester, container, locale);
        await _type(tester, _video);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.acquireSubmit),
        );
        await tester.pump();

        expect(_url(), findsOne);
        expect(find.text(l10n.uploadsAcquireChecking), findsOne);
        expect(tester.widget<WaxButton>(_submit()).busy, isTrue);

        // Pressed again, it sends nothing more.
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.acquireSubmit),
          warnIfMissed: false,
        );
        await tester.pump();
        gate.complete();
        await tester.pumpAndSettle();
        expect(repo.acquisitionCalls, hasLength(1));
        expect(_url(), findsNothing);
      });

      testWidgets('shows a refusal inline, keeping the dialog and the link', (
        tester,
      ) async {
        final repo = _repo()
          ..uploadError = _refused('playlist-unavailable')
          ..acquireItemTitle = 'Night Drive'
          ..acquireSource = 'playlist';
        final container = appContainer(repo: repo);
        await _open(tester, container, locale);
        await _type(tester, _video);
        await _send(tester);

        expect(find.text(l10n.errorSourcePlaylistUnavailable), findsOne);
        expect(find.text('the server says no, in English'), findsNothing);
        expect(message(container), isNull);
        expect(_url(), findsOne);
        expect(tester.widget<WaxButton>(_submit()).busy, isFalse);
        expect(tester.widget<WaxButton>(_submit()).onPressed, isNotNull);

        // Correcting the link clears it, and the next send goes through.
        await _type(tester, 'https://tube.example/playlist?list=PL2');
        expect(find.text(l10n.errorSourcePlaylistUnavailable), findsNothing);
        repo.uploadError = null;
        await _send(tester);
        expect(_url(), findsNothing);
        expect(repo.acquisitionCalls.single.url, contains('PL2'));
        expect(
          message(container),
          l10n.uploadsAcquireQueuedTitled('playlist', 'Night Drive'),
        );
      });

      testWidgets('words an unknown reason, and none, as the general case', (
        tester,
      ) async {
        final repo = _repo()..uploadError = _refused('holo-projection');
        final container = appContainer(repo: repo);
        await _open(tester, container, locale);
        await _type(tester, _video);
        await _send(tester);
        expect(find.text(l10n.errorSourceRefused), findsOne);

        repo.uploadError = _refused(null);
        await _type(tester, '$_video&t=1');
        await _send(tester);
        expect(find.text(l10n.errorSourceRefused), findsOne);
      });

      testWidgets('keeps a refusal of what was typed in the server words', (
        tester,
      ) async {
        final repo = _repo()
          ..uploadError = const WaxDeckApiException(
            code: 'invalid-request',
            statusCode: 400,
            message: 'that host is on a private network',
          );
        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _video);
        await _send(tester);
        expect(find.text('that host is on a private network'), findsOne);
        expect(_url(), findsOne);
      });

      /// What the URL field shows as its error, if anything.
      String? fieldError(WidgetTester tester) =>
          tester.widget<WaxTextField>(find.byType(WaxTextField)).errorText;

      testWidgets('says a failure that is not about the link above the form, '
          'not under the field', (tester) async {
        final repo = _repo();
        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _video);
        for (final (code, sentence) in <(String, String)>[
          ('storage-full', l10n.errorStorageFull),
          ('internal', l10n.errorInternal),
          ('timeout', l10n.errorTimeout),
          ('read-only', l10n.errorReadOnly),
        ]) {
          repo.uploadError = WaxDeckApiException(
            code: code,
            statusCode: 500,
            message: 'the server says no, in English',
          );
          await _send(tester);
          expect(find.text(sentence), findsOne, reason: code);
          expect(fieldError(tester), isNull, reason: code);
          // Open, editable, and ready to try again.
          expect(_url(), findsOne);
          expect(tester.widget<WaxButton>(_submit()).busy, isFalse);
          expect(tester.widget<WaxButton>(_submit()).onPressed, isNotNull);
        }

        // The next send clears the line, and success closes the dialog.
        repo.uploadError = null;
        await _send(tester);
        expect(_url(), findsNothing);
      });

      testWidgets('keeps a refusal of the link under the field, whatever the '
          'code that carries it', (tester) async {
        final repo = _repo();
        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _video);
        for (final error in [
          _refused('live'),
          const WaxDeckApiException(
            code: 'invalid-request',
            statusCode: 400,
            message: 'that host is on a private network',
            params: {'reason': 'blocked-address'},
          ),
          const WaxDeckApiException(
            code: 'invalid-request',
            statusCode: 400,
            message: 'the host does not resolve',
            params: {'reason': 'invalid-address'},
          ),
        ]) {
          repo.uploadError = error;
          await _send(tester);
          expect(fieldError(tester), isNotNull, reason: error.message);
        }
      });

      testWidgets('says an invalid request about anything else above the '
          'form, in the server words', (tester) async {
        final repo = _repo();
        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _video);
        for (final params in <Map<String, String>?>[
          null,
          {'field': 'library'},
          {'field': 'url'},
          // A feed's refusals say nothing about a video link.
          {'reason': 'not-a-feed'},
          {'reason': 'too-large'},
        ]) {
          repo.uploadError = WaxDeckApiException(
            code: 'invalid-request',
            statusCode: 400,
            message: 'that library does not take audiobooks',
            params: params,
          );
          await _send(tester);
          expect(
            find.text('that library does not take audiobooks'),
            findsOne,
            reason: '$params',
          );
          expect(fieldError(tester), isNull, reason: '$params');
          expect(_url(), findsOne);
        }
      });

      testWidgets('says a bridge that is not running above the form: it is '
          'not about the link', (tester) async {
        final repo = _repo()
          ..uploadError = const WaxDeckApiException(
            code: 'source-unavailable',
            statusCode: 503,
            message: 'start the bridge first',
          );
        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _video);
        await _send(tester);

        expect(find.text('start the bridge first'), findsOne);
        expect(fieldError(tester), isNull);
        expect(_url(), findsOne);
      });

      testWidgets('clears the line above the form when the link is edited', (
        tester,
      ) async {
        final repo = _repo()
          ..uploadError = const WaxDeckApiException(
            code: 'storage-full',
            statusCode: 507,
            message: 'the server says no, in English',
          );
        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _video);
        await _send(tester);
        expect(find.text(l10n.errorStorageFull), findsOne);

        await _type(tester, '$_video&t=1');
        expect(find.text(l10n.errorStorageFull), findsNothing);
      });

      testWidgets('a refusal that lands after the link was edited is a '
          'message, and the field is left alone', (tester) async {
        final gate = Completer<void>();
        final repo = _repo()
          ..createAcquisitionGate = gate
          ..uploadError = _refused('live');
        final container = appContainer(repo: repo);
        await _open(tester, container, locale);
        await _type(tester, _video);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.acquireSubmit),
        );
        await tester.pump();
        // The busy spinner never settles: type and pump, do not settle.
        await tester.enterText(_url(), '$_video&t=1');
        await tester.pump();

        gate.complete();
        await tester.pumpAndSettle();
        expect(message(container), l10n.errorSourceLive);
        expect(fieldError(tester), isNull);
        expect(_url(), findsOne);
        expect(tester.widget<WaxButton>(_submit()).busy, isFalse);
        expect(tester.widget<WaxButton>(_submit()).onPressed, isNotNull);
      });

      testWidgets('an error that is not the server\'s answer frees the '
          'dialog, says so, and still reaches the log', (tester) async {
        final repo = _repo()..acquireFailure = StateError('boom');
        final container = appContainer(repo: repo);
        await _open(tester, container, locale);
        await _type(tester, _video);
        await _send(tester);

        expect(tester.takeException(), isStateError);
        expect(find.text(l10n.errorUnexpected), findsOne);
        expect(fieldError(tester), isNull);
        expect(_url(), findsOne);
        expect(message(container), isNull);
        expect(tester.widget<WaxButton>(_submit()).busy, isFalse);
        expect(tester.widget<WaxButton>(_submit()).onPressed, isNotNull);
      });

      testWidgets('fits the longest refusal in a narrow dialog', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final reasons = <String, String>{
          'playlist-unavailable': l10n.errorSourcePlaylistUnavailable,
          'playlist-empty': l10n.errorSourcePlaylistEmpty,
          'video-private': l10n.errorSourceVideoPrivate,
          'video-unavailable': l10n.errorSourceVideoUnavailable,
          'age-restricted': l10n.errorSourceAgeRestricted,
          'region-blocked': l10n.errorSourceRegionBlocked,
          'members-only': l10n.errorSourceMembersOnly,
          'live': l10n.errorSourceLive,
          'not-started': l10n.errorSourceNotStarted,
          'no-audio': l10n.errorSourceNoAudio,
          'unsupported-url': l10n.errorSourceUnsupportedUrl,
          'rate-limited': l10n.errorSourceRateLimited,
          'source-broken': l10n.errorSourceBroken,
          'timed-out': l10n.errorSourceTimedOut,
          'stalled': l10n.errorSourceStalled,
        };
        final longest = reasons.entries.reduce(
          (a, b) => b.value.length > a.value.length ? b : a,
        );
        final repo = _repo()..uploadError = _refused(longest.key);
        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _video);
        await _send(tester);

        // A RenderFlex overflow would be the exception taken here.
        expect(tester.takeException(), isNull);
        final sentence = find.text(longest.value);
        expect(sentence, findsOne);
        final field = tester.getRect(find.byType(WaxTextField));
        final text = tester.getRect(sentence);
        expect(text.left, greaterThanOrEqualTo(field.left));
        expect(text.right, lessThanOrEqualTo(field.right));
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(text.right, lessThanOrEqualTo(screen.width));
        // The same sentence also in the general line.
        repo.uploadError = WaxDeckApiException(
          code: 'conflict',
          statusCode: 409,
          message: longest.value,
        );
        await _send(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(longest.value), findsOne);
      });

      testWidgets('closes on success and names what was queued', (
        tester,
      ) async {
        final repo = _repo()
          ..acquireItemTitle = 'Long Division'
          ..acquireSource = 'video';
        final container = appContainer(repo: repo);
        await _open(tester, container, locale);
        await _type(tester, _video);
        await _send(tester);

        expect(_url(), findsNothing);
        expect(
          message(container),
          l10n.uploadsAcquireQueuedTitled('video', 'Long Division'),
        );
        expect(message(container), contains('Long Division'));
      });

      testWidgets('says the plain sentence when the answer has no title', (
        tester,
      ) async {
        final container = appContainer(repo: _repo());
        await _open(tester, container, locale);
        await _type(tester, _video);
        await _send(tester);
        expect(message(container), l10n.uploadsAcquireQueued);
      });

      testWidgets('closed during the check, it reports the outcome', (
        tester,
      ) async {
        final gate = Completer<void>();
        final repo = _repo()
          ..createAcquisitionGate = gate
          ..acquireItemTitle = 'Night Drive'
          ..acquireSource = 'channel';
        final container = appContainer(repo: repo);
        await _open(tester, container, locale);
        await _type(tester, _video);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.acquireSubmit),
        );
        await tester.pump();
        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle();
        expect(_url(), findsNothing);
        expect(message(container), isNull);

        gate.complete();
        await tester.pumpAndSettle();
        expect(repo.acquisitionCalls, hasLength(1));
        expect(
          message(container),
          l10n.uploadsAcquireQueuedTitled('channel', 'Night Drive'),
        );
      });

      testWidgets('closed during the check, a refusal is a message', (
        tester,
      ) async {
        final gate = Completer<void>();
        final repo = _repo()
          ..createAcquisitionGate = gate
          ..uploadError = _refused('live');
        final container = appContainer(repo: repo);
        await _open(tester, container, locale);
        await _type(tester, _video);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.acquireSubmit),
        );
        await tester.pump();
        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle();

        gate.complete();
        await tester.pumpAndSettle();
        expect(message(container), l10n.errorSourceLive);
      });

      testWidgets('answered while it closes, it pops nothing more', (
        tester,
      ) async {
        final gate = Completer<void>();
        final repo = _repo()
          ..createAcquisitionGate = gate
          ..acquireItemTitle = 'Night Drive'
          ..acquireSource = 'video';
        final container = appContainer(repo: repo);
        await _open(tester, container, locale);
        await _type(tester, _video);
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.acquireSubmit),
        );
        await tester.pump();
        await tester.tap(find.text(l10n.commonCancel));
        // Mid exit transition: the dialog is still built, but gone.
        await tester.pump(const Duration(milliseconds: 10));
        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Open'), findsOne);
        expect(
          message(container),
          l10n.uploadsAcquireQueuedTitled('video', 'Night Drive'),
        );
      });

      testWidgets('offers the playlist only for a video and a playlist', (
        tester,
      ) async {
        await _open(tester, appContainer(repo: _repo()), locale);
        expect(_playlistSwitch(), findsNothing);

        await _type(tester, _video);
        expect(_playlistSwitch(), findsNothing);
        await _type(tester, 'https://tube.example/playlist?list=PL1');
        expect(_playlistSwitch(), findsNothing);

        await _type(tester, _both);
        expect(_playlistSwitch(), findsOne);
        expect(find.text(l10n.uploadsAcquirePlaylist), findsOne);
        expect(tester.widget<WaxSwitch>(_playlistSwitch()).value, isFalse);

        await _type(tester, 'https://youtu.be/abc123?list=PL1');
        expect(_playlistSwitch(), findsOne);
        await _type(tester, 'https://youtu.be/abc123');
        expect(_playlistSwitch(), findsNothing);
      });

      testWidgets('sends playlist only when the switch is shown and on', (
        tester,
      ) async {
        final repo = _repo();
        await _open(tester, appContainer(repo: repo), locale);

        await _type(tester, _both);
        await _send(tester);
        expect(repo.acquisitionCalls.last.playlist, isNull);

        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _both);
        await tester.tap(_playlistSwitch());
        await tester.pumpAndSettle();
        expect(tester.widget<WaxSwitch>(_playlistSwitch()).value, isTrue);
        await _send(tester);
        expect(repo.acquisitionCalls.last.playlist, isTrue);

        // On, then the link stops naming both: off, and not sent.
        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _both);
        await tester.tap(_playlistSwitch());
        await tester.pumpAndSettle();
        await _type(tester, _video);
        expect(_playlistSwitch(), findsNothing);
        await _send(tester);
        expect(repo.acquisitionCalls.last.playlist, isNull);

        // And back to naming both: it opens off again.
        await _open(tester, appContainer(repo: repo), locale);
        await _type(tester, _both);
        await tester.tap(_playlistSwitch());
        await tester.pumpAndSettle();
        await _type(tester, _video);
        await _type(tester, _both);
        expect(tester.widget<WaxSwitch>(_playlistSwitch()).value, isFalse);
      });
    });
  }
}
