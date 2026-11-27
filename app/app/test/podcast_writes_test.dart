import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/podcasts/episode_actions.dart';
import 'package:waxdeck/src/podcasts/podcasts_controller.dart';
import 'package:waxdeck/src/podcasts/show_actions.dart';
import 'package:waxdeck/src/sync/catalog_reads.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

// A podcast write that has changed rows when it answers says so through
// the one path every catalog write uses, so every read of the catalog a
// screen holds open follows it, not a list of them kept at the site.

const _show = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episode = 'ep-01JZX5N8QW3F4V9T2B7KDEPIS01';

final class _Invalidations extends ProviderObserver {
  final seen = <ProviderBase<Object?>>{};

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    seen.add(context.provider);
  }
}

/// A server that follows one show with one fetched episode, and a
/// container holding every plain read of the registry open over it.
({FakeRepository repo, ProviderContainer container, _Invalidations swept})
_open() {
  final repo = FakeRepository()
    ..addSubscription(testShow(_show))
    ..episodesByShow[_show] = [testEpisode(_episode)];
  final swept = _Invalidations();
  final container = appContainer(repo: repo, observers: [swept]);
  for (final read in catalogReadProviders) {
    container.listen(read, (_, _) {});
  }
  return (repo: repo, container: container, swept: swept);
}

/// A store whose sweep prelude can be made to throw: a defect in the
/// sweep a write lands through.
class _BrokenStore extends FakeArtworkStore {
  bool broken = false;

  @override
  void forgetAbsences() {
    if (broken) throw StateError('the sweep broke');
    super.forgetAbsences();
  }
}

/// Every plain read of the registry: more than any site's own list held.
Matcher get _everyRead => containsAll(catalogReadProviders);

void main() {
  testWidgets('a subscription from the hub has every open read read again', (
    tester,
  ) async {
    final (:repo, :container, :swept) = _open();
    await tester.pump();
    swept.seen.clear();

    await container
        .read(subscriptionsProvider.notifier)
        .subscribe(url: 'https://shire.example/feed.xml');

    expect(repo.subscribeCalls, hasLength(1));
    expect(swept.seen, _everyRead);
    // The reads the sweep prompted.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an OPML import has every open read read again', (tester) async {
    final (:repo, :container, :swept) = _open();
    await tester.pump();
    swept.seen.clear();

    await container.read(subscriptionsProvider.notifier).importOpml('<opml/>');

    expect(repo.importedOpml, ['<opml/>']);
    expect(swept.seen, _everyRead);
    // The reads the sweep prompted.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a subscription from the show has every open read read again', (
    tester,
  ) async {
    final (:repo, :container, :swept) = _open();
    repo.subscriptions.remove(_show);
    final show = podcastDetailProvider(_show);
    container.listen(show, (_, _) {});
    expect((await container.read(show.future)).subscribed, isFalse);
    swept.seen.clear();

    await container.read(show.notifier).subscribe();

    expect(repo.subscribeCalls, hasLength(1));
    expect(swept.seen, _everyRead);
    expect((await container.read(show.future)).subscribed, isTrue);
    // The reads the sweep prompted.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('leaving a show has every open read read again', (tester) async {
    final (:repo, :container, :swept) = _open();
    final show = podcastDetailProvider(_show);
    container.listen(show, (_, _) {});
    await container.read(show.future);
    swept.seen.clear();

    await container.read(show.notifier).unsubscribe();

    expect(repo.unsubscribeCalls, [_show]);
    expect(swept.seen, _everyRead);
    expect((await container.read(show.future)).subscribed, isFalse);
    // The reads the sweep prompted.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a feed refresh has every open read read again', (tester) async {
    final (:repo, :container, :swept) = _open();
    late BuildContext context;
    late WidgetRef ref;
    await mountApp(
      tester,
      Consumer(
        builder: (c, r, _) {
          context = c;
          ref = r;
          return const SizedBox();
        },
      ),
      container: container,
      routed: false,
    );
    await tester.pump();
    swept.seen.clear();

    await runShowAction(
      context,
      ref,
      ShowAction.refresh,
      pid: _show,
      title: 'The Prancing Pony Hour',
      hasArtwork: false,
    );

    expect(repo.refreshPodcastCalls, [_show]);
    expect(swept.seen, _everyRead);
    // The reads the sweep prompted, and the shell's message.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('an episode\'s audio removed from its show\'s listing has '
      'every open read read again', (tester) async {
    final (:repo, :container, :swept) = _open();
    final listing = episodesProvider(_show);
    container.listen(listing, (_, _) {});
    await container.read(listing.future);
    swept.seen.clear();

    await container.read(listing.notifier).removeEpisodeDownload(_episode);

    expect(repo.removeDownloadCalls, [_episode]);
    expect(swept.seen, _everyRead);
    expect(swept.seen, contains(listing));
    // The reads the sweep prompted.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an episode\'s audio removed outside a listing has every '
      'open read read again', (tester) async {
    final (:repo, :container, :swept) = _open();
    late BuildContext context;
    late WidgetRef ref;
    await mountApp(
      tester,
      Consumer(
        builder: (c, r, _) {
          context = c;
          ref = r;
          return const SizedBox();
        },
      ),
      container: container,
      routed: false,
    );
    await tester.pump();
    swept.seen.clear();

    await EpisodeActions(ref: ref)
        .removeDownload(context, testEpisode(_episode));

    expect(repo.removeDownloadCalls, [_episode]);
    expect(swept.seen, _everyRead);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a show nobody listens to takes the answer of its write', (
    tester,
  ) async {
    final (:repo, :container, swept: _) = _open();
    repo.subscriptions.remove(_show);
    final show = podcastDetailProvider(_show);
    expect((await container.read(show.future)).subscribed, isFalse);
    repo.getPodcastCalls.clear();

    await container.read(show.notifier).subscribe();
    await tester.pump(const Duration(seconds: 1));

    expect(container.read(show).value?.subscribed, isTrue);
    expect(repo.getPodcastCalls, isEmpty);
  });

  testWidgets('a show whose write broke in its sweep leaves no answer for a '
      'later build', (tester) async {
    final repo = FakeRepository()..addSubscription(testShow(_show));
    repo.subscriptions.remove(_show);
    final store = _BrokenStore();
    final container = appContainer(repo: repo, artwork: store);
    final show = podcastDetailProvider(_show);
    container.listen(show, (_, _) {});
    await container.read(show.future);

    store.broken = true;
    await expectLater(
      container.read(show.notifier).subscribe(),
      throwsStateError,
    );
    store.broken = false;
    repo.getPodcastCalls.clear();
    container.invalidate(show);
    await container.read(show.future);

    expect(repo.getPodcastCalls, [_show], reason: 'read, not handed over');
    await tester.pump(const Duration(seconds: 1));
  });

  group('a show open on a long listing', () {
    // Three pages of episodes, all loaded, under an open show.
    Future<
      ({
        FakeRepository repo,
        ProviderContainer container,
        ProviderBase<AsyncValue<PodcastDetail>> show,
        ProviderBase<AsyncValue<EpisodeListState>> episodes,
      })
    >
    open(WidgetTester tester, {bool subscribed = true}) async {
      final (:repo, :container, swept: _) = _open();
      repo.episodesByShow[_show] = [
        for (var i = 0; i < 120; i++)
          testEpisode('ep-01JZX5N8QW3F4V9T2B7KD${'$i'.padLeft(5, '0')}'),
      ];
      if (!subscribed) repo.subscriptions.remove(_show);
      final show = podcastDetailProvider(_show);
      final episodes = episodesProvider(_show);
      container
        ..listen(show, (_, _) {})
        ..listen(episodes, (_, _) {});
      await container.read(show.future);
      await container.read(episodes.future);
      await container.read(episodes.notifier).loadMore();
      await container.read(episodes.notifier).loadMore();
      expect(container.read(episodes).value?.items, hasLength(120));
      await tester.pump();
      repo.getPodcastCalls.clear();
      repo.listEpisodesCalls.clear();
      return (repo: repo, container: container, show: show, episodes: episodes);
    }

    for (final follow in [true, false]) {
      testWidgets('${follow ? 'followed' : 'left'}, takes the show from the '
          'answer and reads its episodes where the listing stands', (
        tester,
      ) async {
        final (:repo, :container, :show, :episodes) = await open(
          tester,
          subscribed: !follow,
        );
        final notifier = container.read(podcastDetailProvider(_show).notifier);

        await (follow ? notifier.subscribe() : notifier.unsubscribe());
        await tester.pump(const Duration(seconds: 1));

        expect(container.read(show).value?.subscribed, follow);
        expect(
          repo.getPodcastCalls,
          isEmpty,
          reason: 'the write answered what the show is now',
        );
        final listing = container.read(episodes).value!;
        expect(listing.items, hasLength(120));
        expect(listing.hasMore, isFalse);
        // The loaded extent, once: three pages.
        expect(repo.listEpisodesCalls, hasLength(3));
      });
    }

    testWidgets('keeps its pages when an episode\'s audio is removed', (
      tester,
    ) async {
      final (:repo, :container, show: _, :episodes) = await open(tester);
      final deep = container.read(episodes).value!.items[110].pid;

      await container
          .read(episodesProvider(_show).notifier)
          .removeEpisodeDownload(deep);
      await tester.pump(const Duration(seconds: 1));

      final listing = container.read(episodes).value!;
      expect(listing.items, hasLength(120));
      expect(listing.items[110].downloaded, isFalse);
    });

    testWidgets('marks an episode queued in place when its fetch is asked', (
      tester,
    ) async {
      final (:repo, :container, show: _, :episodes) = await open(tester);
      final deep = container.read(episodes).value!.items[110].pid;
      await container
          .read(episodesProvider(_show).notifier)
          .removeEpisodeDownload(deep);
      await tester.pump(const Duration(seconds: 1));
      repo.listEpisodesCalls.clear();

      await container.read(episodesProvider(_show).notifier).fetchEpisode(deep);

      final listing = container.read(episodes).value!;
      expect(listing.items, hasLength(120));
      expect(listing.items[110].fetchState, 'queued');
      expect(repo.listEpisodesCalls, isEmpty, reason: 'no read asked');
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
