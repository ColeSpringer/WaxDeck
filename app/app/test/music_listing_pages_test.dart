import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

/// A listing page can come back empty and still carry a cursor: the
/// server drops rows the caller may not see after it cuts the page. A
/// music listing that read one page as the whole answer said "nothing
/// here" over tracks one page further on.
void main() {
  const MusicListing tracks = (dimension: null, segment: '');
  const page = MusicItemsController.pageSize;

  List<ItemSummary> hidden(String tag, int count) => <ItemSummary>[
    for (var i = 0; i < count; i++) testItem('tr-$tag-$i'),
  ];

  ProviderContainer containerOver(FakeRepository repo) {
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final keep = container.listen(musicItemsProvider(tracks), (_, _) {});
    addTearDown(keep.close);
    return container;
  }

  test('a first page the listing emptied is read past', () async {
    final unseen = hidden('unseen', page);
    final repo = FakeRepository(items: [...unseen, testItem('tr-shown')])
      ..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = containerOver(repo);

    final first = await container.read(musicItemsProvider(tracks).future);
    expect(first.items.map((i) => i.pid), <String>['tr-shown']);
  });

  test('loading more reads past later empty pages, however many', () async {
    // Seven, past any budget a probe keeps.
    final unseen = hidden('unseen', 7 * page);
    final repo = FakeRepository(
      items: [...hidden('seen', page), ...unseen, testItem('tr-last')],
    )..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = containerOver(repo);

    await container.read(musicItemsProvider(tracks).future);
    await container.read(musicItemsProvider(tracks).notifier).loadMore();
    final state = container.read(musicItemsProvider(tracks)).value!;
    expect(state.items.last.pid, 'tr-last');
    expect(state.hasMore, isFalse);
  });

  test('leaving a listing while a page is loading is no error', () async {
    // Empty pages behind the one in flight, so the walk asks again after
    // the listing has gone.
    final unseen = hidden('unseen', 2 * page);
    final repo = FakeRepository(
      items: [...hidden('seen', page), ...unseen, testItem('tr-last')],
    )..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final keep = container.listen(musicItemsProvider(tracks), (_, _) {});
    await container.read(musicItemsProvider(tracks).future);
    final controller = container.read(musicItemsProvider(tracks).notifier);
    final gate = Completer<void>();
    repo.listItemsGate = gate;
    final more = controller.loadMore();

    keep.close();
    await pumpEventQueue();
    repo.listItemsGate = null;
    gate.complete();
    await expectLater(more, completes);
  });

  test('a short first page is shown as it is, its cursor kept', () async {
    // Read on to a quota, a page failing further in threw away the rows
    // in hand, and a run of short pages walked the listing. The screen
    // asks for more as it needs, a list too short to scroll included.
    final unseen = hidden('unseen', page - 1);
    final repo = FakeRepository(
      items: [testItem('tr-first'), ...unseen, testItem('tr-second')],
    )..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = containerOver(repo);

    final first = await container.read(musicItemsProvider(tracks).future);
    expect(first.items.map((i) => i.pid), <String>['tr-first']);
    expect(first.hasMore, isTrue);
    expect(repo.listItemsCalls, hasLength(1));
  });

  test('leaving a listing ends its first walk', () async {
    // Pages the listing emptied, one after another: a walk that outlived
    // the listing went on asking for every one of them.
    final unseen = hidden('unseen', 6 * page);
    final repo = FakeRepository(items: [...unseen, testItem('tr-last')])
      ..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final gate = Completer<void>();
    repo.listItemsGate = gate;
    final keep = container.listen(musicItemsProvider(tracks), (_, _) {});
    await pumpEventQueue();
    expect(repo.listItemsCalls, hasLength(1));

    keep.close();
    await pumpEventQueue();
    repo.listItemsGate = null;
    gate.complete();
    await pumpEventQueue();

    expect(repo.listItemsCalls, hasLength(1), reason: 'nobody is reading');
  });

  test('reading a listing through does not stop at an empty page', () async {
    final unseen = hidden('unseen', page);
    final repo = FakeRepository(
      items: [...hidden('seen', page), ...unseen, testItem('tr-last')],
    )..hiddenFromListings.addAll(unseen.map((i) => i.pid));
    final container = containerOver(repo);

    await container.read(musicItemsProvider(tracks).future);
    final all = await container
        .read(musicItemsProvider(tracks).notifier)
        .readThrough(atMost: 3 * page);
    expect(all.last.pid, 'tr-last');
  });
}
