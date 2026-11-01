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

PickedAudioFile _file(String name, [String dir = '']) {
  final bytes = Uint8List.fromList(List<int>.filled(8, 7));
  return PickedAudioFile(
    name: name,
    relativeDir: dir,
    size: bytes.length,
    openRead: ([int? start, int? end]) => Stream.value(
      Uint8List.sublistView(bytes, start ?? 0, end ?? bytes.length),
    ),
  );
}

/// A picker that hands the sheet its rows, so the sheet under test is the
/// real one. With [folderFiles] it also offers a folder row.
class _Picker implements FilePickerPort {
  _Picker([this.folderFiles = const []]);

  final List<PickedAudioFile> folderFiles;

  @override
  bool get canPickFolders => folderFiles.isNotEmpty;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => [_file('one.flac')];

  @override
  Future<FolderPick> pickAudioFolder({
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => FolderPick(files: folderFiles);

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
  Future<void> Function(BuildContext, WidgetRef) open, {
  FilePickerPort? picker,
}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    filePickerProvider.overrideWithValue(picker ?? _Picker()),
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
        ], fixed: MediaType.podcast),
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
            showAddToLibrarySheet(context, ref, fixed: MediaType.podcast),
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

  testWidgets('an audiobook folder offers book grouping', (tester) async {
    await _openDialog(
      tester,
      _host(
        _repo(),
        (context, ref) => showDialog<void>(
          context: context,
          builder: (_) => const MediaTypeDialog(
            initial: MediaType.audiobook,
            fileCount: 3,
            initialIdentify: false,
          ),
        ),
      ),
    );

    expect(find.text('One book in 3 parts'), findsOneWidget);
    expect(find.text('Separate books'), findsOneWidget);
    expect(find.text('One album'), findsNothing);

    await _expectTwoMedia(tester, MediaType.music);
    expect(find.text('One album'), findsOneWidget);
    expect(find.text('One book in 3 parts'), findsNothing);
  });

  testWidgets('the books hub does not ask the kind', (tester) async {
    final repo = _repo();
    await _openDialog(
      tester,
      _host(
        repo,
        (context, ref) =>
            showAddToLibrarySheet(context, ref, fixed: MediaType.audiobook),
        picker: _Picker([_file('01.mp3', 'Book'), _file('02.mp3', 'Book')]),
      ),
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.addUploadFolder));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaType),
      findsNothing,
    );
    expect(find.text('Upload 2 files as an audiobook'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    final batch = repo.batchesById.values.single;
    expect(batch.mediaType, MediaType.audiobook);
    expect(batch.grouping, UploadGrouping.album);
  });

  testWidgets('the music hub says music and groups by auto-detection', (
    tester,
  ) async {
    final repo = _repo();
    await _openDialog(
      tester,
      _host(
        repo,
        (context, ref) =>
            showAddToLibrarySheet(context, ref, fixed: MediaType.music),
        picker: _Picker([_file('01.flac', 'Album'), _file('02.flac', 'Album')]),
      ),
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.addUploadFolder));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaType),
      findsNothing,
    );
    expect(find.text('Upload 2 files as music'), findsOneWidget);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    final batch = repo.batchesById.values.single;
    expect(batch.mediaType, MediaType.music);
    expect(batch.grouping, UploadGrouping.auto);
  });

  testWidgets('home detects an m4b folder', (tester) async {
    final repo = _repo();
    await _openDialog(
      tester,
      _host(
        repo,
        (context, ref) => showAddToLibrarySheet(context, ref),
        picker: _Picker([
          _file('book.m4b', 'Book'),
          _file('notes.mp3', 'Book'),
        ]),
      ),
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.addUploadFolder));
    await tester.pumpAndSettle();

    expect(find.text('What are these 2 files?'), findsOneWidget);
    expect(find.text('Audiobook'), findsOneWidget);
    expect(find.text('Music'), findsNothing);
    expect(find.text('One book in 2 parts'), findsOneWidget);

    // The grouping follows the kind until it has been touched.
    await _expectTwoMedia(tester, MediaType.music);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    final batch = repo.batchesById.values.single;
    expect(batch.mediaType, MediaType.music);
    expect(batch.grouping, UploadGrouping.auto);
  });

  testWidgets('a grouping the person picked survives a kind change', (
    tester,
  ) async {
    final repo = _repo();
    await _openDialog(
      tester,
      _host(
        repo,
        (context, ref) => showAddToLibrarySheet(context, ref),
        picker: _Picker([
          _file('book.m4b', 'Book'),
          _file('notes.mp3', 'Book'),
        ]),
      ),
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.addUploadFolder));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadGroupingOption('tracks')),
    );
    await tester.pumpAndSettle();
    await _expectTwoMedia(tester, MediaType.music);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.batchesById.values.single.grouping, UploadGrouping.tracks);
  });

  testWidgets('the books hub does not ask the kind of a link either', (
    tester,
  ) async {
    final repo = _repo();
    await _openDialog(
      tester,
      _host(
        repo,
        (context, ref) =>
            showAddToLibrarySheet(context, ref, fixed: MediaType.audiobook),
      ),
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.addFromUrl));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.acquireUrl), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaType),
      findsNothing,
    );
    expect(find.text('Add an audiobook from URL'), findsOneWidget);
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.acquireUrl),
      'https://tube.example/watch?v=one',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls.single.mediaType, MediaType.audiobook);
  });

  testWidgets('one file from a section says its kind in the title', (
    tester,
  ) async {
    for (final (kind, title) in [
      (MediaType.audiobook, 'Upload as an audiobook'),
      (MediaType.music, 'Upload as music'),
    ]) {
      await _openDialog(
        tester,
        _host(
          _repo(),
          (context, ref) => showAddToLibrarySheet(context, ref, fixed: kind),
        ),
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.addUploadFile));
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget, reason: '$kind');
      expect(
        find.bySemanticsIdentifier(SemanticsIds.uploadMediaType),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
