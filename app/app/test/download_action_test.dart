import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connectivity/connectivity_port.dart';
import 'package:waxdeck/src/downloads/download_state.dart';
import 'package:waxdeck/src/downloads/wifi_only_gate.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/player/download_action.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

const _book = 'bk-01JZX5N8QW3F4V9T2B7KD3M9R6';
const _me = 'us-1';

/// The pill renderer in an entity bar, as a screen places it.
class _Bar extends ConsumerWidget {
  const _Bar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final download = downloadWaxAction(
      context.l10n,
      ref.watch(downloadStateProvider(_book)),
      label: context.l10n.bookDownloadOffline,
      semanticsId: SemanticsIds.bookDownload,
      onStart: () =>
          unawaited(ref.read(downloadStateProvider(_book).notifier).start()),
    );
    return WaxActionBar(actions: <WaxAction>[?download]);
  }
}

/// Both renderers over one item, each under its own handle, or neither
/// once the screen is [closed].
///
/// Returns the container, which a test that visits again passes back as
/// [container]: what the first visit learnt outlives the screen.
Future<ProviderContainer> _pumpBoth(
  WidgetTester tester, {
  FakeDownloads? downloads,
  FakeArtworkStore? artwork,
  WifiOnlyGate? gate,
  ProviderContainer? container,
  bool closed = false,
}) async {
  assert(
    container == null || (downloads == null && artwork == null && gate == null),
    'a given container carries its own downloads, artwork and gate',
  );
  final over =
      container ??
      appContainer(
        artwork: artwork,
        downloads: downloads,
        extra: [if (gate != null) transferGateProvider.overrideWithValue(gate)],
      );
  await mountApp(
    tester,
    Scaffold(
      body: closed
          ? const SizedBox.shrink()
          : const Column(
              children: <Widget>[
                _Bar(),
                DownloadAction(
                  pid: _book,
                  label: 'Download',
                  semanticsId: SemanticsIds.downloadButton,
                ),
              ],
            ),
    ),
    routed: false,
    container: over,
  );
  return over;
}

Finder get _pill => waxControl<WaxButton>(SemanticsIds.bookDownload);

Finder get _icon => waxControl<WaxIconButton>(SemanticsIds.downloadButton);

/// A connection that starts on mobile data and moves when told.
class _Net implements ConnectivityPort {
  ConnectionCost now = ConnectionCost.metered;
  final _costs = StreamController<ConnectionCost>.broadcast();

  /// Held open, [cost] answers what was true when it was asked, once this
  /// completes.
  Completer<void>? costGate;

  /// How many times the platform was asked, and followed.
  var asked = 0;
  var followed = 0;

  @override
  Future<ConnectionCost> cost() async {
    asked++;
    final answer = now;
    if (costGate case final gate?) await gate.future;
    return answer;
  }

  @override
  Stream<ConnectionCost> get costs {
    followed++;
    return _costs.stream;
  }

  void move(ConnectionCost cost) {
    now = cost;
    _costs.add(cost);
  }
}

/// A store whose completeness answer waits on [answer] while it is set.
class _SlowDownloads extends FakeDownloads {
  _SlowDownloads({super.local});

  Completer<void>? answer = Completer<void>();

  @override
  Future<bool> isComplete(String pid) async {
    if (answer case final gate?) await gate.future;
    return super.isComplete(pid);
  }
}

/// A store that stops answering once a download is asked for.
class _UnreadableDownloads extends FakeDownloads {
  @override
  Future<bool> isComplete(String pid) async {
    if (downloaded.isNotEmpty) throw const FileSystemException('unreadable');
    return super.isComplete(pid);
  }
}

void main() {
  testWidgets('a book fetched for offline brings its marks along', (
    tester,
  ) async {
    // Made on another device before this one ever opened the book, they
    // would otherwise reach it only through a player opened online.
    final db = inMemoryMirrorDatabase();
    final repo = FakeRepository()
      ..bookmarks[_book] = [
        Bookmark(
          id: 'bm-01JZX5N8QW3F4V9T2B7KD3M9R6',
          positionMs: 60000,
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      ];
    final sync = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    )..account = _me;
    final downloads = FakeDownloads();
    addTearDown(() async {
      sync.dispose();
      downloads.dispose();
      await db.close();
    });
    await mountApp(
      tester,
      const Scaffold(
        body: DownloadAction(
          pid: _book,
          label: 'Download',
          semanticsId: SemanticsIds.bookDownload,
        ),
      ),
      routed: false,
      container: appContainer(repo: repo, sync: sync, downloads: downloads),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.bookDownload));
    await tester.pump();
    downloads.emit(
      const DownloadProgress(pid: _book, fraction: 1, complete: true),
    );
    await tester.pumpAndSettle();

    expect(downloads.downloaded, [_book]);
    expect(
      [for (final m in await sync.localBookmarks(_book, owner: _me)) m.mark.id],
      ['bm-01JZX5N8QW3F4V9T2B7KD3M9R6'],
    );
  });

  testWidgets('a transfer in flight shows how far it has got', (tester) async {
    final semantics = tester.ensureSemantics();
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();

    await tester.tap(_pill);
    await tester.pump();
    downloads.emit(
      const DownloadProgress(pid: _book, fraction: 0.42, complete: false),
    );
    await tester.pump();

    final pill = tester.widget<WaxButton>(_pill);
    expect(pill.progress, 0.42);
    expect(pill.label, 'Downloading 42%');
    final node = tester
        .getSemantics(find.bySemanticsIdentifier(SemanticsIds.bookDownload))
        .getSemanticsData();
    expect(node.label, 'Downloading');
    expect(node.value, '42%');
    // The icon form spins in the live tint rather than greying out.
    final icon = tester.widget<WaxIconButton>(_icon);
    expect(icon.busy, isTrue);
    expect(icon.onPressed, isNotNull);

    downloads.byPid[_book] = testLocal('/books/one.m4b');
    downloads.emit(
      const DownloadProgress(pid: _book, fraction: 1, complete: true),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<WaxButton>(_pill).label, 'Downloaded');
    semantics.dispose();
  });

  testWidgets('a finished download is lit as an icon and a status pill', (
    tester,
  ) async {
    final downloads = FakeDownloads(
      local: {_book: testLocal('/books/one.m4b')},
    );
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();

    final icon = tester.widget<WaxIconButton>(_icon);
    expect(icon.glyph, WaxIcons.success);
    expect(icon.status, isTrue);
    expect(icon.active, isTrue);
    final colors = WaxColors.of(tester.element(_icon));
    expect(
      tester
          .widget<WaxIcon>(
            find.descendant(of: _icon, matching: find.byType(WaxIcon)),
          )
          .color,
      colors.accent,
    );

    final pill = tester.widget<WaxButton>(_pill);
    expect(pill.status, isTrue);
    expect(pill.icon, WaxIcons.success);
    expect(pill.label, 'Downloaded');
  });

  testWidgets('a failed download offers a retry in both renderers', (
    tester,
  ) async {
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();

    await tester.tap(_pill);
    await tester.pump();
    downloads.emit(
      const DownloadProgress(
        pid: _book,
        fraction: 0,
        complete: false,
        failure: DownloadFailure.interrupted,
      ),
    );
    await tester.pumpAndSettle();

    final pill = tester.widget<WaxButton>(_pill);
    expect(pill.label, 'Retry download');
    expect(pill.icon, WaxIcons.warning);
    expect(pill.status, isFalse);
    expect(pill.onPressed, isNotNull);
    final icon = tester.widget<WaxIconButton>(_icon);
    expect(icon.glyph, WaxIcons.warning);
    expect(icon.label, 'Retry download');
    expect(icon.onPressed, isNotNull);

    await tester.tap(_icon);
    await tester.pump();
    expect(downloads.downloaded, [_book, _book]);
    expect(tester.widget<WaxIconButton>(_icon).busy, isTrue);
  });

  testWidgets('with no download manager there is no action at all', (
    tester,
  ) async {
    await _pumpBoth(tester);
    await tester.pump();

    expect(find.byType(WaxButton), findsNothing);
    expect(find.byType(WaxIconButton), findsNothing);
  });

  testWidgets('an item the device is still fetching reads as in flight', (
    tester,
  ) async {
    // A reopened screen must not offer a second start for it.
    final downloads = FakeDownloads(
      items: const <DownloadedItem>[
        DownloadedItem(
          pid: _book,
          sizeBytes: 1024,
          files: 1,
          complete: false,
          active: true,
        ),
      ],
    );
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();

    expect(tester.widget<WaxButton>(_pill).progress, 0);
    expect(tester.widget<WaxIconButton>(_icon).busy, isTrue);
  });

  testWidgets('an unfinished item nothing is moving offers the download, '
      'which takes it up', (tester) async {
    // Parked on a not-found, or rows left with no transfer: a pill that
    // never moves and takes no press would trap it.
    final downloads = FakeDownloads(
      items: const <DownloadedItem>[
        DownloadedItem(pid: _book, sizeBytes: 1024, files: 1, complete: false),
      ],
    );
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();

    final pill = tester.widget<WaxButton>(_pill);
    expect(pill.label, 'Download for offline');
    expect(pill.progress, isNull);
    expect(tester.widget<WaxIconButton>(_icon).busy, isFalse);

    await tester.tap(_pill);
    await tester.pump();
    expect(downloads.downloaded, [_book]);
    expect(tester.widget<WaxButton>(_pill).progress, 0);
  });

  test(
    'a bug the port throws still settles the start, and is reported',
    () async {
      final downloads = FakeDownloads()..downloadError = StateError('closed');
      addTearDown(downloads.dispose);
      final container = appContainer(downloads: downloads);
      container.listen(downloadStateProvider(_book), (_, _) {});
      await pumpEventQueue();

      final reported = <Object>[];
      await runZonedGuarded(
        () => container.read(downloadStateProvider(_book).notifier).start(),
        (error, _) => reported.add(error),
      );

      expect(
        container.read(downloadStateProvider(_book)),
        isA<DownloadFailed>().having(
          (s) => s.cause,
          'cause',
          isA<StateError>(),
        ),
      );
      expect(reported.single, isA<StateError>());
    },
  );

  test('a bug the probe hits offers the download, and is reported', () async {
    final downloads = _ProbeBug();
    addTearDown(downloads.dispose);
    final container = appContainer(downloads: downloads);

    final reported = <Object>[];
    runZonedGuarded(
      () => container.listen(downloadStateProvider(_book), (_, _) {}),
      (error, _) => reported.add(error),
    );
    await pumpEventQueue();

    expect(container.read(downloadStateProvider(_book)), isA<DownloadIdle>());
    expect(reported.single, isA<StateError>());
  });

  testWidgets('a paused item reads as ready, and starting it resumes it', (
    tester,
  ) async {
    final downloads = FakeDownloads(
      items: const <DownloadedItem>[
        DownloadedItem(
          pid: _book,
          sizeBytes: 1024,
          files: 1,
          complete: false,
          paused: true,
        ),
      ],
    );
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();

    final pill = tester.widget<WaxButton>(_pill);
    expect(pill.label, 'Download for offline');
    expect(pill.progress, isNull);

    await tester.tap(_pill);
    await tester.pump();
    expect(downloads.downloaded, [_book]);
    expect(downloads.resumed, [_book]);
  });

  for (final (reason, detail) in <(DownloadFailure, String)>[
    (DownloadFailure.gone, 'No longer on the server'),
    (DownloadFailure.refused, 'The server refused the download'),
    (DownloadFailure.interrupted, 'The transfer was interrupted'),
  ]) {
    testWidgets('a download that gave up as ${reason.name} says why', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final downloads = FakeDownloads();
      addTearDown(downloads.dispose);
      await _pumpBoth(tester, downloads: downloads);
      await tester.pump();

      await tester.tap(_pill);
      await tester.pump();
      downloads.emit(
        DownloadProgress(
          pid: _book,
          fraction: 0,
          complete: false,
          failure: reason,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<WaxButton>(_pill).detail, detail);
      expect(tester.widget<WaxIconButton>(_icon).detail, detail);
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.bookDownload))
            .getSemanticsData()
            .hint,
        detail,
      );
      semantics.dispose();
    });
  }

  testWidgets('a refusal from the server is a failure that keeps its cause', (
    tester,
  ) async {
    final downloads = FakeDownloads()
      ..downloadError = const WaxDeckApiException(
        code: 'forbidden',
        message: 'not yours',
      );
    final artwork = FakeArtworkStore();
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads, artwork: artwork);
    await tester.pump();

    await tester.tap(_pill);
    await tester.pumpAndSettle();

    final pill = tester.widget<WaxButton>(_pill);
    expect(pill.label, 'Retry download');
    expect(pill.detail, 'Your account is not allowed to do that.');
    expect(tester.takeException(), isNull);
    expect(artwork.pinned, isEmpty);
  });

  test('an item already on disk reads done when the server is out of '
      'reach', () async {
    final downloads = FakeDownloads(local: {_book: testLocal('/books/one.m4b')})
      ..downloadError = const WaxDeckApiException(
        code: 'transport',
        message: '',
      );
    addTearDown(downloads.dispose);
    final container = appContainer(downloads: downloads);
    container.listen(downloadStateProvider(_book), (_, _) {});

    // Started before the probe answers, as a quick tap would.
    await container.read(downloadStateProvider(_book).notifier).start();

    expect(container.read(downloadStateProvider(_book)), isA<DownloadDone>());
  });

  testWidgets('the cover is pinned once the audio lands, never after a '
      'failure', (tester) async {
    final downloads = FakeDownloads();
    final artwork = FakeArtworkStore();
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads, artwork: artwork);
    await tester.pump();

    await tester.tap(_pill);
    await tester.pump();
    expect(artwork.pinned, isEmpty);
    downloads.emit(
      const DownloadProgress(
        pid: _book,
        fraction: 0,
        complete: false,
        failure: DownloadFailure.interrupted,
      ),
    );
    await tester.pumpAndSettle();
    expect(artwork.pinned, isEmpty);

    await tester.tap(_pill);
    await tester.pump();
    downloads.emit(
      const DownloadProgress(pid: _book, fraction: 0.5, complete: false),
    );
    await tester.pump();
    expect(artwork.pinned, isEmpty);
    downloads.byPid[_book] = testLocal('/books/one.m4b');
    downloads.emit(
      const DownloadProgress(pid: _book, fraction: 1, complete: true),
    );
    await tester.pumpAndSettle();
    expect(artwork.pinned, [_book]);
  });

  testWidgets('a download goes on and pins its cover with the screen gone', (
    tester,
  ) async {
    final downloads = FakeDownloads();
    final artwork = FakeArtworkStore();
    addTearDown(downloads.dispose);
    final container = await _pumpBoth(
      tester,
      downloads: downloads,
      artwork: artwork,
    );
    await tester.pump();
    await tester.tap(_pill);
    await tester.pump();

    await _pumpBoth(tester, container: container, closed: true);
    await tester.pumpAndSettle();
    downloads.byPid[_book] = testLocal('/books/one.m4b');
    downloads.emit(
      const DownloadProgress(pid: _book, fraction: 1, complete: true),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(artwork.pinned, [_book]);
  });

  testWidgets('a cancel from the notification settles to ready', (
    tester,
  ) async {
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();
    await tester.tap(_pill);
    await tester.pump();

    downloads.emit(
      const DownloadProgress(
        pid: _book,
        fraction: 0,
        complete: false,
        stopped: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<WaxButton>(_pill).label, 'Download for offline');
    expect(tester.widget<WaxIconButton>(_icon).glyph, WaxIcons.downloads);
    expect(tester.widget<WaxIconButton>(_icon).busy, isFalse);
  });

  testWidgets('a cancel in the app settles a running start to ready', (
    tester,
  ) async {
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();
    await tester.tap(_pill);
    await tester.pump();

    await downloads.cancel(_book);
    await tester.pumpAndSettle();

    expect(tester.widget<WaxButton>(_pill).label, 'Download for offline');
    expect(tester.widget<WaxButton>(_pill).progress, isNull);
  });

  testWidgets('removing a finished download settles to ready', (tester) async {
    final downloads = FakeDownloads(
      local: {_book: testLocal('/books/one.m4b')},
    );
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();
    expect(tester.widget<WaxButton>(_pill).label, 'Downloaded');

    // The fake's removal waits a turn, which only a pump hands it.
    unawaited(downloads.remove(_book));
    await tester.pumpAndSettle();

    expect(tester.widget<WaxButton>(_pill).label, 'Download for offline');
  });

  testWidgets('a finished download a sync commit freed settles to ready', (
    tester,
  ) async {
    final downloads = FakeDownloads(
      local: {_book: testLocal('/books/one.m4b')},
    );
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();
    expect(tester.widget<WaxIconButton>(_icon).status, isTrue);

    // What the manager says once a free leaves the item incomplete.
    downloads.byPid.remove(_book);
    downloads.emit(
      const DownloadProgress(
        pid: _book,
        fraction: 0,
        complete: false,
        stopped: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<WaxButton>(_pill).label, 'Download for offline');
    final icon = tester.widget<WaxIconButton>(_icon);
    expect(icon.status, isFalse);
    expect(icon.glyph, WaxIcons.downloads);
  });

  test(
    'a store that stops answering settles to failed with its cause',
    () async {
      final downloads = _UnreadableDownloads();
      addTearDown(downloads.dispose);
      final container = appContainer(downloads: downloads);
      container.listen(downloadStateProvider(_book), (_, _) {});
      await pumpEventQueue();

      await container.read(downloadStateProvider(_book).notifier).start();

      expect(
        container.read(downloadStateProvider(_book)),
        isA<DownloadFailed>().having(
          (s) => s.cause,
          'cause',
          isA<FileSystemException>(),
        ),
      );
    },
  );

  testWidgets('a transfer the wifi-only gate holds says so until it opens', (
    tester,
  ) async {
    final net = _Net();
    final gate = WifiOnlyGate(connectivity: net, wifiOnly: () => true);
    final downloads = FakeDownloads();
    addTearDown(() {
      gate.dispose();
      downloads.dispose();
    });
    await _pumpBoth(tester, downloads: downloads, gate: gate);
    await tester.pump();

    await tester.tap(_pill);
    await tester.pump();
    await tester.pump();

    final pill = tester.widget<WaxButton>(_pill);
    expect(pill.label, 'Waiting for wifi');
    expect(pill.detail, 'Download on wifi only is on');
    expect(pill.status, isTrue, reason: 'held, not a stalled 0%');
    final icon = tester.widget<WaxIconButton>(_icon);
    expect(icon.label, 'Waiting for wifi');
    expect(icon.detail, 'Download on wifi only is on');
    expect(icon.busy, isFalse);
    expect(icon.status, isTrue);

    net.move(ConnectionCost.unmetered);
    await tester.pump();
    await tester.pump();

    expect(tester.widget<WaxButton>(_pill).label, 'Downloading 0%');
    expect(tester.widget<WaxButton>(_pill).detail, isNull);
    expect(tester.widget<WaxIconButton>(_icon).busy, isTrue);
  });

  test('every transfer reads the one gate, asked once', () async {
    const other = 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1';
    final net = _Net();
    final gate = WifiOnlyGate(connectivity: net, wifiOnly: () => true);
    final downloads = FakeDownloads();
    addTearDown(() {
      gate.dispose();
      downloads.dispose();
    });
    final container = appContainer(
      downloads: downloads,
      extra: [transferGateProvider.overrideWithValue(gate)],
    );
    for (final pid in [_book, other]) {
      container.listen(downloadStateProvider(pid), (_, _) {});
    }
    await pumpEventQueue();

    for (final pid in [_book, other]) {
      unawaited(container.read(downloadStateProvider(pid).notifier).start());
    }
    await pumpEventQueue();

    for (final pid in [_book, other]) {
      expect(
        container.read(downloadStateProvider(pid)),
        isA<DownloadTransferring>().having((s) => s.held, 'held', isTrue),
      );
    }
    expect(net.asked, 1);
    expect(net.followed, 1);
  });

  testWidgets('a pause reads ready and a resume reads moving again', (
    tester,
  ) async {
    // As a fresh visit would read the same item each time.
    final net = _Net();
    final gate = WifiOnlyGate(connectivity: net, wifiOnly: () => true);
    final downloads = FakeDownloads();
    addTearDown(() {
      gate.dispose();
      downloads.dispose();
    });
    await _pumpBoth(tester, downloads: downloads, gate: gate);
    await tester.pump();
    await tester.tap(_pill);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<WaxButton>(_pill).label, 'Waiting for wifi');

    downloads.emit(
      const DownloadProgress(
        pid: _book,
        fraction: 0.25,
        complete: false,
        paused: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<WaxButton>(_pill).label, 'Download for offline');
    expect(tester.widget<WaxIconButton>(_icon).busy, isFalse);

    downloads.emit(
      const DownloadProgress(pid: _book, fraction: 0.25, complete: false),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<WaxButton>(_pill).label, 'Waiting for wifi');

    net.move(ConnectionCost.unmetered);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<WaxButton>(_pill).label, 'Downloading 25%');
  });

  testWidgets('a visit to a downloaded item never offers the download', (
    tester,
  ) async {
    final downloads = _SlowDownloads(
      local: {_book: testLocal('/books/one.m4b')},
    );
    addTearDown(downloads.dispose);
    final container = await _pumpBoth(tester, downloads: downloads);
    await tester.pump();

    // Until the device answers, nothing is pressable and no verb shows.
    expect(tester.widget<WaxButton>(_pill).onPressed, isNull);
    expect(tester.widget<WaxButton>(_pill).status, isTrue);
    expect(tester.widget<WaxIconButton>(_icon).onPressed, isNull);

    downloads.answer!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<WaxButton>(_pill).label, 'Downloaded');

    // Visited again: what this run already knows is done reads done at
    // once, before the device answers again.
    await _pumpBoth(tester, container: container, closed: true);
    await tester.pumpAndSettle();
    final again = downloads.answer = Completer<void>();
    await _pumpBoth(tester, container: container);
    await tester.pump();
    expect(tester.widget<WaxButton>(_pill).label, 'Downloaded');
    expect(tester.widget<WaxIconButton>(_icon).status, isTrue);
    again.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<WaxButton>(_pill).label, 'Downloaded');
  });

  test('a start ends when the manager goes away under it', () async {
    // A sign-out disposes the manager mid-transfer: its stream closes
    // and no ending will ever arrive on it.
    final downloads = FakeDownloads();
    final container = appContainer(downloads: downloads);
    container.listen(downloadStateProvider(_book), (_, _) {});
    await pumpEventQueue();

    var ended = false;
    unawaited(
      container
          .read(downloadStateProvider(_book).notifier)
          .start()
          .then((_) => ended = true),
    );
    await pumpEventQueue();
    expect(ended, isFalse);

    downloads.dispose();
    await pumpEventQueue();

    expect(ended, isTrue);
    expect(container.read(downloadStateProvider(_book)), isA<DownloadIdle>());
  });

  testWidgets('a device that will not say what it holds still offers the '
      'download', (tester) async {
    // Nothing pressable is drawn only until the device answers; one that
    // never answers must not leave the pill dead.
    final downloads = _ProbeFails();
    addTearDown(downloads.dispose);
    await _pumpBoth(tester, downloads: downloads);
    await tester.pump();

    expect(tester.widget<WaxButton>(_pill).onPressed, isNotNull);
    expect(tester.widget<WaxIconButton>(_icon).onPressed, isNotNull);
  });

  testWidgets('a removal no screen saw is not read as done on the next visit', (
    tester,
  ) async {
    final downloads = _SlowDownloads(local: {_book: testLocal('/b.m4b')})
      ..answer = null;
    addTearDown(downloads.dispose);
    final container = await _pumpBoth(tester, downloads: downloads);
    await tester.pumpAndSettle();
    expect(tester.widget<WaxButton>(_pill).label, 'Downloaded');

    // Removed from the Downloads screen while nothing here is drawn.
    await _pumpBoth(tester, container: container, closed: true);
    await tester.pumpAndSettle();
    unawaited(downloads.remove(_book));
    await tester.pumpAndSettle();

    final again = downloads.answer = Completer<void>();
    await _pumpBoth(tester, container: container);
    await tester.pump();
    expect(tester.widget<WaxButton>(_pill).label, isNot('Downloaded'));
    again.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<WaxButton>(_pill).label, 'Download for offline');
  });

  testWidgets('a gate answer a newer change overtook is dropped', (
    tester,
  ) async {
    final net = _Net()..costGate = Completer<void>();
    final first = net.costGate!;
    final gate = WifiOnlyGate(connectivity: net, wifiOnly: () => true);
    final downloads = FakeDownloads();
    addTearDown(() {
      gate.dispose();
      downloads.dispose();
    });
    await _pumpBoth(tester, downloads: downloads, gate: gate);
    await tester.pump();
    await tester.tap(_pill);
    await tester.pump();

    // The connection moves to wifi while the first ask, made on mobile
    // data, is still out; that answer lands last and says nothing.
    net.move(ConnectionCost.unmetered);
    await tester.pump();
    first.complete();
    await tester.pump();
    await tester.pump();

    expect(tester.widget<WaxButton>(_pill).label, 'Downloading 0%');
  });
}

/// A store whose completeness probe throws.
class _ProbeFails extends FakeDownloads {
  @override
  Future<bool> isComplete(String pid) async =>
      throw const FileSystemException('unreadable');
}

/// A store whose probe hits a bug rather than an unreadable disk.
class _ProbeBug extends FakeDownloads {
  @override
  Future<bool> isComplete(String pid) async => throw StateError('closed');
}
