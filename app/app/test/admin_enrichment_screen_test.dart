import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/admin/enrichment_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';

const _coverage = EnrichmentCoverage(
  artists: CoverageCount(enriched: 12, total: 40),
  releaseGroups: CoverageCount(enriched: 3, total: 0),
  books: CoverageCount(enriched: 1, total: 2),
  lyrics: CoverageCount(enriched: 0, total: 90),
  lyricsAsked: 7,
);

EnrichmentStatus _status({
  bool configured = true,
  bool running = false,
  String? runningJob,
  List<String> phases = const ['group-art', 'lyrics', 'track-fields'],
  EnrichmentLastRun? lastRun,
}) => EnrichmentStatus(
  providers: const [
    EnrichmentProvider(
      name: 'fanarttv',
      capabilities: ['aux-art', 'artist-art'],
      configured: true,
      builtin: false,
    ),
    EnrichmentProvider(
      name: 'deezer',
      capabilities: ['cover', 'lyrics'],
      configured: true,
      builtin: false,
    ),
    EnrichmentProvider(
      name: 'lrclib',
      capabilities: ['lyrics'],
      configured: false,
      builtin: true,
    ),
  ],
  coverage: _coverage,
  running: running,
  runningJob: runningJob,
  configured: configured,
  phases: phases,
  lastRun: lastRun,
);

({FakeRepository repo, ProviderContainer container}) _setUp(
  WidgetTester tester, {
  EnrichmentStatus? status,
}) {
  final repo = FakeRepository()..enrichmentStatus = status ?? _status();
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return (repo: repo, container: container);
}

Future<FakeRepository> _pump(
  WidgetTester tester, {
  EnrichmentStatus? status,
}) async {
  final (:repo, :container) = _setUp(tester, status: status);
  await _host(tester, container, const EnrichmentScreen());
  return repo;
}

Future<void> _host(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: localizedHost(child),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _id(String id) => find.bySemanticsIdentifier(id);

Future<void> _tap(WidgetTester tester, String id) async {
  await tester.ensureVisible(_id(id));
  await tester.tap(_id(id), warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a server with nothing to run says so and offers no run', (
    tester,
  ) async {
    final repo = await _pump(
      tester,
      status: _status(configured: false, phases: const []),
    );

    expect(find.textContaining('nothing to do'), findsOneWidget);
    await _tap(tester, SemanticsIds.enrichmentRun);
    expect(repo.runEnrichmentCalls, isEmpty);
  });

  testWidgets('a server whose sources are all off says to switch one on', (
    tester,
  ) async {
    final all = _status(configured: false, phases: const []);
    await _pump(
      tester,
      status: EnrichmentStatus(
        providers: [
          for (final p in all.providers)
            EnrichmentProvider(
              name: p.name,
              capabilities: p.capabilities,
              configured: p.configured,
              builtin: p.builtin,
              enabled: p.builtin,
            ),
        ],
        coverage: all.coverage,
        running: false,
        configured: false,
        phases: const [],
      ),
    );
    expect(
      find.text(
        'A pass has nothing to do: the sources that could run are switched '
        'off. Switch one on below, or set a MusicBrainz contact and restart.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('configure a provider'), findsNothing);
  });

  testWidgets('runs a pass, and a forced one over the phases chosen', (
    tester,
  ) async {
    final repo = await _pump(tester);

    await _tap(tester, SemanticsIds.enrichmentRun);
    expect(repo.runEnrichmentCalls.single.force, isFalse);
    expect(repo.runEnrichmentCalls.single.forcePhases, isEmpty);

    // Only the phases this server runs can be forced.
    await _tap(tester, SemanticsIds.enrichmentRunMode('phases'));
    expect(_id(SemanticsIds.enrichmentPhase('identity')), findsNothing);
    expect(find.text('Release-group artwork'), findsWidgets);
    await _tap(tester, SemanticsIds.enrichmentPhase('lyrics'));
    await _tap(tester, SemanticsIds.enrichmentRun);
    expect(repo.runEnrichmentCalls.last.forcePhases, ['lyrics']);

    await _tap(tester, SemanticsIds.enrichmentRunMode('all'));
    await _tap(tester, SemanticsIds.enrichmentRun);
    expect(repo.runEnrichmentCalls.last.force, isTrue);
  });

  testWidgets('moves and switches the sources, then saves the order', (
    tester,
  ) async {
    final repo = await _pump(tester);
    // The catalog's built-in moves and switches like the rest, and says
    // what it waits on.
    expect(
      find.text(
        'Lyrics. Built into the catalog. Waits on a MusicBrainz contact.',
      ),
      findsOneWidget,
    );
    await _tap(tester, SemanticsIds.enrichmentSourceUp('lrclib'));
    await _tap(tester, SemanticsIds.enrichmentSourceEnabled('lrclib'));
    await _tap(tester, SemanticsIds.enrichmentSourceDown('fanarttv'));
    await _tap(tester, SemanticsIds.enrichmentSourceEnabled('fanarttv'));
    await _tap(tester, SemanticsIds.enrichmentSourcesSave);

    final saved = repo.putEnrichmentSourcesCalls.single;
    expect(saved.map((s) => s.name), ['lrclib', 'fanarttv', 'deezer']);
    expect(saved.map((s) => s.enabled), [false, false, true]);
    // Saved is saved: nothing is left to revert.
    await _tap(tester, SemanticsIds.enrichmentSourcesSave);
    expect(repo.putEnrichmentSourcesCalls, hasLength(1));
  });

  testWidgets('a chosen phase the server stops offering runs nothing', (
    tester,
  ) async {
    final (:repo, :container) = _setUp(tester);
    await _host(tester, container, const EnrichmentScreen());
    await _tap(tester, SemanticsIds.enrichmentRunMode('phases'));
    await _tap(tester, SemanticsIds.enrichmentPhase('lyrics'));

    repo.enrichmentStatus = _status(
      phases: const ['group-art', 'track-fields'],
    );
    container.invalidate(enrichmentStatusProvider);
    await tester.pumpAndSettle();
    await _tap(tester, SemanticsIds.enrichmentRun);
    // Not a normal pass in its place.
    expect(repo.runEnrichmentCalls, isEmpty);
  });

  testWidgets('the move buttons point the way they move', (tester) async {
    await _pump(tester);
    WaxGlyph glyph(String id) => tester
        .widget<WaxIconButton>(
          find.ancestor(of: _id(id), matching: find.byType(WaxIconButton)),
        )
        .glyph;
    expect(glyph(SemanticsIds.enrichmentSourceUp('deezer')), WaxIcons.expand);
    expect(
      glyph(SemanticsIds.enrichmentSourceDown('deezer')),
      WaxIcons.collapse,
    );
  });

  testWidgets('a running pass is read again until it ends', (tester) async {
    final repo = await _pump(tester, status: _status(running: true));
    expect(find.text('A pass is running now.'), findsOneWidget);

    repo
      ..enrichmentStatus = _status()
      ..enrichmentCache = const EnrichmentCacheReport(rows: 4242, bytes: 0);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('A pass is running now.'), findsNothing);
    // What the pass cached is read once it ends.
    expect(find.text('4242'), findsOneWidget);
  });

  testWidgets('a revisit reads the status and the cache again', (tester) async {
    final (:repo, :container) = _setUp(tester, status: _status(running: true));
    await _host(tester, container, const EnrichmentScreen());
    expect(find.text('A pass is running now.'), findsOneWidget);

    await _host(tester, container, const SizedBox());
    repo
      ..enrichmentStatus = _status()
      ..enrichmentCache = const EnrichmentCacheReport(rows: 4242, bytes: 0);
    await _host(tester, container, const EnrichmentScreen());
    expect(find.text('A pass is running now.'), findsNothing);
    expect(find.text('4242'), findsOneWidget);
  });

  testWidgets('revert puts back the order the server holds', (tester) async {
    final repo = await _pump(tester);
    await _tap(tester, SemanticsIds.enrichmentSourceUp('deezer'));
    await _tap(tester, SemanticsIds.enrichmentSourcesRevert);
    await _tap(tester, SemanticsIds.enrichmentSourcesSave);

    expect(repo.putEnrichmentSourcesCalls, isEmpty);
    final order = [
      for (final name in ['fanarttv', 'deezer'])
        tester.getTopLeft(_id(SemanticsIds.enrichmentSource(name))).dy,
    ];
    expect(order.first, lessThan(order.last));
  });

  testWidgets('the last run shows its walks, and none says so', (tester) async {
    await _pump(tester);
    expect(find.text('No pass has finished yet.'), findsOneWidget);
  });

  testWidgets('a finished pass is listed walk by walk', (tester) async {
    await _pump(
      tester,
      status: _status(
        lastRun: EnrichmentLastRun(
          artistsEnriched: 314,
          artistsMatched: 271,
          artFetched: 58,
          finishedAt: DateTime.utc(2026, 9, 27, 3, 45),
        ),
      ),
    );
    expect(find.text('314'), findsOneWidget);
    expect(find.text('271'), findsOneWidget);
    expect(find.text('58'), findsOneWidget);
    expect(find.text('No pass has finished yet.'), findsNothing);
  });

  testWidgets('prunes the cache by age once the word is typed', (tester) async {
    final (:repo, :container) = _setUp(tester);
    repo.pruneEnrichmentCacheResult = const EnrichmentCachePruneResult(
      removed: 1,
      freedBytes: 2048,
    );
    await _host(tester, container, const EnrichmentScreen());
    await tester.enterText(_id(SemanticsIds.enrichmentCacheOlderThan), '30');
    await tester.pumpAndSettle();
    await _tap(tester, SemanticsIds.enrichmentCachePrune);
    expect(repo.pruneEnrichmentCacheCalls, isEmpty);

    await tester.enterText(_id(SemanticsIds.confirmField), 'PRUNE');
    await tester.pumpAndSettle();
    await _tap(tester, SemanticsIds.confirmAccept);

    expect(repo.pruneEnrichmentCacheCalls.single.olderThanSeconds, 30 * 86400);
    expect(repo.pruneEnrichmentCacheCalls.single.maxBytes, isNull);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      startsWith('1 answer pruned,'),
    );
  });

  testWidgets('coverage reads each class against its total', (tester) async {
    await _pump(tester);
    expect(find.text('12 of 40'), findsOneWidget);
    // An unknown total is not a total of zero.
    expect(find.text('3'), findsWidgets);
    expect(find.text('3 of 0'), findsNothing);
    expect(find.text('0 of 90'), findsOneWidget);
    expect(find.text('7 looked up, none found'), findsOneWidget);
  });

  testWidgets('lyrics nobody has looked up yet carry no caption', (
    tester,
  ) async {
    await _pump(
      tester,
      status: EnrichmentStatus(
        coverage: const EnrichmentCoverage(
          artists: CoverageCount(enriched: 0, total: 0),
          releaseGroups: CoverageCount(enriched: 0, total: 0),
          books: CoverageCount(enriched: 0, total: 0),
          lyrics: CoverageCount(enriched: 0, total: 12),
        ),
        running: false,
      ),
    );
    expect(find.text('0 of 12'), findsOneWidget);
    expect(find.textContaining('none found'), findsNothing);
  });

  testWidgets('a pass that owed lookups or stopped early says so', (
    tester,
  ) async {
    await _pump(
      tester,
      status: _status(
        lastRun: EnrichmentLastRun(
          deferred: 17,
          stalled: const ['lyrics', 'group-art'],
          finishedAt: DateTime.utc(2026, 9, 27, 3, 45),
        ),
      ),
    );
    expect(find.text('17'), findsOneWidget);
    expect(find.text('Left owed'), findsOneWidget);
    expect(
      find.text(
        'Stopped early: Lyrics, Release-group artwork. Every source serving '
        'them failed three times in a row and sat out the pass; the lookups '
        'they owe are asked once more on the next pass.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a pass that walked to the end says nothing of stalls', (
    tester,
  ) async {
    await _pump(
      tester,
      status: _status(
        lastRun: EnrichmentLastRun(finishedAt: DateTime.utc(2026, 9, 27)),
      ),
    );
    expect(find.textContaining('Stopped early'), findsNothing);
  });

  testWidgets('the MusicBrainz genres entry and one artist half read as such', (
    tester,
  ) async {
    await _pump(
      tester,
      status: const EnrichmentStatus(
        providers: [
          EnrichmentProvider(
            name: 'deezer',
            capabilities: ['cover', 'artist-front', 'fields'],
            configured: true,
            builtin: false,
          ),
          EnrichmentProvider(
            name: 'musicbrainz',
            capabilities: ['genres'],
            configured: true,
            builtin: true,
          ),
          EnrichmentProvider(
            name: 'lrclib',
            capabilities: ['lyrics'],
            configured: true,
            builtin: true,
          ),
        ],
        coverage: _coverage,
        running: false,
      ),
    );
    expect(find.text('Covers, Artist portraits, Details'), findsOneWidget);
    expect(find.text('Lyrics. Built into the catalog'), findsOneWidget);
    expect(
      find.text(
        'Genres. Built into the catalog. Switched off, its genres are left '
        'out; the identity lookups still run.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a status read that fails keeps the page and the edits', (
    tester,
  ) async {
    final (:repo, :container) = _setUp(tester, status: _status(running: true));
    await _host(tester, container, const EnrichmentScreen());
    await tester.enterText(_id(SemanticsIds.enrichmentCacheOlderThan), '30');
    await _tap(tester, SemanticsIds.enrichmentSourceDown('fanarttv'));

    repo.enrichmentStatusError = const WaxDeckApiException(
      code: 'catalog-maintenance',
      message: 'busy',
      statusCode: 503,
    );
    await tester.pump(enrichmentRunningPoll);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Could not load the enrichment status.'), findsNothing);
    expect(find.text('30'), findsOneWidget);
    final order = [
      for (final name in ['deezer', 'fanarttv'])
        tester.getTopLeft(_id(SemanticsIds.enrichmentSource(name))).dy,
    ];
    expect(order.first, lessThan(order.last));

    // Read again, once it answers.
    repo.enrichmentStatusError = null;
    repo.enrichmentStatus = _status();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('A pass is running now.'), findsNothing);
  });

  testWidgets('a moved source keeps its row, and the focus in it', (
    tester,
  ) async {
    await _pump(tester);
    final before = tester.element(
      _id(SemanticsIds.enrichmentSource('fanarttv')),
    );
    await _tap(tester, SemanticsIds.enrichmentSourceDown('fanarttv'));
    final after = tester.element(
      _id(SemanticsIds.enrichmentSource('fanarttv')),
    );
    expect(identical(before, after), isTrue);
  });

  testWidgets('a save is not undone by a read already out', (tester) async {
    final (:repo, :container) = _setUp(tester, status: _status(running: true));
    await _host(tester, container, const EnrichmentScreen());
    await _tap(tester, SemanticsIds.enrichmentSourceDown('fanarttv'));
    final gate = repo.enrichmentStatusGate = Completer<void>();
    await tester.pump(enrichmentRunningPoll);

    repo.enrichmentStatusGate = null;
    await _tap(tester, SemanticsIds.enrichmentSourcesSave);
    gate.complete();
    await tester.pumpAndSettle();

    final order = [
      for (final name in ['deezer', 'fanarttv'])
        tester.getTopLeft(_id(SemanticsIds.enrichmentSource(name))).dy,
    ];
    expect(order.first, lessThan(order.last));
    // Nothing left unsaved to offer.
    await _tap(tester, SemanticsIds.enrichmentSourcesSave);
    expect(repo.putEnrichmentSourcesCalls, hasLength(1));
    await _host(tester, container, const SizedBox());
  });

  testWidgets('a refused run reads the status and the jobs again', (
    tester,
  ) async {
    final (:repo, :container) = _setUp(tester);
    container.listen(adminJobsProvider, (_, _) {});
    await _host(tester, container, const EnrichmentScreen());
    final reads = (status: repo.enrichmentStatusReads, jobs: repo.jobReads);
    repo.runEnrichmentError = const WaxDeckApiException(
      code: 'conflict',
      message: 'an enrichment pass is already running',
      statusCode: 409,
    );

    await _tap(tester, SemanticsIds.enrichmentRun);

    expect(repo.enrichmentStatusReads, greaterThan(reads.status));
    expect(repo.jobReads, greaterThan(reads.jobs));
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'A pass is already running.',
    );
  });

  testWidgets('a started run shows on the jobs too', (tester) async {
    final (:repo, :container) = _setUp(tester);
    container.listen(adminJobsProvider, (_, _) {});
    await _host(tester, container, const EnrichmentScreen());
    final jobs = repo.jobReads;

    await _tap(tester, SemanticsIds.enrichmentRun);

    expect(repo.jobReads, greaterThan(jobs));
  });

  testWidgets('prune bounds that are not whole numbers are refused', (
    tester,
  ) async {
    final repo = await _pump(tester);
    for (final (field, typed) in [
      (SemanticsIds.enrichmentCacheMaxBytes, '1.5'),
      (SemanticsIds.enrichmentCacheOlderThan, '-5'),
      (SemanticsIds.enrichmentCacheMaxBytes, '17592186044416'),
    ]) {
      await tester.enterText(_id(SemanticsIds.enrichmentCacheOlderThan), '');
      await tester.enterText(_id(SemanticsIds.enrichmentCacheMaxBytes), '');
      await tester.enterText(_id(field), typed);
      await tester.pumpAndSettle();
      await _tap(tester, SemanticsIds.enrichmentCachePrune);
      expect(
        find.textContaining('whole number'),
        findsOneWidget,
        reason: typed,
      );
      expect(_id(SemanticsIds.confirmField), findsNothing, reason: typed);
    }
    expect(repo.pruneEnrichmentCacheCalls, isEmpty);
  });

  testWidgets('a prune confirmed after the screen went sends nothing', (
    tester,
  ) async {
    final (:repo, :container) = _setUp(tester);
    await _host(tester, container, const EnrichmentScreen());
    await tester.enterText(_id(SemanticsIds.enrichmentCacheOlderThan), '30');
    await tester.pumpAndSettle();
    await _tap(tester, SemanticsIds.enrichmentCachePrune);
    await tester.enterText(_id(SemanticsIds.confirmField), 'PRUNE');
    await tester.pumpAndSettle();

    // The screen's own route goes from under the dialog, as Back does.
    final screen = tester.element(find.byType(EnrichmentScreen));
    Navigator.of(screen).replace(
      oldRoute: ModalRoute.of(screen)!,
      newRoute: MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, SemanticsIds.confirmAccept);

    expect(tester.takeException(), isNull);
    expect(repo.pruneEnrichmentCacheCalls, isEmpty);
  });

  testWidgets('a pass still running says so, whatever is left to run', (
    tester,
  ) async {
    final (:repo, :container) = _setUp(
      tester,
      status: _status(configured: false, running: true, phases: const []),
    );
    await _host(tester, container, const EnrichmentScreen());
    expect(find.text('A pass is running now.'), findsOneWidget);
    // Left, so the pass's poll goes with the screen.
    await _host(tester, container, const SizedBox());
  });

  testWidgets('sources are read by name, not by id', (tester) async {
    final served = _status();
    await _pump(
      tester,
      status: EnrichmentStatus(
        providers: [
          const EnrichmentProvider(
            name: 'googlebooks',
            capabilities: ['book'],
            configured: true,
            builtin: false,
          ),
          ...served.providers,
        ],
        coverage: served.coverage,
        running: false,
        phases: served.phases,
      ),
    );
    expect(find.text('fanart.tv'), findsOneWidget);
    expect(find.text('Deezer'), findsOneWidget);
    expect(find.text('Google Books'), findsOneWidget);
    expect(find.text('fanarttv'), findsNothing);
  });

  testWidgets('a running pass is followed by its job alone', (tester) async {
    final (:repo, :container) = _setUp(
      tester,
      status: _status(running: true, runningJob: 'jb-1'),
    );
    repo.jobs = [const Job(pid: 'jb-1', kind: 'enrich', state: 'running')];
    await _host(tester, container, const EnrichmentScreen());
    final reads = repo.enrichmentStatusReads;

    await tester.pump(enrichmentRunningPoll);
    await tester.pump(enrichmentRunningPoll);
    expect(repo.enrichmentStatusReads, reads);
    expect(repo.jobByPidReads, 2);

    repo
      ..jobs = [const Job(pid: 'jb-1', kind: 'enrich', state: 'done')]
      ..enrichmentStatus = _status();
    await tester.pump(enrichmentRunningPoll);
    await tester.pumpAndSettle();
    expect(repo.enrichmentStatusReads, reads + 1);
    expect(find.text('A pass is running now.'), findsNothing);
  });

  testWidgets('a save the server refuses reads the sources again', (
    tester,
  ) async {
    final (:repo, :container) = _setUp(tester);
    await _host(tester, container, const EnrichmentScreen());
    await _tap(tester, SemanticsIds.enrichmentSourceDown('fanarttv'));
    repo.putEnrichmentSourcesError = const WaxDeckApiException(
      code: 'invalid-request',
      message:
          'the order must name every provider this server adds; missing itunes',
      statusCode: 400,
    );
    final reads = repo.enrichmentStatusReads;

    await _tap(tester, SemanticsIds.enrichmentSourcesSave);

    expect(repo.enrichmentStatusReads, greaterThan(reads));
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'The sources changed on the server. Look them over and save again.',
    );
  });

  testWidgets('the cache is asked for beside the status, not after it', (
    tester,
  ) async {
    final (:repo, :container) = _setUp(tester);
    repo.enrichmentStatusGate = Completer<void>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedHost(const EnrichmentScreen()),
      ),
    );
    await tester.pump();

    expect(repo.enrichmentCacheReads, 1);
    repo.enrichmentStatusGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.enrichmentCacheReads, 1);
  });

  testWidgets('a save that fails on the way keeps the edit', (tester) async {
    final (:repo, :container) = _setUp(tester);
    await _host(tester, container, const EnrichmentScreen());
    await _tap(tester, SemanticsIds.enrichmentSourceDown('fanarttv'));
    repo.putEnrichmentSourcesError = const WaxDeckApiException(
      code: 'transport',
      message: 'connection refused',
    );

    await _tap(tester, SemanticsIds.enrichmentSourcesSave);
    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Could not reach the server. Check the connection and try again.',
    );

    // The edit is still there to save once the server answers.
    repo.putEnrichmentSourcesError = null;
    await _tap(tester, SemanticsIds.enrichmentSourcesSave);
    expect(repo.putEnrichmentSourcesCalls, hasLength(2));
    expect(repo.putEnrichmentSourcesCalls.last.map((s) => s.name), [
      'deezer',
      'fanarttv',
      'lrclib',
    ]);
  });

  testWidgets('a save while a pass runs says that pass keeps its order', (
    tester,
  ) async {
    final (:repo, :container) = _setUp(
      tester,
      status: _status(running: true, runningJob: 'jb-1'),
    );
    repo.jobs = [const Job(pid: 'jb-1', kind: 'enrich', state: 'running')];
    await _host(tester, container, const EnrichmentScreen());
    await _tap(tester, SemanticsIds.enrichmentSourceDown('fanarttv'));

    await _tap(tester, SemanticsIds.enrichmentSourcesSave);

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'Source order saved. The pass running now keeps the order it started '
      'with.',
    );
    // Left, so the pass's poll goes with the screen.
    await _host(tester, container, const SizedBox());
  });

  testWidgets('a status rebuilt while it reads polls once', (tester) async {
    final (:repo, :container) = _setUp(
      tester,
      status: _status(running: true, runningJob: 'jb-1'),
    );
    repo.jobs = [const Job(pid: 'jb-1', kind: 'enrich', state: 'running')];
    final gate = repo.enrichmentStatusGate = Completer<void>();
    final listen = container.listen(enrichmentStatusProvider, (_, _) {});
    await tester.pump();
    container
      ..invalidate(enrichmentStatusProvider)
      ..read(enrichmentStatusProvider);
    await tester.pump();
    expect(repo.enrichmentStatusReads, 2, reason: 'both builds are out');
    repo.enrichmentStatusGate = null;
    gate.complete();
    await container.read(enrichmentStatusProvider.future);
    await tester.pump();

    await tester.pump(enrichmentRunningPoll);
    await tester.pump();

    // One poll, not one per build.
    expect(repo.jobByPidReads, 1);
    listen.close();
    container.dispose();
  });

  testWidgets('run is busy until the pass has started', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = await _pump(tester);
    repo.runEnrichmentGate = Completer<void>();

    await _tap(tester, SemanticsIds.enrichmentRun);
    WaxButton run() => tester.widget<WaxButton>(
      find.byWidgetPredicate(
        (w) => w is WaxButton && w.semanticsId == SemanticsIds.enrichmentRun,
      ),
    );
    expect(run().busy, isTrue);

    repo.runEnrichmentGate!.complete();
    await tester.pumpAndSettle();
    expect(run().busy, isFalse);
  });
}
