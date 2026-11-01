import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/uploads/upload_phase.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

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
  }) {
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        uploadRetryBackoffProvider.overrideWithValue((_) => Duration.zero),
        if (monotonic != null)
          monotonicClockProvider.overrideWithValue(monotonic),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

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
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          uploadRetryBackoffProvider.overrideWithValue((attempt) {
            waits.add(attempt);
            return Duration.zero;
          }),
        ],
      );
      addTearDown(container.dispose);
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
