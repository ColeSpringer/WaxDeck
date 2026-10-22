import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/add_to_library.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

// What the add flows offer as a medium. A podcast is a feed's show, so
// neither the file dialog nor the link dialog lists it, and a caller that
// asks for one gets music.

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

/// A picker that hands the sheet its three rows, so the sheet under test
/// is the real one.
class _Picker implements FilePickerPort {
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

FakeRepository _repo() =>
    FakeRepository()
      ..sessionState = const SessionState(authenticated: true, user: _user);

/// A host that opens one of the add flows from a button.
Widget _host(
  FakeRepository repo,
  Future<void> Function(BuildContext, WidgetRef) open,
) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    filePickerProvider.overrideWithValue(_Picker()),
  ],
  child: routedHost(
    Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Center(
          child: WaxButton(label: 'Open', onPressed: () => open(context, ref)),
        ),
      ),
    ),
  ),
);

Finder _option(MediaType type) => find.bySemanticsIdentifier(
  SemanticsIds.uploadMediaTypeOption(type.wireName),
);

/// Opens the medium choice and checks what it lists, then closes it by
/// choosing [choose].
Future<void> _expectTwoMedia(WidgetTester tester, MediaType choose) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadMediaType));
  await tester.pumpAndSettle();
  expect(_option(MediaType.music), findsOneWidget);
  expect(_option(MediaType.audiobook), findsOneWidget);
  expect(_option(MediaType.podcast), findsNothing);
  expect(find.text('Podcast'), findsNothing);
  await tester.tap(_option(choose));
  await tester.pumpAndSettle();
}

Future<void> _openDialog(WidgetTester tester, Widget host) async {
  await tester.pumpWidget(host);
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'the selector words the media it offers and survives one it does not',
    () {
      final l10n = AppLocalizationsEn();
      expect(MediaTypeSelector.label(l10n, MediaType.music), 'Music');
      expect(MediaTypeSelector.label(l10n, MediaType.audiobook), 'Audiobook');
      expect(MediaTypeSelector.label(l10n, MediaType.podcast), 'podcast');
    },
  );

  test('a selector is not built on a medium it does not offer', () {
    expect(
      () => MediaTypeSelector(value: MediaType.podcast, onChanged: (_) {}),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => MediaTypeSelector(value: MediaType.audiobook, onChanged: (_) {}),
      returnsNormally,
    );
  });

  testWidgets('the file dialog offers music and audiobook, not podcast', (
    tester,
  ) async {
    final repo = _repo();
    await _openDialog(
      tester,
      _host(
        repo,
        (context, ref) =>
            uploadPickedFiles(context, ref, <PickedAudioFile>[_file('a.m4b')]),
      ),
    );

    await _expectTwoMedia(tester, MediaType.audiobook);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.uploadsById.values.single.mediaType, MediaType.audiobook);
  });

  testWidgets('the link dialog offers the same two, and always a format', (
    tester,
  ) async {
    final repo = _repo();
    await _openDialog(
      tester,
      _host(repo, (context, ref) => acquireFromUrl(context, ref)),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.acquireFormat),
      findsOneWidget,
    );
    await _expectTwoMedia(tester, MediaType.audiobook);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.acquireFormat),
      findsOneWidget,
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.acquireUrl),
      'https://tube.example/watch?v=one',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls.single.mediaType, MediaType.audiobook);
  });

  testWidgets('a podcast default opens the file dialog on music', (
    tester,
  ) async {
    final repo = _repo();
    await _openDialog(
      tester,
      _host(
        repo,
        (context, ref) => uploadPickedFiles(context, ref, <PickedAudioFile>[
          _file('a.flac'),
        ], initial: MediaType.podcast),
      ),
    );

    expect(find.text('Music'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.uploadsById.values.single.mediaType, MediaType.music);
  });

  testWidgets('a podcast section opens the add sheet\'s link dialog on music', (
    tester,
  ) async {
    final repo = _repo();
    await _openDialog(
      tester,
      _host(
        repo,
        (context, ref) =>
            showAddToLibrarySheet(context, ref, initial: MediaType.podcast),
      ),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.addFromUrl));
    await tester.pumpAndSettle();
    expect(find.text('Music'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.acquireFormat),
      findsOneWidget,
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.acquireUrl),
      'https://tube.example/watch?v=one',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls.single.mediaType, MediaType.music);
  });
}
