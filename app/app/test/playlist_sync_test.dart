import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/playlists/playlist_screen.dart';
import 'package:waxdeck/src/playlists/playlist_sync_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
  canDelete: true,
);

const _plain = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDPLAINER',
  username: 'sam',
  roles: ['user'],
);

final _bound = PlaylistSource(
  source: 'youtube',
  url: 'https://tube.example/playlist?list=PLbound',
  title: 'Road Tapes',
  live: true,
  mode: 'mirror',
  intervalHours: 6,
  disabled: false,
  consecutiveFailures: 0,
  lastSyncedAt: DateTime.utc(2026, 8, 20),
);

Widget _host(FakeRepository repo, Widget home) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    filePickerProvider.overrideWithValue(null),
  ],
  child: routedHost(home, pushed: true),
);

Future<Playlist> _manualPlaylist(FakeRepository repo) =>
    repo.createPlaylist(name: 'Road Trip', kind: 'static');

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
  await tester.pumpAndSettle();
  await tester.tap(
    find.bySemanticsIdentifier(SemanticsIds.playlistSyncSettings),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sync entry is offered on an owned manual playlist only', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final manual = await _manualPlaylist(repo);
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: manual.pid)));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncSettings),
      findsOneWidget,
    );
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    final smart = await repo.createPlaylist(
      name: 'Smart',
      kind: 'smart',
      rule: const SmartRule(root: RuleNode.all([])),
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: smart.pid)));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistOverflow));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncSettings),
      findsNothing,
      reason: 'a smart playlist has no membership to bind',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistExportM3u),
      findsOneWidget,
      reason: 'the neighbouring rows are unchanged',
    );
  });

  testWidgets('the sheet binds a URL with the picked mode and interval', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncSheet),
      findsOneWidget,
    );
    // Unbound: nothing to sync or unbind yet.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncNow),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncUnbind),
      findsNothing,
    );

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncUrl),
      'https://tube.example/playlist?list=PLnew',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncMode));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncModeOption('append')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncInterval),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncIntervalOption(12)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncSave));
    await tester.pumpAndSettle();

    final call = repo.setPlaylistSourceCalls.single;
    expect(call.pid, pl.pid);
    expect(call.url, 'https://tube.example/playlist?list=PLnew');
    expect(call.mode, 'append');
    expect(call.intervalHours, 12);
    expect(find.text('Sync settings saved'), findsOneWidget);
    // The binding landed, so the running verbs appear.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncNow),
      findsOneWidget,
    );
  });

  testWidgets('mirror-trash is offered only with the delete right', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _plain),
    );
    final pl = await _manualPlaylist(repo);
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncMode));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(
        SemanticsIds.playlistSyncModeOption('mirror-trash'),
      ),
      findsNothing,
      reason: 'hidden, never disabled: the house rule for gated affordances',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncModeOption('mirror')),
      findsOneWidget,
    );
  });

  testWidgets('preview dry-runs and reports what a sync would do', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    repo.playlistSyncPreview = const PlaylistSyncPreview(
      entries: 5,
      wouldAdd: 2,
      wouldDownload: 3,
      wouldRemove: 0,
      wouldTrash: 0,
      pending: 0,
      unavailable: 1,
      missing: 0,
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSources[pl.pid] = _bound;
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncPreview),
    );
    await tester.pumpAndSettle();

    expect(repo.previewPlaylistSyncCalls.single.mode, 'mirror');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncPreviewDialog),
      findsOneWidget,
    );
    expect(find.text('2 tracks would join the list'), findsOneWidget);
    expect(find.text('3 new entries would be downloaded'), findsOneWidget);
    expect(find.text('1 entry is unavailable at the source'), findsOneWidget);
    // Nothing was stored by a dry run.
    expect(repo.setPlaylistSourceCalls, isEmpty);
  });

  testWidgets('sync now queues a run and unbind removes the binding', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSources[pl.pid] = _bound;
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncNow));
    await tester.pumpAndSettle();
    expect(repo.syncPlaylistSourceCalls, [pl.pid]);
    expect(find.text('Sync started'), findsOneWidget);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncUnbind),
    );
    await tester.pumpAndSettle();
    expect(repo.unbindPlaylistSourceCalls, [pl.pid]);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncSheet),
      findsNothing,
      reason: 'unbinding closes the sheet',
    );
  });

  testWidgets('a bound playlist wears a sync chip; an unbound one does not', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSources[pl.pid] = _bound;
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncChip),
      findsOneWidget,
    );
    expect(find.text('Synced'), findsOneWidget);

    final other = await repo.createPlaylist(name: 'Plain', kind: 'static');
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: other.pid)));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncChip),
      findsNothing,
    );
  });

  testWidgets('a never-run binding says scheduled, not synced', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSources[pl.pid] = const PlaylistSource(
      source: 'youtube',
      url: 'https://tube.example/playlist?list=PLbound',
      live: true,
      mode: 'mirror',
      intervalHours: 6,
      disabled: false,
      consecutiveFailures: 0,
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    expect(find.text('Sync scheduled'), findsOneWidget);
    expect(
      find.text('Synced'),
      findsNothing,
      reason: 'synced is a claim about a run that never happened',
    );
  });

  testWidgets('a never-run matched binding says matched, not scheduled', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    // What the import dialog's keep-matched switch stores: an export,
    // no URL, no interval - and so no schedule for anyone to wait on.
    repo.playlistSources[pl.pid] = const PlaylistSource(
      source: 'spotify',
      live: false,
      mode: 'mirror',
      refCount: 12,
      disabled: false,
      consecutiveFailures: 0,
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    expect(find.text('Matched'), findsOneWidget);
    expect(
      find.text('Sync scheduled'),
      findsNothing,
      reason: 'a matched export has no schedule to be waiting for',
    );
  });

  testWidgets('the sheet frames the failure and reads out the last run', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSources[pl.pid] = PlaylistSource(
      source: 'youtube',
      url: 'https://tube.example/playlist?list=PLbound',
      live: true,
      mode: 'mirror',
      intervalHours: 6,
      disabled: false,
      consecutiveFailures: 1,
      lastError: 'the tube is down',
      lastSyncedAt: DateTime.utc(2026, 8, 20),
      lastRun: const PlaylistSyncCounts(
        added: 3,
        removed: 1,
        trashed: 0,
        queued: 0,
        unavailable: 0,
        missing: 0,
      ),
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    expect(find.text('The last sync failed: the tube is down'), findsOneWidget);
    expect(find.text('Last sync: 3 added, 1 removed'), findsOneWidget);
  });

  testWidgets('saving an empty URL is refused, not bound', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncSave));
    await tester.pumpAndSettle();
    expect(find.text('bind a url or a source export'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncNow),
      findsNothing,
      reason: 'the refusal must not leave a bound-looking sheet',
    );
  });

  testWidgets('a failing binding says so on the chip', (tester) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSources[pl.pid] = const PlaylistSource(
      source: 'youtube',
      url: 'https://tube.example/playlist?list=PLbound',
      live: true,
      mode: 'mirror',
      intervalHours: 6,
      disabled: false,
      consecutiveFailures: 2,
      lastError: 'the tube is down',
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    expect(find.text('Sync failing'), findsOneWidget);
  });

  testWidgets('an unbound sheet offers both arms and binds an export', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);

    // The live arm is the default, so the URL field is what is drawn.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncUrl),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncArm));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncArmOption('matched')),
    );
    await tester.pumpAndSettle();

    // The matched arm swaps the URL for a source and a paste box, and
    // takes no interval.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncUrl),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncInterval),
      findsNothing,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncSource),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncSourceOption('text')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncPayload),
      'Salt Harbour - The Bree Trio',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncSave));
    await tester.pumpAndSettle();

    final call = repo.setPlaylistSourceCalls.single;
    expect(call.source, 'text');
    expect(call.payload, 'Salt Harbour - The Bree Trio');
    expect(call.url, isNull);
    expect(call.intervalHours, isNull);
  });

  testWidgets('a matched binding offers no mirror-trash and no interval', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSources[pl.pid] = const PlaylistSource(
      source: 'text',
      live: false,
      mode: 'append',
      refCount: 12,
      disabled: false,
      consecutiveFailures: 0,
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncInterval),
      findsNothing,
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncMode));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(
        SemanticsIds.playlistSyncModeOption('mirror-trash'),
      ),
      findsNothing,
      reason: 'a matched binding downloads nothing, so it trashes nothing',
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncModeOption('mirror')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncSave));
    await tester.pumpAndSettle();

    // Settings only: the export is not resent, because the sheet was
    // never handed one - and the refs survive on the server because of
    // it. No interval either: the fake refuses one on a matched
    // binding, as the endpoint does.
    final call = repo.setPlaylistSourceCalls.single;
    expect(call.mode, 'mirror');
    expect(call.source, isNull);
    expect(call.payload, isNull);
    expect(call.url, isNull);
    expect(call.intervalHours, isNull);
    expect(repo.playlistSources[pl.pid]?.refCount, 12);
  });

  testWidgets('a binding that lands under an open sheet is what Save sends', (
    tester,
  ) async {
    // The sheet opened unbound, so its arm is the choice above the
    // form; the binding arrives underneath from somewhere else (the
    // import dialog's keep-matched switch, another device). A sheet
    // that kept believing its own arm would go on sending an interval
    // and stay refused until it was closed and reopened.
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        filePickerProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(PlaylistScreen(pid: pl.pid), pushed: true),
      ),
    );
    await tester.pumpAndSettle();
    await _openSheet(tester);

    repo.playlistSources[pl.pid] = const PlaylistSource(
      source: 'text',
      live: false,
      mode: 'append',
      refCount: 4,
      disabled: false,
      consecutiveFailures: 0,
    );
    container.invalidate(playlistSyncProvider(pl.pid));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncSave));
    await tester.pumpAndSettle();

    final call = repo.setPlaylistSourceCalls.single;
    expect(call.url, isNull);
    expect(call.intervalHours, isNull, reason: 'a matched binding takes none');
    expect(find.text('Sync settings saved'), findsOneWidget);
  });

  testWidgets('clearing the URL is a refused rebind, not a settings save', (
    tester,
  ) async {
    // The trap the wire's absent-versus-empty rule closes: a blank URL
    // reads as "names no source" if the server looks at the value, so
    // the binding somebody was replacing would survive under a 200.
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSources[pl.pid] = _bound;
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncUrl),
      '',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncSave));
    await tester.pumpAndSettle();

    // Sent as a bind with a blank url, and refused as one.
    expect(repo.setPlaylistSourceCalls.single.url, '');
    expect(find.text('bind a url or a source export'), findsOneWidget);
    // The stored binding is untouched.
    expect(repo.playlistSources[pl.pid]?.url, _bound.url);
  });

  testWidgets('a failed binding read offers a retry rather than a form', (
    tester,
  ) async {
    // The provider does not retry, so a non-404 read failure is final.
    // Drawing the unbound form over it would put a Save in front of a
    // binding this sheet never saw, and settings-only is exactly the
    // body that would rewrite it.
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSourceReadError = const WaxDeckApiException(
      statusCode: 503,
      code: 'catalog-maintenance',
      message: 'the catalog is busy',
    );
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncSave),
      findsNothing,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(repo.setPlaylistSourceCalls, isEmpty);
  });

  testWidgets('a bound live sheet saves settings until the URL is edited', (
    tester,
  ) async {
    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
    );
    final pl = await _manualPlaylist(repo);
    repo.playlistSources[pl.pid] = _bound;
    await tester.pumpWidget(_host(repo, PlaylistScreen(pid: pl.pid)));
    await tester.pumpAndSettle();
    await _openSheet(tester);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncInterval),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncIntervalOption(12)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncSave));
    await tester.pumpAndSettle();

    // The URL still reads what it was seeded with, so this is a
    // settings-only save and the server is spared the probe.
    expect(repo.setPlaylistSourceCalls.single.url, isNull);
    expect(repo.setPlaylistSourceCalls.single.intervalHours, 12);

    // Typing a different URL makes the next save a rebind.
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.playlistSyncUrl),
      'https://tube.example/playlist?list=PLother',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playlistSyncSave));
    await tester.pumpAndSettle();

    expect(
      repo.setPlaylistSourceCalls.last.url,
      'https://tube.example/playlist?list=PLother',
    );
  });
}
