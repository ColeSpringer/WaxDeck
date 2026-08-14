import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/books/books_controller.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/podcasts/podcasts_controller.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/stats/share_cards.dart';
import 'package:waxdeck/src/stats/stats_controller.dart';

/// The messages that select on a token - a Dart enum's `name`, or a
/// word the server sent. Nothing references those case strings, so
/// renaming one falls to the fallback silently. This is the gate.
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

      test('the pin sheet names every kind it is offered', () {
        // The tokens the three callers pass, which is the whole
        // vocabulary. A kind added there without an arm here falls to a
        // sentence naming nothing.
        for (final what in <String>['album', 'artist', 'book']) {
          expect(l10n.homePinSheetPin(what), isNot(l10n.homePinSheetPin('x')));
          expect(
            l10n.homePinSheetUnpin(what),
            isNot(l10n.homePinSheetUnpin('x')),
          );
        }
      });

      test('the recap names every ranked list it can draw', () {
        final fallback = l10n.statsTopEmptyMessage('none-of-them');
        for (final kind in topListKinds) {
          expect(
            l10n.statsTopEmptyMessage(kind),
            isNot(fallback),
            reason: 'statsTopEmptyMessage has no arm for $kind',
          );
        }
      });

      test('every card shape reads as itself', () {
        final fallback = l10n.statsCardPreviewSpoken('none-of-them');
        for (final format in ShareCardFormat.values) {
          expect(l10n.statsCardPreviewSpoken(format.name), isNot(fallback));
        }
      });

      // Open vocabularies, so a missing arm echoes the wire token. The
      // lists are the ones `api/spec/shares.yaml` and
      // `api/spec/review.yaml` document.
      test('a share says what it opens', () {
        for (final kind in <String>[
          'track',
          'album',
          'playlist',
          'book',
          'episode',
        ]) {
          expect(l10n.sharingKind(kind), isNot(kind));
        }
        expect(l10n.sharingKind('hologram'), 'hologram');
      });

      test('an entry says where it came from and how it ended', () {
        for (final origin in <String>['upload', 'acquisition']) {
          expect(reviewOriginLabel(l10n, origin), isNot(origin));
        }
        expect(reviewOriginLabel(l10n, 'telepathy'), 'telepathy');
        for (final status in <String>[
          'pending',
          'applied',
          'auto-applied',
          'as-is',
          'unofficial',
          'skipped',
          'discarded',
          'reverted',
        ]) {
          expect(reviewStatusLabel(l10n, status), isNot(status));
        }
        expect(reviewStatusLabel(l10n, 'sublimated'), 'sublimated');
      });

      test('a listening span never spells a unit in one language', () {
        // Both the stat tiles and the episode rows draw this one, so a
        // unit letter left in English would sit in two places at once.
        for (final ms in <int>[45000, 6 * 60000, 126 * 60000]) {
          expect(l10n.formatListenTime(ms), isNotEmpty);
        }
        if (locale == 'es') {
          expect(l10n.formatListenTime(45000), '45 s');
          expect(l10n.formatListenTime(126 * 60000), '2 h 6 min');
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
