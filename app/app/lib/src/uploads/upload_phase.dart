import 'package:waxdeck_api/waxdeck_api.dart';

/// What one upload row is doing, from one source: this app's transfer
/// while it runs one for the session, the server's state otherwise.
sealed class UploadPhase {
  const UploadPhase();
}

/// Bytes are going up from here. [sent] is this app's own count, which a
/// list page fetched a moment ago can trail.
final class UploadSending extends UploadPhase {
  const UploadSending({
    required this.sent,
    required this.total,
    this.retrying = false,
  });

  final int sent;
  final int total;

  /// A chunk failed on the wire and is waiting out its backoff.
  final bool retrying;
}

/// A session this client is creating, listed before the create's answer
/// reached it (the server's event travels a connection of its own).
final class UploadStarting extends UploadPhase {
  const UploadStarting(this.total);

  final int total;
}

/// Every byte arrived and the session is being sealed.
final class UploadSealing extends UploadPhase {
  const UploadSealing();
}

/// The transfer here gave up; the source is still held, so Retry can
/// resume it.
final class UploadStalled extends UploadPhase {
  const UploadStalled(this.error);

  final Object error;
}

/// The server is still receiving, nothing here is sending, and it took
/// bytes lately: another device or tab is sending it. [received] is the
/// server's count as last read.
final class UploadElsewhere extends UploadPhase {
  const UploadElsewhere({required this.received, required this.total});

  final int received;
  final int total;
}

/// The server is still receiving, but nothing has sent it bytes for
/// [uploadIdleWindow]: a closed tab, a device that gave up, an app
/// restart.
final class UploadInterrupted extends UploadPhase {
  const UploadInterrupted();
}

/// How long the server can go without taking a byte for a session still
/// receiving while some client is still sending it. A sender gives up a
/// try of a chunk once 30 s pass without progress (none of it sent yet, a
/// send stuck, or no answer after the last of it), and the read that
/// resyncs before each retry within 40 s (a 10 s connect, then 30 s for
/// the answer); a chunk is tried four times with 1, 2 and 4 s of backoff
/// between, so a sender that has not stopped gets a byte to the server at
/// least every 287 s (4 x 40 + 3 x 40 + 7, a try counted at 40 s); six
/// minutes is past that. Judged on the server's own measure of the gap
/// ([UploadSession.idle]) and this device's monotonic clock, so no two
/// clocks are compared.
const uploadIdleWindow = Duration(minutes: 6);

/// The server's own state for a session past receiving.
final class UploadSettled extends UploadPhase {
  const UploadSettled(this.state);

  final String state;
}

/// [sealed] and [refused] are terminal: kept until a page agrees, so a
/// page read before the seal answered cannot contradict it. [stopped]
/// keeps Retry until a page says the session settled or is gone.
enum TransferStatus { running, sealing, stopped, sealed, refused }

/// What this app is doing for one session right now.
final class LiveTransfer {
  const LiveTransfer({
    required this.status,
    required this.sent,
    this.retrying = false,
    this.error,
  });

  final TransferStatus status;
  final int sent;
  final bool retrying;

  /// Why a stopped transfer stopped.
  final Object? error;

  /// Whether the transfer is over and the entry waits only for the list
  /// to catch up.
  bool get finished =>
      status == TransferStatus.sealed || status == TransferStatus.refused;
}

sealed class TransferEvent {
  const TransferEvent();
}

/// A transfer starts or resumes at [from].
final class TransferStarted extends TransferEvent {
  const TransferStarted(this.from);

  final int from;
}

/// The server holds [sent] bytes.
final class ChunkAcked extends TransferEvent {
  const ChunkAcked(this.sent);

  final int sent;
}

final class ChunkRetrying extends TransferEvent {
  const ChunkRetrying();
}

final class Sealing extends TransferEvent {
  const Sealing();
}

final class Stopped extends TransferEvent {
  const Stopped(this.error);

  final Object error;
}

/// The server sealed the session.
final class Sealed extends TransferEvent {
  const Sealed();
}

/// The server refused the seal and ended the session.
final class SealRefused extends TransferEvent {
  const SealRefused();
}

/// Discarded here, or finished and the list agrees: nothing left to show.
final class Ended extends TransferEvent {
  const Ended();
}

/// The one way a [LiveTransfer] changes. Only a start makes one where
/// there is none, so a late answer for a session discarded meanwhile
/// cannot bring it back.
LiveTransfer? reduceTransfer(
  LiveTransfer? current,
  TransferEvent event,
) => switch (event) {
  TransferStarted(:final from) => LiveTransfer(
    status: TransferStatus.running,
    sent: from,
  ),
  Ended() => null,
  _ when current == null => null,
  ChunkAcked(:final sent) => LiveTransfer(
    status: TransferStatus.running,
    sent: sent,
  ),
  ChunkRetrying() => LiveTransfer(
    status: TransferStatus.running,
    sent: current.sent,
    retrying: true,
  ),
  Sealing() => LiveTransfer(status: TransferStatus.sealing, sent: current.sent),
  Stopped(:final error) => LiveTransfer(
    status: TransferStatus.stopped,
    sent: current.sent,
    error: error,
  ),
  Sealed() => LiveTransfer(status: TransferStatus.sealed, sent: current.sent),
  SealRefused() => LiveTransfer(
    status: TransferStatus.refused,
    sent: current.sent,
  ),
};

/// [creating] is whether a create this client has in flight may have
/// opened [session], which a refresh can list before the create answers.
/// A session nothing here sends is someone else's while the server, when
/// it was read, had gone less than [uploadIdleWindow] without taking a
/// byte for it: judged as of the read, so a row turns Interrupted only once
/// a fresh read says so.
UploadPhase uploadPhaseOf(
  UploadSession session,
  LiveTransfer? live, {
  bool creating = false,
}) => switch (live) {
  LiveTransfer(status: TransferStatus.running, :final sent, :final retrying) =>
    UploadSending(sent: sent, total: session.sizeBytes, retrying: retrying),
  LiveTransfer(status: TransferStatus.sealing) => const UploadSealing(),
  LiveTransfer(status: TransferStatus.sealed)
      when session.state == 'receiving' =>
    const UploadSealing(),
  LiveTransfer(status: TransferStatus.refused)
      when session.state == 'receiving' =>
    const UploadSettled('discarded'),
  LiveTransfer(status: TransferStatus.stopped, :final error?)
      when session.state == 'receiving' =>
    UploadStalled(error),
  null
      when creating &&
          session.state == 'receiving' &&
          session.receivedBytes == 0 =>
    UploadStarting(session.sizeBytes),
  null when session.state == 'receiving' && session.idle < uploadIdleWindow =>
    UploadElsewhere(received: session.receivedBytes, total: session.sizeBytes),
  _ =>
    session.state == 'receiving'
        ? const UploadInterrupted()
        : UploadSettled(session.state),
};
