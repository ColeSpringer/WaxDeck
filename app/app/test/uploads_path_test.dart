import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
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

UploadSession _session(String id) => UploadSession(
  id: id,
  fileName: '$id.mp3',
  sizeBytes: 64,
  receivedBytes: 64,
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

  ProviderContainer host(FakeRepository repo) {
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
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
    final state = container.read(uploadsProvider).value!;
    expect(state.uploads, isEmpty);
    expect(state.failed, isEmpty);
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
      expect(state.failed, {mine});
    });
  });
}
