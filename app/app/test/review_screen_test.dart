import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/review/review_screen.dart';
import 'package:waxdeck/src/shell/navigation_history.dart';
import 'package:waxdeck/src/shell/pending_actions.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/shell/shortcuts.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'localized_host.dart';
import 'wax_finders.dart';

/// Narrow enough that the queue is the whole page: the detail pane is
/// the two-pane arrangement's business and every test here is about the
/// list and its keys.
///
/// Unrouted unless [routed], the reverse of [mountApp]'s default: a test
/// here stays on the list unless it opens an entry, which takes the app's
/// routes.
Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  bool routed = false,
}) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await mountApp(
    tester,
    const ReviewScreen(),
    container: container,
    routed: routed,
  );
}

/// The surface at the location it publishes, with the entry open.
Future<void> _pumpOpenEntry(WidgetTester tester, ProviderContainer container) =>
    pumpApp(
      tester,
      const ReviewSurface(openEntryId: 'rv-1'),
      container: container,
      at: '/review/rv-1',
    );

/// The surface on its own, with the entry open.
Future<void> _pumpSurface(WidgetTester tester, ProviderContainer container) =>
    pumpApp(
      tester,
      const ReviewSurface(openEntryId: 'rv-1'),
      container: container,
      routed: false,
    );

Finder _row(String id) =>
    find.bySemanticsIdentifier(SemanticsIds.reviewRow(id));

/// A pending entry with a release to approve it against.
ReviewEntryDetail _matchable(String id) => ReviewEntryDetail(
  id: id,
  kind: 'match',
  status: 'pending',
  mediaType: MediaType.music,
  origin: 'scan',
  trackCount: 1,
  createdAt: DateTime.utc(2026, 7, 1),
  candidates: const [
    ReviewCandidate(
      mbid: 'mb-1',
      title: 'Neon Meridian',
      artist: 'The Cardinal Waves',
      similarityPct: 94,
    ),
  ],
);

/// Decides, then fails every read of the queue after it.
class _RefetchFails extends FakeRepository {
  var _failing = false;

  @override
  Future<ReviewEntryPage> listReviewQueue({
    String? status,
    String? cursor,
    int? limit,
  }) async {
    if (_failing) {
      throw const WaxDeckApiException(
        code: 'transport',
        message: 'connection refused',
      );
    }
    return super.listReviewQueue(status: status, cursor: cursor, limit: limit);
  }

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
    String? mediaType,
    bool? useSuggested,
  }) async {
    final decided = await super.decideReviewEntry(
      entryId,
      action: action,
      candidateMbid: candidateMbid,
      mediaType: mediaType,
      useSuggested: useSuggested,
    );
    _failing = true;
    return decided;
  }
}

/// rv-1 to rv-3 pending, in that order, rv-1 approvable.
void _seedThree(FakeRepository repo) {
  repo.reviewEntries = [
    testReviewEntry('rv-1'),
    testReviewEntry('rv-2', title: 'Second Album'),
    testReviewEntry('rv-3', title: 'Third Album'),
  ];
  repo.reviewEntryDetails['rv-1'] = _matchable('rv-1');
}

/// Holds a decision on [held] before it is made, until [release]
/// completes; every other decision goes at once.
class _HeldOn extends FakeRepository {
  _HeldOn(this.held);

  final String held;
  final release = Completer<void>();

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
    String? mediaType,
    bool? useSuggested,
  }) async {
    if (entryId == held) await release.future;
    return super.decideReviewEntry(
      entryId,
      action: action,
      candidateMbid: candidateMbid,
      mediaType: mediaType,
      useSuggested: useSuggested,
    );
  }
}

/// Reads a decided entry's detail off its row, as the server does once
/// it is filed, so the pane draws it decided; holds a revert's answer
/// while [revertGate] is set.
class _Revertible extends FakeRepository {
  Completer<void>? revertGate;

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
    String? mediaType,
    bool? useSuggested,
  }) {
    reviewEntryDetails.remove(entryId);
    return super.decideReviewEntry(
      entryId,
      action: action,
      candidateMbid: candidateMbid,
      mediaType: mediaType,
      useSuggested: useSuggested,
    );
  }

  @override
  Future<ReviewEntry> revertReviewEntry(String entryId) async {
    await revertGate?.future;
    return super.revertReviewEntry(entryId);
  }
}

/// Answers a decision on any entry in [warnings] with its warnings, as a
/// write-back that failed on a file.
class _Warns extends FakeRepository {
  _Warns({super.sessionState});

  final warnings = <String, List<String>>{};

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
    String? mediaType,
    bool? useSuggested,
  }) async {
    final decided = await super.decideReviewEntry(
      entryId,
      action: action,
      candidateMbid: candidateMbid,
      mediaType: mediaType,
      useSuggested: useSuggested,
    );
    return ReviewDecideResult(
      entry: decided.entry,
      warnings: warnings[entryId] ?? const [],
    );
  }
}

/// Holds the read of an entry's detail while [detailGates] has a gate for
/// it, so the pane draws its skeleton for as long as a test needs.
class _DetailHeld extends FakeRepository {
  _DetailHeld({super.sessionState});

  final detailGates = <String, Completer<void>>{};

  @override
  Future<ReviewEntryDetail> getReviewEntry(String entryId) async {
    await detailGates[entryId]?.future;
    return super.getReviewEntry(entryId);
  }
}

const _admin = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

/// Decides at once, then holds the answer until [release] completes.
class _HeldDecisions extends FakeRepository {
  _HeldDecisions({super.sessionState});

  final release = Completer<void>();

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
    String? mediaType,
    bool? useSuggested,
  }) async {
    final decided = await super.decideReviewEntry(
      entryId,
      action: action,
      candidateMbid: candidateMbid,
      mediaType: mediaType,
      useSuggested: useSuggested,
    );
    await release.future;
    return decided;
  }

  @override
  Future<List<ReviewBulkOutcome>> decideReviewBulk(
    List<String> entryIds, {
    required String action,
  }) async {
    final outcomes = await super.decideReviewBulk(entryIds, action: action);
    await release.future;
    return outcomes;
  }
}

void main() {
  testWidgets('a failed queue draws Try again busy while it retries', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..reviewError = const WaxDeckApiException(
        code: 'internal',
        message: 'down',
        statusCode: 500,
      );
    await _pump(tester, appContainer(repo: repo));
    await tester.pump();
    // Every retry from here on waits, as on a server that has gone away.
    repo.reviewQueueGate = Completer<void>();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final retry = find.widgetWithText(WaxButton, 'Try again');
    expect(retry, findsOneWidget);
    expect(tester.widget<WaxButton>(retry).busy, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the next page of the queue is a ghost row that fits its slot', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..reviewEntries = [
        for (var i = 0; i <= ReviewQueueController.pageSize; i++)
          testReviewEntry('rv-$i'),
      ];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    final rowHeight = tester.getSize(_row('rv-0')).height;
    repo.reviewQueueGate = Completer<void>();
    final loading = container.read(reviewQueueProvider.notifier).loadMore();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byType(SkeletonShapes),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    // The slot is the list's fixed row extent, which is what the real
    // rows measure: the ghost stands exactly where one of them would.
    expect(
      tester.getSize(find.byType(SkeletonShapes)).height,
      moreOrLessEquals(rowHeight),
    );
    expect(find.byType(WaxSpinner), findsNothing);
    expect(tester.takeException(), isNull);
    repo.reviewQueueGate!.complete();
    await loading;
    await tester.pumpAndSettle();
  });

  testWidgets('the queue loading ghost fits a short window', (tester) async {
    tester.view.physicalSize = const Size(900, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
    repo.reviewQueueGate = Completer<void>();
    await mountApp(
      tester,
      const ReviewScreen(),
      container: appContainer(repo: repo),
      routed: false,
    );
    await tester.pump();

    expect(find.byType(SkeletonShapes), findsOneWidget);
    expect(tester.takeException(), isNull);
    repo.reviewQueueGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the Decided chip counts reverted and discarded entries', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', status: 'applied'),
      testReviewEntry('rv-3', status: 'reverted'),
      testReviewEntry('rv-4', status: 'discarded'),
    ];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('Pending (1)'), findsOneWidget);
    expect(find.text('Decided (3)'), findsOneWidget);
  });

  testWidgets("the queue pads none of the window's insets: the page and "
      'its bar have taken them', (tester) async {
    const insets = FakeViewPadding(top: 24, bottom: 34);
    tester.view
      ..padding = insets
      ..viewPadding = insets;
    final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
    await _pump(tester, appContainer(repo: repo));
    await tester.pump();

    final list = find
        .ancestor(of: _row('rv-1'), matching: find.byType(ListView))
        .first;
    expect(
      tester
          .widget<SliverPadding>(
            find.descendant(of: list, matching: find.byType(SliverPadding)),
          )
          .padding,
      EdgeInsets.zero,
    );
    expect(tester.getRect(list).bottom, 1400 - 34, reason: 'its foot');
  });

  testWidgets("selecting, the bulk bar's surface reaches the window's edges "
      'at the foot, its controls and the queue above it clear of the '
      'insets', (tester) async {
    const insets = FakeViewPadding(left: 40, right: 30, bottom: 20);
    tester.view
      ..padding = insets
      ..viewPadding = insets;
    final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();
    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();

    final bulk = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_BulkBar',
      ),
    );
    expect((bulk.left, bulk.right, bulk.bottom), (0.0, 700.0, 1400.0));
    final skip = tester.getRect(
      find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip),
    );
    expect(skip.right, 700 - 30 - 16.0, reason: 'its controls, the end');
    expect(skip.bottom, lessThanOrEqualTo(1400 - 20.0));
    final queue = tester.getRect(
      find.ancestor(of: _row('rv-1'), matching: find.byType(ListView)).first,
    );
    expect((queue.left, queue.right, queue.bottom), (40.0, 670.0, bulk.top));
  });

  testWidgets('renders entries with best-candidate and identifying rows', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry(
        'rv-1',
        best: const CandidateSummary(
          mbid: 'mb-1',
          title: 'Neon Meridian',
          artist: 'The Cardinal Waves',
          year: 2011,
          similarityPct: 94,
        ),
      ),
      testReviewEntry(
        'rv-2',
        title: 'Mystery Tape',
        identifying: true,
        origin: 'upload',
      ),
    ];
    await _pump(tester, appContainer(repo: repo));
    // No pumpAndSettle: the identifying row's spinner animates forever.
    await tester.pump();
    await tester.pump();

    expect(_row('rv-1'), findsOneWidget);
    expect(
      find.text('10 tracks, 94% Neon Meridian, The Cardinal Waves (2011)'),
      findsOneWidget,
    );
    final identifyingRow = _row('rv-2');
    expect(
      find.descendant(of: identifyingRow, matching: find.byType(WaxSpinner)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: identifyingRow, matching: find.text('Upload')),
      findsOneWidget,
    );
  });

  testWidgets('a row says how many of its files the library holds', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1', origin: 'upload', duplicateCount: 2),
      testReviewEntry('rv-2', origin: 'upload'),
    ];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: _row('rv-1'), matching: find.text('2 duplicates')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row('rv-2'),
        matching: find.textContaining('duplicate'),
      ),
      findsNothing,
    );
  });

  testWidgets('a decided row drops its duplicates chip', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1', origin: 'upload', duplicateCount: 1),
      testReviewEntry(
        'rv-2',
        origin: 'upload',
        status: 'as-is',
        duplicateCount: 1,
      ),
    ];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.reviewFilter(ReviewFilter.decided.name),
      ),
    );
    await tester.pumpAndSettle();

    expect(_row('rv-2'), findsOneWidget);
    expect(
      find.descendant(of: _row('rv-2'), matching: find.text('1 duplicate')),
      findsNothing,
    );
  });

  testWidgets('j and k move the selection and a approves it', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    // Down twice, back up once: the selection must land on the first
    // row again, and a decides exactly that row.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls, hasLength(1));
    expect(repo.decideReviewCalls.single.entryId, 'rv-1');
    expect(repo.decideReviewCalls.single.action, 'approve');
    expect(repo.decideReviewCalls.single.mediaType, isNull);
  });

  testWidgets('a sends a staged row\'s medium', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [testReviewEntry('rv-1', origin: 'upload')];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls.single.action, 'approve');
    expect(repo.decideReviewCalls.single.mediaType, 'music');
  });

  testWidgets('a does not approve an audiobook against a release', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1', origin: 'upload', mediaType: MediaType.audiobook),
    ];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();
    final raised = <String?>[];
    container.listen(
      shellMessagesProvider,
      (_, next) => raised.add(shellMessageText(next)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls, isEmpty);
    expect(raised, ['Approve is not offered for an audiobook; keep it as is.']);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.action, 'skip');
  });

  testWidgets('the medium chosen in the pane reaches the keys', (tester) async {
    final repo = FakeRepository()
      ..reviewEntries = [testReviewEntry('rv-1', origin: 'upload')];
    final container = appContainer(repo: repo);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpOpenEntry(tester, container);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewMediumOption('audiobook')),
    );
    await tester.pumpAndSettle();
    final raised = <String?>[];
    container.listen(
      shellMessagesProvider,
      (_, next) => raised.add(shellMessageText(next)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls, isEmpty);
    expect(raised, ['Approve is not offered for an audiobook; keep it as is.']);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.action, 'unofficial');
    expect(repo.decideReviewCalls.single.mediaType, 'audiobook');
  });

  group('u with the suggested artist and title', () {
    const suggestion = ReviewOverride(artist: 'Mono Tides', title: 'Long Dive');

    Future<FakeRepository> open(WidgetTester tester, {bool on = false}) async {
      final repo = FakeRepository()
        ..reviewEntries = [testReviewEntry('rv-1', origin: 'acquisition')]
        ..reviewEntryDetails['rv-1'] = ReviewEntryDetail(
          id: 'rv-1',
          kind: 'match',
          status: 'pending',
          mediaType: MediaType.music,
          origin: 'acquisition',
          trackCount: 1,
          suggested: suggestion,
          createdAt: DateTime.utc(2026, 7, 1),
        );
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpOpenEntry(tester, appContainer(repo: repo));
      if (on) {
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.reviewUseSuggested),
        );
        await tester.pumpAndSettle();
      }
      return repo;
    }

    testWidgets('follows the pane\'s control when on', (tester) async {
      final repo = await open(tester, on: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.action, 'unofficial');
      expect(repo.decideReviewCalls.single.useSuggested, isTrue);
    });

    testWidgets('sends nothing extra when off', (tester) async {
      final repo = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.action, 'unofficial');
      expect(repo.decideReviewCalls.single.useSuggested, isNull);
    });

    testWidgets('u never sends it for an audiobook', (tester) async {
      final repo = await open(tester, on: true);
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.reviewMediumOption('audiobook'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.action, 'unofficial');
      expect(repo.decideReviewCalls.single.mediaType, 'audiobook');
      expect(repo.decideReviewCalls.single.useSuggested, isNull);
    });

    testWidgets('a never sends it', (tester) async {
      final repo = await open(tester, on: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.action, 'approve');
      expect(repo.decideReviewCalls.single.useSuggested, isNull);
    });

    testWidgets('u with the pane closed sends no useSuggested', (tester) async {
      final repo = await open(tester, on: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewUseSuggested),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.action, 'unofficial');
      expect(repo.decideReviewCalls.single.useSuggested, isNull);
    });

    testWidgets('reopening the entry finds the switch off', (tester) async {
      await open(tester, on: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();
      final control = find.ancestor(
        of: find.bySemanticsIdentifier(SemanticsIds.reviewUseSuggested),
        matching: find.byType(WaxSwitch),
      );
      expect(tester.widget<WaxSwitch>(control).value, isFalse);
    });

    testWidgets('s never sends it', (tester) async {
      final repo = await open(tester, on: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.action, 'skip');
      expect(repo.decideReviewCalls.single.useSuggested, isNull);
    });
  });

  testWidgets('a medium picked before a track landed is not sent by a key', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..reviewEntries = [testReviewEntry('rv-1', origin: 'upload')];
    final container = appContainer(repo: repo);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpOpenEntry(tester, container);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewMediumOption('audiobook')),
    );
    await tester.pumpAndSettle();

    repo.reviewEntryDetails['rv-1'] = ReviewEntryDetail(
      id: 'rv-1',
      kind: 'match',
      status: 'pending',
      mediaType: MediaType.music,
      origin: 'upload',
      mediumFixed: true,
      title: 'Neon Meridian',
      trackCount: 1,
      createdAt: DateTime.utc(2026, 7, 1),
      tracks: const [
        ReviewTrack(pid: 'tr-1', path: 'a.flac', title: 'a', durationMs: 1000),
      ],
    );
    container.invalidate(reviewEntryProvider('rv-1'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.action, 'unofficial');
    expect(repo.decideReviewCalls.single.mediaType, 'music');
  });

  ReviewEntryDetail stagedDetail({bool landed = false, String? libraryPid}) =>
      ReviewEntryDetail(
        id: 'rv-1',
        kind: 'match',
        status: 'pending',
        mediaType: MediaType.music,
        origin: 'upload',
        libraryPid: libraryPid,
        mediumFixed: landed,
        title: 'Neon Meridian',
        trackCount: 1,
        createdAt: DateTime.utc(2026, 7, 1),
        tracks: [
          ReviewTrack(
            pid: landed ? 'tr-1' : null,
            path: 'a.flac',
            title: 'a',
            durationMs: 1000,
          ),
        ],
      );

  testWidgets('a refused key decision is sent again with the medium the '
      'entry offers then', (tester) async {
    final repo = FakeRepository()
      ..reviewEntries = [testReviewEntry('rv-1', origin: 'upload')];
    final container = appContainer(repo: repo);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpOpenEntry(tester, container);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewMediumOption('audiobook')),
    );
    await tester.pumpAndSettle();

    repo.reviewError = const WaxDeckApiException(
      code: 'catalog-busy',
      message: 'a conflicting catalog job is already running',
      statusCode: 409,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.mediaType, 'audiobook');
    final message = container.read(shellMessagesProvider)!;
    expect(message.actionLabel, 'Retry');

    repo.reviewError = null;
    repo.reviewEntryDetails['rv-1'] = stagedDetail(landed: true);
    container.invalidate(reviewEntryProvider('rv-1'));
    await tester.pumpAndSettle();
    message.onAction!();
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls, hasLength(2));
    expect(repo.decideReviewCalls.last.mediaType, 'music');
  });

  testWidgets('a medium picked on a row whose pane is not open is not sent by '
      'a key', (tester) async {
    final repo = FakeRepository()
      ..reviewEntries = [testReviewEntry('rv-1', origin: 'upload')];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();
    container
        .read(selectedMediumProvider('rv-1').notifier)
        .select(MediaType.audiobook);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls.single.mediaType, 'music');
  });

  testWidgets('a medium the entry\'s library no longer takes is not sent', (
    tester,
  ) async {
    const mixed = UploadTarget(
      pid: 'lb-1',
      name: 'Library',
      mediaTypes: [MediaType.music, MediaType.audiobook],
      managed: true,
    );
    final repo = FakeRepository()
      ..reviewEntries = [testReviewEntry('rv-1', origin: 'upload')]
      ..reviewEntryDetails['rv-1'] = stagedDetail(libraryPid: 'lb-1')
      ..uploadTargets.add(mixed);
    final container = appContainer(repo: repo);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpOpenEntry(tester, container);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewMediumOption('audiobook')),
    );
    await tester.pumpAndSettle();

    repo.uploadTargets
      ..clear()
      ..add(
        const UploadTarget(
          pid: 'lb-1',
          name: 'Library',
          mediaTypes: [MediaType.music],
          managed: true,
        ),
      );
    container.invalidate(uploadTargetsProvider);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pumpAndSettle();

    expect(repo.decideReviewCalls.single.mediaType, 'music');
  });

  testWidgets('deciding the last row keeps the keys working', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    // Down to the last row and decide it: the queue shortens under the
    // cursor, which used to leave every decision key guarding itself
    // out until j or k pulled the index back into range.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.entryId, 'rv-2');

    // The next key decides the row the cursor landed on, with no j or k
    // in between.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls, hasLength(2));
    expect(repo.decideReviewCalls.last.entryId, 'rv-1');
  });

  testWidgets('the selected row is highlighted', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [testReviewEntry('rv-1')];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final material = tester.widget<Material>(
      find.descendant(of: _row('rv-1'), matching: find.byType(Material)).first,
    );
    final context = tester.element(_row('rv-1'));
    expect(material.color, WaxColors.of(context).accentContainer);
  });

  testWidgets('typing in a text field does not trigger shortcuts', (
    tester,
  ) async {
    // Exercises the AppShortcuts guard the review screen's bindings sit
    // behind: a binding fires while the shortcut scope holds focus, and
    // stays silent once an EditableText takes primary focus.
    var fired = 0;
    await tester.pumpWidget(
      localizedHost(
        Scaffold(
          body: AppShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyA): () => fired++,
            },
            child: const TextField(key: Key('guard-field')),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fired, 1);

    await tester.tap(find.byKey(const Key('guard-field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fired, 1);
  });

  testWidgets('bulk select decides every checked entry', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();

    expect(
      repo.reviewEntries.where((e) => e.status == 'skipped'),
      hasLength(2),
    );
    expect(
      shellMessageText(container.read(shellMessagesProvider)),
      'Decided 2 entries',
    );
  });

  testWidgets('a key pressed again while its decision runs sends nothing', (
    tester,
  ) async {
    final repo = _HeldDecisions();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(repo.decideReviewCalls, hasLength(1));

    repo.release.complete();
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls.single.action, 'skip');
  });

  testWidgets('a key for another entry goes while one decision runs', (
    tester,
  ) async {
    final repo = _HeldDecisions();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-1', 'rv-2']);

    repo.release.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a bulk decision in flight draws busy and takes no second '
      'press', (tester) async {
    final repo = _HeldDecisions();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    WaxButton button(String id) =>
        tester.widget<WaxButton>(waxControl<WaxButton>(id));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pump();
    expect(button(SemanticsIds.reviewBulkSkip).busy, isTrue);
    expect(button(SemanticsIds.reviewBulkApprove).onPressed, isNull);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip),
      warnIfMissed: false,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewBulkApprove),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repo.decideBulkCalls, hasLength(1));

    repo.release.complete();
    await tester.pumpAndSettle();
    expect(
      shellMessageText(container.read(shellMessagesProvider)),
      'Decided 2 entries',
    );
  });

  testWidgets('a busy library offers the same decision again', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [testReviewEntry('rv-1')];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    repo.reviewError = const WaxDeckApiException(
      code: 'catalog-busy',
      message: 'a conflicting catalog job is already running',
      statusCode: 409,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    final message = container.read(shellMessagesProvider)!;
    expect(
      shellMessageText(message),
      "Another job is holding the library's files. Try again shortly.",
    );
    expect(message.actionLabel, 'Retry');

    repo.reviewError = null;
    message.onAction!();
    await tester.pumpAndSettle();
    expect(repo.decideReviewCalls, hasLength(2));
    expect(repo.decideReviewCalls.last.entryId, 'rv-1');
    expect(repo.reviewEntries.single.status, isNot('pending'));
  });

  testWidgets('a bulk decision says what the server warned of and sends the '
      'busy entries again', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    repo.bulkOutcomes.addAll({
      'rv-1': const ReviewBulkOutcome(
        entryId: 'rv-1',
        ok: true,
        warnings: ['one.flac: already in the library; nothing was added'],
      ),
      'rv-2': const ReviewBulkOutcome(
        entryId: 'rv-2',
        ok: false,
        code: 'catalog-busy',
        error: 'a conflicting catalog job is already running',
      ),
    });
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();

    final message = container.read(shellMessagesProvider)!;
    expect(
      shellMessageText(message),
      'Decided 1 entry, 1 failed\n'
      "Another job is holding the library's files. Try again shortly.\n"
      'one.flac: already in the library; nothing was added',
    );
    expect(message.actionLabel, 'Retry');
    message.onAction!();
    await tester.pumpAndSettle();
    expect(repo.decideBulkCalls.last.entryIds, ['rv-2']);
    expect(repo.decideBulkCalls.last.action, 'skip');
  });

  testWidgets('a decision refused for a reason keeps the server\'s words', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [testReviewEntry('rv-1', origin: 'upload')];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    repo.reviewError = const WaxDeckApiException(
      code: 'conflict',
      message: 'a.flac: destination already exists in the library',
      statusCode: 409,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();

    // Which file and why: the table's "something changed first" would
    // send the person to try the same thing again.
    final message = container.read(shellMessagesProvider)!;
    expect(
      shellMessageText(message),
      'a.flac: destination already exists in the library',
    );
    expect(message.actionLabel, isNull, reason: 'trying again changes nothing');
  });

  testWidgets('a bulk decision names the one refusal it met', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', title: 'Second Album'),
    ];
    repo.bulkOutcomes['rv-2'] = const ReviewBulkOutcome(
      entryId: 'rv-2',
      ok: false,
      code: 'conflict',
      error: 'b.flac: destination already exists in the library',
    );
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();

    final message = container.read(shellMessagesProvider)!;
    expect(
      shellMessageText(message),
      'Decided 1 entry, 1 failed\n'
      'b.flac: destination already exists in the library',
    );
    expect(message.actionLabel, isNull);
  });

  testWidgets('a bulk approve passes over entries holding duplicates', (
    tester,
  ) async {
    // What the a and u keys do, for the same reason: the pane holds
    // those two back from a unit the library already has, and the row
    // only knows that something matched.
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1'),
      testReviewEntry('rv-2', origin: 'upload', duplicateCount: 2),
      testReviewEntry('rv-3', origin: 'upload', duplicateCount: 1),
    ];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-3'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewBulkApprove),
    );
    await tester.pumpAndSettle();

    expect(repo.decideBulkCalls.single.entryIds, ['rv-1']);
    expect(
      {for (final e in repo.reviewEntries) e.id: e.status},
      {'rv-1': 'applied', 'rv-2': 'pending', 'rv-3': 'pending'},
    );
    expect(
      shellMessageText(container.read(shellMessagesProvider)),
      'Decided 1 entry\n'
      '2 entries hold duplicates; open each to decide',
    );
  });

  testWidgets('a bulk approve of entries that all hold duplicates sends '
      'nothing', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1', origin: 'upload', duplicateCount: 2),
      testReviewEntry('rv-2'),
    ];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.reviewBulkApprove),
    );
    await tester.pumpAndSettle();

    expect(repo.decideBulkCalls, isEmpty);
    expect(repo.reviewEntries.first.status, 'pending');
    expect(
      shellMessageText(container.read(shellMessagesProvider)),
      '1 entry holds duplicates; open it to decide',
    );
    // Out of selection, where a tap on the row opens it.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.reviewBulkApprove),
      findsNothing,
    );
  });

  group('a bulk decision and the medium chosen in a pane', () {
    /// rv-1 open beside the queue and switched to Audiobook, rv-3 an
    /// audiobook of its own; all three selected.
    Future<ProviderContainer> pumpSwitched(
      WidgetTester tester,
      FakeRepository repo, {
      List<ReviewEntry> more = const [],
    }) async {
      repo.reviewEntries = [
        testReviewEntry('rv-1', origin: 'upload'),
        testReviewEntry('rv-2', origin: 'upload', title: 'Second Album'),
        testReviewEntry(
          'rv-3',
          origin: 'upload',
          title: 'Third Album',
          mediaType: MediaType.audiobook,
        ),
        ...more,
      ];
      final container = appContainer(repo: repo);
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpOpenEntry(tester, container);
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.reviewMediumOption('audiobook'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(_row('rv-1'));
      await tester.pumpAndSettle();
      await tester.tap(_row('rv-2'));
      await tester.pumpAndSettle();
      await tester.tap(_row('rv-3'));
      await tester.pumpAndSettle();
      for (final entry in more) {
        await tester.tap(_row(entry.id));
        await tester.pumpAndSettle();
      }
      return container;
    }

    testWidgets('keep as is holds back an entry switched to audiobook', (
      tester,
    ) async {
      final repo = FakeRepository();
      final container = await pumpSwitched(tester, repo);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkAsIs));
      await tester.pumpAndSettle();

      expect(repo.decideBulkCalls.single.entryIds, ['rv-2', 'rv-3']);
      expect(
        shellMessageText(container.read(shellMessagesProvider)),
        'Decided 2 entries\n'
        '1 entry is set to a medium a bulk decision does not cover; '
        'open it to decide',
      );
    });

    testWidgets('approve never sends an audiobook', (tester) async {
      final repo = FakeRepository();
      final container = await pumpSwitched(tester, repo);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.reviewBulkApprove),
      );
      await tester.pumpAndSettle();

      expect(repo.decideBulkCalls.single.entryIds, ['rv-2']);
      expect(
        shellMessageText(container.read(shellMessagesProvider)),
        'Decided 1 entry\n'
        '2 entries are set to a medium a bulk decision does not cover; '
        'open each to decide',
      );
    });

    testWidgets('approve says the duplicates and the medium apart', (
      tester,
    ) async {
      final repo = FakeRepository();
      final container = await pumpSwitched(
        tester,
        repo,
        more: [
          testReviewEntry(
            'rv-4',
            origin: 'upload',
            title: 'Fourth Album',
            duplicateCount: 1,
          ),
        ],
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.reviewBulkApprove),
      );
      await tester.pumpAndSettle();

      expect(repo.decideBulkCalls.single.entryIds, ['rv-2']);
      expect(
        shellMessageText(container.read(shellMessagesProvider)),
        'Decided 1 entry\n'
        '1 entry holds duplicates; open it to decide\n'
        '2 entries are set to a medium a bulk decision does not cover; '
        'open each to decide',
      );
    });

    testWidgets('skip still decides every entry', (tester) async {
      final repo = FakeRepository();
      await pumpSwitched(tester, repo);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
      await tester.pumpAndSettle();

      expect(repo.decideBulkCalls.single.entryIds, ['rv-1', 'rv-2', 'rv-3']);
    });
  });

  testWidgets('a bulk skip still decides entries holding duplicates', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      testReviewEntry('rv-1', origin: 'upload', duplicateCount: 2),
    ];
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();

    expect(repo.decideBulkCalls.single.entryIds, ['rv-1']);
    expect(
      shellMessageText(container.read(shellMessagesProvider)),
      'Decided 1 entry',
    );
  });

  testWidgets('a bulk Retry leaves a selection made since alone', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntries = [
      for (final id in ['rv-1', 'rv-2', 'rv-5', 'rv-6']) testReviewEntry(id),
    ];
    repo.bulkOutcomes['rv-2'] = const ReviewBulkOutcome(
      entryId: 'rv-2',
      ok: false,
      code: 'catalog-busy',
      error: 'a conflicting catalog job is already running',
    );
    final container = appContainer(repo: repo);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    await tester.longPress(_row('rv-1'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();
    final retry = container.read(shellMessagesProvider)!;
    expect(retry.actionLabel, 'Retry');

    // A new selection, then the old offer taken up.
    await tester.longPress(_row('rv-5'));
    await tester.pumpAndSettle();
    await tester.tap(_row('rv-6'));
    await tester.pumpAndSettle();
    retry.onAction!();
    await tester.pumpAndSettle();
    expect(repo.decideBulkCalls.last.entryIds, ['rv-2']);

    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
    await tester.pumpAndSettle();
    expect(repo.decideBulkCalls.last.entryIds, ['rv-5', 'rv-6']);
  });

  for (final (key, action) in [
    (LogicalKeyboardKey.keyA, 'approve'),
    (LogicalKeyboardKey.keyU, 'unofficial'),
  ]) {
    testWidgets('$action from the list opens an entry holding duplicates', (
      tester,
    ) async {
      // The pane can tell which decisions a copy of the library's own
      // audio leaves open; the row only knows that something matched.
      final repo = FakeRepository();
      repo.reviewEntries = [
        testReviewEntry('rv-1', origin: 'upload', duplicateCount: 2),
      ];
      final container = appContainer(repo: repo);
      await _pump(tester, container, routed: true);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();

      expect(repo.decideReviewCalls, isEmpty);
      expect(find.byType(ReviewEntryScreen), findsOneWidget);
    });
  }

  testWidgets('a and u on the entry its pane already shows say where it is '
      'decided', (tester) async {
    // Opening it again would land where the reviewer already is.
    final repo = FakeRepository()
      ..reviewEntries = [
        testReviewEntry('rv-1', origin: 'upload', duplicateCount: 1),
      ];
    final container = appContainer(repo: repo);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpOpenEntry(tester, container);
    expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsOneWidget);
    final raised = <String?>[];
    container.listen(
      shellMessagesProvider,
      (_, next) => raised.add(shellMessageText(next)),
    );

    for (final key in [LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyU]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(raised, [
      for (var i = 0; i < 2; i++)
        'This entry holds duplicates; decide it with its own buttons.',
    ]);
    expect(repo.decideReviewCalls, isEmpty);
  });

  testWidgets('a failing queue shows the error with a retry', (tester) async {
    final repo = FakeRepository();
    repo.reviewError = const WaxDeckApiException(
      code: 'internal',
      message: 'queue exploded',
      statusCode: 500,
    );
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    // The code's own sentence rather than the server's: a failed read
    // refused nothing anybody typed. The title was drawn before the
    // conversion too, so the absent server line is what proves it.
    expect(find.text('Could not load the review queue'), findsOneWidget);
    expect(
      find.text('The server ran into a problem it could not handle.'),
      findsOneWidget,
    );
    expect(find.text('queue exploded'), findsNothing);
    repo.reviewError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing waiting for review'), findsOneWidget);
  });

  testWidgets('an admin sets a library matching mode from the bar', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
          username: 'admin',
          roles: ['admin'],
        ),
      ),
    );
    repo.libraries.add(const LibraryInfo(pid: 'lb-1', name: 'Music'));
    // Singles deliberately non-default, so the survival assert below
    // can only pass if the write actually carried the stored value.
    repo.matchingModes['lb-1'] = const LibraryMatching(
      mode: 'auto',
      singlesAutoApply: true,
    );
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.matchingMenu));
    await tester.pumpAndSettle();
    expect(find.text('Music: Review everything'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.matchingOption('lb-1', 'review')),
    );
    await tester.pumpAndSettle();
    expect(repo.matchingModes['lb-1']!.mode, 'review');
    // A mode change is a full-replace write that must not flip the
    // singles switch along the way.
    expect(repo.matchingModes['lb-1']!.singlesAutoApply, isTrue);
  });

  testWidgets('an admin toggles singles auto-apply from the bar', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
          username: 'admin',
          roles: ['admin'],
        ),
      ),
    );
    repo.libraries.add(const LibraryInfo(pid: 'lb-1', name: 'Music'));
    // A non-default mode, so the survival assert below can only pass
    // if the toggle's full-replace write re-sent the stored mode.
    repo.matchingModes['lb-1'] = const LibraryMatching(mode: 'review');
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.matchingMenu));
    await tester.pumpAndSettle();
    expect(find.text('Music: Auto-apply confident singles'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.matchingSingles('lb-1')),
    );
    await tester.pumpAndSettle();
    expect(repo.matchingModes['lb-1']!.singlesAutoApply, isTrue);
    // The toggle rides the same full-replace write; the mode survives.
    expect(repo.matchingModes['lb-1']!.mode, 'review');

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.matchingMenu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.matchingSingles('lb-1')),
    );
    await tester.pumpAndSettle();
    expect(repo.matchingModes['lb-1']!.singlesAutoApply, isFalse);
  });

  testWidgets('the matching control is hidden from non-admins', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-01JZX5N8QW3F4V9T2B7KDUSER001',
          username: 'plain',
          roles: ['user'],
        ),
      ),
    );
    repo.libraries.add(const LibraryInfo(pid: 'lb-1', name: 'Music'));
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.matchingMenu), findsNothing);
  });

  testWidgets('the podcast library offers no matching rows', (tester) async {
    // Its episodes come from their feeds, and the server refuses a
    // matching change on it.
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
          username: 'admin',
          roles: ['admin'],
        ),
      ),
    );
    repo.libraries.addAll(const [
      LibraryInfo(pid: 'lb-1', name: 'Music'),
      LibraryInfo(pid: 'lb-p', name: 'Podcasts', media: 'podcast'),
    ]);
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.matchingMenu));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.matchingOption('lb-1', 'auto')),
      findsOneWidget,
    );
    for (final mode in const ['auto', 'review', 'off']) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.matchingOption('lb-p', mode)),
        findsNothing,
      );
    }
    expect(
      find.bySemanticsIdentifier(SemanticsIds.matchingSingles('lb-p')),
      findsNothing,
    );
  });

  testWidgets('a server whose only library is the podcast one offers no '
      'matching menu', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(
          id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
          username: 'admin',
          roles: ['admin'],
        ),
      ),
    );
    repo.libraries.add(
      const LibraryInfo(pid: 'lb-p', name: 'Podcasts', media: 'podcast'),
    );
    await _pump(tester, appContainer(repo: repo));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.matchingMenu), findsNothing);
  });

  // The pane's decision bar and the bulk bar are on screen together, and
  // either can decide the entry the other is deciding.
  group('one entry decided from the pane and from the bulk bar', () {
    /// rv-1 open beside the queue, with a release to approve it against,
    /// and rv-1 and rv-2 selected.
    Future<ProviderContainer> pumpBoth(
      WidgetTester tester,
      _HeldDecisions repo,
    ) async {
      repo.reviewEntries = [
        testReviewEntry('rv-1'),
        testReviewEntry('rv-2', title: 'Second Album'),
      ];
      repo.reviewEntryDetails['rv-1'] = ReviewEntryDetail(
        id: 'rv-1',
        kind: 'match',
        status: 'pending',
        mediaType: MediaType.music,
        origin: 'scan',
        trackCount: 1,
        createdAt: DateTime.utc(2026, 7, 1),
        candidates: const [
          ReviewCandidate(
            mbid: 'mb-1',
            title: 'Neon Meridian',
            artist: 'The Cardinal Waves',
            similarityPct: 94,
          ),
        ],
      );
      final container = appContainer(repo: repo);
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpOpenEntry(tester, container);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewPane),
        findsOneWidget,
      );
      await tester.longPress(_row('rv-1'));
      await tester.pumpAndSettle();
      await tester.tap(_row('rv-2'));
      await tester.pumpAndSettle();
      return container;
    }

    WaxButton button(WidgetTester tester, String id) =>
        tester.widget<WaxButton>(waxControl<WaxButton>(id));

    testWidgets("the pane's decision out holds the bulk bar, which sends "
        'nothing and reports no failure', (tester) async {
      final repo = _HeldDecisions();
      // What the server answers an entry already being decided.
      repo.bulkOutcomes['rv-1'] = const ReviewBulkOutcome(
        entryId: 'rv-1',
        ok: false,
        code: 'conflict',
        error: 'the entry is being decided',
      );
      final container = await pumpBoth(tester, repo);
      final raised = <String>[];
      container.listen(shellMessagesProvider, (_, next) {
        if (shellMessageText(next) case final text?) raised.add(text);
      });

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pump();
      expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-1']);
      expect(button(tester, SemanticsIds.reviewBulkAsIs).onPressed, isNull);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.reviewBulkAsIs),
        warnIfMissed: false,
      );
      await tester.pump();

      repo.release.complete();
      await tester.pumpAndSettle();
      expect(repo.decideBulkCalls, isEmpty);
      expect(repo.decideReviewCalls, hasLength(1));
      // The pane's own confirmation, and no failure beside it.
      expect(raised, ['Decided 1 entry']);
    });

    testWidgets('a bulk decision out holds its entries from the pane and the '
        'queue keys', (tester) async {
      final repo = _HeldDecisions();
      final container = await pumpBoth(tester, repo);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkAsIs));
      await tester.pump();
      expect(repo.decideBulkCalls.single.entryIds, ['rv-1', 'rv-2']);
      expect(button(tester, SemanticsIds.reviewApprove).onPressed, isNull);
      expect(button(tester, SemanticsIds.reviewApprove).busy, isFalse);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        warnIfMissed: false,
      );
      // The queue's own key, on the row the pane shows.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(repo.decideReviewCalls, isEmpty);
      // Refused whole: not even its action's key was taken.
      expect(container.read(pendingActionsProvider), {
        PendingAction.reviewEntry('rv-1'),
        PendingAction.reviewEntry('rv-2'),
      });

      repo.release.complete();
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls, isEmpty);
      expect(
        shellMessageText(container.read(shellMessagesProvider)),
        'Decided 2 entries',
      );
    });
  });

  group('the two panes', () {
    /// The width the report came from: a 1020-pixel window, less the
    /// shell rail and the console list that used to sit in front of
    /// this screen, is about what it gets to lay itself out in.
    Future<WaxSplitter> pumpSurface(
      WidgetTester tester,
      ProviderContainer container, {
      double width = 900,
    }) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpSurface(tester, container);
      return tester.widget<WaxSplitter>(find.byType(WaxSplitter));
    }

    testWidgets('leave the majority to the entry somebody opened', (
      tester,
    ) async {
      final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
      final container = appContainer(repo: repo);
      final seam = await pumpSurface(tester, container);

      // A third of the room, bounded, which is well under half of it.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewSplitter),
        findsOneWidget,
      );
      expect(seam.position, greaterThanOrEqualTo(ReviewSurface.listMin));
      expect(seam.position, lessThanOrEqualTo(ReviewSurface.listMax));
      expect(seam.min, ReviewSurface.listMin);

      // The point of the whole arrangement: the submission being read
      // gets more than the queue of one-line rows beside it, and never
      // less than the diff table's own minimum. It used to get 343
      // against the list's 380.
      final pane = tester
          .getSize(find.bySemanticsIdentifier(SemanticsIds.reviewPane))
          .width;
      expect(pane, greaterThanOrEqualTo(ReviewSurface.paneMin));
      expect(pane, greaterThan(seam.position));
      // Which is also the seam's own limit: dragging can take room from
      // the entry, but not the room the table needs to be read at all.
      expect(
        seam.max,
        lessThanOrEqualTo(seam.position + pane - ReviewSurface.paneMin),
      );
    });

    group("the foot bars stand on the window's foot", () {
      const insets = FakeViewPadding(left: 40, right: 30, bottom: 20);
      final bulkBar = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_BulkBar',
      );

      Future<void> pumpInset(WidgetTester tester) async {
        tester.view
          ..padding = insets
          ..viewPadding = insets;
        final repo = FakeRepository()
          ..reviewEntries = [testReviewEntry('rv-1'), testReviewEntry('rv-2')]
          ..reviewEntryDetails['rv-1'] = _matchable('rv-1');
        await pumpSurface(tester, appContainer(repo: repo));
        await tester.pumpAndSettle();
      }

      testWidgets("the pane's decision bar reaches the window's end and "
          'foot from the pane, its controls clear of the insets, and the '
          'queue beside it takes the foot itself', (tester) async {
        await pumpInset(tester);
        final pane = tester.getRect(
          find.bySemanticsIdentifier(SemanticsIds.reviewPane),
        );
        final bar = tester.getRect(find.byType(WaxFootBar));
        expect((bar.left, bar.right, bar.bottom), (pane.left, 900.0, 1000.0));
        final approve = tester.getRect(
          find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        );
        expect(approve.left, pane.left + 12);
        // The last of the wrapped buttons, on its last line.
        final skip = tester.getRect(
          find.bySemanticsIdentifier(SemanticsIds.reviewSkip),
        );
        expect(skip.bottom, 1000 - 20 - 12.0);
        final queue = tester.getRect(
          find
              .ancestor(of: _row('rv-1'), matching: find.byType(ListView))
              .first,
        );
        expect((queue.left, queue.bottom), (40.0, 1000 - 20.0));
      });

      testWidgets("selecting, the bulk bar takes the page's foot and the "
          "pane's bar stands on it", (tester) async {
        await pumpInset(tester);
        await tester.longPress(_row('rv-2'));
        await tester.pumpAndSettle();

        final bulk = tester.getRect(bulkBar);
        expect((bulk.left, bulk.right, bulk.bottom), (0.0, 900.0, 1000.0));
        final skip = tester.getRect(
          find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip),
        );
        expect(skip.right, 900 - 30 - 16.0, reason: 'its controls, the end');
        expect(skip.bottom, lessThanOrEqualTo(1000 - 20.0));
        final bar = tester.getRect(find.byType(WaxFootBar));
        expect(bar.bottom, bulk.top);
        expect(
          tester
              .getRect(find.bySemanticsIdentifier(SemanticsIds.reviewSkip))
              .bottom,
          bulk.top - 12,
        );
      });
    });

    group('hold their floors inside the side insets', () {
      const insets = FakeViewPadding(left: 44, right: 30);

      /// The narrowest window that holds both once the queue and the
      /// entry have taken the cutouts beside them.
      const fits =
          ReviewSurface.listMin +
          WaxSplitter.hitWidth +
          ReviewSurface.paneMin +
          44 +
          30;

      Future<void> pumpAt(WidgetTester tester, double width) async {
        tester.view
          ..physicalSize = Size(width, 1000)
          ..devicePixelRatio = 1
          ..padding = insets
          ..viewPadding = insets;
        addTearDown(tester.view.reset);
        final repo = FakeRepository()
          ..reviewEntries = [testReviewEntry('rv-1'), testReviewEntry('rv-2')]
          ..reviewEntryDetails['rv-1'] = _matchable('rv-1');
        await _pumpSurface(tester, appContainer(repo: repo));
        await tester.pumpAndSettle();
      }

      double queue(WidgetTester tester) => tester
          .getSize(
            find
                .ancestor(of: _row('rv-1'), matching: find.byType(ListView))
                .first,
          )
          .width;

      /// How far the diff table's own scroller can move: nowhere while
      /// the entry has the width it declares.
      double tableOverflow(WidgetTester tester) => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.descendant(
                of: find.bySemanticsIdentifier(SemanticsIds.reviewPane),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is SingleChildScrollView &&
                      widget.scrollDirection == Axis.horizontal,
                ),
              ),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .maxScrollExtent;

      testWidgets('one pane until the room inside the cutouts holds both', (
        tester,
      ) async {
        await pumpAt(tester, fits - 1);
        expect(find.byType(WaxSplitter), findsNothing);
        expect(find.byType(ReviewEntryScreen), findsOneWidget);

        await pumpAt(tester, fits);
        expect(find.byType(WaxSplitter), findsOneWidget);
        expect(queue(tester), ReviewSurface.listMin, reason: 'the queue');
        expect(tableOverflow(tester), 0, reason: 'the diff table');
      });

      testWidgets('the seam dragged to either end leaves each part its '
          'floor inside the cutout beside it', (tester) async {
        await pumpAt(tester, 1100);
        Future<void> drag(double dx) async {
          final gesture = await tester.startGesture(
            tester.getCenter(find.byType(WaxSplitter)),
          );
          await gesture.moveBy(Offset(dx.sign * 40, 0));
          await gesture.moveBy(Offset(dx, 0));
          await gesture.up();
          await tester.pumpAndSettle();
        }

        await drag(2000);
        expect(tableOverflow(tester), 0, reason: 'the diff table');
        await drag(-2000);
        expect(queue(tester), ReviewSurface.listMin, reason: 'the queue');
      });
    });

    testWidgets('remember where the seam was dragged to, and reset', (
      tester,
    ) async {
      final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
      final container = appContainer(repo: repo);
      // Wider than the threshold by enough to have somewhere to drag
      // to: at the narrowest two-pane width the seam is pinned between
      // the two floors, which is what those floors are for.
      await pumpSurface(tester, container, width: 1100);

      double seamAt() =>
          tester.widget<WaxSplitter>(find.byType(WaxSplitter)).position;

      // Two moves rather than one: the first crosses the drag slop the
      // arena withholds, and the second is what the seam has to follow
      // one for one - a splitter that lags the pointer by a constant is
      // a splitter nobody can put anywhere on purpose.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WaxSplitter)),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      final grabbed = seamAt();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(seamAt(), grabbed + 40);
      // Nothing is written down yet: a preference is what somebody
      // settled on, and a drag has not settled on anything.
      expect(container.read(reviewListWidthProvider), 0);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(container.read(reviewListWidthProvider), seamAt().round());
      expect(seamAt(), greaterThan(ReviewSurface.listMin));

      // A double tap hands it back to the layout, which is the only way
      // out of a width somebody dragged and then regretted.
      await tester.tap(find.byType(WaxSplitter));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(WaxSplitter));
      await tester.pumpAndSettle();
      expect(container.read(reviewListWidthProvider), 0);
    });

    testWidgets('let j move the cursor off the open entry, and keep it there '
        'through a rebuild', (tester) async {
      final repo = FakeRepository()
        ..reviewEntries = [
          testReviewEntry('rv-1'),
          testReviewEntry('rv-2', title: 'Second Album'),
          testReviewEntry('rv-3', title: 'Third Album'),
        ];
      final container = appContainer(repo: repo);
      await pumpSurface(tester, container);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      // A rebuild from elsewhere: the queue read again.
      container.invalidate(reviewQueueProvider);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();

      expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-2']);
      expect(
        tester.widget<ReviewEntryView>(find.byType(ReviewEntryView)).entryId,
        'rv-1',
        reason: 'the pane keeps the entry it opened',
      );
    });

    testWidgets('give the whole page to the entry rather than a squeezed '
        'pair', (tester) async {
      final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
      final container = appContainer(repo: repo);
      // The width the report came from: a 1020-pixel window, less the
      // shell rail and the console list that used to sit in front of
      // this screen. Two panes here would leave the diff table 398 of
      // the 420 it declares, so the answer is one pane at 724 rather
      // than a split that brings the scrollbar back - and the
      // submission still goes from the 343 it had to the whole width.
      tester.view.physicalSize = const Size(724, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpSurface(tester, container);

      expect(find.byType(WaxSplitter), findsNothing);
      expect(
        tester.getSize(find.byType(ReviewEntryScreen)).width,
        greaterThan(ReviewSurface.paneMin),
      );
    });

    testWidgets('are not drawn where the entry could not be read', (
      tester,
    ) async {
      final repo = FakeRepository()..reviewEntries = [testReviewEntry('rv-1')];
      final container = appContainer(repo: repo);
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpSurface(tester, container);

      // The entry takes the screen, so there is nothing to divide - the
      // same answer a phone gets, and the reason the seam is not a
      // control anybody has to find on one.
      expect(find.byType(WaxSplitter), findsNothing);
    });

    /// The surface over the app's own table, open on [entryId]: one
    /// screen spans both review locations there, so its cursor carries
    /// across a move of the pane as it does in the app.
    Future<GoRouter> openOnTable(
      WidgetTester tester,
      ProviderContainer container,
      String entryId,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await mountApp(tester, const Scaffold(), container: container);
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go(WaxRoute.reviewEntry(entryId));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewPane),
        findsOneWidget,
      );
      return router;
    }

    String location(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.path;
    String paneEntry(WidgetTester tester) =>
        tester.widget<ReviewEntryView>(find.byType(ReviewEntryView)).entryId;
    Color? surfaceOf(WidgetTester tester, String id) => tester
        .widget<Material>(
          find.descendant(of: _row(id), matching: find.byType(Material)).first,
        )
        .color;

    testWidgets('open the next entry once the open one is approved', (
      tester,
    ) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();

      expect(repo.decideReviewCalls.single.entryId, 'rv-1');
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      expect(paneEntry(tester), 'rv-2');
      expect(_row('rv-1'), findsNothing);
      // One row lit, and it is the one the pane shows.
      final colors = WaxColors.of(tester.element(_row('rv-2')));
      expect(surfaceOf(tester, 'rv-2'), colors.accentContainer);
      expect(surfaceOf(tester, 'rv-3'), colors.canvas);
    });

    testWidgets('keep one row lit while the queue is slow to read again', (
      tester,
    ) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );
      final gate = repo.reviewQueueGate = Completer<void>();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      gate.complete();
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      final colors = WaxColors.of(tester.element(_row('rv-2')));
      expect(surfaceOf(tester, 'rv-2'), colors.accentContainer);
      expect(surfaceOf(tester, 'rv-3'), colors.canvas);
    });

    testWidgets('move on when the queue cannot be read again', (tester) async {
      final repo = _RefetchFails();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      // No time passes: the move must not wait out Riverpod's retries.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      // The retries end with the scope.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('step back to the entry before the last one decided', (
      tester,
    ) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-3',
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewSkip));
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      expect(paneEntry(tester), 'rv-2');
      final colors = WaxColors.of(tester.element(_row('rv-2')));
      expect(surfaceOf(tester, 'rv-2'), colors.accentContainer);
      expect(surfaceOf(tester, 'rv-1'), colors.canvas);
    });

    testWidgets('a decision on an entry open past the first page keeps the '
        'loaded rows, and the pane lands on its neighbour', (tester) async {
      const rows = ReviewQueueController.pageSize + 10;
      const at = ReviewQueueController.pageSize + 4;
      final repo = FakeRepository()
        ..reviewEntries = [
          for (var i = 0; i < rows; i++)
            testReviewEntry('rv-$i', title: 'Album $i'),
        ];
      final container = appContainer(repo: repo);
      final router = await openOnTable(tester, container, 'rv-$at');
      await container.read(reviewQueueProvider.notifier).loadMore();
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewSkip));
      await tester.pumpAndSettle();

      expect(repo.decideReviewCalls.single.entryId, 'rv-$at');
      expect(location(router), WaxRoute.reviewEntry('rv-${at + 1}'));
      expect(paneEntry(tester), 'rv-${at + 1}');
      expect(
        container
            .read(reviewQueueProvider)
            .requireValue
            .entries
            .map((entry) => entry.id),
        [
          for (var i = 0; i < rows; i++)
            if (i != at) 'rv-$i',
        ],
      );
    });

    testWidgets('close onto the empty queue once the only entry is decided', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..reviewEntries = [testReviewEntry('rv-1')]
        ..reviewEntryDetails['rv-1'] = _matchable('rv-1');
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.review);
      expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsNothing);
      expect(find.text('Nothing waiting for review'), findsOneWidget);
    });

    testWidgets('follow a key decision on the row the pane shows', (
      tester,
    ) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.entryId, 'rv-1');
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      expect(paneEntry(tester), 'rv-2');

      // The cursor came along, so the next key decides what is open.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.last.entryId, 'rv-2');
      expect(location(router), WaxRoute.reviewEntry('rv-3'));
    });

    testWidgets('draw a key decision on the open row in the pane at once, '
        'and take no second key for it', (tester) async {
      final repo = _Revertible();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );
      final queue = repo.reviewQueueGate = Completer<void>();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Decided, while the queue reads again: Revert is the undo.
      expect(paneEntry(tester), 'rv-1');
      expect(find.text('Decided: Applied'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewRevert),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-1']);

      queue.complete();
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls, hasLength(1));
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
    });

    testWidgets('pass over a next entry somebody else decided meanwhile', (
      tester,
    ) async {
      final repo = _HeldDecisions();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pump();
      // Another reviewer takes rv-2 while this decision is out.
      repo.reviewEntries = [
        for (final e in repo.reviewEntries)
          e.id == 'rv-2'
              ? testReviewEntry(
                  'rv-2',
                  status: 'skipped',
                  title: 'Second Album',
                )
              : e,
      ];
      repo.release.complete();
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.reviewEntry('rv-3'));
      expect(paneEntry(tester), 'rv-3');
    });

    testWidgets('stay on the open entry when somebody else decides it', (
      tester,
    ) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final container = appContainer(repo: repo);
      final router = await openOnTable(tester, container, 'rv-1');

      repo.reviewEntries = [
        testReviewEntry('rv-1', status: 'skipped'),
        ...repo.reviewEntries.skip(1),
      ];
      container.invalidate(reviewQueueProvider);
      container.invalidate(reviewEntryProvider('rv-1'));
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.reviewEntry('rv-1'));
      expect(paneEntry(tester), 'rv-1');
    });

    testWidgets('stay on an entry whose decision failed', (tester) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );
      repo.reviewError = const WaxDeckApiException(
        code: 'conflict',
        message: 'a.flac: destination already exists in the library',
        statusCode: 409,
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.reviewEntry('rv-1'));
      expect(paneEntry(tester), 'rv-1');
      final message = raisedMessage(tester)!;
      expect(
        shellMessageText(message),
        'a.flac: destination already exists in the library',
      );
      expect(message.actionLabel, isNull);
    });

    testWidgets('stay on an entry its revert leaves decided', (tester) async {
      final repo = FakeRepository()
        ..reviewEntries = [
          testReviewEntry('rv-1', status: 'applied'),
          testReviewEntry('rv-2', status: 'applied', title: 'Second Album'),
        ];
      final container = appContainer(repo: repo);
      container
          .read(reviewFilterProvider.notifier)
          .select(ReviewFilter.decided);
      final router = await openOnTable(tester, container, 'rv-1');

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewRevert));
      await tester.pumpAndSettle();

      expect(repo.revertedReviewEntryIds, ['rv-1']);
      expect(location(router), WaxRoute.reviewEntry('rv-1'));
      expect(paneEntry(tester), 'rv-1');
      expect(find.text('Decided: Reverted'), findsOneWidget);
      // The bar says so where it stands; nothing else needs to.
      expect(raisedMessage(tester), isNull);
    });

    testWidgets('offer to undo an approve the pane moved off, and stay where '
        'it moved to', (tester) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      final message = raisedMessage(tester)!;
      expect(shellMessageText(message), 'Decided 1 entry');
      expect(message.actionLabel, 'Undo');

      await pressRaisedAction(tester);
      expect(repo.revertedReviewEntryIds, ['rv-1']);
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      expect(paneEntry(tester), 'rv-2');
      // A reverted entry is decided, so it is not waiting any more.
      expect(_row('rv-1'), findsNothing);
      // One row lit, so the keys act on the entry the pane shows.
      final colors = WaxColors.of(tester.element(_row('rv-2')));
      expect(surfaceOf(tester, 'rv-2'), colors.accentContainer);
      expect(surfaceOf(tester, 'rv-3'), colors.canvas);
      // Nothing on screen moves, so the undo says it worked.
      final undone = raisedMessage(tester)!;
      expect(shellMessageText(undone), 'Decision undone');
      expect(undone.onAction, isNull);
      expect(undone.channel, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.last.entryId, 'rv-2');
      expect(repo.decideReviewCalls.last.action, 'skip');
    });

    /// The whole app at a desktop window, open on [entryId] beside the
    /// queue: the shell's message bar is drawn only there.
    Future<GoRouter> openInApp(
      WidgetTester tester,
      FakeRepository repo,
      String entryId,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = appContainer(repo: repo);
      await pumpWholeApp(tester, container: container);
      final router = container.read(routerProvider)
        ..go(WaxRoute.reviewEntry(entryId));
      await tester.pumpAndSettle();
      return router;
    }

    ShellMessenger messengerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(Navigator).first),
          listen: false,
        ).read(shellMessengerProvider);

    /// The shell's bar drawing [text].
    Rect messageBar(WidgetTester tester, String text) => tester.getRect(
      find.ancestor(of: find.text(text), matching: find.byType(Material)).first,
    );

    /// How far above the window's bottom the bar drawing [text] rests.
    double restsAbove(WidgetTester tester, String text) =>
        tester.view.physicalSize.height - messageBar(tester, text).bottom;

    /// The pane's decision bar: the foot bar its buttons stand in.
    Rect decisionBar(WidgetTester tester) => tester.getRect(
      find
          .ancestor(
            of: find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
            matching: find.byType(WaxFootBar),
          )
          .first,
    );

    Future<void> outlast(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    FakeRepository signedIn() => FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );

    testWidgets('a decision that lands once the visitor went to another tab '
        'leaves them there, and back does not return to the decided entry', (
      tester,
    ) async {
      final repo = signedIn();
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');
      final gate = repo.decideReviewGate = Completer<void>();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pump();
      router.go(WaxRoute.home);
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repo.decideReviewCalls.single.entryId, 'rv-1');
      expect(location(router), WaxRoute.home);
      expect(find.text('Decided 1 entry'), findsOneWidget);
      final history = ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
        listen: false,
      ).read(waxHistoryProvider)!;
      expect(history.isBehind(WaxRoute.reviewEntry('rv-1')), isFalse);
    });

    WaxHistory historyOf(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
      listen: false,
    ).read(waxHistoryProvider)!;

    Future<void> aFewFrames(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('a decision whose queue read lands once the visitor went '
        'elsewhere in the branch is not somewhere back returns to', (
      tester,
    ) async {
      final repo = signedIn();
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');
      final queue = repo.reviewQueueGate = Completer<void>();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await aFewFrames(tester);
      router.go(WaxRoute.tasks);
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen, skipOffstage: false), findsNothing);
      queue.complete();
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.tasks);

      historyOf(tester).back();
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.home);
    });

    testWidgets('a decision whose queue read lands once the window narrowed '
        'to one pane leaves the decided entry, and back does not return to '
        'it', (tester) async {
      final repo = signedIn();
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');
      final queue = repo.reviewQueueGate = Completer<void>();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await aFewFrames(tester);
      tester.view.physicalSize = const Size(700, 1000);
      await aFewFrames(tester);
      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      queue.complete();
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.review);
      expect(find.byType(ReviewEntryView), findsNothing);

      historyOf(tester).back();
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.home);
    });

    testWidgets('a bulk decision that lands once the window narrowed to one '
        'pane leaves the open entry it took', (tester) async {
      final repo = _HeldDecisions(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');

      await tester.longPress(_row('rv-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
      await aFewFrames(tester);
      expect(repo.decideBulkCalls.single.entryIds, ['rv-1']);
      tester.view.physicalSize = const Size(700, 1000);
      await aFewFrames(tester);
      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      repo.release.complete();
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.review);

      historyOf(tester).back();
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.home);
    });

    testWidgets("draw the confirmation clear of the next entry's decision "
        'bar', (tester) async {
      final repo = signedIn();
      _seedThree(repo);
      repo.reviewEntryDetails['rv-2'] = _matchable('rv-2');
      final router = await openInApp(tester, repo, 'rv-1');

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      expect(find.text('Decided 1 entry'), findsOneWidget);
      expect(
        messageBar(tester, 'Decided 1 entry').overlaps(decisionBar(tester)),
        isFalse,
      );

      // At the button's centre, as a mouse would, the confirmation up.
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-1', 'rv-2']);
      expect(location(router), WaxRoute.reviewEntry('rv-3'));
    });

    testWidgets('leave the buttons under a confirmation drawn clear of them '
        'to a screen reader exploring by touch', (tester) async {
      final repo = signedIn();
      _seedThree(repo);
      repo.reviewEntryDetails['rv-2'] = _matchable('rv-2');
      await openInApp(tester, repo, 'rv-1');
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      final bar = messageBar(tester, 'Decided 1 entry');
      expect(bar.bottom, lessThanOrEqualTo(decisionBar(tester).top));

      // The message is its bar to a screen reader, and nothing below it.
      final message = tester.getSemantics(find.text('Decided 1 entry'));
      expect(semanticsRectOnScreen(message), bar);
      // So a finger on a button under the lift lands on the button.
      final approve = find.bySemanticsIdentifier(SemanticsIds.reviewApprove);
      expect(
        touchExploredAt(tester, tester.getCenter(approve))?.id,
        tester.getSemantics(approve).id,
      );
    });

    testWidgets('undo from the confirmation drawn clear of the pane', (
      tester,
    ) async {
      final repo = signedIn();
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      expect(
        messageBar(tester, 'Decided 1 entry').overlaps(decisionBar(tester)),
        isFalse,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(repo.revertedReviewEntryIds, ['rv-1']);
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      expect(find.text('Decision undone'), findsOneWidget);
    });

    testWidgets('draw the confirmation clear of a decision bar the bulk bar '
        'holds up', (tester) async {
      final repo = signedIn();
      _seedThree(repo);
      await openInApp(tester, repo, 'rv-1');
      await tester.longPress(_row('rv-3'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();

      expect(find.text('Decided 1 entry'), findsOneWidget);
      expect(
        messageBar(tester, 'Decided 1 entry').overlaps(decisionBar(tester)),
        isFalse,
      );
    });

    testWidgets('draw a message where it always rests once the entry '
        'closes', (tester) async {
      final repo = signedIn();
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');
      router.go(WaxRoute.review);
      await tester.pumpAndSettle();
      messengerOf(tester).show('Scan started');
      await tester.pumpAndSettle();
      final resting = restsAbove(tester, 'Scan started');
      await outlast(tester);

      router.go(WaxRoute.reviewEntry('rv-1'));
      await tester.pumpAndSettle();
      messengerOf(tester).show('Link copied');
      await tester.pumpAndSettle();
      expect(restsAbove(tester, 'Link copied'), greaterThan(resting));
      await outlast(tester);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.reviewPaneClose),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsNothing);
      messengerOf(tester).show('Saved');
      await tester.pumpAndSettle();
      expect(restsAbove(tester, 'Saved'), resting);
    });

    testWidgets('draw a message where it always rests while the pane is on '
        'a hidden tab', (tester) async {
      final repo = signedIn();
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');
      router.go(WaxRoute.review);
      await tester.pumpAndSettle();
      messengerOf(tester).show('Scan started');
      await tester.pumpAndSettle();
      final resting = restsAbove(tester, 'Scan started');
      await outlast(tester);

      router.go(WaxRoute.reviewEntry('rv-1'));
      await tester.pumpAndSettle();
      router.go(WaxRoute.home);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewPane),
        findsNothing,
        reason: 'the pane is mounted, on a tab out of sight',
      );
      messengerOf(tester).show('Saved');
      await tester.pumpAndSettle();
      expect(restsAbove(tester, 'Saved'), resting);
    });

    _DetailHeld heldDetails() => _DetailHeld(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );

    Future<void> frames(WidgetTester tester, int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('lift a message drawn between entries above the next '
        "entry's buttons once they are drawn", (tester) async {
      final repo = heldDetails();
      _seedThree(repo);
      await openInApp(tester, repo, 'rv-1');
      final detail = repo.detailGates['rv-2'] = Completer<void>();
      await tester.tap(_row('rv-2'));
      await frames(tester, 2);
      expect(paneEntry(tester), 'rv-2');
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        findsNothing,
        reason: 'the pane draws its skeleton',
      );

      messengerOf(tester).show('Link copied');
      await frames(tester, 6);
      final up = tester.state(find.byType(WaxMessageBar));
      detail.complete();
      // The same bar moved, its entrance not played again.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.state(find.byType(WaxMessageBar)), same(up));
        expect(
          tester
              .widget<WaxMessageBar>(find.byType(WaxMessageBar))
              .animation!
              .value,
          1,
        );
      }
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        findsOneWidget,
      );
      expect(
        messageBar(tester, 'Link copied').bottom,
        lessThanOrEqualTo(decisionBar(tester).top),
      );
    });

    testWidgets('take a message moved up for a bar off when its time is '
        'out, not later', (tester) async {
      final repo = heldDetails();
      _seedThree(repo);
      await openInApp(tester, repo, 'rv-1');
      final detail = repo.detailGates['rv-2'] = Completer<void>();
      await tester.tap(_row('rv-2'));
      await frames(tester, 2);

      messengerOf(tester).show('Link copied');
      await tester.pump();
      await frames(tester, 30);
      final before = messageBar(tester, 'Link copied');
      detail.complete();
      await frames(tester, 6);
      expect(
        messageBar(tester, 'Link copied').bottom,
        lessThan(before.bottom),
        reason: 'moved up for the bar under it',
      );

      // Up about 3.6 s, then about 5 s: a bar that started its time again
      // at the move would still be up.
      await tester.pump(const Duration(milliseconds: 1800));
      expect(find.text('Link copied'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pumpAndSettle();
      expect(find.text('Link copied'), findsNothing);
    });

    testWidgets('rest the confirmation of the last entry decided where a '
        'message always rests once the pane has closed', (tester) async {
      final repo = signedIn()
        ..reviewEntries = [testReviewEntry('rv-1')]
        ..reviewEntryDetails['rv-1'] = _matchable('rv-1');
      final router = await openInApp(tester, repo, 'rv-1');

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.review);
      expect(find.bySemanticsIdentifier(SemanticsIds.reviewPane), findsNothing);
      expect(find.text('Decided 1 entry'), findsOneWidget);
      expect(restsAbove(tester, 'Decided 1 entry'), 10);
    });

    testWidgets('rest a message drawn clear of the pane where a message '
        'always rests once the screen is left', (tester) async {
      final repo = signedIn();
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');
      messengerOf(tester).show('Link copied');
      await tester.pumpAndSettle();
      expect(restsAbove(tester, 'Link copied'), greaterThan(10));

      router.go(WaxRoute.home);
      await tester.pumpAndSettle();

      expect(find.text('Link copied'), findsOneWidget);
      expect(restsAbove(tester, 'Link copied'), 10);
    });

    testWidgets('move a message drawn clear of the pane nowhere while the '
        'pane goes on to the next entry', (tester) async {
      final repo = heldDetails();
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');
      final queue = repo.reviewQueueGate = Completer<void>();
      final detail = repo.detailGates['rv-2'] = Completer<void>();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await frames(tester, 10);
      expect(paneEntry(tester), 'rv-1');
      final placed = messageBar(tester, 'Decided 1 entry');
      expect(placed.bottom, lessThanOrEqualTo(decisionBar(tester).top));

      final drawn = <Rect>[];
      queue.complete();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        drawn.add(messageBar(tester, 'Decided 1 entry'));
      }
      expect(paneEntry(tester), 'rv-2');
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        findsNothing,
        reason: 'the pane draws its skeleton',
      );
      detail.complete();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        drawn.add(messageBar(tester, 'Decided 1 entry'));
      }

      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        findsOneWidget,
      );
      expect(drawn, everyElement(placed));
    });

    testWidgets("keep a decision's warning on screen past the next "
        'decision', (tester) async {
      // The whole app, for the shell's bar: a run of confirmations may
      // replace one another there, and a warning must not go with them.
      const warning = 'a.flac: the tags could not be written';
      final repo = _Warns(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );
      _seedThree(repo);
      repo.reviewEntryDetails['rv-2'] = _matchable('rv-2');
      repo.warnings['rv-1'] = [warning];
      final router = await openInApp(tester, repo, 'rv-1');

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      // The confirmation and its undo first, the warning behind them.
      expect(find.text('Decided 1 entry'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text(warning), findsNothing);
      // The next entry, decided at its button while the first
      // confirmation is up.
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-1', 'rv-2']);

      // Its turn comes once the newest confirmation has had its time, and
      // it gets the whole of its own.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(warning), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text(warning), findsOneWidget);
    });

    testWidgets("draw the next decision's confirmation at once over the "
        "last one's warning, which comes back after it", (tester) async {
      const warning = 'a.flac: the tags could not be written';
      final repo = _Warns(
        sessionState: const SessionState(authenticated: true, user: _admin),
      );
      _seedThree(repo);
      repo.reviewEntryDetails['rv-2'] = _matchable('rv-2');
      repo.warnings['rv-1'] = [warning];
      final router = await openInApp(tester, repo, 'rv-1');
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      await outlast(tester);
      expect(find.text(warning), findsOneWidget);
      expect(location(router), WaxRoute.reviewEntry('rv-2'));

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-1', 'rv-2']);
      expect(find.text('Decided 1 entry'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text(warning), findsNothing);

      await outlast(tester);
      expect(find.text(warning), findsOneWidget);
    });

    /// The whole app on the entry's page of its own: too narrow to hold
    /// the queue beside it, and wide enough for the sidebar, so no tab bar
    /// stands under a message.
    Future<GoRouter> openOnePane(
      WidgetTester tester,
      FakeRepository repo,
      String entryId,
    ) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = appContainer(repo: repo);
      await pumpWholeApp(tester, container: container);
      final router = container.read(routerProvider)
        ..go(WaxRoute.reviewEntry(entryId));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      return router;
    }

    testWidgets("draw a one-pane decision's confirmation where it always "
        'rests, and undo it from there', (tester) async {
      final repo = signedIn();
      _seedThree(repo);
      final router = await openOnePane(tester, repo, 'rv-1');
      // Where a message rests on the queue, which has no bar to clear.
      router.go(WaxRoute.review);
      await tester.pumpAndSettle();
      messengerOf(tester).show('Scan started');
      await tester.pumpAndSettle();
      final resting = restsAbove(tester, 'Scan started');
      expect(resting, 10);
      await outlast(tester);
      router.go(WaxRoute.reviewEntry('rv-1'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.review);
      expect(find.byType(ReviewEntryScreen), findsNothing);
      expect(find.text('Decided 1 entry'), findsOneWidget);
      expect(restsAbove(tester, 'Decided 1 entry'), resting);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.revertedReviewEntryIds, ['rv-1']);
      expect(find.text('Decision undone'), findsOneWidget);
    });

    testWidgets("draw a one-pane page's refusal above its decision bar", (
      tester,
    ) async {
      final repo = signedIn();
      _seedThree(repo);
      final router = await openOnePane(tester, repo, 'rv-1');
      repo.reviewError = const WaxDeckApiException(
        code: 'conflict',
        message: 'a.flac: destination already exists in the library',
        statusCode: 409,
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.reviewEntry('rv-1'));
      const refusal = 'a.flac: destination already exists in the library';
      expect(find.text(refusal), findsOneWidget);
      expect(
        messageBar(tester, refusal).bottom,
        lessThanOrEqualTo(decisionBar(tester).top),
      );
    });

    testWidgets('keep a newer decision on screen past an undo that lands '
        'after it', (tester) async {
      final repo = _Revertible()
        ..sessionState = const SessionState(authenticated: true, user: _admin);
      _seedThree(repo);
      repo.reviewEntryDetails['rv-2'] = _matchable('rv-2');
      final router = await openInApp(tester, repo, 'rv-1');
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      expect(location(router), WaxRoute.reviewEntry('rv-2'));

      // The undo's revert is out while the next decision is made.
      final revert = repo.revertGate = Completer<void>();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-1', 'rv-2']);
      expect(find.text('Decided 1 entry'), findsOneWidget);

      revert.complete();
      await tester.pumpAndSettle();
      expect(repo.revertedReviewEntryIds, ['rv-1']);
      // The newer confirmation and its undo are still the bar.
      expect(find.text('Decided 1 entry'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Decision undone'), findsNothing);

      // And the undone notice has its turn after it.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Decision undone'), findsOneWidget);
    });

    testWidgets('take the confirmation and its undo off for a revert pressed '
        'while the queue reads again, as for its own undo', (tester) async {
      final repo = _Revertible()
        ..sessionState = const SessionState(authenticated: true, user: _admin);
      _seedThree(repo);
      final router = await openInApp(tester, repo, 'rv-1');
      final queue = repo.reviewQueueGate = Completer<void>();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(paneEntry(tester), 'rv-1');
      expect(find.text('Decided 1 entry'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewRevert));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Gone the way an answered offer goes: no undo left to refuse.
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Decided 1 entry'), findsNothing);

      queue.complete();
      await tester.pumpAndSettle();
      expect(repo.revertedReviewEntryIds, ['rv-1']);
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      // Said at once, with nothing left in front of it.
      expect(find.text('Decision undone'), findsOneWidget);
    });

    testWidgets('undo from elsewhere without coming back', (tester) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      final undo = raisedMessage(tester)!.onAction!;

      router.go(WaxRoute.uploads);
      await tester.pumpAndSettle();
      undo();
      await tester.pumpAndSettle();

      expect(repo.revertedReviewEntryIds, ['rv-1']);
      expect(location(router), WaxRoute.uploads);
    });

    testWidgets('stay put on an undo the server refuses, and say why', (
      tester,
    ) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final container = appContainer(repo: repo);
      final router = await openOnTable(tester, container, 'rv-1');
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      await tester.pumpAndSettle();
      final raised = <String?>[];
      container.listen(
        shellMessagesProvider,
        (_, next) => raised.add(shellMessageText(next)),
      );

      repo.reviewError = const WaxDeckApiException(
        code: 'catalog-busy',
        message: 'a conflicting catalog job is already running',
        statusCode: 409,
      );
      await pressRaisedAction(tester);

      expect(repo.revertedReviewEntryIds, isEmpty);
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      expect(raised, [
        "Another job is holding the library's files. Try again shortly.",
      ]);
    });

    testWidgets('keep the cursor on the open entry when an entry arrives '
        'above it', (tester) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final container = appContainer(repo: repo);
      await openOnTable(tester, container, 'rv-2');

      repo.reviewEntries = [
        testReviewEntry('rv-0', title: 'Just Arrived'),
        ...repo.reviewEntries,
      ];
      container.invalidate(reviewQueueProvider);
      await tester.pumpAndSettle();

      final colors = WaxColors.of(tester.element(_row('rv-2')));
      expect(surfaceOf(tester, 'rv-2'), colors.accentContainer);
      for (final id in ['rv-0', 'rv-1', 'rv-3']) {
        expect(surfaceOf(tester, id), colors.canvas, reason: id);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.single.entryId, 'rv-2');
    });

    testWidgets('follow a key decision onto the row the pane reached while '
        'it was out', (tester) async {
      // The key decides rv-2 and is held; the pane's approve of rv-1 lands
      // first and moves the pane onto rv-2.
      final repo = _HeldOn('rv-2');
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      // Frames rather than settling: rv-2's decision draws busy.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(location(router), WaxRoute.reviewEntry('rv-2'));

      repo.release.complete();
      await tester.pumpAndSettle();

      expect(repo.decideReviewCalls.map((c) => c.entryId), ['rv-1', 'rv-2']);
      expect(location(router), WaxRoute.reviewEntry('rv-3'));
      expect(paneEntry(tester), 'rv-3');
    });

    for (final landed in [false, true]) {
      testWidgets('move on after a revert pressed while the queue reads '
          'again, the revert ${landed ? 'landed' : 'still out'} as the '
          'queue reads', (tester) async {
        final repo = _Revertible();
        _seedThree(repo);
        final router = await openOnTable(
          tester,
          appContainer(repo: repo),
          'rv-1',
        );
        final queue = repo.reviewQueueGate = Completer<void>();
        final revert = Completer<void>();
        if (!landed) repo.revertGate = revert;

        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.reviewApprove),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        // Decided, and still open while the queue reads again.
        expect(paneEntry(tester), 'rv-1');
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewRevert));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        queue.complete();
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        revert.complete();
        await tester.pumpAndSettle();

        expect(repo.revertedReviewEntryIds, ['rv-1']);
        // Reverted is decided for good, so the pane goes on as it does
        // after an undo, and says what it did.
        expect(location(router), WaxRoute.reviewEntry('rv-2'));
        expect(paneEntry(tester), 'rv-2');
        expect(_row('rv-1'), findsNothing);
        final undone = raisedMessage(tester)!;
        expect(shellMessageText(undone), 'Decision undone');
        expect(undone.onAction, isNull);
        expect(undone.channel, isNull);
        // One row lit, so the keys act on the entry the pane shows.
        final colors = WaxColors.of(tester.element(_row('rv-2')));
        expect(surfaceOf(tester, 'rv-2'), colors.accentContainer);
        expect(surfaceOf(tester, 'rv-3'), colors.canvas);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.pumpAndSettle();
        expect(repo.decideReviewCalls.last.entryId, 'rv-2');
      });
    }

    testWidgets('move on after an undo pressed while the queue reads again', (
      tester,
    ) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );
      final queue = repo.reviewQueueGate = Completer<void>();

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewApprove));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // The pane still draws the decided entry; the confirmation is up.
      expect(paneEntry(tester), 'rv-1');
      final confirmation = raisedMessage(tester)!;
      expect(confirmation.actionLabel, 'Undo');
      confirmation.onAction!();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      queue.complete();
      await tester.pumpAndSettle();

      expect(repo.revertedReviewEntryIds, ['rv-1']);
      expect(location(router), WaxRoute.reviewEntry('rv-2'));
      expect(paneEntry(tester), 'rv-2');
      // One row lit, so the keys act on the entry the pane shows.
      final colors = WaxColors.of(tester.element(_row('rv-2')));
      expect(surfaceOf(tester, 'rv-2'), colors.accentContainer);
      expect(surfaceOf(tester, 'rv-3'), colors.canvas);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(repo.decideReviewCalls.last.entryId, 'rv-2');
    });

    testWidgets('stay on the open entry when it is searched for again', (
      tester,
    ) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.reviewIdentifyToggle),
      );
      await tester.pumpAndSettle();
      final search = find.bySemanticsIdentifier(
        SemanticsIds.reviewIdentifySubmit,
      );
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.pumpAndSettle();

      expect(repo.reidentifyCalls.single.entryId, 'rv-1');
      expect(location(router), WaxRoute.reviewEntry('rv-1'));
      expect(paneEntry(tester), 'rv-1');
    });

    testWidgets('offer no undo for a decision that cannot be reverted', (
      tester,
    ) async {
      final repo = FakeRepository();
      _seedThree(repo);
      await openOnTable(tester, appContainer(repo: repo), 'rv-1');

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewSkip));
      await tester.pumpAndSettle();

      final message = raisedMessage(tester)!;
      expect(shellMessageText(message), 'Decided 1 entry');
      expect(message.actionLabel, isNull);
      expect(message.onAction, isNull);
    });

    testWidgets('follow a bulk decision that took the open entry past every '
        'entry it took', (tester) async {
      final repo = FakeRepository();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.longPress(_row('rv-1'));
      await tester.pumpAndSettle();
      await tester.tap(_row('rv-2'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
      await tester.pumpAndSettle();

      expect(repo.decideBulkCalls.single.entryIds, ['rv-1', 'rv-2']);
      expect(location(router), WaxRoute.reviewEntry('rv-3'));
      expect(paneEntry(tester), 'rv-3');
      final message = raisedMessage(tester)!;
      expect(shellMessageText(message), 'Decided 2 entries');
      expect(message.actionLabel, isNull);
    });

    testWidgets('follow a bulk decision onto the row the pane reached while '
        'it was out', (tester) async {
      // The bulk takes rv-2 while rv-1 is open; the pane moves onto rv-2
      // before the answer lands, and leaves it once it has.
      final repo = _HeldDecisions();
      _seedThree(repo);
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.longPress(_row('rv-2'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
      await tester.pump();
      expect(repo.decideBulkCalls.single.entryIds, ['rv-2']);
      router.go(WaxRoute.reviewEntry('rv-2'));
      // Frames rather than settling: the bulk's button draws busy.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(location(router), WaxRoute.reviewEntry('rv-2'));

      repo.release.complete();
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.reviewEntry('rv-3'));
      expect(paneEntry(tester), 'rv-3');
    });

    testWidgets('stay on the open entry when a bulk decision could not take '
        'it', (tester) async {
      final repo = FakeRepository();
      _seedThree(repo);
      repo.bulkOutcomes['rv-1'] = const ReviewBulkOutcome(
        entryId: 'rv-1',
        ok: false,
        code: 'conflict',
        error: 'the entry is being decided',
      );
      final router = await openOnTable(
        tester,
        appContainer(repo: repo),
        'rv-1',
      );

      await tester.longPress(_row('rv-1'));
      await tester.pumpAndSettle();
      await tester.tap(_row('rv-2'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.reviewBulkSkip));
      await tester.pumpAndSettle();

      expect(location(router), WaxRoute.reviewEntry('rv-1'));
      expect(paneEntry(tester), 'rv-1');
    });
  });

  group('a decision is a catalog write', () {
    const MusicListing tracks = (
      dimension: null,
      segment: '',
      domain: BrowseDomain.music,
    );
    final decisions =
        <String, Future<void> Function(ProviderContainer container)>{
          'one decided from the queue': (container) => container
              .read(reviewQueueProvider.notifier)
              .decide('rv-1', 'approve'),
          'several decided together': (container) => container
              .read(reviewQueueProvider.notifier)
              .decideBulk(['rv-1'], 'approve'),
          'one decided from its pane': (container) => container
              .read(reviewEntryProvider('rv-1').notifier)
              .decide('approve'),
          'one reverted': (container) =>
              container.read(reviewEntryProvider('rv-1').notifier).revert(),
        };
    for (final MapEntry(key: name, value: decide) in decisions.entries) {
      test('$name has an open listing read again', () async {
        final repo = FakeRepository(items: [testItem('tr-1')])
          ..reviewEntries = [testReviewEntry('rv-1')];
        final container = appContainer(repo: repo);
        addTearDown(container.dispose);
        container.listen(musicItemsProvider(tracks), (_, _) {});
        await container.read(musicItemsProvider(tracks).future);
        container.listen(reviewEntryProvider('rv-1'), (_, _) {});
        await container.read(reviewEntryProvider('rv-1').future);
        final before = repo.listItemsCalls.length;

        await decide(container);
        await container.pump();
        await pumpEventQueue();

        expect(repo.listItemsCalls, hasLength(before + 1));
      });
    }
  });
}
