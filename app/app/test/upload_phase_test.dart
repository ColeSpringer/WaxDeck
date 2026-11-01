import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/uploads/upload_phase.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

void main() {
  const wireDropped = 'wire dropped';

  group('reduceTransfer', () {
    test('a start runs from the offset it resumes at', () {
      final live = reduceTransfer(null, const TransferStarted(64));
      expect(live?.status, TransferStatus.running);
      expect(live?.sent, 64);
      expect(live?.retrying, isFalse);
      expect(live?.error, isNull);
    });

    test('a start after a stop runs again and forgets the error', () {
      final stopped = reduceTransfer(
        reduceTransfer(null, const TransferStarted(0)),
        const Stopped(wireDropped),
      );
      final live = reduceTransfer(stopped, const TransferStarted(32));
      expect(live?.status, TransferStatus.running);
      expect(live?.sent, 32);
      expect(live?.error, isNull);
    });

    test('an acked chunk moves the bytes sent and ends a retry', () {
      final retrying = reduceTransfer(
        reduceTransfer(null, const TransferStarted(0)),
        const ChunkRetrying(),
      );
      expect(retrying?.retrying, isTrue);
      final live = reduceTransfer(retrying, const ChunkAcked(128));
      expect(live?.status, TransferStatus.running);
      expect(live?.sent, 128);
      expect(live?.retrying, isFalse);
    });

    test('a retrying chunk keeps the bytes already sent', () {
      final live = reduceTransfer(
        reduceTransfer(null, const TransferStarted(96)),
        const ChunkRetrying(),
      );
      expect(live?.status, TransferStatus.running);
      expect(live?.sent, 96);
      expect(live?.retrying, isTrue);
    });

    test('sealing keeps the bytes and is no longer retrying', () {
      final live = reduceTransfer(
        reduceTransfer(
          reduceTransfer(null, const TransferStarted(0)),
          const ChunkRetrying(),
        ),
        const Sealing(),
      );
      expect(live?.status, TransferStatus.sealing);
      expect(live?.sent, 0);
      expect(live?.retrying, isFalse);
    });

    test('a stop keeps the bytes and holds the error', () {
      final live = reduceTransfer(
        reduceTransfer(null, const TransferStarted(48)),
        const Stopped(wireDropped),
      );
      expect(live?.status, TransferStatus.stopped);
      expect(live?.sent, 48);
      expect(live?.error, wireDropped);
    });

    test('a seal or a refused seal keeps the bytes and finishes', () {
      final started = reduceTransfer(null, const TransferStarted(64));
      final sealed = reduceTransfer(started, const Sealed());
      expect(sealed?.status, TransferStatus.sealed);
      expect(sealed?.sent, 64);
      expect(sealed?.finished, isTrue);
      final refused = reduceTransfer(started, const SealRefused());
      expect(refused?.status, TransferStatus.refused);
      expect(refused?.finished, isTrue);
      expect(started?.finished, isFalse);
    });

    test('an end removes the transfer', () {
      expect(
        reduceTransfer(
          reduceTransfer(null, const TransferStarted(0)),
          const Ended(),
        ),
        isNull,
      );
    });

    test('only a start brings back a transfer that ended', () {
      for (final event in const <TransferEvent>[
        ChunkAcked(16),
        ChunkRetrying(),
        Sealing(),
        Stopped(wireDropped),
        Sealed(),
        SealRefused(),
        Ended(),
      ]) {
        expect(reduceTransfer(null, event), isNull, reason: '$event');
      }
    });
  });

  group('uploadPhaseOf', () {
    final receiving = testUpload('up-1', sizeBytes: 256, receivedBytes: 0);

    test('a running transfer sends from its own count, not the page', () {
      final phase = uploadPhaseOf(
        receiving,
        reduceTransfer(null, const TransferStarted(128)),
      );
      expect(
        phase,
        isA<UploadSending>()
            .having((p) => p.sent, 'sent', 128)
            .having((p) => p.total, 'total', 256)
            .having((p) => p.retrying, 'retrying', isFalse),
      );
    });

    test('a running transfer in backoff reads as retrying', () {
      final phase = uploadPhaseOf(
        receiving,
        reduceTransfer(
          reduceTransfer(null, const TransferStarted(0)),
          const ChunkRetrying(),
        ),
      );
      expect(phase, isA<UploadSending>().having((p) => p.retrying, 'r', true));
    });

    test('a sealing transfer reads as finishing whatever the page says', () {
      final sealing = reduceTransfer(
        reduceTransfer(null, const TransferStarted(256)),
        const Sealing(),
      );
      expect(uploadPhaseOf(receiving, sealing), isA<UploadSealing>());
      expect(
        uploadPhaseOf(testUpload('up-1', state: 'staged'), sealing),
        isA<UploadSealing>(),
      );
    });

    test('a sealed transfer reads as finishing until the page settles', () {
      final sealed = reduceTransfer(
        reduceTransfer(null, const TransferStarted(256)),
        const Sealed(),
      );
      expect(uploadPhaseOf(receiving, sealed), isA<UploadSealing>());
      expect(
        uploadPhaseOf(testUpload('up-1', state: 'staged'), sealed),
        isA<UploadSettled>().having((p) => p.state, 'state', 'staged'),
      );
    });

    test('a refused seal reads as discarded, never as receiving', () {
      final refused = reduceTransfer(
        reduceTransfer(null, const TransferStarted(256)),
        const SealRefused(),
      );
      expect(
        uploadPhaseOf(receiving, refused),
        isA<UploadSettled>().having((p) => p.state, 'state', 'discarded'),
      );
    });

    test('a stopped transfer on a receiving session is stalled', () {
      final stopped = reduceTransfer(
        reduceTransfer(null, const TransferStarted(0)),
        const Stopped(wireDropped),
      );
      expect(
        uploadPhaseOf(receiving, stopped),
        isA<UploadStalled>().having((p) => p.error, 'error', wireDropped),
      );
    });

    test('a stopped transfer the server settled reads settled', () {
      final stopped = reduceTransfer(
        reduceTransfer(null, const TransferStarted(0)),
        const Stopped(wireDropped),
      );
      expect(
        uploadPhaseOf(testUpload('up-1', state: 'staged'), stopped),
        isA<UploadSettled>().having((p) => p.state, 'state', 'staged'),
      );
    });

    test('a receiving session with no transfer here is interrupted', () {
      expect(uploadPhaseOf(receiving, null), isA<UploadInterrupted>());
    });

    group('a receiving session with no transfer here', () {
      UploadSession quietFor(Duration idle) =>
          testUpload('up-1', sizeBytes: 256, receivedBytes: 64, idle: idle);

      test('is sent from elsewhere while the server took bytes lately', () {
        expect(
          uploadPhaseOf(
            quietFor(uploadIdleWindow - const Duration(milliseconds: 1)),
            null,
          ),
          isA<UploadElsewhere>()
              .having((p) => p.received, 'received', 64)
              .having((p) => p.total, 'total', 256),
        );
        expect(
          uploadPhaseOf(quietFor(Duration.zero), null),
          isA<UploadElsewhere>(),
          reason: 'a chunk is arriving',
        );
      });

      test('is interrupted once the server went a whole window without', () {
        expect(
          uploadPhaseOf(quietFor(uploadIdleWindow), null),
          isA<UploadInterrupted>(),
        );
        expect(
          uploadPhaseOf(
            quietFor(uploadIdleWindow + const Duration(milliseconds: 1)),
            null,
          ),
          isA<UploadInterrupted>(),
        );
      });

      test('defers to a transfer here and to a settled state', () {
        expect(
          uploadPhaseOf(
            quietFor(Duration.zero),
            reduceTransfer(null, const TransferStarted(64)),
          ),
          isA<UploadSending>(),
        );
        expect(
          uploadPhaseOf(testUpload('up-1', state: 'staged'), null),
          isA<UploadSettled>(),
        );
      });

      test('outlasts the longest a sender goes without the server taking a '
          'byte', () {
        // Four tries of a chunk and the three reads that resync between
        // them, each cut at 40 s, with 1, 2 and 4 s of backoff.
        const resendCycle = Duration(seconds: 4 * 40 + 3 * 40 + 1 + 2 + 4);
        expect(uploadIdleWindow, greaterThan(resendCycle));
      });
    });

    test('a session listed while its create is in flight is starting', () {
      expect(
        uploadPhaseOf(receiving, null, creating: true),
        isA<UploadStarting>().having((p) => p.total, 'total', 256),
      );
      expect(
        uploadPhaseOf(
          testUpload('up-1', sizeBytes: 256, receivedBytes: 64),
          null,
          creating: true,
        ),
        isA<UploadInterrupted>(),
        reason: 'a create in flight has received nothing yet',
      );
    });

    test('a settled session with no transfer reads its state', () {
      for (final state in ['staged', 'imported', 'discarded']) {
        expect(
          uploadPhaseOf(testUpload('up-1', state: state), null),
          isA<UploadSettled>().having((p) => p.state, 'state', state),
        );
      }
    });
  });
}
