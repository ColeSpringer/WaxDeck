import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/playlists/playlist_import.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlists_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _track = ItemSummary(
  pid: 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6',
  mediaType: MediaType.music,
  title: 'Prancing Pony Blues',
  artist: 'The Bree Trio',
  durationMs: 214000,
);

Widget _host(FakeRepository repo, Widget home) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: routedHost(home, pushed: true),
);

/// Opens the import menu and picks [source].
Future<void> _openImport(
  WidgetTester tester,
  PlaylistImportSource source,
) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistImport));
  await tester.pumpAndSettle();
  await tester.tap(
    find.bySemanticsIdentifier(SemanticsIds.playlistImportSource(source.wire)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('imports a Spotify CSV and shows the missing report', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track])
      ..playlistImportResult = const PlaylistImportResult(
        playlistPid: 'pl-01JZX5N8QW3F4V9T2B7KDNEW01',
        name: 'Roadtrip',
        requested: 3,
        resolved: 2,
        missing: [
          PlaylistImportMiss(artist: 'The Cardinal Waves', title: 'Neon'),
        ],
        rungs: ResolveRungCounts(
          essence: 0,
          strongId: 1,
          fingerprint: 0,
          descriptive: 1,
        ),
      );
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await _openImport(tester, PlaylistImportSource.spotify);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportName),
      'Roadtrip',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      'Track Name,Artist Name\nNeon,The Cardinal Waves\n',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    expect(repo.importPlaylistCalls, hasLength(1));
    final call = repo.importPlaylistCalls.single;
    expect(call.source, 'spotify');
    expect(call.name, 'Roadtrip');
    expect(call.payload, contains('Neon,The Cardinal Waves'));

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportReport),
      findsOneWidget,
    );
    expect(
      find.text('Created "Roadtrip" with 2 of 3 entries.'),
      findsOneWidget,
    );
    expect(find.text('The Cardinal Waves - Neon'), findsOneWidget);
  });

  testWidgets('a fully unmatched import reports no playlist', (tester) async {
    final repo = FakeRepository(items: const [_track]);
    // The fake derives an empty result: nothing resolved, no playlist.
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await _openImport(tester, PlaylistImportSource.text);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      'Nobody - Nothing\n',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    expect(repo.importPlaylistCalls.single.source, 'text');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportReport),
      findsOneWidget,
    );
    expect(find.textContaining('no playlist'), findsOneWidget);
  });

  testWidgets('the M3U source still rides the M3U endpoint', (tester) async {
    final repo = FakeRepository(items: const [_track])
      ..importMatched = 1
      ..importUnmatched = 0;
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await _openImport(tester, PlaylistImportSource.m3u);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportName),
      'From M3U',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      '#EXTM3U\n/music/pony.flac\n',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    expect(repo.importedM3uContents, hasLength(1));
    expect(repo.importPlaylistCalls, isEmpty);
  });

  testWidgets('an M3U import without a name says so and asks again', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await _openImport(tester, PlaylistImportSource.m3u);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      '#EXTM3U\n/music/pony.flac\n',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    // Said inside the dialog, which stays open: a snackbar would render
    // on the scaffold behind the modal route.
    expect(
      find.text('An M3U import needs a name for the playlist.'),
      findsOneWidget,
    );
    expect(repo.importedM3uContents, isEmpty);
  });

  testWidgets('export portable copies the refs JSON', (tester) async {
    final repo = FakeRepository(items: const [_track])
      ..portableExport = const PortablePlaylist(
        name: 'Road Trip',
        refs: [
          PortableRef(
            kind: 'track',
            title: 'Prancing Pony Blues',
            artist: 'The Bree Trio',
            durationMs: 214000,
          ),
        ],
      );
    final created = await repo.createPlaylist(
      name: 'Road Trip',
      kind: 'static',
      itemPids: [_track.pid],
    );
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: created.pid)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportPortable),
    );
    await tester.pumpAndSettle();

    expect(repo.exportedPortablePids, [created.pid]);
    expect(copied.single, contains('"name":"Road Trip"'));
    expect(copied.single, contains('"title":"Prancing Pony Blues"'));
    expect(copied.single, contains('"kind":"track"'));
    expect(find.text('Portable playlist copied'), findsOneWidget);
  });

  testWidgets('imports a portable JSON export through the refs source', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track])
      ..playlistImportResult = const PlaylistImportResult(
        playlistPid: 'pl-01JZX5N8QW3F4V9T2B7KDNEW02',
        name: 'From Elsewhere',
        requested: 1,
        resolved: 1,
        missing: [],
        rungs: ResolveRungCounts(
          essence: 1,
          strongId: 0,
          fingerprint: 0,
          descriptive: 0,
        ),
      );
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await _openImport(tester, PlaylistImportSource.portable);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      '{"name":"From Elsewhere","refs":[{"kind":"track","essence":"abc",'
      '"title":"Neon","artist":"The Cardinal Waves","durationMs":180000}]}',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    // The pasted JSON became structured refs, never a payload, and the
    // export's own name rode along.
    expect(repo.importPlaylistCalls, hasLength(1));
    final call = repo.importPlaylistCalls.single;
    expect(call.source, 'portable');
    expect(call.name, 'From Elsewhere');
    expect(call.payload, isNull);
    expect(call.refs, hasLength(1));
    expect(call.refs!.single.title, 'Neon');
    expect(call.refs!.single.essence, 'abc');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportReport),
      findsOneWidget,
    );
  });

  testWidgets('rejects garbage in the portable source with a message', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track]);
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await _openImport(tester, PlaylistImportSource.portable);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      'not json at all',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    expect(repo.importPlaylistCalls, isEmpty);
    expect(find.text('This is not the copied portable JSON'), findsOneWidget);
  });

  group('the portable parser', () {
    test('keeps every ref the export carried', () {
      final (name, refs) = parsePortablePlaylistJson(
        '{"name":"Mix","refs":[{"kind":"track","title":"One"},'
        '{"kind":"track","title":"Two","isrc":"X"}]}',
      );
      expect(name, 'Mix');
      expect(refs.map((r) => r.title), ['One', 'Two']);
      expect(refs.last.isrc, 'X');
    });

    test('refuses an export with nothing in it', () {
      expect(
        () => parsePortablePlaylistJson('{"name":"Empty","refs":[]}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
