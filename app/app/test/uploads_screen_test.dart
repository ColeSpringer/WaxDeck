import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/upload_phase.dart';
import 'package:waxdeck/src/shell/async_box_face.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck/src/uploads/uploads_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'direction_glyph.dart';
import 'fakes.dart';
import 'routed_host.dart';
import 'row_nodes.dart';
import 'wax_finders.dart';

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

/// Lists every session still receiving as the server saw it before its
/// first chunk.
class _StaleList extends FakeRepository {
  _StaleList() : super(sessionState: testUploaderSession());

  @override
  Future<UploadPage> listUploads({String? cursor, int? limit}) async {
    final page = await super.listUploads(cursor: cursor, limit: limit);
    return UploadPage(
      uploads: [
        for (final u in page.uploads)
          u.state == 'receiving'
              ? testUpload(
                  u.id,
                  fileName: u.fileName,
                  sizeBytes: u.sizeBytes,
                  receivedBytes: 0,
                )
              : u,
      ],
      nextCursor: page.nextCursor,
      quota: page.quota,
    );
  }
}

/// Opens the session on the server, then holds the create's answer until
/// [release] opens: the server's event for it can refresh the list first.
class _ListedBeforeCreated extends FakeRepository {
  _ListedBeforeCreated() : super(sessionState: testUploaderSession());

  final reached = Completer<void>();
  final release = Completer<void>();

  @override
  Future<UploadSession> createUpload({
    required String fileName,
    required int sizeBytes,
    required String mediaType,
    String? libraryPid,
    String? sha256,
    String? batchId,
    String? batchPath,
    bool? identify,
  }) async {
    final session = await super.createUpload(
      fileName: fileName,
      sizeBytes: sizeBytes,
      mediaType: mediaType,
      libraryPid: libraryPid,
      sha256: sha256,
      batchId: batchId,
      batchPath: batchPath,
      identify: identify,
    );
    reached.complete();
    await release.future;
    return session;
  }
}

/// Opens each session on the server, then holds the create's answer
/// until the test lets that create go: a refresh can list it first.
class _HeldCreates extends FakeRepository {
  _HeldCreates() : super(sessionState: testUploaderSession());

  /// One gate per create, in call order.
  final held = <Completer<void>>[];

  @override
  Future<UploadSession> createUpload({
    required String fileName,
    required int sizeBytes,
    required String mediaType,
    String? libraryPid,
    String? sha256,
    String? batchId,
    String? batchPath,
    bool? identify,
  }) async {
    final session = await super.createUpload(
      fileName: fileName,
      sizeBytes: sizeBytes,
      mediaType: mediaType,
      libraryPid: libraryPid,
      sha256: sha256,
      batchId: batchId,
      batchPath: batchPath,
      identify: identify,
    );
    final gate = Completer<void>();
    held.add(gate);
    await gate.future;
    return session;
  }
}

/// A monotonic clock the test moves by hand.
class _Monotonic {
  Duration now = Duration.zero;

  Duration call() => now;
}

Widget _host(
  FakeRepository repo, {
  FilePickerPort? picker,
  Duration backoff = Duration.zero,
  Duration Function()? monotonic,
}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    uploadRetryBackoffProvider.overrideWithValue((_) => backoff),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    filePickerProvider.overrideWithValue(picker),
    if (monotonic != null) monotonicClockProvider.overrideWithValue(monotonic),
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
  testWidgets('load more points down to the sessions it brings in', (
    tester,
  ) async {
    final repo = FakeRepository()..uploadsNextCursor = 'more';
    repo.uploadsById['up-1'] = testUpload('up-1', fileName: 'one.flac');
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expectPointing(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.uploadsMore),
      up: false,
    );
  });

  testWidgets('a pressed Load more stays, busy, over the ghost row', (
    tester,
  ) async {
    final repo = FakeRepository()..uploadsNextCursor = 'more';
    repo.uploadsById['up-1'] = testUpload('up-1', fileName: 'one.flac');
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    repo.listUploadsGate = Completer<void>();
    await expectLoadMoreHolds(
      tester,
      waxControl<WaxButton>(SemanticsIds.uploadsMore),
    );
    repo.listUploadsGate!.complete();
    repo.listUploadsGate = null;
    await tester.pumpAndSettle();
  });

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

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRow('up-1')),
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

  testWidgets('a receiving session with no transfer here reads Interrupted', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.uploadsById['up-1'] = testUpload(
      'up-1',
      receivedBytes: 1048576,
      sizeBytes: 4194304,
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final row = find.bySemanticsIdentifier(SemanticsIds.uploadRow('up-1'));
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.uploadPhase('up-1')),
        matching: find.text(
          'Interrupted. Discard it, then upload the file again.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(WaxProgressBar)),
      findsNothing,
      reason: 'nothing here is moving it',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRetry('up-1')),
      findsNothing,
      reason: 'there is no source here to send again',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadDelete('up-1')),
      findsOneWidget,
    );
  });

  testWidgets('a session another device is sending reads its share, with '
      'nothing to retry or discard, until it goes quiet', (tester) async {
    final clock = _Monotonic();
    final repo = FakeRepository(sessionState: testUploaderSession());
    repo.uploadsById['up-1'] = testUpload(
      'up-1',
      receivedBytes: 1048576,
      sizeBytes: 4194304,
      idle: const Duration(seconds: 30),
    );
    await tester.pumpWidget(_host(repo, monotonic: clock.call));
    await tester.pumpAndSettle();
    final listed = repo.listUploadsCalls;

    final row = find.bySemanticsIdentifier(SemanticsIds.uploadRow('up-1'));
    final phase = find.bySemanticsIdentifier(SemanticsIds.uploadPhase('up-1'));
    final discard = find.bySemanticsIdentifier(
      SemanticsIds.uploadDelete('up-1'),
    );
    expect(
      find.descendant(of: phase, matching: find.textContaining('25% of')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(WaxProgressBar)),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRetry('up-1')),
      findsNothing,
    );
    expect(
      discard,
      findsNothing,
      reason: 'discarding would fail the upload still being sent',
    );

    // More arrives before the window is out: that session is read again,
    // alone, and is still being sent.
    repo.uploadsById['up-1'] = testUpload(
      'up-1',
      receivedBytes: 2097152,
      sizeBytes: 4194304,
      idle: const Duration(seconds: 5),
    );
    // Read with 30 s gone, it is due when the window would close.
    var due = uploadIdleWindow - const Duration(seconds: 30);
    clock.now += due;
    await tester.pump(due);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: phase, matching: find.textContaining('50% of')),
      findsOneWidget,
    );
    expect(discard, findsNothing);
    expect(repo.getUploadCalls, 1);

    // Then nothing more: a window on, the read says it has gone quiet,
    // and it is offered to discard.
    repo.uploadsById['up-1'] = testUpload(
      'up-1',
      receivedBytes: 2097152,
      sizeBytes: 4194304,
      idle: uploadIdleWindow + const Duration(seconds: 5),
    );
    due = uploadIdleWindow - const Duration(seconds: 5);
    clock.now += due;
    await tester.pump(due);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: phase,
        matching: find.text(
          'Interrupted. Discard it, then upload the file again.',
        ),
      ),
      findsOneWidget,
    );
    expect(discard, findsOneWidget);
    expect(repo.getUploadCalls, 2);
    expect(repo.listUploadsCalls, listed, reason: 'the list is never reloaded');
  });

  testWidgets('a re-read timer that fires a hair before its row is due still '
      'reads that row, and only the rows that are due', (tester) async {
    // A timer rounds its delay down to a whole millisecond, so it can land
    // under a millisecond ahead of the stopwatch it was set from: the row
    // is not yet due by the clock when the timer calls.
    final clock = _Monotonic();
    final repo = FakeRepository(sessionState: testUploaderSession());
    repo.uploadsById['up-1'] = testUpload(
      'up-1',
      receivedBytes: 1048576,
      sizeBytes: 4194304,
      idle: const Duration(seconds: 30),
    );
    repo.uploadsById['up-2'] = testUpload(
      'up-2',
      receivedBytes: 1048576,
      sizeBytes: 4194304,
      idle: const Duration(seconds: 5),
    );
    await tester.pumpWidget(_host(repo, monotonic: clock.call));
    await tester.pumpAndSettle();
    final discard = find.bySemanticsIdentifier(
      SemanticsIds.uploadDelete('up-1'),
    );
    expect(discard, findsNothing);

    // Nothing more arrived for up-1 by the end of its window.
    repo.uploadsById['up-1'] = testUpload(
      'up-1',
      receivedBytes: 1048576,
      sizeBytes: 4194304,
      idle: uploadIdleWindow + const Duration(seconds: 1),
    );
    final due = uploadIdleWindow - const Duration(seconds: 30);
    clock.now += due - const Duration(microseconds: 999);
    await tester.pump(due);
    await tester.pumpAndSettle();

    expect(
      repo.getUploadCalls,
      1,
      reason: 'a row read on the thirty second retry is offered late',
    );
    expect(discard, findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadDelete('up-2')),
      findsNothing,
      reason: 'up-2 is not due for another twenty-five seconds',
    );
  });

  testWidgets('an old empty session stays interrupted through a batch, while '
      "the batch's own sessions read as starting", (tester) async {
    final repo = _HeldCreates();
    repo.uploadsById['up-old'] = testUpload(
      'up-old',
      sizeBytes: 64,
      receivedBytes: 0,
    );
    final picker = _FakePicker([
      readerFile('a1.flac', Uint8List(64), dir: 'Long Form'),
      readerFile('a2.flac', Uint8List(64), dir: 'Long Form'),
    ]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UploadsScreen)),
    );
    Finder phaseOf(String id) =>
        find.bySemanticsIdentifier(SemanticsIds.uploadPhase(id));
    final interrupted = find.descendant(
      of: phaseOf('up-old'),
      matching: find.text(
        'Interrupted. Discard it, then upload the file again.',
      ),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadGroupingOption('album')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    for (final (at, id) in [(0, 'up-FAKE0'), (1, 'up-FAKE1')]) {
      expect(repo.held, hasLength(at + 1));
      // The server's event for the create lists the session first.
      container.invalidate(uploadsProvider);
      await tester.pumpAndSettle();
      expect(interrupted, findsOneWidget, reason: 'create ${at + 1}');
      expect(
        find.descendant(of: phaseOf(id), matching: find.textContaining('0%')),
        findsOneWidget,
        reason: 'create ${at + 1}',
      );
      repo.held[at].complete();
      await tester.pumpAndSettle();
    }
    expect(repo.uploadsById['up-FAKE1']!.state, 'staged');
    expect(interrupted, findsOneWidget);
  });

  testWidgets('a run started while the list still loads waits for it, so '
      'an old empty session is never taken for its own', (tester) async {
    final repo = _HeldCreates()..listUploadsGate = Completer<void>();
    repo.uploadsById['up-old'] = testUpload('up-old', sizeBytes: 64);
    final picker = _FakePicker([readerFile('fresh.flac', Uint8List(64))]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pump();
    // Frames by hand: the list's loading face animates while it waits.
    Future<void> frames() async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await frames();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await frames();
    expect(repo.held, isEmpty, reason: 'nothing is created before the list');

    repo.listUploadsGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.held, hasLength(1));
    // The server's event for the create lists the session first.
    ProviderScope.containerOf(
      tester.element(find.byType(UploadsScreen)),
    ).invalidate(uploadsProvider);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.uploadPhase('up-old')),
        matching: find.text(
          'Interrupted. Discard it, then upload the file again.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.uploadPhase('up-FAKE0')),
        matching: find.textContaining('0%'),
      ),
      findsOneWidget,
    );

    repo.held.single.complete();
    await tester.pumpAndSettle();
    expect(repo.uploadsById['up-FAKE0']!.state, 'staged');
  });

  testWidgets('a session listed before its create answers reads as '
      'starting', (tester) async {
    final repo = _ListedBeforeCreated();
    final picker = _FakePicker([
      readerFile('long-take.flac', Uint8List(2621440)),
    ]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.reached.isCompleted, isTrue);
    final id = repo.uploadsById.keys.single;

    ProviderScope.containerOf(
      tester.element(find.byType(UploadsScreen)),
    ).invalidate(uploadsProvider);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRow(id)),
      findsOneWidget,
    );
    expect(
      find.text('Interrupted. Discard it, then upload the file again.'),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.uploadPhase(id)),
        matching: find.text('0% of 2.5 MB received'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRetry(id)),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadDelete(id)),
      findsNothing,
    );

    repo.release.complete();
    await tester.pumpAndSettle();
    expect(repo.uploadsById[id]!.state, 'staged');
  });

  testWidgets('a running upload shows progress, not Retry, through a '
      'session refresh', (tester) async {
    final repo = _StaleList()
      ..putUploadDataGate = Completer<void>()
      ..putUploadDataGateAt = 2;
    // 2.5 MiB: the held chunk is the second of three.
    final picker = _FakePicker([
      readerFile('long-take.flac', Uint8List(2621440)),
    ]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.putUploadDataReached.isCompleted, isTrue);
    final id = repo.uploadsById.keys.single;

    // The server's event for this session refreshes the list, which
    // answers the row as it stood before any chunk arrived.
    ProviderScope.containerOf(
      tester.element(find.byType(UploadsScreen)),
    ).invalidate(uploadsProvider);
    await tester.pumpAndSettle();

    final row = find.bySemanticsIdentifier(SemanticsIds.uploadRow(id));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRetry(id)),
      findsNothing,
    );
    expect(find.text('Transfer failed'), findsNothing);
    expect(
      find.descendant(of: row, matching: find.byType(WaxProgressBar)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.uploadPhase(id)),
        matching: find.text('40% of 2.5 MB received'),
      ),
      findsOneWidget,
      reason: 'progress reads the bytes this app sent, not the stale page',
    );

    repo.putUploadDataGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.uploadsById[id]!.state, 'staged');
    expect(find.text('staged'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRetry(id)),
      findsNothing,
    );
  });

  testWidgets('a chunk waiting out its backoff says it is trying again', (
    tester,
  ) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    var puts = 0;
    repo.onPutUploadData = () => repo.uploadError = ++puts == 2
        ? const WaxDeckApiException(
            code: 'transport',
            message: 'connection closed',
          )
        : null;
    final picker = _FakePicker([
      readerFile('long-take.flac', Uint8List(2621440)),
    ]);
    await tester.pumpWidget(
      _host(repo, picker: picker, backoff: const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();
    final id = repo.uploadsById.keys.single;
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.uploadPhase(id)),
        matching: find.text('Connection lost, trying again'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRetry(id)),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repo.uploadsById[id]!.state, 'staged');
    expect(find.text('Connection lost, trying again'), findsNothing);
  });

  testWidgets('a transfer that gave up offers Retry, which finishes it', (
    tester,
  ) async {
    final repo = FakeRepository(sessionState: testUploaderSession());
    var puts = 0;
    repo.onPutUploadData = () {
      if (++puts == 2) {
        repo.uploadError = const WaxDeckApiException(
          code: 'invalid-request',
          message: 'offset out of range',
          statusCode: 400,
        );
      }
    };
    final picker = _FakePicker([
      readerFile('long-take.flac', Uint8List(2621440)),
    ]);
    await tester.pumpWidget(_host(repo, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadPick));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();
    final id = repo.uploadsById.keys.single;
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.uploadPhase(id)),
        matching: find.text('Transfer failed'),
      ),
      findsOneWidget,
    );

    repo
      ..uploadError = null
      ..onPutUploadData = null;
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadRetry(id)));
    await tester.pumpAndSettle();
    expect(repo.uploadsById[id]!.state, 'staged');
    expect(
      find.bySemanticsIdentifier(SemanticsIds.uploadRetry(id)),
      findsNothing,
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
          'Already in the library: Neon Meridian by The Cardinal Waves',
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
    expect(find.textContaining('may sit staged'), findsNothing);
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
