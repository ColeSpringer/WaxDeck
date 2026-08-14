import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/books/books_controller.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_controller.dart';

/// The messages that select on a Dart enum's `name`.
///
/// Nothing in Dart references those case strings, so renaming a value or
/// adding one compiles, analyzes, and passes every other test while the
/// screen quietly falls to the `other` arm. This is the gate that fails
/// instead.
void main() {
  for (final locale in <String>['en', 'es']) {
    group('$locale selects', () {
      late AppLocalizations l10n;

      setUpAll(() async {
        l10n = await AppLocalizations.delegate.load(Locale(locale));
      });

      /// A case the message does not carry reads the same as a name it
      /// has never heard of.
      void covers(
        String message,
        Iterable<Enum> values,
        String Function(String name) of,
      ) {
        test('$message covers every case', () {
          final fallback = of('a-name-no-arm-carries');
          for (final value in values) {
            expect(
              of(value.name),
              isNot(fallback),
              reason: '$message has no arm for ${value.name}',
            );
          }
        });
      }

      const dimensions = MusicDimension.values;
      covers(
        'musicDimensionTitle',
        dimensions,
        (n) => l10n.musicDimensionTitle(n),
      );
      covers(
        'musicDimensionSingularTitle',
        dimensions,
        (n) => l10n.musicDimensionSingularTitle(n),
      );
      covers(
        'musicBucketUnknownTitle',
        dimensions,
        (n) => l10n.musicBucketUnknownTitle(n),
      );
      covers(
        'musicIndexLoadError',
        dimensions,
        (n) => l10n.musicIndexLoadError(n),
      );
      covers(
        'musicIndexEmptyTitle',
        dimensions,
        (n) => l10n.musicIndexEmptyTitle(n),
      );
      covers(
        'musicIndexEmptyMessage',
        dimensions,
        (n) => l10n.musicIndexEmptyMessage(n),
      );
      covers('musicIndexStartOf', dimensions, (n) => l10n.musicIndexStartOf(n));
      covers(
        'musicListingBucketEmptyTitle',
        dimensions,
        (n) => l10n.musicListingBucketEmptyTitle(n),
      );
      covers('musicIndexCount', dimensions, (n) => l10n.musicIndexCount(n, 3));
      covers(
        'musicIndexCountAtLeast',
        dimensions,
        (n) => l10n.musicIndexCountAtLeast(n, 3),
      );
      covers('booksSortRow', BookSort.values, (n) => l10n.booksSortRow(n));
      covers(
        'podcastSortRow',
        SubscriptionSort.values,
        (n) => l10n.podcastSortRow(n),
      );

      // BookFilter.all is worded as the fallback on purpose: no chip
      // narrowed the grid, so the sentence names nothing.
      covers(
        'booksFilterEmptyMessage',
        BookFilter.values.where((f) => f != BookFilter.all),
        (n) => l10n.booksFilterEmptyMessage(n),
      );

      test('podcastCueStartsAt covers every cue kind', () {
        final fallback = l10n.podcastCueStartsAt('none-of-them', '4:05');
        for (final kind in PodcastCue.values) {
          expect(l10n.podcastCueStartsAt(kind.name, '4:05'), isNot(fallback));
        }
      });

      // Only where the arms differ from their wire values: the fallback
      // echoes the kind, and English words it the same way, so a missing
      // arm is invisible there.
      if (locale != 'en') {
        test('playlistRuleMediaType covers the kinds a rule can test', () {
          for (final kind in <String>['music', 'podcast', 'audiobook']) {
            expect(l10n.playlistRuleMediaType(kind), isNot(kind));
          }
          expect(l10n.playlistRuleMediaType('holo'), 'holo');
        });
      }
    });
  }
}
