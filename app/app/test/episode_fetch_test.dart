import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/podcasts/episode_fetch.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

const _pid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

void main() {
  group('episodeFetchOf', () {
    test('an episode the server holds is done, whatever else it says', () {
      expect(
        episodeFetchOf(testEpisode(_pid, fetchState: 'failed')),
        isA<EpisodeFetchDone>(),
      );
      expect(
        episodeFetchOf(testEpisode(_pid, fetchState: 'queued')),
        isA<EpisodeFetchDone>(),
      );
    });

    test('no fetch state is ready', () {
      expect(
        episodeFetchOf(testEpisode(_pid, downloaded: false)),
        isA<EpisodeFetchReady>(),
      );
    });

    test('failed carries the server reason', () {
      final fetch = episodeFetchOf(
        testEpisode(
          _pid,
          downloaded: false,
          fetchState: 'failed',
          fetchError: 'the host refused',
        ),
      );
      expect(fetch, isA<EpisodeFetchFailed>());
      expect((fetch as EpisodeFetchFailed).reason, 'the host refused');
    });

    test('queued, and any value the server may add later, is queued', () {
      for (final state in <String>['queued', 'running']) {
        expect(
          episodeFetchOf(
            testEpisode(_pid, downloaded: false, fetchState: state),
          ),
          isA<EpisodeFetchQueued>(),
          reason: state,
        );
      }
    });
  });

  group('episodeFetchWaxAction', () {
    final l10n = AppLocalizationsEn();
    WaxAction action(EpisodeFetch fetch) => episodeFetchWaxAction(
      l10n,
      _pid,
      fetch,
      onFetch: () {},
      onRemove: () {},
    );

    test('the four states share one slot and a press where one is left', () {
      final ready = action(const EpisodeFetch.ready());
      final queued = action(const EpisodeFetch.queued());
      final failed = action(const EpisodeFetch.failed('the host refused'));
      final done = action(const EpisodeFetch.done());
      expect(ready.slot, _pid);
      expect(<Object?>{
        ready.slot,
        queued.slot,
        failed.slot,
        done.slot,
      }, hasLength(1));

      expect(ready.label, 'Download');
      expect(ready.state, isA<WaxActionReady>());
      expect(ready.onPressed, isNotNull);
      expect(ready.semanticsId, SemanticsIds.episodeFetch(_pid));

      expect(queued.label, 'Queued for download');
      expect(queued.state, isA<WaxActionStatus>());
      expect(queued.onPressed, isNull);
      expect(queued.semanticsId, SemanticsIds.episodeFetch(_pid));

      expect(failed.label, 'Retry download');
      expect(failed.state, isA<WaxActionFailed>());
      expect(failed.detail, contains('the host refused'));
      expect(failed.onPressed, isNotNull);
      expect(failed.semanticsId, SemanticsIds.episodeFetch(_pid));

      expect(done.label, 'Remove download');
      expect(done.state, isA<WaxActionDone>());
      expect(done.onPressed, isNotNull);
      expect(done.semanticsId, SemanticsIds.episodeRemove(_pid));
    });

    test('a failure with no reason has no detail to read', () {
      expect(action(const EpisodeFetch.failed(null)).detail, isNull);
    });
  });
}
