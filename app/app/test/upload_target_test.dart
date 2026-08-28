import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/add_to_library.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// Which library a submission is filed under, on the servers where that
/// is a question at all.
///
/// It is a narrow choice by design: the pid selects whose settings
/// govern the import, not where the bytes are placed, so the picker
/// appears only where there is more than one candidate and sends
/// nothing where there is one.

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

const _music = UploadTarget(
  pid: 'lb-music',
  name: 'Music',
  mediaTypes: [MediaType.music],
  managed: true,
);
const _bootlegs = UploadTarget(
  pid: 'lb-bootlegs',
  name: 'Bootlegs',
  mediaTypes: [MediaType.music],
  managed: false,
);
const _books = UploadTarget(
  pid: 'lb-books',
  name: 'Books',
  mediaTypes: [MediaType.audiobook],
  managed: true,
);

PickedAudioFile _file(String name) {
  final bytes = Uint8List.fromList(List<int>.filled(8, 7));
  return PickedAudioFile(
    name: name,
    size: bytes.length,
    openRead: ([int? start, int? end]) => Stream.value(
      Uint8List.sublistView(bytes, start ?? 0, end ?? bytes.length),
    ),
  );
}

class _OneFilePicker implements FilePickerPort {
  @override
  bool get canPickFolders => false;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => [_file('one.flac')];

  @override
  Future<FolderPick> pickAudioFolder({
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const FolderPick();

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    String anyLabel = '',
  }) async => null;
}

FakeRepository _repo(List<UploadTarget> targets) => FakeRepository()
  ..sessionState = const SessionState(authenticated: true, user: _user)
  ..uploadTargets.addAll(targets);

(Widget, ProviderContainer Function()) _host(
  FakeRepository repo, {
  ClientSettingsStore? settings,
}) {
  late ProviderContainer container;
  final picker = _OneFilePicker();
  final host = ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      filePickerProvider.overrideWithValue(picker),
      if (settings != null)
        clientSettingsStoreProvider.overrideWithValue(settings),
    ],
    child: routedHost(
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return Scaffold(
            body: Center(
              child: WaxButton(
                label: 'Open',
                onPressed: () => pickAndUpload(context, ref, picker),
              ),
            ),
          );
        },
      ),
    ),
  );
  return (host, () => container);
}

Future<void> _openPick(WidgetTester tester, Widget host) async {
  await tester.pumpWidget(host);
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm));
  await tester.pumpAndSettle();
}

String? _sentLibraryPid(FakeRepository repo) =>
    repo.uploadsById.values.single.libraryPid;

void main() {
  testWidgets('one candidate is not a question, and nothing is named', (
    tester,
  ) async {
    // The server routes exactly as it did before the picker existed;
    // naming the only candidate would pin a policy nobody asked for.
    final repo = _repo([_music, _books]);
    final (host, _) = _host(repo);
    await _openPick(tester, host);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadLibrary),
      findsNothing,
    );
    await _confirm(tester);
    expect(_sentLibraryPid(repo), isNull);
  });

  testWidgets('two candidates for the medium get a picker', (tester) async {
    final repo = _repo([_music, _bootlegs, _books]);
    final (host, _) = _host(repo);
    await _openPick(tester, host);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadLibrary),
      findsOneWidget,
    );
    // The first candidate, since nothing is remembered.
    await _confirm(tester);
    expect(_sentLibraryPid(repo), _music.pid);
  });

  testWidgets('choosing the second candidate sends it, and remembers it', (
    tester,
  ) async {
    final repo = _repo([_music, _bootlegs]);
    final settings = MemoryClientSettingsStore();
    final (host, _) = _host(repo, settings: settings);
    await _openPick(tester, host);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadLibrary));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.uploadLibraryOption(_bootlegs.pid),
      ),
    );
    await tester.pumpAndSettle();
    await _confirm(tester);

    expect(_sentLibraryPid(repo), _bootlegs.pid);
    expect(
      await settings.read(ClientSettingKeys.uploadTarget),
      _bootlegs.pid,
      reason: 'the next launch has to be able to read it back',
    );
  });

  testWidgets('a stored choice is honoured on the first dialog of a launch', (
    tester,
  ) async {
    // The read is the store's rather than a Notifier's default, which
    // is the whole point: a cold start is the launch this exists for,
    // and a hydrating setting answers empty on its first read.
    final settings = MemoryClientSettingsStore();
    await settings.write(ClientSettingKeys.uploadTarget, _bootlegs.pid);
    final repo = _repo([_music, _bootlegs]);
    final (host, _) = _host(repo, settings: settings);
    await _openPick(tester, host);
    await _confirm(tester);

    expect(_sentLibraryPid(repo), _bootlegs.pid);
  });

  testWidgets('a remembered choice that is gone falls back, and is not sent', (
    tester,
  ) async {
    // A pid from another server, or one whose library stopped accepting
    // this medium: the picker opens on a candidate that is actually on
    // offer rather than sending a pid the server would refuse.
    final repo = _repo([_music, _bootlegs]);
    final settings = MemoryClientSettingsStore();
    await settings.write(ClientSettingKeys.uploadTarget, 'lb-elsewhere');
    final (host, _) = _host(repo, settings: settings);
    await _openPick(tester, host);
    await _confirm(tester);

    expect(_sentLibraryPid(repo), _music.pid);
  });

  testWidgets('a server with no targets draws no picker and names nothing', (
    tester,
  ) async {
    // One too old for the route, one that refused the read, and one
    // where this account has nothing writable all read the same here.
    final repo = _repo(const [])
      ..uploadTargetsError = const WaxDeckApiException(
        code: 'transport',
        message: '404 page not found',
        statusCode: 404,
      );
    final (host, _) = _host(repo);
    await _openPick(tester, host);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadLibrary),
      findsNothing,
    );
    await _confirm(tester);
    expect(_sentLibraryPid(repo), isNull);
  });
}
