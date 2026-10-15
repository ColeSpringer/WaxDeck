import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/library/item_kind.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDKINDA1';
const _b = 'tr-01JZX5N8QW3F4V9T2B7KDKINDB2';
const _c = 'tr-01JZX5N8QW3F4V9T2B7KDKINDC3';
const _job = 'jb-01JZX5N8QW3F4V9T2B7KDKIND00';

const _admin = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

/// A screen whose one button starts the kind change.
class _Starter extends StatelessWidget {
  const _Starter({required this.pids, required this.to});

  final List<String> pids;
  final String to;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: WaxButton(
        label: 'Start',
        onPressed: () => confirmSetKind(context, pids: pids, to: to),
      ),
    ),
  );
}

FakeRepository _repo({bool admin = true}) => FakeRepository(
  sessionState: SessionState(
    authenticated: true,
    user: admin
        ? _admin
        : const WaxDeckUser(id: 'us-2', username: 'sam', roles: ['user']),
  ),
);

Future<PlayerHarness> _pump(
  WidgetTester tester,
  FakeRepository repo, {
  required List<String> pids,
  required String to,
  FakeEngine? engine,
}) async {
  final container = playbackContainer(
    repo: repo,
    engine: engine ?? FakeEngine(),
    extra: [
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  // Signed in, as the app is wherever a kind change is offered.
  await tester.runAsync(() => container.read(authControllerProvider.future));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(_Starter(pids: pids, to: to)),
    ),
  );
  await tester.pumpAndSettle();
  return PlayerHarness(container);
}

/// Confirms the dialog and lets every poll it makes run.
Future<void> _confirm(WidgetTester tester, {int polls = 1}) async {
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
  await tester.pump();
  for (var i = 0; i < polls; i++) {
    await tester.pump(kindChangePoll);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tracks that become one book open it', (tester) async {
    await _pump(tester, _repo(), pids: [_a, _b], to: 'audiobook');
    await _confirm(tester);

    expect(
      tester.widget<BookScreen>(find.byType(BookScreen)).pid,
      'bk-${_a.substring(3)}',
    );
  });

  testWidgets('a book that becomes music opens its first part\'s album', (
    tester,
  ) async {
    const album = 'al-01JZX5N8QW3F4V9T2B7KDKINDAL';
    final repo = _repo()
      ..libraryItems.add(
        const ItemSummary(
          pid: _a,
          mediaType: MediaType.music,
          title: 'First Lecture',
          albumPid: album,
          durationMs: 60000,
        ),
      );
    await _pump(tester, repo, pids: ['bk-${_a.substring(3)}'], to: 'music');
    await _confirm(tester);

    expect(find.byType(BookScreen), findsNothing);
    expect(tester.widget<AlbumScreen>(find.byType(AlbumScreen)).pid, album);
  });

  testWidgets('a refused change says why and stays put', (tester) async {
    final repo = _repo()
      ..metadataError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'a cue track cannot change kind',
        statusCode: 400,
      );
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    expect(
      shellMessageText(raisedMessage(tester)),
      'a cue track cannot change kind',
    );
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('a change that failed says why', (tester) async {
    final repo = _repo()
      ..jobs = const [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'failed',
          error: 'a file of the item is not on disk',
        ),
      ];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    expect(
      shellMessageText(raisedMessage(tester)),
      'The change could not be made: a file of the item is not on disk',
    );
    expect(find.byType(BookScreen), findsNothing);
  });

  testWidgets('an item folded into one out of sight says so and goes nowhere', (
    tester,
  ) async {
    final repo = _repo(admin: false)
      ..jobs = [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'done',
          result: {
            'converted': const <String>[],
            'absorbed': {_a: ''},
            'created': const <String>[],
            'writeBackFailures': const <Object>[],
          },
        ),
      ];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    expect(
      shellMessageText(raisedMessage(tester)),
      'It became part of an item in a library you cannot open.',
    );
    expect(find.byType(BookScreen), findsNothing);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('files the change could not write are owned up to', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'done',
          result: {
            'converted': ['bk-${_a.substring(3)}'],
            'absorbed': const <String, Object?>{},
            'created': const <String>[],
            'writeBackFailures': const [
              {'path': 'a.mp3', 'reason': 'permission denied'},
            ],
          },
        ),
      ];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    expect(
      shellMessageText(raisedMessage(tester)),
      'Saved, but some files kept their old tags.',
    );
    expect(find.byType(BookScreen), findsOneWidget);
  });

  testWidgets('a lost poll reads as still running, not refused', (
    tester,
  ) async {
    final repo = _repo()
      ..getJobError = const WaxDeckApiException(
        code: 'unavailable',
        message: 'the server did not answer',
        statusCode: 503,
      );
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester);

    final message = raisedMessage(tester);
    expect(shellMessageText(message), 'Still changing. Follow it in Tasks.');
    expect(message!.actionLabel, 'Tasks');
  });

  testWidgets('a change still running after the wait points at Tasks', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester, polls: kindChangePolls);

    final message = raisedMessage(tester);
    expect(shellMessageText(message), 'Still changing. Follow it in Tasks.');
    expect(message!.actionLabel, 'Tasks');
  });

  testWidgets('a state the app does not know reads as still running', (
    tester,
  ) async {
    final repo = _repo(admin: false)
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'settling')];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await _confirm(tester, polls: kindChangePolls);

    expect(
      shellMessageText(raisedMessage(tester)),
      'It carries on in the background; you will be told when it is done.',
    );
  });

  testWidgets('a folded item that was playing stops, and nothing of it stays '
      'queued', (tester) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await _pump(
      tester,
      _repo(),
      pids: [_a, _b, _c],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(_c)]);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    await _confirm(tester);

    expect(engine.playing, isFalse);
    expect(
      shellMessageText(raisedMessage(tester)),
      'What was playing is part of the book now; play it from here.',
    );
    // An item the server no longer has is nothing to persist, nor to
    // offer back at the next launch.
    final queue = harness.container.read(queueControllerProvider);
    expect(queue.entries, isEmpty);
    await harness.endPlayback(tester);
  });

  testWidgets('what follows a folded item that was playing waits, unplayed', (
    tester,
  ) async {
    const d = 'tr-01JZX5N8QW3F4V9T2B7KDKINDD4';
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await _pump(
      tester,
      _repo(),
      pids: [_a, _b],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(d)]);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    await _confirm(tester);

    final queue = harness.container.read(queueControllerProvider);
    expect([for (final e in queue.entries) e.pid], [d]);
    expect(queue.currentEntry?.pid, d);
    expect(engine.playing, isFalse, reason: 'it waits rather than starting');
    await harness.endPlayback(tester);
  });

  testWidgets('a change that failed part way lets go of what it folded, '
      'then says why', (tester) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final repo = _repo()
      ..jobs = [
        Job(
          pid: _job,
          kind: 'set-kind',
          state: 'failed',
          error: 'a file of the item is not on disk',
          result: {
            'converted': ['bk-${_a.substring(3)}'],
            'absorbed': {'tr-${_b.substring(3)}': 'bk-${_a.substring(3)}'},
            'created': const <String>[],
            'writeBackFailures': const <Object>[],
          },
        ),
      ];
    final harness = await _pump(
      tester,
      repo,
      pids: [_a, _b, _c],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(_c)]);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    await _confirm(tester);

    expect(engine.playing, isFalse);
    final queue = harness.container.read(queueControllerProvider);
    expect([for (final e in queue.entries) e.pid], [_c]);
    expect(
      shellMessageText(raisedMessage(tester)),
      'The change could not be made: a file of the item is not on disk',
    );
    expect(find.byType(BookScreen), findsNothing);
    await harness.endPlayback(tester);
  });

  testWidgets('a station tuned over a folded entry plays on, unremarked', (
    tester,
  ) async {
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final repo = _repo();
    final harness = await _pump(
      tester,
      repo,
      pids: [_a, _b],
      to: 'audiobook',
      engine: engine,
    );
    harness.play([testItem(_b), testItem(_c)]);
    await tester.pumpAndSettle();
    final station = RadioStation(
      pid: 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1',
      name: 'Coastal FM',
      streamUrl: 'https://stream.example/coastal',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    repo.radioStationsByPid[station.pid] = station;
    // The queue keeps its entry under the station.
    await harness.container.read(radioPlaybackProvider.notifier).play(station);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    await _confirm(tester);

    expect(
      harness.container.read(radioPlaybackProvider).station?.pid,
      station.pid,
    );
    expect(engine.playing, isTrue);
    expect(raisedMessage(tester), isNull);
    await harness.container.read(radioPlaybackProvider.notifier).stop();
    await harness.endPlayback(tester);
  });

  testWidgets('a dialog opened over the running change is left standing', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    await _pump(tester, repo, pids: [_a], to: 'audiobook');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
    await tester.pump();
    await tester.pump(kindChangePoll);

    // Something outside the dialog opens one over it meanwhile, as a
    // shared link arriving does.
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('Start')),
        builder: (_) => const AlertDialog(content: Text('A shared link')),
      ),
    );
    // Bounded pumps: the change's spinner never settles while it runs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('A shared link'), findsOneWidget);

    repo.jobs = const [
      Job(
        pid: _job,
        kind: 'set-kind',
        state: 'failed',
        error: 'a file of the item is not on disk',
      ),
    ];
    await tester.pump(kindChangePoll);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('A shared link'), findsOneWidget);
    expect(find.text('Reading the files again'), findsNothing);
    expect(
      shellMessageText(raisedMessage(tester)),
      'The change could not be made: a file of the item is not on disk',
    );
  });

  testWidgets('back while the change runs leaves the dialog to finish it', (
    tester,
  ) async {
    final repo = _repo()
      ..jobs = const [Job(pid: _job, kind: 'set-kind', state: 'running')];
    await _pump(tester, repo, pids: [_a, _b], to: 'audiobook');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.kindConfirm));
    await tester.pump();
    await tester.pump(kindChangePoll);

    // System back, the way the platform sends it.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pump();
    expect(find.text('Reading the files again'), findsOneWidget);

    repo.jobs = [
      Job(
        pid: _job,
        kind: 'set-kind',
        state: 'done',
        result: {
          'converted': ['bk-${_a.substring(3)}'],
          'absorbed': {'tr-${_b.substring(3)}': 'bk-${_a.substring(3)}'},
          'created': const <String>[],
          'writeBackFailures': const <Object>[],
        },
      ),
    ];
    await tester.pump(kindChangePoll);
    await tester.pumpAndSettle();
    expect(
      tester.widget<BookScreen>(find.byType(BookScreen)).pid,
      'bk-${_a.substring(3)}',
    );
  });

  for (final (to, pid, sentence) in [
    ('audiobook', _a, 'This is already an audiobook, so nothing changed.'),
    (
      'music',
      'bk-${_a.substring(3)}',
      'This is already music, so nothing changed.',
    ),
  ]) {
    testWidgets('a change to $to that found it already says so', (
      tester,
    ) async {
      // A view drawn before another device changed it: the server skips
      // an item already of the kind rather than refusing it.
      final repo = _repo()
        ..jobs = const [
          Job(
            pid: _job,
            kind: 'set-kind',
            state: 'done',
            result: {
              'converted': <String>[],
              'absorbed': <String, Object?>{},
              'created': <String>[],
              'writeBackFailures': <Object>[],
            },
          ),
        ];
      await _pump(tester, repo, pids: [pid], to: to);
      await _confirm(tester);

      expect(shellMessageText(raisedMessage(tester)), sentence);
      expect(find.text('Start'), findsOneWidget, reason: 'nowhere to go');
    });
  }
}
