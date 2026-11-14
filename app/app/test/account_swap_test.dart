import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/music/album_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart' show MusicDimension;
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/share_intake.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// What a tab already showing one account's album draws when another tab
/// signs in over the same browser's cookie.

const _ann = WaxDeckUser(id: 'us-ann', username: 'ann', roles: ['user']);
const _ben = WaxDeckUser(id: 'us-ben', username: 'ben', roles: ['user']);

ItemSummary _track(String title, int number) => ItemSummary(
  pid: 'tr-$title',
  mediaType: MediaType.music,
  title: title,
  artist: 'Nightjar',
  album: 'Gullwing',
  artistPid: 'ar-1',
  albumPid: 'al-1',
  trackNumber: number,
  durationMs: 240000,
);

/// A server where what the album holds and how often its tracks were
/// played depend on who asks: Ann's grants reach a track Ben's do not, and
/// each has a count of their own on the track both see.
class _Server extends FakeRepository {
  _Server() : super(sessionState: const SessionState(authenticated: true)) {
    signIn(_ann);
  }

  static const annPlays = 3;
  static const benPlays = 5;

  /// Who each read the album page makes was made for, in call order.
  final List<String?> albumReads = [];
  final List<String?> trackReads = [];
  final List<String?> batchReads = [];

  String? get _who => sessionState.user?.username;

  void signIn(WaxDeckUser who) {
    final ann = who == _ann;
    sessionState = SessionState(authenticated: true, user: who);
    facetItems['album 1'] = <ItemSummary>[
      _track('Shared', 1),
      if (ann) _track('Granted', 2),
    ];
    playCounts['tr-Shared'] = ann ? annPlays : benPlays;
  }

  @override
  Future<AlbumDetail> getAlbum(String pid) async {
    albumReads.add(_who);
    return AlbumDetail(pid: pid, title: 'Gullwing');
  }

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  }) {
    if (facet == 'album') trackReads.add(_who);
    return super.listItems(
      mediaType: mediaType,
      facet: facet,
      facetKey: facetKey,
      cursor: cursor,
      limit: limit,
    );
  }

  @override
  Future<List<PlayState>> listPlayStates(List<String> pids) {
    batchReads.add(_who);
    return super.listPlayStates(pids);
  }
}

/// How many reads of each kind the album page has made.
typedef _Reads = ({int album, int tracks, int playStates});

_Reads _readsOf(_Server server) => (
  album: server.albumReads.length,
  tracks: server.trackReads.length,
  playStates: server.batchReads.length,
);

final _album = WaxRoute.musicBucket(MusicDimension.albums, 'al-1');

/// The signed-in app at desktop width, on Ann's album page.
Future<ProviderContainer> _onAlbum(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await pumpWholeApp(
    tester,
    container: appContainer(
      repo: server,
      extra: [
        shareIntakeProvider.overrideWithValue(const InertShareIntakePort()),
      ],
    ),
  );
  container.read(routerProvider).go(_album);
  await tester.pumpAndSettle();
  expect(find.byType(AlbumScreen), findsOneWidget);
  expect(_drawnCounts(tester), <String, int>{
    'Shared': _Server.annPlays,
    'Granted': 0,
  });
  return container;
}

/// Each drawn row's title and count.
Map<String, int> _drawnCounts(WidgetTester tester) => <String, int>{
  for (final row in tester.widgetList<MediaListRow>(find.byType(MediaListRow)))
    row.data.title: row.data.playCount ?? 0,
};

/// What every count node on the page says.
Iterable<String> _countWords(WidgetTester tester) => <String>[
  for (var index = 0; index < 2; index++)
    for (final element
        in find
            .bySemanticsIdentifier(SemanticsIds.trackPlays(index))
            .evaluate())
      (element as RenderObjectElement).renderObject.debugSemantics!.label,
];

/// [frames] as runs, each with how many frames it held.
String _runs(List<String> frames) {
  final runs = <String>[];
  for (final frame in frames) {
    final last = runs.isEmpty ? null : runs.last.split(' x').first;
    if (last == frame) {
      final count = int.parse(runs.last.split(' x').last) + 1;
      runs[runs.length - 1] = '$frame x$count';
    } else {
      runs.add('$frame x1');
    }
  }
  return runs.join(', ');
}

/// Whose session the app holds: a name, or `out`.
String _session(ProviderContainer container) =>
    container.read(authControllerProvider).value?.user?.username ?? 'out';

/// Which of the two screens are mounted this frame.
String _screens(WidgetTester tester) => <String>[
  if (find.byType(AlbumScreen).evaluate().isNotEmpty) 'album',
  if (find.byType(LoginScreen).evaluate().isNotEmpty) 'login',
].join('+');

/// Starts Ben's session in Ann's place and pumps frame by frame until it
/// has settled, handing each frame to [onFrame]; answers the frames, as
/// session and screens.
Future<List<String>> _swapToBen(
  WidgetTester tester,
  ProviderContainer container,
  _Server server, {
  void Function(int frame)? onFrame,
}) async {
  server.signIn(_ben);
  var swapped = false;
  final swap = container
      .read(authControllerProvider.notifier)
      .refreshSession()
      .whenComplete(() => swapped = true);
  final frames = <String>[];
  for (var frame = 0; frame < 400; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    frames.add('${_session(container)}:${_screens(tester)}');
    onFrame?.call(frame);
    if (swapped && !tester.binding.hasScheduledFrame) break;
  }
  // Before the await: a swap that never settles fails here, with the
  // frames, rather than as a timeout.
  expect(swapped, isTrue, reason: _runs(frames));
  await swap;
  return frames;
}

void main() {
  testWidgets('a session from another account draws nothing read as the '
      'last one, and reads the album again as the new one', (tester) async {
    final server = _Server();
    final container = await _onAlbum(tester, server);
    final annPage = tester.state(find.byType(AlbumScreen));
    final annWords = _countWords(tester).single;
    final before = _readsOf(server);

    final frames = await _swapToBen(
      tester,
      container,
      server,
      onFrame: (frame) {
        if (_session(container) != _ben.username) return;
        final drawn = _drawnCounts(tester);
        final why = 'frame $frame';
        expect(drawn.values, isNot(contains(_Server.annPlays)), reason: why);
        expect(drawn.keys, isNot(contains('Granted')), reason: why);
        expect(_countWords(tester), isNot(contains(annWords)), reason: why);
        if (find.byType(AlbumScreen).evaluate().isNotEmpty) {
          expect(
            tester.state(find.byType(AlbumScreen)),
            isNot(same(annPage)),
            reason: why,
          );
        }
      },
    );

    expect(frames.where((f) => f.startsWith('ben:')), isNotEmpty);
    expect(container.read(signedInAccountProvider), _ben.id);
    // Each read made again, and only as Ben.
    for (final (name, reads, from) in <(String, List<String?>, int)>[
      ('album', server.albumReads, before.album),
      ('tracks', server.trackReads, before.tracks),
      ('play states', server.batchReads, before.playStates),
    ]) {
      expect(reads.sublist(from), isNotEmpty, reason: name);
      expect(reads.sublist(from), everyElement(_ben.username), reason: name);
    }
    expect(_drawnCounts(tester), <String, int>{'Shared': _Server.benPlays});
    expect(_countWords(tester), isNot(contains(annWords)));
  });

  testWidgets('the swap passes through the sign-in screen and settles back '
      'where it was', (tester) async {
    final server = _Server();
    final container = await _onAlbum(tester, server);

    final frames = await _swapToBen(tester, container, server);

    // Signed out, then Ben, as a sign-out and a sign-in would go.
    final sessions = <String>[for (final f in frames) f.split(':').first];
    final arrived = sessions.indexOf(_ben.username);
    final why = _runs(frames);
    expect(arrived, isPositive, reason: why);
    expect(sessions.take(arrived), everyElement('out'), reason: why);
    expect(sessions.skip(arrived), everyElement(_ben.username), reason: why);
    expect(frames.last, 'ben:album', reason: why);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    expect(container.read(playbackHeldProvider), isFalse);
    expect(container.read(routerProvider).state.uri.toString(), _album);
  });

  testWidgets('a session read again for the same account keeps the page and '
      'reads nothing', (tester) async {
    final server = _Server();
    final container = await _onAlbum(tester, server);
    final page = tester.state(find.byType(AlbumScreen));
    final before = _readsOf(server);

    // Rights moved: the same account, answered anew.
    server.sessionState = const SessionState(
      authenticated: true,
      user: WaxDeckUser(
        id: 'us-ann',
        username: 'ann',
        roles: ['user'],
        uploadEnabled: true,
      ),
    );
    // Not awaited before the frames: a refresh that waited on them would
    // otherwise time out rather than fail the frame checks.
    final refresh = container
        .read(authControllerProvider.notifier)
        .refreshSession();
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(LoginScreen), findsNothing, reason: 'frame $frame');
      expect(tester.state(find.byType(AlbumScreen)), same(page));
    }
    await refresh;
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(AlbumScreen)), same(page));
    expect(_readsOf(server), before);
    expect(_drawnCounts(tester), <String, int>{
      'Shared': _Server.annPlays,
      'Granted': 0,
    });
    expect(container.read(playbackHeldProvider), isFalse);
  });
}
