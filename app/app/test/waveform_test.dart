import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/waveform.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const _pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

void main() {
  group('normalising peaks', () {
    test('a ready waveform becomes heights from 0 to 1', () {
      // Normalised against the track's own loudest bucket, so a master
      // cut quiet draws a shape rather than a line along the axis.
      final peaks = normalisedPeaks(
        const Waveform(state: 'ready', peaks: [0, 32, 64], resolution: 3),
      );
      expect(peaks, isNotNull);
      expect(peaks!.first, 0);
      expect(peaks[1], closeTo(0.5, 0.01));
      expect(peaks.last, 1);
    });

    test('pending and unavailable both draw the plain bar', () {
      expect(normalisedPeaks(const Waveform(state: 'pending')), isNull);
      expect(normalisedPeaks(const Waveform(state: 'unavailable')), isNull);
      // An open set: anything unrecognised reads as unavailable rather
      // than as a spinner nothing resolves.
      expect(normalisedPeaks(const Waveform(state: 'reticulating')), isNull);
    });

    test('a silent file is not divided by its own silence', () {
      expect(
        normalisedPeaks(
          const Waveform(state: 'ready', peaks: [0, 0, 0], resolution: 3),
        ),
        isNull,
      );
    });

    test('resolution is read rather than assumed', () {
      // A response whose two fields disagree is trusted for the count it
      // reported: the thousand buckets are a catalog constant an
      // analysis-version bump may change.
      final peaks = normalisedPeaks(
        const Waveform(
          state: 'ready',
          peaks: [255, 128, 64, 32],
          resolution: 2,
        ),
      );
      expect(peaks, hasLength(2));
    });
  });

  group('the seek bar reads the waveform', () {
    testWidgets('a music track asks for its peaks', (tester) async {
      final repo = FakeRepository(items: [testItem(_pid)])
        ..waveforms[_pid] = Waveform(
          state: 'ready',
          peaks: List<int>.generate(1000, (i) => i % 256),
          resolution: 1000,
        );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: testItem(_pid),
      );
      await tester.pumpAndSettle();

      expect(repo.waveformCalls, contains(_pid));
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerSeek),
        findsOneWidget,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('a podcast episode does not', (tester) async {
      // Episodes are excluded from the analyze pass upstream by design,
      // so the answer is known before it is asked for.
      final repo = FakeRepository()..addSubscription(testShow('pc-1'));
      final episode = testItem(
        'tr-01JZX5N8QW3F4V9T2B7KDEP0001',
        mediaType: MediaType.podcast,
      );
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(minutes: 30)),
        item: episode,
      );
      await tester.pumpAndSettle();

      expect(repo.waveformCalls, isEmpty);
      await harness.endPlayback(tester);
    });

    test('a refusal draws the bar rather than an error', () async {
      // A waveform is decoration: an item that has gone away, a catalog
      // in maintenance, and a credential that has just rotated all mean
      // the same thing to a seek bar.
      final repo = FakeRepository(items: [testItem(_pid)])
        ..waveformError = const WaxDeckApiException(
          code: 'catalog-maintenance',
          message: 'the catalog is being rebuilt',
          statusCode: 503,
        );
      final container = playbackContainer(repo: repo, engine: FakeEngine());
      final sub = container.listen(waveformProvider(_pid), (_, _) {});
      addTearDown(sub.close);
      expect(await container.read(waveformProvider(_pid).future), isNull);
    });
  });

  // The chapter view is a window on the book's envelope, not a second
  // request: a part is a file boundary and a chapter is not.
  group('slicing a book\'s envelope', () {
    final book = <double>[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0];

    test('takes the span the chapter covers', () {
      expect(slicePeaks(book, 0.2, 0.5), <double>[0.3, 0.4, 0.5]);
      expect(slicePeaks(book, 0, 0.1), <double>[0.1]);
      // The tail rounds outward rather than dropping the last bucket.
      expect(slicePeaks(book, 0.9, 1), <double>[1.0]);
    });

    test('keeps the book\'s own scale', () {
      // A quiet chapter stays quiet. Renormalising the slice would make
      // the same audio look different depending on which view was
      // last tapped, and would tell a listener a whispered chapter is
      // as loud as the loudest thing in the book.
      final quiet = slicePeaks(book, 0, 0.3)!;
      expect(quiet.reduce((a, b) => a > b ? a : b), lessThan(0.5));
    });

    test('answers null where there is nothing to slice', () {
      expect(slicePeaks(null, 0, 1), isNull);
      expect(slicePeaks(const <double>[], 0, 1), isNull);
      // A zero-length or inverted span is a chapter list disagreeing
      // with a duration, which is a plain bar rather than a crash.
      expect(slicePeaks(book, 0.5, 0.5), isNull);
      expect(slicePeaks(book, 0.8, 0.2), isNull);
    });
  });
}
