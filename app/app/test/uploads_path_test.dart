import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

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
}
