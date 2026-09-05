import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'books_controller.dart';
import 'series_controller.dart';

/// Reads series pages until the list is exhausted, or until [atLeast]
/// of them are in hand.
///
/// The page can come back short or empty with more to come - the
/// listing enumerates and hydrates separately, and drops what the
/// caller cannot see on top of that - so the loop follows `nextCursor`
/// rather than a non-empty page, and stops at a bound so a pathological
/// library cannot spin here.
Future<List<BookSeries>> _drainBookSeries(
  WaxDeckRepository repository, {
  int? atLeast,
}) async {
  final out = <BookSeries>[];
  String? cursor;
  for (var page = 0; page < 20; page++) {
    final next = await repository.listBookSeries(cursor: cursor, limit: 200);
    out.addAll(next.series);
    cursor = next.nextCursor;
    if (cursor == null) break;
    if (atLeast != null && out.length >= atLeast) break;
  }
  return out;
}

/// Every series in the library, drained.
///
/// Drained rather than paged: the merge picker is over a list a library
/// has tens of, not thousands, and a target has to be findable in one
/// look. The index screen reads the same list for the same reason.
final bookSeriesProvider = FutureProvider.autoDispose<List<BookSeries>>(
  (ref) => _drainBookSeries(ref.watch(repositoryProvider)),
  retry: retryUnlessRefused,
);

/// As many series as the hub's shelf can draw.
///
/// A separate read from the drained one on purpose: the shelf is on the
/// audiobook hub's build path, so every entry into the domain - every
/// back-navigation out of a book among them - would otherwise pay for
/// the whole list to draw at most a dozen tiles. This one stops as soon
/// as it has them, which on any ordinary library is the first page.
final bookSeriesShelfProvider = FutureProvider.autoDispose<List<BookSeries>>(
  (ref) => _drainBookSeries(
    ref.watch(repositoryProvider),
    atLeast: kBookSeriesShelf,
  ),
  retry: retryUnlessRefused,
);

/// How many series the hub's shelf draws before Show all is the way on.
const int kBookSeriesShelf = 12;

/// The picker that folds one book's series into another.
///
/// The book's own series is the loser: "merge this into that" is the
/// sentence the row says, and the survivor is the spelling the curator
/// picks. Everything the books carry rides along; only the name goes.
Future<void> showSeriesMergeSheet(
  BuildContext context, {
  required BookDetail book,
}) async {
  final loser = book.seriesPid;
  if (loser == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final container = ProviderScope.containerOf(context, listen: false);
  await showWaxOptionSheet(
    context,
    builder: (sheetContext) => Consumer(
      builder: (_, ref, _) {
        final series = ref.watch(bookSeriesProvider);
        return Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.seriesMergeSheet,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(
                title: l10n.bookSeriesMergeTitle(book.series ?? loser),
              ),
              Text(
                l10n.bookSeriesMergeHelp,
                style: WaxType.bodySmall.copyWith(
                  color: WaxColors.of(sheetContext).textSecondary,
                ),
              ),
              const SizedBox(height: WaxSpace.s12),
              // Scrollable, and only as tall as it needs to be: a
              // library with one other series gets a short sheet, one
              // with forty gets a list that scrolls instead of a sheet
              // taller than the screen.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: switch (series) {
                      AsyncValue(value: final rows?) => <Widget>[
                        for (final row in rows)
                          if (row.pid != loser)
                            WaxOptionRow(
                              title: row.name,
                              subtitle: row.bookCount > 0
                                  ? l10n.bookSeriesBookCount(row.bookCount)
                                  : null,
                              glyph: WaxIcons.audiobooks,
                              semanticsId: SemanticsIds.seriesMergeTarget(
                                row.pid,
                              ),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                unawaited(
                                  _merge(
                                    container: container,
                                    messenger: messenger,
                                    l10n: l10n,
                                    survivor: row,
                                    loser: loser,
                                  ),
                                );
                              },
                            ),
                        if (rows.every((row) => row.pid == loser))
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: WaxSpace.s12,
                            ),
                            child: Text(l10n.bookSeriesMergeEmpty),
                          ),
                      ],
                      AsyncValue(hasError: true, error: final Object error) =>
                        <Widget>[
                          ErrorState(
                            title: l10n.bookSeriesMergeTitle(
                              book.series ?? loser,
                            ),
                            message: sheetContext.explain(error),
                            onRetry: () => ref.invalidate(bookSeriesProvider),
                          ),
                        ],
                      _ => const <Widget>[
                        SkeletonShapes(shape: SkeletonShape.list),
                      ],
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _merge({
  required ProviderContainer container,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required BookSeries survivor,
  required String loser,
}) async {
  try {
    await container
        .read(repositoryProvider)
        .mergeDuplicates(
          entityType: 'series',
          survivorPid: survivor.pid,
          loserPids: <String>[loser],
        );
    container
      ..invalidate(bookSeriesProvider)
      ..invalidate(bookSeriesDetailProvider)
      ..invalidate(bookDetailProvider);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.bookSeriesMergeDone(survivor.name))),
    );
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainRefusal(l10n, e))));
  }
}
