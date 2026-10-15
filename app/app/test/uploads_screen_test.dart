import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/shell/async_box_face.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck/src/uploads/uploads_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';
import 'row_nodes.dart';

/// A picker resolving to fixed reader-backed files, mirroring the web
/// port's lazy-reference shape.
class _FakePicker implements FilePickerPort {
  _FakePicker(this.files);

  final List<PickedAudioFile> files;

  @override
  bool get canPickFolders => false;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => files;

  @override
  Future<FolderPick> pickAudioFolder({
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const FolderPick();

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    String anyLabel = '',
  }) async => files.isEmpty ? null : files.first;
}

/// A lazy in-memory source with the port's windowed-read contract.
PickedAudioFile readerFile(String name, Uint8List bytes, {String dir = ''}) =>
    PickedAudioFile(
      name: name,
      size: bytes.length,
      relativeDir: dir,
      openRead: ([int? start, int? end]) => Stream.value(
        Uint8List.sublistView(bytes, start ?? 0, end ?? bytes.length),
      ),
    );

Widget _host(FakeRepository repo, {FilePickerPort? picker}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    filePickerProvider.overrideWithValue(picker),
  ],
  child: routedHost(const UploadsScreen()),
);

/// The server refusing a session its allowance cannot take.
const _quotaRefusal = WaxDeckApiException(
  code: 'quota-exceeded',
  message:
      'uploads waiting for review may total 1024 bytes, 0 in use; this one '
      'needs 2048 more',
  statusCode: 413,
);

/// The last message the shell was asked to show.
String? _message(WidgetTester tester) => shellMessageText(
  ProviderScope.containerOf(
    tester.element(find.byType(UploadsScreen)),
  ).read(shellMessengerProvider),
);

void main() {
  testWidgets('a refresh redraws the sessions it already has', (tester) async {
    // The box-shaped sibling of the sliver face, and for the same
    // reason: a reload carries the value it had, and a switch on the
    // state's runtime type blanks the screen the reader was reading.
    final repo = FakeRepository();
    repo.uploadsById['up-1'] = testUpload('up-1', fileName: 'one.flac');
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.byType(AsyncBoxFace<UploadsState>), findsOneWidget);
    expect(find.text('one.flac'), findsWidgets);

    final gate = Completer<void>();
    repo.listUploadsGate = gate;
    ProviderScope.containerOf(
      tester.element(find.byType(AsyncBoxFace<UploadsState>)),
    ).invalidate(uploadsProvider);
    await tester.pump();
    await tester.pump();

    expect(find.text('one.flac'), findsWidgets);
    expect(
      find.byType(SkeletonShapes),
      findsNothing,
      reason: 'a reload must not blank the sessions it already holds',
    );
    gate.complete();
    repo.listUploadsGate = null;
    await tester.pumpAndSettle();
  });

  testWidgets('renders session states and the duplicate warning', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.uploadsById['up-1'] = testUpload(
      'up-1',
      receivedBytes: 1048576,
      sizeBytes: 4194304,
    );
    repo.uploadsById['up-2'] = testUpload(
      'up-2',
      fileName: 'meridian-2.flac',
      state: 'staged',
      reviewEntryId: 'rv-9',
      duplicate: const DuplicateWarning(
        itemPid: 'tr-9',
        kind: 'content',
        title: 'Neon Meridian',
        artist: 'The Cardinal Waves',
      ),
    );
    repo.uploadsById['up-3'] = testUpload(
      'up-3',
      fileName: 'meridian-3.flac',
      state: 'imported',
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final receivingRow = find.bySemanticsIdentifier(
      SemanticsIds.uploadRow('up-1'),
    );
    expect(receivingRow, findsOneWidget);
    expect(
      find.descendant(
        of: receivingRow,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: receivingRow,
        matching: find.text('25% of 4.0 MB received'),
      ),
      findsOneWidget,
    );
    expect(find.text('staged'), findsOneWidget);
    expect(find.text('imported'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadDuplicate('up-2')),
      findsOneWidget,
    );
    expect(
      find.text('Duplicate (exact copy): Neon Meridian by The Cardinal Waves'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadReview('up-2')),
      findsOneWidget,
    );
  });

  testWidgets('an imported duplicate says the library kept what it had', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.uploadsById['up-1'] = testUpload(
      'up-1',
      fileName: 'meridian.flac',
      state: 'imported',
      duplicate: const DuplicateWarning(
        itemPid: 'tr-9',
        kind: 'content',
        title: 'Neon Meridian',
        artist: 'The Cardinal Waves',
      ),
    );
    repo.uploadsById['up-2'] = testUpload(
      'up-2',
      fileName: 'elsewhere.flac',
      state: 'staged',
      duplicate: const DuplicateWarning(kind: 'id'),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.uploadDuplicate('up-1')),
        matching: find.text(
          'Already in the library: Neon Meridian by The Cardinal Waves. '
          'Its details stay as they were.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.uploadDuplicate('up-2')),
        matching: find.text(
          'Duplicate (same identifier): an item in a library you cannot open',
        ),
      ),
      findsOneWidget,
      reason: 'a holder the uploader cannot see is not named',
    );
  });

  testWidgets('groups batch members under one header even interleaved', (
    tester,
  ) async {
    final repo = FakeRepository();
    // A solo session lands between the batch's members (a concurrent
    // upload from another tab interleaves creation order); the batch
    // still buckets under a single header.
    repo.uploadsById['up-b'] = testUpload(
      'up-b',
      fileName: 'one.flac',
      batchId: 'ub-1',
      state: 'staged',
    );
    repo.uploadsById['up-a'] = testUpload(
      'up-a',
      fileName: 'solo.flac',
      state: 'staged',
    );
    repo.uploadsById['up-c'] = testUpload(
      'up-c',
      fileName: 'two.flac',
      batchId: 'ub-1',
      state: 'staged',
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadBatch('ub-1')),
      findsOneWidget,
    );
    expect(find.text('Uploaded together, 2 files'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRow('up-a')),
      findsOneWidget,
    );
  });

  testWidgets('a batch that lands above another leaves it its rows', (
    tester,
  ) async {
    UploadSession staged(String id, String batchId) =>
        testUpload(id, fileName: '$id.flac', batchId: batchId, state: 'staged');
    final repo = FakeRepository();
    repo.uploadsById
      ..['up-1'] = staged('up-1', 'ub-1')
      ..['up-2'] = staged('up-2', 'ub-1');
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Both headers read "2 files" and every discard button the same, so
    // nothing but the identifier tells the rows apart.
    await expectRowsKeepTheirNodes(
      tester,
      [
        SemanticsIds.uploadBatch('ub-1'),
        SemanticsIds.uploadRow('up-1'),
        SemanticsIds.uploadDelete('up-1'),
      ],
      () async {
        final older = repo.uploadsById.values.toList();
        repo.uploadsById
          ..clear()
          ..['up-3'] = staged('up-3', 'ub-2')
          ..['up-4'] = staged('up-4', 'ub-2')
          ..addAll({for (final upload in older) upload.id: upload});
        ProviderScope.containerOf(
          tester.element(find.byType(AsyncBoxFace<UploadsState>)),
        ).invalidate(uploadsProvider);
        await tester.pumpAndSettle();
      },
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadDelete('up-3')),
      findsOneWidget,
    );
  });

  testWidgets('shows the quota header with usage against the cap', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.uploadPageQuota = const UploadQuota(
      bytesInUse: 512 * 1024,
      quotaBytes: 1024 * 1024,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadQuota),
      findsOneWidget,
    );
    expect(find.text('512 KB of 1.0 MB'), findsOneWidget);
  });

  testWidgets('hides upload affordances without upload rights', (tester) async {
    final repo = FakeRepository();
    final picker = _FakePicker([readerFile('cut.flac', Uint8List(10))]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.uploadPick), findsNothing);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadFromUrl),
      findsNothing,
    );
    expect(find.text('No uploads yet'), findsOneWidget);
  });

  testWidgets('hides the pick button while no picker port is wired', (
    tester,
  ) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier(SemanticsIds.uploadPick), findsNothing);
    // URL acquisition needs no picker, only rights.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadFromUrl),
      findsOneWidget,
    );
  });

  testWidgets('add from URL queues an acquisition', (tester) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadFromUrl));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier(SemanticsIds.acquireUrl), findsOneWidget);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.acquireUrl),
      'https://tube.example/watch?v=neon-meridian',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls, hasLength(1));
    expect(
      repo.acquisitionCalls.single.url,
      'https://tube.example/watch?v=neon-meridian',
    );
    expect(repo.acquisitionCalls.single.mediaType, MediaType.music);
    expect(repo.acquisitionCalls.single.format, 'best');
    expect(find.bySemanticsIdentifier(SemanticsIds.acquireUrl), findsNothing);
  });

  testWidgets('a link that is not http is caught before it is sent', (
    tester,
  ) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadFromUrl));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.acquireUrl),
      'tube.example/watch?v=neon-meridian',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls, isEmpty);
    expect(
      find.text('Enter a link starting with http:// or https://'),
      findsOneWidget,
    );
  });

  testWidgets('acquiring can pick a download format', (tester) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadFromUrl));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.acquireUrl),
      'https://tube.example/watch?v=neon-meridian',
    );
    await tester.pumpAndSettle();

    // Open the format dropdown and choose MP3.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireFormat));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MP3').last);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls.single.format, 'mp3');
  });

  testWidgets('picking one file windows it up without a batch', (tester) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    // 2.5 MiB: two full 1 MiB windows plus a remainder.
    final picker = _FakePicker([
      readerFile('fresh-cut.flac', Uint8List(2621440)),
    ]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    // A single file asks no grouping question.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadGrouping),
      findsNothing,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.putUploadDataCalls, hasLength(3));
    expect(repo.putUploadDataCalls[0].offset, 0);
    expect(repo.putUploadDataCalls[1].offset, 1048576);
    expect(repo.putUploadDataCalls[2].offset, 2097152);
    expect(repo.putUploadDataCalls[2].byteCount, 524288);
    final session = repo.uploadsById.values.single;
    expect(session.state, 'staged');
    expect(session.mediaType, MediaType.music);
    expect(repo.batchesById, isEmpty);
    expect(find.text('staged'), findsOneWidget);
  });

  testWidgets('several files ask the grouping and flow through a batch', (
    tester,
  ) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    final picker = _FakePicker([
      readerFile('a1.flac', Uint8List(64), dir: 'Long Form'),
      readerFile('a2.flac', Uint8List(64), dir: 'Long Form'),
    ]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadGrouping),
      findsOneWidget,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadGroupingOption('album')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.batchesById, hasLength(1));
    final batch = repo.batchesById.values.single;
    expect(batch.grouping, UploadGrouping.album);
    expect(repo.batchJoins, hasLength(2));
    expect(repo.batchJoins[0].batchPath, 'Long Form');
    expect(repo.completedBatchIds, [batch.id]);
  });

  testWidgets('a picked Audible file is refused before the media-type '
      'question', (tester) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    final picker = _FakePicker([readerFile('book.aax', Uint8List(32))]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
      findsNothing,
    );
    expect(
      _message(tester),
      "Skipped 1 Audible file; DRM audio can't be played",
    );
    expect(repo.uploadsById, isEmpty);
  });

  testWidgets('quota-exceeded says import or discard, not storage full', (
    tester,
  ) async {
    final repo = FakeRepository(sessionState: testUploaderSession())
      // The file fits the allowance; what is staged already does not
      // leave room for it.
      ..uploadPageQuota = const UploadQuota(bytesInUse: 1000, quotaBytes: 1024)
      ..createUploadRefusal = _quotaRefusal;
    final picker = _FakePicker([readerFile('big.flac', Uint8List(32))]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      _message(tester),
      'big.flac: You already have as much waiting as your limit allows. '
      'Import or discard some in Past uploads, then try again.',
    );
  });

  testWidgets('a file larger than the whole allowance says no clearing '
      'makes room', (tester) async {
    final repo = FakeRepository(sessionState: testUploaderSession())
      ..uploadPageQuota = const UploadQuota(bytesInUse: 0, quotaBytes: 1024)
      ..createUploadRefusal = _quotaRefusal;
    final picker = _FakePicker([readerFile('big.flac', Uint8List(2048))]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      _message(tester),
      'big.flac: Larger than your whole upload limit of 1 KB, so clearing '
      'Past uploads cannot make room. An administrator can raise the limit.',
    );
  });

  testWidgets('quota-exceeded against an allowance not known says only '
      'that', (tester) async {
    // Without the limit nothing tells a full allowance from a file no
    // allowance admits, and the table's sentence is true of both.
    final repo = FakeRepository(sessionState: testUploaderSession())
      ..createUploadRefusal = _quotaRefusal;
    final picker = _FakePicker([readerFile('big.flac', Uint8List(32))]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(
      _message(tester),
      'big.flac: That is over a limit this server keeps.',
    );
  });

  testWidgets('a zero-byte file is named, not sent', (tester) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    final picker = _FakePicker([
      readerFile('silence.flac', Uint8List(0)),
      readerFile('sound.flac', Uint8List(32)),
    ]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    // One file goes, so no grouping question and no batch.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadGrouping),
      findsNothing,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.uploadsById.values.map((u) => u.fileName), ['sound.flac']);
    expect(repo.batchesById, isEmpty);

    // Nothing but an empty file asks nothing at all.
    picker.files
      ..clear()
      ..add(readerFile('silence.flac', Uint8List(0)));
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
      findsNothing,
    );
    expect(_message(tester), 'silence.flac: The file is empty');
    expect(repo.uploadsById, hasLength(1));
  });

  testWidgets('a failing file does not stop the batch or its finalize', (
    tester,
  ) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    repo.onCreateUpload = (fileName) {
      repo.uploadError = fileName == 'broken.flac'
          ? const WaxDeckApiException(
              code: 'unsupported-format',
              message: '.flac files are not accepted',
              statusCode: 415,
            )
          : null;
    };
    final picker = _FakePicker([
      readerFile('ok-one.flac', Uint8List(32)),
      readerFile('broken.flac', Uint8List(32)),
      readerFile('ok-two.flac', Uint8List(32)),
    ]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    // Both good files joined and the finalize ran exactly once.
    expect(repo.batchJoins, hasLength(2));
    expect(repo.completedBatchIds, hasLength(1));
  });
}
