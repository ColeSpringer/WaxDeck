import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/uploads/upload_phase.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'app_host.dart';
import 'fakes.dart';

/// Pages the session list by cursor, each page held until its gate
/// opens, if it has one.
class _PagedUploads extends FakeRepository {
  final pages = <String?, UploadPage>{};
  final gates = <String?, Completer<void>>{};

  @override
  Future<UploadPage> listUploads({String? cursor, int? limit}) async {
    await gates[cursor]?.future;
    return pages[cursor] ?? const UploadPage(uploads: []);
  }
}

/// With [listGate] set, a listing reads the sessions when it is asked
/// and answers once the gate opens, as a slow GET would.
class _SlowList extends FakeRepository {
  Completer<void>? listGate;

  /// The cursor a first page answers with; every later page is empty.
  String? firstCursor;

  @override
  Future<UploadPage> listUploads({String? cursor, int? limit}) async {
    if (cursor != null) return const UploadPage(uploads: []);
    final gate = listGate;
    final page = UploadPage(
      uploads: uploadsById.values.toList(),
      nextCursor: firstCursor,
    );
    await gate?.future;
    return page;
  }
}

/// A [_SlowList] holding the [chunk]th chunk at the fake's own gate.
_SlowList _heldAt(int chunk) => _SlowList()
  ..putUploadDataGate = Completer<void>()
  ..putUploadDataGateAt = chunk;

/// [u] with the fields a server read moves.
UploadSession _with(UploadSession u, {String? state, Duration? idle}) =>
    UploadSession(
      id: u.id,
      fileName: u.fileName,
      sizeBytes: u.sizeBytes,
      receivedBytes: u.receivedBytes,
      idle: idle ?? u.idle,
      mediaType: u.mediaType,
      libraryPid: u.libraryPid,
      batchId: u.batchId,
      state: state ?? u.state,
      reviewEntryId: u.reviewEntryId,
      duplicate: u.duplicate,
      uploadedBy: u.uploadedBy,
      createdAt: u.createdAt,
      expiresAt: u.expiresAt,
    );

const _lost = WaxDeckApiException(code: 'transport', message: 'closed');

/// Seals the session, then loses the answer on the wire.
class _SealsThenDrops extends FakeRepository {
  int completeCalls = 0;

  @override
  Future<UploadSession> completeUpload(String uploadId) async {
    completeCalls++;
    await super.completeUpload(uploadId);
    throw _lost;
  }
}

/// Loses the seal's answer while the server is still sealing: reads say
/// receiving with idle zero until the [stagedAt]th, then staged, and the
/// [gateAt]th waits on [gate]; [onRead] runs at each, and the first
/// [wireDownFor] fail on the wire. A complete meanwhile is the server's
/// "still being completed" conflict.
class _SealStillRunning extends FakeRepository {
  _SealStillRunning({
    this.gateAt = 2,
    this.stagedAt = 3,
    this.wireDownFor = 0,
    this.onRead,
  });

  final int gateAt;
  final int stagedAt;
  final int wireDownFor;
  final void Function()? onRead;
  int completeCalls = 0;
  int reads = 0;
  bool running = false;
  final gate = Completer<void>();
  final waiting = Completer<void>();

  @override
  Future<UploadSession> completeUpload(String uploadId) async {
    completeCalls++;
    if (running) {
      throw const WaxDeckApiException(
        code: 'conflict',
        message: 'the upload is still being completed; ask again shortly',
        statusCode: 409,
      );
    }
    running = true;
    uploadsById[uploadId] = _with(uploadsById[uploadId]!, idle: Duration.zero);
    throw _lost;
  }

  @override
  Future<UploadSession> getUpload(String uploadId) async {
    if (!running) return super.getUpload(uploadId);
    reads++;
    onRead?.call();
    if (reads == gateAt) {
      waiting.complete();
      await gate.future;
    }
    if (reads <= wireDownFor) throw _lost;
    if (reads >= stagedAt) {
      running = false;
      uploadsById[uploadId] = _with(uploadsById[uploadId]!, state: 'staged');
    }
    return uploadsById[uploadId]!;
  }
}

/// The seal never reached the server: the session waits, idle, for one.
class _SealNeverArrived extends FakeRepository {
  int completeCalls = 0;
  bool fail = true;

  @override
  Future<UploadSession> completeUpload(String uploadId) async {
    completeCalls++;
    if (!fail) return super.completeUpload(uploadId);
    uploadsById[uploadId] = _with(
      uploadsById[uploadId]!,
      idle: const Duration(seconds: 5),
    );
    throw _lost;
  }
}

/// The seal lands and its answer is lost; the first [failing] reads after
/// it fail on the wire too (every one, when null), [onRead] running at
/// each.
class _SealAndReadLost extends _SealsThenDrops {
  _SealAndReadLost({this.failing, this.onRead});

  final int? failing;
  final void Function()? onRead;

  @override
  Future<UploadSession> getUpload(String uploadId) async {
    getUploadCalls++;
    onRead?.call();
    if (failing case final n? when getUploadCalls > n) {
      return uploadsById[uploadId]!;
    }
    throw _lost;
  }
}

/// A link that cannot move a chunk over [fits] bytes inside the stall:
/// the client cuts such a send as `transport-timeout`. Records every PUT's
/// size, cut or taken, and runs [onTaken] after each one taken.
class _NarrowLink extends FakeRepository {
  _NarrowLink(this.fits);

  int fits;
  void Function()? onTaken;
  final sizes = <int>[];

  @override
  Future<UploadSession> putUploadData(
    String uploadId, {
    required int offset,
    required Uint8List bytes,
  }) async {
    sizes.add(bytes.length);
    if (bytes.length > fits) {
      throw const WaxDeckApiException(
        code: 'transport-timeout',
        message: 'the chunk stopped moving',
      );
    }
    final session = await super.putUploadData(
      uploadId,
      offset: offset,
      bytes: bytes,
    );
    onTaken?.call();
    return session;
  }
}

/// Takes the [at]th chunk, then holds its answer until [release] opens:
/// an append that committed before a discard, answered after it.
class _AnswerHeldAt extends FakeRepository {
  _AnswerHeldAt(this.at);

  final int at;
  final reached = Completer<void>();
  final release = Completer<void>();
  var _puts = 0;

  @override
  Future<UploadSession> putUploadData(
    String uploadId, {
    required int offset,
    required Uint8List bytes,
  }) async {
    final session = await super.putUploadData(
      uploadId,
      offset: offset,
      bytes: bytes,
    );
    if (++_puts == at) {
      reached.complete();
      await release.future;
    }
    return session;
  }
}

/// [_heldAt] whose delete either takes the session and then holds its
/// answer until [deleted] opens, or, with [deleteFails], refuses on the
/// wire and keeps it.
class _HeldDelete extends _SlowList {
  _HeldDelete({this.deleteFails = false}) {
    putUploadDataGate = Completer<void>();
    putUploadDataGateAt = 2;
  }

  final bool deleteFails;
  final deleted = Completer<void>();

  @override
  Future<void> deleteUpload(String uploadId) async {
    if (deleteFails) throw _lost;
    await super.deleteUpload(uploadId);
    await deleted.future;
  }
}

UploadSession _session(String id) => UploadSession(
  id: id,
  fileName: '$id.mp3',
  sizeBytes: 64,
  receivedBytes: 64,
  idle: Duration.zero,
  mediaType: MediaType.music,
  state: 'staged',
  createdAt: DateTime.utc(2026, 7, 1),
);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('uploads-path-test');
  });

  tearDown(() => dir.delete(recursive: true));

  ProviderContainer host(
    FakeRepository repo, {
    Duration Function()? monotonic,
  }) => appContainer(
    repo: repo,
    extra: [
      uploadRetryBackoffProvider.overrideWithValue((_) => Duration.zero),
      if (monotonic != null)
        monotonicClockProvider.overrideWithValue(monotonic),
    ],
  );

  test('a path upload streams in chunk-sized windows', () async {
    // Two full chunks plus a remainder: three windowed reads, never
    // the whole file at once.
    final size = UploadsController.chunkBytes * 2 + 123;
    final file = File('${dir.path}/big.m4b')
      ..writeAsBytesSync(List.filled(size, 7));

    final repo = FakeRepository();
    final container = host(repo);
    await container.read(uploadsProvider.future);
    await container
        .read(uploadsProvider.notifier)
        .uploadFromPath(
          fileName: 'big.m4b',
          path: file.path,
          mediaType: 'audiobook',
        );

    expect(repo.putUploadDataCalls, hasLength(3));
    expect(repo.putUploadDataCalls[0].offset, 0);
    expect(repo.putUploadDataCalls[1].offset, UploadsController.chunkBytes);
    expect(repo.putUploadDataCalls[2].byteCount, 123);
    expect(repo.uploadsById.values.single.state, 'staged');
  });

  test('a failed path upload retries from what the server holds', () async {
    final size = UploadsController.chunkBytes + 50;
    final file = File('${dir.path}/book.m4b')
      ..writeAsBytesSync(List.filled(size, 9));

    final repo = FakeRepository();
    final container = host(repo);
    await container.read(uploadsProvider.future);

    final notifier = container.read(uploadsProvider.notifier);
    // First chunk lands, then the wire drops.
    var calls = 0;
    repo.onPutUploadData = () {
      calls++;
      if (calls == 2) {
        repo.uploadError = const WaxDeckApiException(
          code: 'internal',
          message: 'wire dropped',
          statusCode: 500,
        );
      }
    };
    await expectLater(
      notifier.uploadFromPath(
        fileName: 'book.m4b',
        path: file.path,
        mediaType: 'audiobook',
      ),
      throwsA(isA<WaxDeckApiException>()),
    );
    final uploadId = repo.uploadsById.keys.single;
    expect(
      repo.uploadsById[uploadId]!.receivedBytes,
      UploadsController.chunkBytes,
    );

    // Retry resumes from the server's offset, not from zero.
    repo.uploadError = null;
    repo.onPutUploadData = null;
    await notifier.retry(uploadId);
    expect(repo.putUploadDataCalls.last.offset, UploadsController.chunkBytes);
    expect(repo.uploadsById[uploadId]!.state, 'staged');
    expect(repo.uploadsById[uploadId]!.receivedBytes, size);
  });

  test('a session the server ended leaves no row to retry', () async {
    final file = File('${dir.path}/noise.mp3')
      ..writeAsBytesSync(List.filled(64, 0));
    final repo = FakeRepository()
      ..completeRefusal = const WaxDeckApiException(
        code: 'unsupported-format',
        message: 'the file does not read as audio',
        statusCode: 415,
        params: <String, String>{'reason': 'unreadable'},
      );
    final container = host(repo);
    await container.read(uploadsProvider.future);

    await expectLater(
      container
          .read(uploadsProvider.notifier)
          .uploadFromPath(
            fileName: 'noise.mp3',
            path: file.path,
            mediaType: 'music',
          ),
      throwsA(isA<WaxDeckApiException>()),
    );
    expect(container.read(uploadsProvider).value!.uploads, isEmpty);
    // Held until a page agrees, so a stale one cannot bring the row back
    // as one to send again.
    final id = container.read(liveTransfersProvider).keys.single;
    expect(
      uploadPhaseOf(testUpload(id), container.read(liveTransfersProvider)[id]),
      isA<UploadSettled>().having((p) => p.state, 'state', 'discarded'),
    );
    container.invalidate(uploadsProvider);
    await container.read(uploadsProvider.future);
    expect(container.read(liveTransfersProvider), isEmpty);
  });

  test('a refusal that says the session ended is not checked again', () async {
    final file = File('${dir.path}/noise.mp3')
      ..writeAsBytesSync(List.filled(64, 0));
    final repo = FakeRepository()
      ..completeRefusal = const WaxDeckApiException(
        code: 'conflict',
        message: 'the received bytes do not match the declared SHA-256',
        statusCode: 409,
        params: <String, String>{'reason': 'checksum-mismatch'},
      );
    final container = host(repo);
    await container.read(uploadsProvider.future);

    await expectLater(
      container
          .read(uploadsProvider.notifier)
          .uploadFromPath(
            fileName: 'noise.mp3',
            path: file.path,
            mediaType: 'music',
          ),
      throwsA(isA<WaxDeckApiException>()),
    );
    expect(repo.getUploadCalls, 0);
    expect(container.read(uploadsProvider).value!.uploads, isEmpty);
  });

  group('a page that lands while a transfer moves', () {
    late File file;
    late Completer<void> gate;
    late _PagedUploads repo;

    setUp(() {
      file = File('${dir.path}/noise.mp3')
        ..writeAsBytesSync(List.filled(64, 0));
      gate = Completer<void>();
      repo = _PagedUploads()
        ..pages[null] = const UploadPage(uploads: [], nextCursor: 'c2')
        ..pages['c2'] = UploadPage(uploads: [_session('up-OLD')])
        ..gates['c2'] = gate;
    });

    test('does not bring back a row dropped meanwhile', () async {
      repo.completeRefusal = const WaxDeckApiException(
        code: 'unsupported-format',
        message: 'the file does not read as audio',
        statusCode: 415,
        params: <String, String>{'reason': 'unreadable'},
      );
      final container = host(repo);
      await container.read(uploadsProvider.future);
      final notifier = container.read(uploadsProvider.notifier);
      // Load more is pressed while the file is on its way up.
      Future<void>? paging;
      repo.onPutUploadData = () => paging ??= notifier.loadMore();

      await expectLater(
        notifier.uploadFromPath(
          fileName: 'noise.mp3',
          path: file.path,
          mediaType: 'music',
        ),
        throwsA(isA<WaxDeckApiException>()),
      );
      gate.complete();
      await paging;

      final state = container.read(uploadsProvider).value!;
      expect(state.uploads.map((u) => u.id), ['up-OLD']);
      expect(state.loadingMore, isFalse);
      expect(state.hasMore, isFalse);
    });

    test('keeps a failure marked meanwhile', () async {
      final container = host(repo);
      await container.read(uploadsProvider.future);
      final notifier = container.read(uploadsProvider.notifier);
      Future<void>? paging;
      repo.onPutUploadData = () {
        paging ??= notifier.loadMore();
        repo.uploadError = const WaxDeckApiException(
          code: 'internal',
          message: 'wire dropped',
          statusCode: 500,
        );
      };

      await expectLater(
        notifier.uploadFromPath(
          fileName: 'noise.mp3',
          path: file.path,
          mediaType: 'music',
        ),
        throwsA(isA<WaxDeckApiException>()),
      );
      gate.complete();
      await paging;

      final state = container.read(uploadsProvider).value!;
      final mine = repo.uploadsById.keys.single;
      expect(state.uploads.map((u) => u.id), [mine, 'up-OLD']);
      expect(
        container.read(liveTransfersProvider)[mine]?.status,
        TransferStatus.stopped,
      );
    });
  });

  group('a transfer in flight', () {
    late File file;

    setUp(() {
      // Three chunks, so the second is one with a chunk either side.
      file = File(
        '${dir.path}/long.flac',
      )..writeAsBytesSync(List.filled(UploadsController.chunkBytes * 2 + 7, 3));
    });

    Future<void> start(ProviderContainer container) => container
        .read(uploadsProvider.notifier)
        .uploadFromPath(
          fileName: 'long.flac',
          path: file.path,
          mediaType: 'music',
        );

    test('a refresh mid-transfer does not read as failed', () async {
      final repo = _heldAt(2);
      final container = host(repo);
      await container.read(uploadsProvider.future);
      final upload = start(container);
      await repo.putUploadDataReached.future;

      // What the server's event for this very session does.
      container.invalidate(uploadsProvider);
      final state = await container.read(uploadsProvider.future);
      final row = state.uploads.single;
      expect(
        uploadPhaseOf(row, container.read(liveTransfersProvider)[row.id]),
        isA<UploadSending>().having(
          (p) => p.sent,
          'sent',
          UploadsController.chunkBytes,
        ),
      );

      repo.putUploadDataGate!.complete();
      await upload;
      expect(repo.uploadsById[row.id]!.state, 'staged');
    });

    test('a page read before the seal does not undo it', () async {
      final repo = _heldAt(3);
      final container = host(repo);
      await container.read(uploadsProvider.future);
      final phases = <UploadPhase>[];
      void observe() {
        final rows = container.read(uploadsProvider).value?.uploads ?? [];
        final live = container.read(liveTransfersProvider);
        phases.addAll([for (final u in rows) uploadPhaseOf(u, live[u.id])]);
      }

      container
        ..listen(uploadsProvider, (_, _) => observe())
        ..listen(liveTransfersProvider, (_, _) => observe());
      final upload = start(container);
      await repo.putUploadDataReached.future;
      final id = repo.uploadsById.keys.single;

      // A refresh reads the session before the last chunk and the seal,
      // and its answer lands after both.
      final gate = repo.listGate = Completer<void>();
      container.invalidate(uploadsProvider);
      final stale = container.read(uploadsProvider.future);
      repo.putUploadDataGate!.complete();
      await upload;
      expect(repo.uploadsById[id]!.state, 'staged');
      gate.complete();
      repo.listGate = null;
      await stale;

      expect(
        uploadPhaseOf(
          container.read(uploadsProvider).value!.uploads.single,
          container.read(liveTransfersProvider)[id],
        ),
        isA<UploadSealing>(),
        reason: 'the page still says receiving, the seal says finished',
      );

      // A page read after the seal settles the row and retires the entry.
      container.invalidate(uploadsProvider);
      final fresh = await container.read(uploadsProvider.future);
      expect(
        uploadPhaseOf(
          fresh.uploads.single,
          container.read(liveTransfersProvider)[id],
        ),
        isA<UploadSettled>().having((p) => p.state, 'state', 'staged'),
      );
      expect(container.read(liveTransfersProvider), isEmpty);
      expect(phases, isNot(contains(isA<UploadInterrupted>())));
    });

    test('a later page does not retire a seal on the client copy', () async {
      final repo = _heldAt(3)..firstCursor = 'c2';
      final container = host(repo);
      await container.read(uploadsProvider.future);
      final upload = start(container);
      await repo.putUploadDataReached.future;
      final id = repo.uploadsById.keys.single;

      final gate = repo.listGate = Completer<void>();
      container.invalidate(uploadsProvider);
      final stale = container.read(uploadsProvider.future);
      repo.putUploadDataGate!.complete();
      await upload;
      // The held list now carries this client's own staged copy; the
      // second page says nothing about the session.
      await container.read(uploadsProvider.notifier).loadMore();
      gate.complete();
      repo.listGate = null;
      await stale;

      expect(
        uploadPhaseOf(
          container.read(uploadsProvider).value!.uploads.single,
          container.read(liveTransfersProvider)[id],
        ),
        isA<UploadSealing>(),
      );
    });

    test('Retry is refused while the transfer runs', () async {
      final repo = _heldAt(2);
      final container = host(repo);
      await container.read(uploadsProvider.future);
      final upload = start(container);
      await repo.putUploadDataReached.future;

      final id = repo.uploadsById.keys.single;
      await container.read(uploadsProvider.notifier).retry(id);
      repo.putUploadDataGate!.complete();
      await upload;

      final offsets = repo.putUploadDataCalls.map((c) => c.offset).toList();
      expect(offsets, [
        0,
        UploadsController.chunkBytes,
        UploadsController.chunkBytes * 2,
      ]);
      expect(repo.uploadsById[id]!.state, 'staged');
    });

    test('a dropped wire retries before it fails', () async {
      final repo = FakeRepository();
      final container = host(repo);
      await container.read(uploadsProvider.future);
      final statuses = <TransferStatus>[];
      container.listen(liveTransfersProvider, (_, next) {
        statuses.addAll(next.values.map((t) => t.status));
      });
      var puts = 0;
      repo.onPutUploadData = () {
        puts++;
        // The second chunk's first try finds no server, its second does.
        repo.uploadError = puts == 2
            ? const WaxDeckApiException(
                code: 'transport',
                message: 'connection closed',
              )
            : null;
      };

      await start(container);

      final id = repo.uploadsById.keys.single;
      expect(repo.uploadsById[id]!.state, 'staged');
      expect(repo.getUploadCalls, 1);
      expect(repo.putUploadDataCalls.map((c) => c.offset), [
        0,
        UploadsController.chunkBytes,
        UploadsController.chunkBytes * 2,
      ]);
      expect(statuses, isNot(contains(TransferStatus.stopped)));
    });

    test('a wire that stays down stalls after three tries', () async {
      final repo = FakeRepository();
      final waits = <int>[];
      final container = appContainer(
        repo: repo,
        extra: [
          uploadRetryBackoffProvider.overrideWithValue((attempt) {
            waits.add(attempt);
            return Duration.zero;
          }),
        ],
      );
      await container.read(uploadsProvider.future);
      var puts = 0;
      repo.onPutUploadData = () {
        if (++puts == 2) {
          repo.uploadError = const WaxDeckApiException(
            code: 'transport',
            message: 'connection closed',
          );
        }
      };

      await expectLater(start(container), throwsA(isA<WaxDeckApiException>()));

      final id = repo.uploadsById.keys.single;
      expect(waits, [1, 2, 3]);
      expect(repo.getUploadCalls, 3, reason: 'one resync before each try');
      expect(puts, 5, reason: 'the first chunk, then the second four times');
      expect(
        uploadPhaseOf(
          repo.uploadsById[id]!,
          container.read(liveTransfersProvider)[id],
        ),
        isA<UploadStalled>(),
      );
    });

    test('the backoff waits 1, 2 and 4 seconds', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final backoff = container.read(uploadRetryBackoffProvider);
      expect([1, 2, 3].map(backoff), const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]);
    });

    for (final (what, error) in const [
      (
        'a server error',
        WaxDeckApiException(code: 'internal', message: 'x', statusCode: 500),
      ),
      (
        'a gateway timeout',
        WaxDeckApiException(code: 'transport', message: 'x', statusCode: 504),
      ),
      (
        'a busy catalog',
        WaxDeckApiException(
          code: 'catalog-busy',
          message: 'x',
          statusCode: 409,
        ),
      ),
    ]) {
      test('$what is tried again', () async {
        final repo = FakeRepository();
        final container = host(repo);
        await container.read(uploadsProvider.future);
        var puts = 0;
        repo.onPutUploadData = () =>
            repo.uploadError = ++puts == 2 ? error : null;

        await start(container);

        expect(repo.getUploadCalls, 1);
        expect(repo.uploadsById.values.single.state, 'staged');
      });
    }

    test('a refusal no retry can mend stops at once', () async {
      final repo = FakeRepository();
      final container = host(repo);
      await container.read(uploadsProvider.future);
      var puts = 0;
      repo.onPutUploadData = () {
        if (++puts == 2) {
          repo.uploadError = const WaxDeckApiException(
            code: 'quota-exceeded',
            message: 'over the allowance',
            statusCode: 413,
          );
        }
      };

      await expectLater(start(container), throwsA(isA<WaxDeckApiException>()));

      final id = repo.uploadsById.keys.single;
      expect(puts, 2);
      expect(repo.getUploadCalls, 0);
      expect(
        container.read(liveTransfersProvider)[id]?.status,
        TransferStatus.stopped,
      );
    });

    const conflict = WaxDeckApiException(
      code: 'conflict',
      message: 'offset does not match; resume there',
      statusCode: 409,
    );

    test('a conflict resyncs once and resumes where the server is', () async {
      final repo = FakeRepository();
      final container = host(repo);
      await container.read(uploadsProvider.future);
      var puts = 0;
      repo.onPutUploadData = () {
        repo.uploadError = null;
        if (++puts != 2) return;
        // The server already holds the second chunk (its answer was
        // lost), so it refuses that offset.
        final id = repo.uploadsById.keys.single;
        final held = repo.uploadsById[id]!;
        repo.uploadsById[id] = testUpload(
          id,
          fileName: held.fileName,
          sizeBytes: held.sizeBytes,
          receivedBytes: UploadsController.chunkBytes * 2,
        );
        repo.uploadError = conflict;
      };

      await start(container);

      expect(repo.getUploadCalls, 1);
      expect(repo.putUploadDataCalls.map((c) => c.offset), [
        0,
        UploadsController.chunkBytes * 2,
      ], reason: 'resumed at the server offset, not resent at the old one');
      expect(repo.uploadsById.values.single.state, 'staged');
    });

    test('a second conflict stops the transfer', () async {
      final repo = FakeRepository();
      final container = host(repo);
      await container.read(uploadsProvider.future);
      var puts = 0;
      repo.onPutUploadData = () =>
          repo.uploadError = ++puts >= 2 ? conflict : null;

      await expectLater(start(container), throwsA(isA<WaxDeckApiException>()));

      final id = repo.uploadsById.keys.single;
      expect(puts, 3);
      expect(repo.getUploadCalls, 1);
      expect(
        container.read(liveTransfersProvider)[id]?.status,
        TransferStatus.stopped,
      );
    });
  });

  group('a link too slow to move a whole chunk inside the stall', () {
    const kib = 1024;

    Future<void> upload(ProviderContainer container, int size) {
      final file = File('${dir.path}/slow.flac')
        ..writeAsBytesSync(List.filled(size, 5));
      return container
          .read(uploadsProvider.notifier)
          .uploadFromPath(
            fileName: 'slow.flac',
            path: file.path,
            mediaType: 'music',
          );
    }

    test(
      'sends it again in halves, and keeps to the size that moved',
      () async {
        final repo = _NarrowLink(256 * kib);
        final container = host(repo);
        await container.read(uploadsProvider.future);

        await upload(container, UploadsController.chunkBytes + 512 * kib);

        expect(repo.sizes, [
          1024 * kib,
          512 * kib,
          for (var i = 0; i < 6; i++) 256 * kib,
        ]);
        expect(repo.uploadsById.values.single.state, 'staged');
      },
    );

    test('never under 64 KiB, and stops once its tries are spent', () async {
      final repo = _NarrowLink(128 * kib);
      // The link narrows to nothing once the first piece is through.
      repo.onTaken = () => repo.fits = 0;
      final container = host(repo);
      await container.read(uploadsProvider.future);

      await expectLater(
        upload(container, UploadsController.chunkBytes),
        throwsA(
          isA<WaxDeckApiException>().having(
            (e) => e.code,
            'code',
            'transport-timeout',
          ),
        ),
      );

      expect(repo.sizes, [
        1024 * kib,
        512 * kib,
        256 * kib,
        128 * kib,
        128 * kib,
        64 * kib,
        64 * kib,
        64 * kib,
      ]);
    });
  });

  test("a later page's rows are judged by when that page was read, and a "
      'row read again leaves the rest', () async {
    var now = Duration.zero;
    final repo = _PagedUploads()
      ..pages[null] = UploadPage(
        uploads: [testUpload('up-1')],
        nextCursor: 'page-2',
      )
      ..pages['page-2'] = UploadPage(
        uploads: [
          testUpload(
            'up-2',
            receivedBytes: 64,
            idle: const Duration(seconds: 30),
          ),
          testUpload('up-3'),
        ],
      );
    final container = host(repo, monotonic: () => now);
    await container.read(uploadsProvider.future);
    now = const Duration(minutes: 2);
    await container.read(uploadsProvider.notifier).loadMore();

    var state = container.read(uploadsProvider).value!;
    expect(state.readAt, {
      'up-1': Duration.zero,
      'up-2': const Duration(minutes: 2),
      'up-3': const Duration(minutes: 2),
    });

    // The one row read again alone; what Load more brought stays.
    now = const Duration(minutes: 8);
    repo.uploadsById['up-2'] = testUpload(
      'up-2',
      receivedBytes: 128,
      idle: const Duration(seconds: 2),
    );
    await container.read(uploadsProvider.notifier).readAgain(['up-2']);
    state = container.read(uploadsProvider).value!;
    expect(state.uploads.map((u) => u.id), ['up-1', 'up-2', 'up-3']);
    expect(state.uploads[1].receivedBytes, 128);
    expect(state.readAt['up-2'], const Duration(minutes: 8));
    expect(state.readAt['up-1'], Duration.zero);

    // One the server no longer has goes, alone.
    repo.uploadsById.remove('up-2');
    await container.read(uploadsProvider.notifier).readAgain(['up-2']);
    state = container.read(uploadsProvider).value!;
    expect(state.uploads.map((u) => u.id), ['up-1', 'up-3']);
  });

  group('a seal whose answer is lost', () {
    late File file;

    setUp(() {
      file = File('${dir.path}/a.flac')..writeAsBytesSync(List.filled(64, 1));
    });

    UploadPhase phase(ProviderContainer c) {
      final row = c.read(uploadsProvider).value!.uploads.single;
      return uploadPhaseOf(row, c.read(liveTransfersProvider)[row.id]);
    }

    Future<void> upload(ProviderContainer c) => c
        .read(uploadsProvider.notifier)
        .uploadFromPath(
          fileName: 'a.flac',
          path: file.path,
          mediaType: 'music',
        );

    test('settles when the seal landed', () async {
      final repo = _SealsThenDrops();
      final c = host(repo);
      await c.read(uploadsProvider.future);

      await upload(c);

      expect(
        phase(c),
        isA<UploadSettled>().having((p) => p.state, 'state', 'staged'),
      );
      final id = c.read(uploadsProvider).value!.uploads.single.id;
      expect(c.read(liveTransfersProvider)[id]!.status, TransferStatus.sealed);
      await c.read(uploadsProvider.notifier).retry(id);
      expect(repo.completeCalls, 1);
      expect(repo.getUploadCalls, 1);
    });

    test('reads Finishing while the server still seals it, refuses Retry, '
        'then settles', () async {
      final repo = _SealStillRunning();
      final c = host(repo);
      await c.read(uploadsProvider.future);

      Object? thrown;
      final run = upload(
        c,
      ).then<void>((_) {}, onError: (Object e) => thrown = e);
      await Future.any([repo.waiting.future, run]);
      expect(thrown, isNull, reason: 'the lost answer stopped the transfer');
      expect(phase(c), isA<UploadSealing>());
      final id = c.read(uploadsProvider).value!.uploads.single.id;
      await c.read(uploadsProvider.notifier).retry(id);
      expect(repo.completeCalls, 1, reason: 'a Retry meanwhile is refused');
      repo.gate.complete();
      await run;

      expect(thrown, isNull);
      expect(
        phase(c),
        isA<UploadSettled>().having((p) => p.state, 'state', 'staged'),
      );
      expect(repo.completeCalls, 1);
    });

    test('stops for Retry when it never reached the server', () async {
      final repo = _SealNeverArrived();
      final c = host(repo);
      await c.read(uploadsProvider.future);

      await expectLater(upload(c), throwsA(isA<WaxDeckApiException>()));
      expect(phase(c), isA<UploadStalled>());
      expect(repo.getUploadCalls, 1, reason: 'one read, no wait');

      repo.fail = false;
      final id = c.read(uploadsProvider).value!.uploads.single.id;
      await c.read(uploadsProvider.notifier).retry(id);
      expect(
        phase(c),
        isA<UploadSettled>().having((p) => p.state, 'state', 'staged'),
      );
    });

    test('keeps reading past where thirty reads used to stop, and settles '
        'once the seal lands', () async {
      final repo = _SealStillRunning(gateAt: 35, stagedAt: 45);
      final c = host(repo);
      await c.read(uploadsProvider.future);

      Object? thrown;
      final run = upload(
        c,
      ).then<void>((_) {}, onError: (Object e) => thrown = e);
      await Future.any([repo.waiting.future, run]);
      expect(thrown, isNull, reason: 'the reads stopped short of the seal');
      expect(phase(c), isA<UploadSealing>());
      repo.gate.complete();
      await run;

      expect(thrown, isNull);
      expect(
        phase(c),
        isA<UploadSettled>().having((p) => p.state, 'state', 'staged'),
      );
      expect(repo.completeCalls, 1);
    });

    test('asks again after a read the wire fails, and settles', () async {
      final repo = _SealAndReadLost(failing: 2);
      final c = host(repo);
      await c.read(uploadsProvider.future);

      await upload(c);

      expect(
        phase(c),
        isA<UploadSettled>().having((p) => p.state, 'state', 'staged'),
      );
      expect(repo.getUploadCalls, 3);
    });

    test('says it cannot reach the server while reads fail on the wire, '
        'until one answers', () async {
      final repo = _SealStillRunning(gateAt: 0, stagedAt: 4, wireDownFor: 2);
      final c = host(repo);
      await c.read(uploadsProvider.future);
      final seen = <UploadPhase>[];
      c.listen(liveTransfersProvider, (_, live) {
        for (final row in c.read(uploadsProvider).value?.uploads ?? []) {
          seen.add(uploadPhaseOf(row, live[row.id]));
        }
      });

      await upload(c);

      // Sealing, two reads lost (said once), one answering still sealing,
      // then the seal landed.
      expect(
        [
          for (final p in seen)
            if (p is UploadSealing) p.unreachable,
        ],
        [false, true, false],
      );
      expect(
        seen.last,
        isA<UploadSettled>().having((p) => p.state, 'state', 'staged'),
      );
      expect(repo.reads, 4);
    });

    test('stops for Retry once the seal\'s budget runs out unread', () async {
      var now = Duration.zero;
      final repo = _SealAndReadLost(
        onRead: () => now += const Duration(minutes: 10),
      );
      final c = host(repo, monotonic: () => now);
      await c.read(uploadsProvider.future);

      await expectLater(upload(c), throwsA(isA<WaxDeckApiException>()));
      expect(phase(c), isA<UploadStalled>());
      expect(now, lessThan(const Duration(minutes: 40)));
    });

    test('stops for Retry once the seal\'s budget runs out with the server '
        'still sealing', () async {
      var now = Duration.zero;
      final repo = _SealStillRunning(
        gateAt: 0,
        stagedAt: 1000,
        onRead: () => now += const Duration(minutes: 10),
      );
      final c = host(repo, monotonic: () => now);
      await c.read(uploadsProvider.future);

      await expectLater(upload(c), throwsA(isA<WaxDeckApiException>()));
      expect(phase(c), isA<UploadStalled>());
      expect(repo.reads, inInclusiveRange(3, 4));
    });
  });

  group('a discard while the transfer runs', () {
    late File file;

    setUp(() {
      // Three chunks, so a held second one has one after it.
      file = File(
        '${dir.path}/long.flac',
      )..writeAsBytesSync(List.filled(UploadsController.chunkBytes * 2 + 7, 3));
    });

    Future<bool> start(ProviderContainer container) => container
        .read(uploadsProvider.notifier)
        .uploadFromPath(
          fileName: 'long.flac',
          path: file.path,
          mediaType: 'music',
        );

    test('ends the send quietly, with nothing sent after it', () async {
      final repo = _heldAt(2);
      final container = host(repo);
      await container.read(uploadsProvider.future);
      Object? thrown;
      bool? sent;
      final run = start(
        container,
      ).then<void>((value) => sent = value, onError: (Object e) => thrown = e);
      await repo.putUploadDataReached.future;
      final id = repo.uploadsById.keys.single;

      await container.read(uploadsProvider.notifier).discard(id);
      repo.putUploadDataGate!.complete();
      await run;

      expect(thrown, isNull, reason: 'a discard is no failure to report');
      expect(sent, isFalse, reason: 'nothing was sent to be counted');
      expect(repo.putUploadDataCalls, hasLength(2));
      expect(container.read(liveTransfersProvider), isEmpty);
      final listed = await container.read(uploadsProvider.future);
      expect(listed.uploads.map((u) => u.id), isNot(contains(id)));
    });

    test('a chunk failing while the delete is out is no failure', () async {
      final repo = _HeldDelete();
      final container = host(repo);
      await container.read(uploadsProvider.future);
      Object? thrown;
      bool? sent;
      final run = start(
        container,
      ).then<void>((value) => sent = value, onError: (Object e) => thrown = e);
      await repo.putUploadDataReached.future;
      final id = repo.uploadsById.keys.single;

      final discarding = container.read(uploadsProvider.notifier).discard(id);
      // The server has the delete; its answer is still on the way when
      // the chunk meets the session gone.
      repo.putUploadDataGate!.complete();
      await run;
      expect(thrown, isNull, reason: 'a discard is no failure to report');
      expect(sent, isFalse);

      repo.deleted.complete();
      await discarding;
      expect(repo.putUploadDataCalls, hasLength(2));
      expect(container.read(liveTransfersProvider), isEmpty);
    });

    test('a delete that fails leaves the send stopped, for Retry', () async {
      final repo = _HeldDelete(deleteFails: true);
      final container = host(repo);
      await container.read(uploadsProvider.future);
      bool? sent;
      final run = start(container).then<void>((value) => sent = value);
      await repo.putUploadDataReached.future;
      final id = repo.uploadsById.keys.single;

      await expectLater(
        container.read(uploadsProvider.notifier).discard(id),
        throwsA(isA<WaxDeckApiException>()),
      );
      repo.putUploadDataGate!.complete();
      await run;
      expect(sent, isFalse, reason: 'the send stopped at the discard');
      expect(repo.putUploadDataCalls, hasLength(2));
      final row = container.read(uploadsProvider).value!.uploads.single;
      expect(
        uploadPhaseOf(row, container.read(liveTransfersProvider)[id]),
        isA<UploadStalled>(),
      );

      await container.read(uploadsProvider.notifier).retry(id);
      expect(repo.putUploadDataCalls, hasLength(3));
      expect(repo.uploadsById[id]!.state, 'staged');
    });

    test('a send a failed delete stopped stays stopped when its chunk then '
        'fails on the wire', () async {
      final repo = _HeldDelete(deleteFails: true);
      final container = host(repo);
      await container.read(uploadsProvider.future);
      bool? sent;
      final run = start(container).then<void>((value) => sent = value);
      await repo.putUploadDataReached.future;
      final id = repo.uploadsById.keys.single;

      await expectLater(
        container.read(uploadsProvider.notifier).discard(id),
        throwsA(isA<WaxDeckApiException>()),
      );
      // The wire that failed the delete fails the chunk out meanwhile too.
      repo.uploadError = _lost;
      repo.putUploadDataGate!.complete();
      await run;
      expect(sent, isFalse);
      final row = container.read(uploadsProvider).value!.uploads.single;
      expect(
        uploadPhaseOf(row, container.read(liveTransfersProvider)[id]),
        isA<UploadStalled>(),
      );

      repo.uploadError = null;
      await container.read(uploadsProvider.notifier).retry(id);
      expect(repo.uploadsById[id]!.state, 'staged');
    });

    test('a chunk answered after it does not bring the row back', () async {
      final repo = _AnswerHeldAt(2);
      final container = host(repo);
      await container.read(uploadsProvider.future);
      Object? thrown;
      final run = start(
        container,
      ).then<void>((_) {}, onError: (Object e) => thrown = e);
      await repo.reached.future;
      final id = repo.uploadsById.keys.single;

      await container.read(uploadsProvider.notifier).discard(id);
      await container.read(uploadsProvider.future);
      repo.release.complete();
      await run;

      expect(thrown, isNull);
      expect(repo.putUploadDataCalls, hasLength(2));
      expect(
        container.read(uploadsProvider).value!.uploads.map((u) => u.id),
        isNot(contains(id)),
      );
      expect(container.read(liveTransfersProvider), isEmpty);
    });
  });

  group('a transfer that stopped', () {
    /// Stops a one-chunk upload refused outright, which no retry can mend
    /// on the wire: the entry stops and keeps its source for Retry.
    Future<(ProviderContainer, FakeRepository, String)> stopped() async {
      final file = File('${dir.path}/stall.flac')
        ..writeAsBytesSync(List.filled(64, 5));
      final repo = FakeRepository();
      final container = host(repo);
      await container.read(uploadsProvider.future);
      repo.onPutUploadData = () => repo.uploadError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'refused',
        statusCode: 400,
      );
      await expectLater(
        container
            .read(uploadsProvider.notifier)
            .uploadFromPath(
              fileName: 'stall.flac',
              path: file.path,
              mediaType: 'music',
            ),
        throwsA(isA<WaxDeckApiException>()),
      );
      repo
        ..uploadError = null
        ..onPutUploadData = null;
      final id = repo.uploadsById.keys.single;
      expect(
        container.read(liveTransfersProvider)[id]?.status,
        TransferStatus.stopped,
      );
      return (container, repo, id);
    }

    test('stays for Retry while the list still says receiving', () async {
      final (container, _, id) = await stopped();
      container.invalidate(uploadsProvider);
      await container.read(uploadsProvider.future);
      expect(
        container.read(liveTransfersProvider)[id]?.status,
        TransferStatus.stopped,
      );
    });

    test('goes once the list says its session settled elsewhere', () async {
      final (container, repo, id) = await stopped();
      repo.uploadsById[id] = testUpload(id, sizeBytes: 64, state: 'staged');
      container.invalidate(uploadsProvider);
      await container.read(uploadsProvider.future);
      expect(container.read(liveTransfersProvider), isEmpty);
    });

    test('goes once a list read to its end no longer holds it', () async {
      final (container, repo, id) = await stopped();
      repo.uploadsById.remove(id);
      container.invalidate(uploadsProvider);
      await container.read(uploadsProvider.future);
      expect(container.read(liveTransfersProvider), isEmpty);
    });

    test('Retry on a session the server no longer has lets the entry and '
        'its row go', () async {
      final (container, repo, id) = await stopped();
      repo.uploadsById.remove(id);

      await expectLater(
        container.read(uploadsProvider.notifier).retry(id),
        throwsA(
          isA<WaxDeckApiException>().having((e) => e.code, 'code', 'not-found'),
        ),
      );

      expect(container.read(liveTransfersProvider), isEmpty);
      expect(
        container.read(uploadsProvider).value!.uploads.map((u) => u.id),
        isNot(contains(id)),
      );
      // Nothing is held to send again.
      await container.read(uploadsProvider.notifier).retry(id);
      expect(repo.getUploadCalls, 1);
    });

    test('Retry refuses a session no longer receiving and lets the entry '
        'go', () async {
      final (container, repo, id) = await stopped();
      final puts = repo.putUploadDataCalls.length;
      repo.uploadsById[id] = testUpload(id, sizeBytes: 64, state: 'staged');

      await container.read(uploadsProvider.notifier).retry(id);

      expect(repo.putUploadDataCalls, hasLength(puts));
      expect(container.read(liveTransfersProvider), isEmpty);
      final row = container
          .read(uploadsProvider)
          .value!
          .uploads
          .singleWhere((u) => u.id == id);
      expect(row.state, 'staged');
      // Nothing is held to send again.
      await container.read(uploadsProvider.notifier).retry(id);
      expect(repo.putUploadDataCalls, hasLength(puts));
      expect(repo.getUploadCalls, 1);
    });
  });
}
