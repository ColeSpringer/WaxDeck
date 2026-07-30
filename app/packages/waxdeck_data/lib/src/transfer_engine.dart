/// What a transfer is doing, as the download manager needs to hear it.
///
/// Four states, not the plugin's dozen. The manager's bookkeeping turns on
/// exactly these distinctions: a transfer that finished (its bytes have a
/// path), one that will not finish, one the listener stopped, and one that
/// is only parked. Everything else the engine reports is progress.
enum TransferState {
  complete,
  failed,
  canceled,

  /// Parked and resumable. Terminal for progress but not for the task: it
  /// keeps its id and its mapping, because [TransferEnginePort.resume]
  /// picks the same one back up.
  paused,
}

/// One report about one transfer.
class TransferEvent {
  const TransferEvent({
    required this.taskId,
    this.state,
    this.fraction,
    this.path,
  });

  final String taskId;

  /// Null while the transfer is merely making progress.
  final TransferState? state;

  /// How far along, 0 to 1, on a progress report.
  final double? fraction;

  /// Where the bytes landed. Set on [TransferState.complete] and nowhere
  /// else — resolving it is the engine's job, because it owns the
  /// directory the file went into.
  final String? path;

  bool get isTerminal =>
      state == TransferState.complete ||
      state == TransferState.failed ||
      state == TransferState.canceled;
}

/// One file to fetch.
class TransferRequest {
  const TransferRequest({required this.url, required this.fileName});

  final String url;

  /// The name to store it under. The caller names files by essence hash,
  /// so the same audio is never fetched twice under two names; where they
  /// go is the engine's decision.
  final String fileName;
}

/// The thing that actually moves bytes.
///
/// WaxDeck-owned and narrow: `background_downloader` sits behind it, and
/// the plugin's task objects never cross the line — the engine holds them
/// and hands out ids. That is what makes the manager's bookkeeping
/// testable, and the manager unlinks files.
abstract interface class TransferEnginePort {
  /// Progress and state, for every transfer this engine is running.
  Stream<TransferEvent> get events;

  /// Begins [request] and answers the id it will be reported under.
  Future<String> start(TransferRequest request);

  /// Parks [taskId], keeping the bytes already fetched. Answers whether it
  /// took: a transfer the engine cannot resume (a server with no range
  /// support) stays running rather than being canceled behind the
  /// caller's back.
  Future<bool> pause(String taskId);

  /// Picks a parked transfer back up, from where it stopped if it can and
  /// from the top if it cannot.
  Future<void> resume(String taskId);

  /// Stops these transfers for good.
  Future<void> cancel(List<String> taskIds);

  void dispose();
}
