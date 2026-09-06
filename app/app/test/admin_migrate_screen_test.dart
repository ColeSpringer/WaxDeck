import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/migrate_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxSwitch;

import 'fakes.dart';
import 'routed_host.dart';

/// A picker resolving pickFile to one fixed archive, standing in for
/// the platform dialog.
class _ZipPicker implements FilePickerPort {
  @override
  bool get canPickFolders => false;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const [];

  @override
  Future<FolderPick> pickAudioFolder({
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const FolderPick();

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    String anyLabel = '',
  }) async => PickedAudioFile(
    name: 'my_spotify_data.zip',
    size: 4096,
    openRead: ([int? start, int? end]) =>
        Stream<List<int>>.value(const [1, 2, 3]),
  );
}

/// A viewport tall enough for the whole form, so no test scrolls.
Future<void> _pump(
  WidgetTester tester,
  FakeRepository repo, [
  ProviderContainer? container,
]) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final scope =
      container ??
      ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          filePickerProvider.overrideWithValue(_ZipPicker()),
        ],
      );
  addTearDown(scope.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: routedHost(const MigrateScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  _credentialsDoNotFollowTheSource();

  testWidgets('submits a navidrome import and points at the task list', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    await _pump(tester, repo, container);

    await tester.enterText(
      find.byKey(const Key('migrate-server-url')),
      'https://navi.example',
    );
    await tester.enterText(
      find.byKey(const Key('migrate-username')),
      'barliman',
    );
    await tester.enterText(
      find.byKey(const Key('migrate-password')),
      'butterbur',
    );
    // One frame for the form to catch up: the text arrives over the
    // platform channel during the pump enterText does, so the rebuild
    // that enables Start import lands on the frame after it.
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('migrate-dry-run')),
        matching: find.byType(WaxSwitch),
      ),
    );
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    final call = repo.createMigrationCalls.single;
    expect(call.source, 'navidrome');
    expect(call.serverUrl, 'https://navi.example');
    expect(call.username, 'barliman');
    expect(call.password, 'butterbur');
    expect(call.token, isNull);
    expect(call.dryRun, isTrue);
    // The message rides the shell's own channel now, like every other
    // admin screen's, so it is asserted where it is raised rather than
    // in a snackbar this screen would have to host itself.
    final raised = container.read(shellMessengerProvider);
    expect(shellMessageText(raised), 'Import started');
    // And it carries the way to watch the import, which is the whole
    // point of saying it started.
    expect(raised?.actionLabel, 'Tasks');
    expect(raised?.onAction, isNotNull);
  });

  testWidgets('the import lands on the account it names', (tester) async {
    final repo = FakeRepository();
    repo.usersById['us-HOUSEMATE'] = UserAccount(
      id: 'us-HOUSEMATE',
      username: 'housemate',
      createdAt: DateTime.utc(2026),
      libraryAccess: const LibraryAccess(mode: 'all'),
    );
    // The one nobody can import onto: a signup nobody approved holds no
    // play state to write.
    repo.usersById['us-PENDING'] = UserAccount(
      id: 'us-PENDING',
      username: 'newcomer',
      createdAt: DateTime.utc(2026),
      libraryAccess: const LibraryAccess(mode: 'all'),
      pending: true,
    );
    await _pump(tester, repo);

    // Defaults to the signed-in administrator, which is what the form
    // did before there was a choice at all.
    expect(find.text('You'), findsOneWidget);
    expect(find.text('newcomer'), findsNothing);

    await tester.tap(find.byKey(const Key('migrate-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('housemate').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('migrate-server-url')),
      'https://navi.example',
    );
    await tester.enterText(find.byKey(const Key('migrate-username')), 'bar');
    await tester.enterText(find.byKey(const Key('migrate-password')), 'but');
    await tester.pump();
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    expect(repo.createMigrationCalls.single.accountId, 'us-HOUSEMATE');
  });

  testWidgets('a history source asks for an account name and nothing else', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('migrate-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last.fm').last);
    await tester.pumpAndSettle();

    // Read with the server's own credentials off a public history:
    // there is no address to point at and no password to give.
    expect(find.byKey(const Key('migrate-server-url')), findsNothing);
    expect(find.byKey(const Key('migrate-password')), findsNothing);
    expect(find.byKey(const Key('migrate-token')), findsNothing);
    expect(find.byKey(const Key('migrate-username')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('migrate-username')),
      'listener',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    final call = repo.createMigrationCalls.single;
    expect(call.source, 'lastfm');
    expect(call.username, 'listener');
    expect(call.serverUrl, isNull);
  });

  testWidgets('a data export is uploaded before the import names it', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('migrate-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spotify data export').last);
    await tester.pumpAndSettle();

    // Nothing to type at all: the archive is the whole of the request.
    expect(find.byKey(const Key('migrate-server-url')), findsNothing);
    expect(find.byKey(const Key('migrate-username')), findsNothing);
    expect(find.byKey(const Key('migrate-export-pick')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('migrate-submit')))
          .onPressed,
      isNull,
      reason: 'nothing has been uploaded yet',
    );

    await tester.tap(find.byKey(const Key('migrate-export-pick')));
    await tester.pumpAndSettle();
    expect(repo.stagedExports, hasLength(1));
    expect(find.byKey(const Key('migrate-export-status')), findsOneWidget);

    // Picking again replaces it, and the one it replaced is handed back
    // rather than left on the server for the sweep.
    await tester.tap(find.byKey(const Key('migrate-export-pick')));
    await tester.pumpAndSettle();
    expect(repo.stagedExports, hasLength(2));
    expect(repo.discardedExports, [repo.stagedExports.first.pid]);

    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    final call = repo.createMigrationCalls.single;
    expect(call.source, 'spotify');
    expect(call.exportId, repo.stagedExports.last.pid);

    // The run read the archive and the server deleted it, so the form
    // no longer names an upload that is gone.
    expect(find.byKey(const Key('migrate-export-status')), findsNothing);
  });

  testWidgets('an upload does not follow the form to another source', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('migrate-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spotify data export').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('migrate-export-pick')));
    await tester.pumpAndSettle();
    expect(repo.stagedExports, hasLength(1));

    // Back to a server source. The upload is still staged, but it is
    // not part of this order: sending it would have the server refuse
    // every submit with a sentence about an export nobody asked for.
    await tester.tap(find.byKey(const Key('migrate-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Navidrome').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('migrate-server-url')),
      'https://navi.example',
    );
    await tester.enterText(find.byKey(const Key('migrate-username')), 'bar');
    await tester.enterText(find.byKey(const Key('migrate-password')), 'but');
    await tester.pump();
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    expect(repo.createMigrationCalls.single.exportId, isNull);
  });

  testWidgets('a credential typed for one source does not enable another', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.enterText(
      find.byKey(const Key('migrate-server-url')),
      'https://navi.example',
    );
    await tester.enterText(find.byKey(const Key('migrate-username')), 'bar');
    await tester.enterText(find.byKey(const Key('migrate-password')), 'but');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('migrate-submit')))
          .onPressed,
      isNotNull,
    );

    // Audiobookshelf draws a token field and no password. The password
    // is still in its controller, and reading it here would enable a
    // Start the server answers "needs an API token".
    await tester.tap(find.byKey(const Key('migrate-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audiobookshelf').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('migrate-submit')))
          .onPressed,
      isNull,
      reason: 'the token this source asks for has not been given',
    );

    await tester.enterText(find.byKey(const Key('migrate-token')), 'abs-token');
    await tester.pump();
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();
    expect(repo.createMigrationCalls.single.token, 'abs-token');
  });

  testWidgets('audiobookshelf swaps credentials for a token field', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('migrate-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audiobookshelf').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('migrate-token')), findsOneWidget);
    expect(find.byKey(const Key('migrate-username')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('migrate-server-url')),
      'https://abs.example',
    );
    await tester.enterText(find.byKey(const Key('migrate-token')), 'abs-token');
    await tester.pump();
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    final call = repo.createMigrationCalls.single;
    expect(call.source, 'audiobookshelf');
    expect(call.token, 'abs-token');
    expect(call.username, isNull);
  });
}

// Jellyfin takes either a login or an API key, and which one arrived is
// what the server records at the order. A password left in its
// controller from another source is sent beside a fresh key, and the
// server takes the password: a login against a host that never had that
// account, refused permanently, with the key never tried.
void _credentialsDoNotFollowTheSource() {
  testWidgets('credentials do not follow the form to another source', (
    tester,
  ) async {
    final repo = FakeRepository();
    await _pump(tester, repo);

    await tester.enterText(
      find.byKey(const Key('migrate-server-url')),
      'https://navi.example',
    );
    await tester.enterText(find.byKey(const Key('migrate-username')), 'bar');
    await tester.enterText(find.byKey(const Key('migrate-password')), 'but');
    await tester.pump();

    await tester.tap(find.byKey(const Key('migrate-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jellyfin').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('migrate-token')), 'jf-key');
    await tester.pump();
    await tester.tap(find.byKey(const Key('migrate-submit')));
    await tester.pumpAndSettle();

    final sent = repo.createMigrationCalls.single;
    expect(sent.token, 'jf-key');
    expect(
      sent.password ?? '',
      isEmpty,
      reason: 'the password was typed for another server',
    );
  });
}
