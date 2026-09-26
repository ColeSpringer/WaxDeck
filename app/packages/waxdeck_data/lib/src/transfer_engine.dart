/// What a transfer is doing, as the download manager needs to hear it:
/// the few distinctions its bookkeeping turns on, not the plugin's dozen.
/// Everything else the engine reports is progress.
enum TransferState {
  complete,
  failed,
  canceled,

  /// Paused and resumable under the same id.
  paused,

  /// Moving bytes again.
  running,
}

/// One report about one transfer.
class TransferEvent {
  const TransferEvent({
    required this.taskId,
    this.state,
    this.fraction,
    this.path,
    this.pid,
    this.fileName,
    this.httpStatus,
  });

  final String taskId;

  /// Null while the transfer is merely making progress.
  final TransferState? state;

  /// How far along, 0 to 1, on a progress report.
  final double? fraction;

  /// Where the bytes landed, on [TransferState.complete]: the engine owns
  /// the directory, so it resolves the path.
  final String? path;

  /// The item and file the transfer was started for, from the task's own
  /// record: what places an event the manager holds no mapping for.
  final String? pid;
  final String? fileName;

  /// The server's status on a failure it answered, such as the 401 of a
  /// URL that has expired.
  final int? httpStatus;

  bool get isTerminal =>
      state == TransferState.complete ||
      state == TransferState.failed ||
      state == TransferState.canceled;
}

/// One file to fetch.
class TransferRequest {
  const TransferRequest({
    required this.url,
    required this.fileName,
    required this.pid,
    required this.group,
    this.displayName = '',
    this.staleAt,
  });

  final String url;

  /// When [url] stops working, on this device's clock.
  final DateTime? staleAt;

  /// The item this file belongs to.
  final String pid;

  /// The notification group it posts under; see [TransferGroup].
  final String group;

  /// The name to store it under. The caller names files by essence hash,
  /// so the same audio is never fetched twice under two names; where they
  /// go is the engine's decision.
  final String fileName;

  /// What its notification is titled.
  final String displayName;
}

/// How the transfers of one notification group are announced.
class TransferGroup {
  const TransferGroup({
    required this.id,
    required this.copy,
    this.announceDone = true,
  });

  final String id;
  final DownloadCopy copy;

  /// Whether a finished transfer says so: only an item's last file does.
  final bool announceDone;
}

/// A download notice's words in the app's language, around placeholders
/// the engine fills in.
class DownloadCopy {
  const DownloadCopy({
    required this.downloading,
    required this.downloaded,
    required this.failed,
    required this.part,
  });

  /// While a file runs, around its percentage.
  final String Function(String progress) downloading;

  final String downloaded;
  final String failed;

  /// One file of several, titled by its item: "Title (3 of 20)".
  final String Function(String title, int number, int total) part;
}

/// A transfer a previous run started, as the plugin's own records have it.
class TrackedTransfer {
  const TrackedTransfer({
    required this.taskId,
    required this.pid,
    required this.fileName,
    this.state,
    this.path,
    this.staleAt,
  });

  final String taskId;
  final String pid;
  final String fileName;

  /// When its URL stops working, where the record says.
  final DateTime? staleAt;

  /// Null while it runs or waits to; [TransferState.paused] or
  /// [TransferState.complete] otherwise.
  final TransferState? state;

  /// Where a complete transfer's bytes are.
  final String? path;
}

/// Whether downloads may post notifications, as the platform answers.
enum NotificationPermission {
  granted,
  undetermined,

  /// Refused, and the platform lets the app say why before asking again.
  deniedExplainable,
  denied,
}

/// Whether transfers may move bytes now: the app's wifi-only hold, since
/// the plugin's own flag came to mean the Wi-Fi transport and held Ethernet.
abstract interface class TransferGate {
  Future<bool> isOpen();

  /// Each change of [isOpen]'s answer.
  Stream<bool> get changes;
}

/// A gate that never holds anything back.
class OpenGate implements TransferGate {
  const OpenGate();

  @override
  Future<bool> isOpen() async => true;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}

/// The thing that actually moves bytes, with `background_downloader`
/// behind it: the plugin's tasks never cross the line, the engine hands
/// out ids, and that is what makes the manager testable.
abstract interface class TransferEnginePort {
  /// Progress and state, for every transfer this engine is running.
  Stream<TransferEvent> get events;

  /// Transfers a previous run left in the plugin's records, read before
  /// [recover] replays them.
  Future<List<TrackedTransfer>> trackedTransfers();

  /// Replays what the platform did while the app was away, and reschedules
  /// what it killed.
  Future<void> recover();

  /// Says how [group]'s transfers are announced, before any of them start.
  Future<void> describe(TransferGroup group);

  /// Begins [request] and answers the id it will be reported under. Throws
  /// when the platform refuses it.
  Future<String> start(TransferRequest request);

  /// Pauses [taskId], keeping the bytes already fetched. Answers false when
  /// there was nothing running to pause.
  Future<bool> pause(String taskId);

  /// Picks a paused or failed transfer back up, from where it stopped if it
  /// can: on [url] when given, the same file at a fresh address.
  Future<void> resume(String taskId, {String? url, DateTime? staleAt});

  /// Stops these transfers for good and forgets their records.
  Future<void> cancel(List<String> taskIds);

  Future<NotificationPermission> notificationPermission();

  Future<NotificationPermission> requestNotificationPermission();

  void dispose();
}
