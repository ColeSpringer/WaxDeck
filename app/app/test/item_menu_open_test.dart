import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/book_bucket_screen.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/library/item_menu.dart';
import 'package:waxdeck/src/podcasts/episode_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _book = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';
const _episode = 'tr-01JZX5N8QW3F4V9T2B7KDEPISOD';

/// Opens an item's sheet as a card's overflow does.
class _Opener extends ConsumerWidget {
  const _Opener({
    required this.pid,
    required this.mediaType,
    this.artistPid,
    this.onPlay,
    this.inProgress = false,
    this.withOpen = true,
    this.showPid,
  });

  final String pid;
  final MediaType mediaType;
  final String? artistPid;
  final void Function(WidgetRef ref)? onPlay;
  final bool inProgress;
  final bool withOpen;
  final String? showPid;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: WaxButton(
        label: 'open',
        onPressed: () => showItemMenuSheet(
          context,
          ref,
          pid: pid,
          title: 'Something',
          mediaType: mediaType,
          artist: 'F. Herbert',
          artistPid: artistPid,
          onPlay: onPlay,
          inProgress: inProgress,
          withOpen: withOpen,
          showPid: showPid,
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, _Opener opener) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(FakeRepository()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
      child: routedHost(opener),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(_byId(SemanticsIds.itemMenuSheet(opener.pid)), findsOneWidget);
}

Finder _byId(String id) => find.bySemanticsIdentifier(id);

/// The sheet is the way to an item's own screen from a shelf whose tap
/// plays, and the touch way to a book's play, which is a hover elsewhere.
void main() {
  testWidgets('an audiobook\'s menu offers Open book and Resume', (
    tester,
  ) async {
    var plays = 0;
    await _open(
      tester,
      _Opener(
        pid: _book,
        mediaType: MediaType.audiobook,
        onPlay: (_) => plays++,
        inProgress: true,
      ),
    );

    expect(_byId(SemanticsIds.itemMenuOpenBook), findsOneWidget);
    // Above the facts, where the verbs a card had are.
    expect(
      tester.getTopLeft(_byId(SemanticsIds.itemMenuOpenBook)).dy,
      lessThan(tester.getTopLeft(_byId(SemanticsIds.itemMenuDetails)).dy),
    );
    expect(
      find.descendant(
        of: _byId(SemanticsIds.itemMenuPlay),
        matching: find.text('Resume'),
      ),
      findsOneWidget,
    );
    await tester.tap(_byId(SemanticsIds.itemMenuPlay));
    await tester.pumpAndSettle();
    expect(plays, 1);
    expect(_byId(SemanticsIds.itemMenuSheet(_book)), findsNothing);
  });

  testWidgets('a book nobody has started offers Play', (tester) async {
    await _open(
      tester,
      _Opener(pid: _book, mediaType: MediaType.audiobook, onPlay: (_) {}),
    );
    expect(
      find.descendant(
        of: _byId(SemanticsIds.itemMenuPlay),
        matching: find.text('Play'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no play row unless the caller passes one', (tester) async {
    await _open(
      tester,
      const _Opener(pid: _book, mediaType: MediaType.audiobook),
    );
    expect(_byId(SemanticsIds.itemMenuOpenBook), findsOneWidget);
    expect(_byId(SemanticsIds.itemMenuPlay), findsNothing);
  });

  testWidgets('Open book opens the book', (tester) async {
    await _open(
      tester,
      const _Opener(pid: _book, mediaType: MediaType.audiobook),
    );
    await tester.tap(_byId(SemanticsIds.itemMenuOpenBook));
    await tester.pumpAndSettle();
    expect(find.byType(BookScreen), findsOneWidget);
  });

  testWidgets('Go to author opens the author\'s books, not the artist', (
    tester,
  ) async {
    await _open(
      tester,
      const _Opener(
        pid: _book,
        mediaType: MediaType.audiobook,
        artistPid: 'ar-1',
      ),
    );
    expect(_byId(SemanticsIds.itemMenuGoArtist), findsNothing);
    expect(
      find.descendant(
        of: _byId(SemanticsIds.itemMenuGoAuthor),
        matching: find.text('Go to author'),
      ),
      findsOneWidget,
    );
    await tester.tap(_byId(SemanticsIds.itemMenuGoAuthor));
    await tester.pumpAndSettle();
    final page = tester.widget<BookBucketScreen>(find.byType(BookBucketScreen));
    expect(page.segment, 'ar-1');
  });

  testWidgets('a book with no author pid offers no Go to author', (
    tester,
  ) async {
    await _open(
      tester,
      const _Opener(pid: _book, mediaType: MediaType.audiobook),
    );
    expect(_byId(SemanticsIds.itemMenuGoAuthor), findsNothing);
  });

  testWidgets('an episode\'s menu opens the episode', (tester) async {
    await _open(
      tester,
      const _Opener(pid: _episode, mediaType: MediaType.podcast),
    );
    expect(_byId(SemanticsIds.itemMenuOpenBook), findsNothing);
    expect(_byId(SemanticsIds.itemMenuPlay), findsNothing);
    await tester.tap(_byId(SemanticsIds.itemMenuOpenEpisode));
    await tester.pumpAndSettle();
    // No show in hand: the flat location, with no ancestry.
    expect(
      tester.widget<EpisodeScreen>(find.byType(EpisodeScreen)).showPid,
      isNull,
    );
  });

  testWidgets('an episode whose show is known opens beneath its show', (
    tester,
  ) async {
    await _open(
      tester,
      const _Opener(
        pid: _episode,
        mediaType: MediaType.podcast,
        showPid: 'pc-1',
      ),
    );
    await tester.tap(_byId(SemanticsIds.itemMenuOpenEpisode));
    await tester.pumpAndSettle();
    final screen = tester.widget<EpisodeScreen>(find.byType(EpisodeScreen));
    expect((screen.pid, screen.showPid), (_episode, 'pc-1'));
  });

  testWidgets('where the tap already opens the item, the menu does not', (
    tester,
  ) async {
    await _open(
      tester,
      const _Opener(
        pid: _book,
        mediaType: MediaType.audiobook,
        withOpen: false,
      ),
    );
    expect(_byId(SemanticsIds.itemMenuOpenBook), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await _open(
      tester,
      const _Opener(
        pid: _episode,
        mediaType: MediaType.podcast,
        withOpen: false,
      ),
    );
    expect(_byId(SemanticsIds.itemMenuOpenEpisode), findsNothing);
  });

  testWidgets('a track\'s menu opens nothing of its own', (tester) async {
    await _open(
      tester,
      const _Opener(
        pid: 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1',
        mediaType: MediaType.music,
      ),
    );
    expect(_byId(SemanticsIds.itemMenuOpenBook), findsNothing);
    expect(_byId(SemanticsIds.itemMenuOpenEpisode), findsNothing);
  });

  testWidgets('a track\'s artist is still the music artist', (tester) async {
    await _open(
      tester,
      const _Opener(
        pid: 'tr-01JZX5N8QW3F4V9T2B7KDTRACK1',
        mediaType: MediaType.music,
        artistPid: 'ar-1',
      ),
    );
    expect(_byId(SemanticsIds.itemMenuGoArtist), findsOneWidget);
    expect(_byId(SemanticsIds.itemMenuGoAuthor), findsNothing);
  });
}
