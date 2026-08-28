import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
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

  testWidgets('the keep-matched switch is offered for every bindable source', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final repo = FakeRepository(items: const [_track]);
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    // M3U is not in the binding's source enum, so there is nothing to
    // keep it matched to.
    await _openImport(tester, PlaylistImportSource.m3u);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportKeepMatched),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Spelled out rather than read back off `canBind`, which is the
    // predicate the widget itself branches on: derived, this test
    // would pass a wrong answer as readily as the right one. It is
    // the binding's own source enum, minus m3u.
    for (final source in const [
      PlaylistImportSource.spotify,
      PlaylistImportSource.applemusic,
      PlaylistImportSource.ytmusic,
      PlaylistImportSource.csv,
      PlaylistImportSource.text,
      PlaylistImportSource.portable,
    ]) {
      await _openImport(tester, source);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playlistImportKeepMatched),
        findsOneWidget,
        reason: '${source.wire} can be bound',
      );
      // The dialog is the source's own, so the switch found above
      // belongs to this one and not to a stale one left open.
      expect(find.text('Import from ${source.labelOf(l10n)}'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('keeping it matched binds the export it just imported', (
    tester,
  ) async {
    const payload = 'Track Name,Artist Name\nNeon,The Cardinal Waves\n';
    final repo = FakeRepository(items: const [_track])
      ..playlistImportResult = const PlaylistImportResult(
        playlistPid: 'pl-01JZX5N8QW3F4V9T2B7KDNEW03',
        name: 'Roadtrip',
        requested: 1,
        resolved: 1,
        missing: [],
        rungs: ResolveRungCounts(
          essence: 0,
          strongId: 1,
          fingerprint: 0,
          descriptive: 0,
        ),
      );
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await _openImport(tester, PlaylistImportSource.spotify);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      payload,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportKeepMatched),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    // The binding is the export, byte for byte, against the pid the
    // import just minted - and mirror, because the playlist is that
    // export rather than a copy of it.
    expect(repo.setPlaylistSourceCalls, hasLength(1));
    final bind = repo.setPlaylistSourceCalls.single;
    expect(bind.pid, 'pl-01JZX5N8QW3F4V9T2B7KDNEW03');
    expect(bind.mode, 'mirror');
    expect(bind.source, 'spotify');
    expect(bind.payload, payload);
    expect(bind.refs, isNull);
    expect(bind.url, isNull);
    expect(bind.intervalHours, isNull);
    expect(
      find.text(
        'Kept matched to this export. Re-match it whenever you like from the '
        "playlist's sync settings.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('a portable import binds the refs it parsed, not the paste', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track])
      ..playlistImportResult = const PlaylistImportResult(
        playlistPid: 'pl-01JZX5N8QW3F4V9T2B7KDNEW04',
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
      '"title":"Neon","artist":"The Cardinal Waves"}]}',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportKeepMatched),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    final bind = repo.setPlaylistSourceCalls.single;
    expect(bind.source, 'portable');
    expect(bind.payload, isNull);
    expect(bind.refs, hasLength(1));
    expect(bind.refs!.single.essence, 'abc');
    // The same ref object the import was given, which is the only
    // assertion that can tell the parse apart from a second parse of
    // the same paste: PortableRef carries no value equality, so
    // identity here is identity.
    expect(
      identical(
        bind.refs!.single,
        repo.importPlaylistCalls.single.refs!.single,
      ),
      isTrue,
    );
  });

  testWidgets('a refused binding is reported and the import still lands', (
    tester,
  ) async {
    final repo = FakeRepository(items: const [_track])
      ..playlistImportResult = const PlaylistImportResult(
        playlistPid: 'pl-01JZX5N8QW3F4V9T2B7KDNEW05',
        name: 'Roadtrip',
        requested: 1,
        resolved: 1,
        missing: [],
        rungs: ResolveRungCounts(
          essence: 0,
          strongId: 1,
          fingerprint: 0,
          descriptive: 0,
        ),
      )
      ..playlistSourceError = const WaxDeckApiException(
        statusCode: 400,
        code: 'invalid-request',
        message: 'a matched source takes append or mirror',
      );
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await _openImport(tester, PlaylistImportSource.text);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      'The Bree Trio - Prancing Pony Blues\n',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportKeepMatched),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    // The paste box is gone and the report is up: the playlist was made,
    // and only the binding failed - in the server's own words.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportReport),
      findsOneWidget,
    );
    expect(
      find.text(
        'The playlist was created, but keeping it matched to the export '
        'failed: a matched source takes append or mirror',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an unmatched import with the switch on binds nothing', (
    tester,
  ) async {
    // Nothing resolved means no playlist, so there is no pid to bind.
    final repo = FakeRepository(items: const [_track]);
    await tester.pumpWidget(_host(repo, const PlaylistsScreen()));
    await tester.pumpAndSettle();

    await _openImport(tester, PlaylistImportSource.text);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportPayload),
      'Nobody - Nothing\n',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportKeepMatched),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistImportRun),
    );
    await tester.pumpAndSettle();

    expect(repo.setPlaylistSourceCalls, isEmpty);
    expect(find.textContaining('Kept matched'), findsNothing);
  });

  group('the portable parser', () {
    // The table comes in as an argument: what it refuses with is copy,
    // and this is not widget code.
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('keeps every ref the export carried', () {
      final (name, refs) = parsePortablePlaylistJson(
        l10n,
        '{"name":"Mix","refs":[{"kind":"track","title":"One"},'
        '{"kind":"track","title":"Two","isrc":"X"}]}',
      );
      expect(name, 'Mix');
      expect(refs.map((r) => r.title), ['One', 'Two']);
      expect(refs.last.isrc, 'X');
    });

    test('refuses an export with nothing in it', () {
      expect(
        () => parsePortablePlaylistJson(l10n, '{"name":"Empty","refs":[]}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
