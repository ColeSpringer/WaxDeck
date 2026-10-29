import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/tools/tasks_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// A repair's closing check: clean but for [counts].
Map<String, Object?> _after({
  bool consistent = true,
  Map<String, int> counts = const {},
}) => {
  for (final key in const [
    'itemsMissingFromSearch',
    'orphanSearchRows',
    'artistRollupDrift',
    'genreRollupDrift',
    'releaseGroupRollupDrift',
    'sortKeyDrift',
    'bookDurationDrift',
    'bookIsbnKeyDrift',
    'albumYearDrift',
    'releaseYearDrift',
    'playlistPositionDrift',
    'orphanArtSources',
    'orphanThumbnails',
    'orphanTagProvenance',
    'strandedTagRows',
  ])
    key: counts[key] ?? 0,
  'consistent': consistent,
  'reclaimable': false,
};

/// A repair's report: its steps at [steps], zero elsewhere.
Map<String, Object?> _summary(
  Map<String, int> steps, {
  Map<String, Object?>? after,
}) => {
  for (final key in const [
    'sortKeysRewritten',
    'orphansDeleted',
    'orphansPending',
    'artSourcesReclaimed',
    'thumbnailsReclaimed',
    'tagProvenanceReclaimed',
    'strandedTagRowsReclaimed',
    'searchRowsRebuilt',
  ])
    key: steps[key] ?? 0,
  'after': ?after,
};

void main() {
  testWidgets('a catalog repair is named, and its finished row says what '
      'it did and how the catalog read after', (tester) async {
    final repo = FakeRepository();
    final at = DateTime.utc(2026, 10, 1);
    repo.toolTasksById
      ..['tt-done'] = ToolTask(
        id: 'tt-done',
        type: 'catalog-repair',
        state: 'done',
        createdAt: at,
        finishedAt: at,
        summary: _summary({
          'sortKeysRewritten': 6,
          'orphansDeleted': 1,
          'orphansPending': 1,
          'artSourcesReclaimed': 11,
          'thumbnailsReclaimed': 12,
          'tagProvenanceReclaimed': 13,
          'strandedTagRowsReclaimed': 14,
          'searchRowsRebuilt': 11,
        }, after: _after()),
      )
      ..['tt-left'] = ToolTask(
        id: 'tt-left',
        type: 'catalog-repair',
        state: 'done',
        createdAt: at,
        finishedAt: at,
        summary: _summary(
          const {},
          after: _after(
            consistent: false,
            counts: {
              'sortKeyDrift': 2,
              'itemsMissingFromSearch': 1,
              // Neither counts against consistency.
              'playlistPositionDrift': 3,
              'orphanArtSources': 4,
            },
          ),
        ),
      )
      ..['tt-running'] = ToolTask(
        id: 'tt-running',
        type: 'catalog-repair',
        state: 'running',
        progressPct: 25,
        createdAt: at,
        summary: _summary({'sortKeysRewritten': 6}),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
        child: routedHost(const TasksScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    Finder inRow(String id, Finder finder) => find.descendant(
      of: find.bySemanticsIdentifier(SemanticsIds.taskRow(id)),
      matching: finder,
    );
    for (final id in ['tt-done', 'tt-left', 'tt-running']) {
      expect(inRow(id, find.text('Catalog repair')), findsOneWidget);
    }
    expect(
      inRow(
        'tt-done',
        find.text(
          'sort keys rewritten 6, empty entries removed 1, unused rows '
          'reclaimed 50, search rows rebuilt 11, consistent',
        ),
      ),
      findsOneWidget,
    );
    expect(inRow('tt-left', find.text('still out of step 3')), findsOneWidget);
    expect(
      find.byKey(const Key('task-summary-tt-running')),
      findsNothing,
      reason: 'a repair under way has no closing check to report',
    );
  });

  testWidgets('a fix task draws the edit glyph, which says nothing of how '
      'it went, not a download arrow', (tester) async {
    final repo = FakeRepository();
    final at = DateTime.utc(2026, 10, 1);
    for (final type in ['catalog-repair', 'health-fix', 'genre-normalize']) {
      repo.toolTasksById['tt-$type'] = ToolTask(
        id: 'tt-$type',
        type: type,
        state: 'queued',
        createdAt: at,
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
        child: routedHost(const TasksScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    for (final type in ['catalog-repair', 'health-fix', 'genre-normalize']) {
      final glyph = tester
          .widget<WaxIcon>(
            find
                .descendant(
                  of: find.bySemanticsIdentifier(
                    SemanticsIds.taskRow('tt-$type'),
                  ),
                  matching: find.byType(WaxIcon),
                )
                .first,
          )
          .glyph;
      final name = WaxIcons.all.entries
          .firstWhere((entry) => entry.value == glyph)
          .key;
      expect(name, 'edit', reason: type);
    }
  });
}
