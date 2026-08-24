import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/uploads/add_to_library.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// The folder flow's honesty: what its filter dropped is said rather
/// than silent, and an identify-on upload says where the files went.

final _l10n = AppLocalizationsEn();

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

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

class _FolderPicker implements FilePickerPort {
  _FolderPicker(this.pick);

  final FolderPick pick;

  @override
  bool get canPickFolders => true;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
  }) async => const [];

  @override
  Future<FolderPick> pickAudioFolder() async => pick;

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    String anyLabel = '',
  }) async => null;
}

(Widget, ProviderContainer Function()) _host(
  FakeRepository repo,
  FilePickerPort picker,
  Future<void> Function(BuildContext, WidgetRef, FilePickerPort) open,
) {
  late ProviderContainer container;
  final host = ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      filePickerProvider.overrideWithValue(picker),
    ],
    child: routedHost(
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return Scaffold(
            body: Center(
              child: WaxButton(
                label: 'Open',
                onPressed: () => open(context, ref, picker),
              ),
            ),
          );
        },
      ),
    ),
  );
  return (host, () => container);
}

FakeRepository _repo() =>
    FakeRepository()
      ..sessionState = const SessionState(authenticated: true, user: _user);

void main() {
  testWidgets('a folder of Audible files says why nothing uploads', (
    tester,
  ) async {
    final (host, containerOf) = _host(
      _repo(),
      _FolderPicker(const FolderPick(skippedDrm: 3, skippedUnsupported: 0)),
      pickFolderAndUpload,
    );
    await tester.pumpWidget(host);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final message = containerOf().read(shellMessengerProvider);
    expect(message?.resolve(_l10n), contains('Audible'));
    expect(message?.resolve(_l10n), contains('DRM'));
    // Nothing survived the filter, so the media-type question never
    // opens over an upload of nothing.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaType),
      findsNothing,
    );
  });

  testWidgets('a folder of only non-audio explains the empty pick', (
    tester,
  ) async {
    final (host, containerOf) = _host(
      _repo(),
      _FolderPicker(const FolderPick(skippedUnsupported: 3)),
      pickFolderAndUpload,
    );
    await tester.pumpWidget(host);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      containerOf().read(shellMessengerProvider)?.resolve(_l10n),
      'Skipped 3 unsupported files',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaType),
      findsNothing,
    );
  });

  testWidgets('expected album cruft is shed without commentary', (
    tester,
  ) async {
    // The cover image and the rip log are left behind by design;
    // announcing them on every folder would teach people to ignore the
    // report that matters.
    final (host, containerOf) = _host(
      _repo(),
      _FolderPicker(
        FolderPick(files: [_file('a.flac')], skippedUnsupported: 2),
      ),
      pickFolderAndUpload,
    );
    await tester.pumpWidget(host);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.uploadMediaType), findsOne);
    final raised = <String>[];
    containerOf().listen(shellMessengerProvider, (_, next) {
      if (next != null) raised.add(next.resolve(_l10n));
    });
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();
    expect(raised, hasLength(1));
    expect(raised.single, contains('Uploaded 1 file'));
  });

  testWidgets('DRM files are named even when audio uploads beside them', (
    tester,
  ) async {
    final (host, containerOf) = _host(
      _repo(),
      _FolderPicker(
        FolderPick(
          files: [_file('a.flac')],
          skippedUnsupported: 1,
          skippedDrm: 2,
        ),
      ),
      pickFolderAndUpload,
    );
    await tester.pumpWidget(host);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // The report holds until the dialog is gone: a toast raised under
    // a modal is hidden from the semantics tree and can expire there.
    expect(containerOf().read(shellMessengerProvider), isNull);

    final raised = <String>[];
    containerOf().listen(shellMessengerProvider, (_, next) {
      if (next != null) raised.add(next.resolve(_l10n));
    });
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();
    // Identify first (the messenger queues in order), the DRM report
    // after it; the cover image's skip says nothing.
    expect(raised, hasLength(2));
    expect(raised.first, contains('Uploaded 1 file'));
    expect(raised.last, contains('Skipped 2 Audible files'));
  });

  testWidgets('an identify-on upload says the files are in review', (
    tester,
  ) async {
    final repo = _repo();
    final (host, containerOf) = _host(
      repo,
      _FolderPicker(FolderPick(files: [_file('a.flac'), _file('b.flac')])),
      pickFolderAndUpload,
    );
    await tester.pumpWidget(host);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Identification defaults on; confirming the dialog runs the batch.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    final message = containerOf().read(shellMessengerProvider);
    expect(message?.resolve(_l10n), contains('Uploaded 2 files'));
    expect(message?.resolve(_l10n), contains('review'));
    expect(message?.actionLabel, 'Open review');
    expect(message?.actionSemanticsId, SemanticsIds.uploadIdentifyingReview);
  });

  testWidgets('an identify-off upload raises no review message', (
    tester,
  ) async {
    final repo = _repo()..prefs = const Prefs(identifyOptOut: true);
    final (host, containerOf) = _host(
      repo,
      _FolderPicker(FolderPick(files: [_file('a.flac')])),
      pickFolderAndUpload,
    );
    await tester.pumpWidget(host);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    // Identify was off by account default: the import is synchronous
    // and the shelves move on their own, so a "waiting in review"
    // message would be a lie.
    expect(containerOf().read(shellMessengerProvider), isNull);
  });
}
