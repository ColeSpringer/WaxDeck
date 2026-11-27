import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';
import '../sync/refresh_in_place.dart';
import 'file_picker_port.dart';
import 'local_file_reader.dart';
import 'upload_phase.dart';

/// The upload-format sets in force: the server-reported ones where the
/// health payload carries them, the hardcoded mirrors where a server
/// predates the fields. A failed read throws through - consumers go
/// through [resolveUploadFormats], which answers the mirror for that
/// one ask and retires the failure so the next ask fetches fresh,
/// rather than memoizing a network blip as the mirror for the rest of
/// the session. retry: null because the resolver's invalidate is the
/// retry: the ladder would hold `.future` unsettled for seconds while
/// every ask times out against it.
final uploadFormatSetsProvider = FutureProvider<UploadFormatSets>(
  retry: (_, _) => null,
  (ref) async {
    // The client, not an account's view: the same for every account.
    final health = await ref.watch(apiClientProvider).health();
    return UploadFormatSets(
      accepted: switch (health.uploadFormats) {
        final formats? when formats.isNotEmpty => formats.toSet(),
        _ => kAcceptedAudioExtensions,
      },
      rejected: switch (health.rejectedFormats) {
        final formats? when formats.isNotEmpty => formats.toSet(),
        _ => kRejectedAudioExtensions,
      },
    );
  },
);

/// The libraries this account may file an upload or an acquisition
/// under.
///
/// Empty is the honest answer for three different servers: one too old
/// for the route, one that refused the read, and one where this account
/// has nothing writable. All three want the same thing from the client -
/// no picker, and the server routing as it always did - so the failure
/// is degraded here rather than surfaced.
///
/// autoDispose because the picker is the only reader and a dialog is a
/// short life; `retry: null` because a failure here is final by
/// construction (there is nothing to show either way) and the backoff
/// would hold `.future` unsettled while a dialog waits on it.
final uploadTargetsProvider = FutureProvider.autoDispose<List<UploadTarget>>(
  retry: (_, _) => null,
  (ref) async {
    try {
      return await ref.watch(repositoryProvider).listUploadTargets();
    } on WaxDeckApiException {
      return const <UploadTarget>[];
    }
  },
);

/// The candidates for one media type, in the order the picker offers
/// them. A single candidate is not a choice, which is what the picker
/// keys its own visibility on.
List<UploadTarget> uploadTargetsFor(
  List<UploadTarget> targets,
  MediaType mediaType,
) => targets.where((t) => t.mediaTypes.contains(mediaType)).toList();

/// How long a pick or drop waits on the health read before filtering
/// with the mirror. Short on purpose: on the web the picker dialog
/// must open inside the tap's transient user activation, and a wait
/// longer than that budget produces no dialog at all.
const _formatsWait = Duration(seconds: 2);

/// The sets for one pick or drop, bounded. Still loading past the
/// budget answers the mirror and leaves the fetch to finish for the
/// next ask; a settled failure answers the mirror and invalidates, so
/// the next ask retries instead of reading the memoized miss.
Future<UploadFormatSets> resolveUploadFormats(WidgetRef ref) async {
  try {
    return await ref
        .read(uploadFormatSetsProvider.future)
        .timeout(_formatsWait);
  } on TimeoutException {
    return const UploadFormatSets();
  } on Object {
    ref.invalidate(uploadFormatSetsProvider);
    return const UploadFormatSets();
  }
}

/// The sets for a drop zone, resolved when a drop lands rather than at
/// build - the zone never rebuilds for the health read, and a drop on
/// a cold start waits the read out instead of filtering with a guess.
Future<UploadFormatSets> Function() dropFormats(WidgetRef ref) =>
    () => resolveUploadFormats(ref);

/// What this app is doing for each session it transfers, keyed by
/// upload id. Container-scoped, so the session list rebuilding on an
/// event cannot touch it; [LiveTransfers.apply] is its only writer.
final liveTransfersProvider =
    NotifierProvider<LiveTransfers, Map<String, LiveTransfer>>(
      LiveTransfers.new,
    );

class LiveTransfers extends Notifier<Map<String, LiveTransfer>> {
  @override
  Map<String, LiveTransfer> build() => const {};

  void apply(String uploadId, TransferEvent event) {
    final next = reduceTransfer(state[uploadId], event);
    if (next == null && !state.containsKey(uploadId)) return;
    state = {
      for (final entry in state.entries)
        if (entry.key != uploadId) entry.key: entry.value,
      uploadId: ?next,
    };
  }
}

/// The creates this client has in flight, and the sessions it had listed
/// when the first of them began: a refresh can list a session before its
/// create answers, and only one this client had not listed by then can be
/// such a session.
final class UploadCreates {
  const UploadCreates({this.inFlight = 0, this.listedBefore = const {}});

  final int inFlight;
  final Set<String> listedBefore;

  /// Whether a create in flight here may have opened [uploadId].
  bool mayHaveOpened(String uploadId) =>
      inFlight > 0 && !listedBefore.contains(uploadId);
}

final uploadCreatesProvider =
    NotifierProvider<UploadCreatesInFlight, UploadCreates>(
      UploadCreatesInFlight.new,
    );

class UploadCreatesInFlight extends Notifier<UploadCreates> {
  @override
  UploadCreates build() => const UploadCreates();

  /// A create begins; the first of a run takes [listed] as what this
  /// client had listed before it.
  void begin(Iterable<String> listed) => state = UploadCreates(
    inFlight: state.inFlight + 1,
    listedBefore: state.inFlight == 0 ? {...listed} : state.listedBefore,
  );

  void end() {
    if (!ref.mounted) return;
    state = state.inFlight <= 1
        ? const UploadCreates()
        : UploadCreates(
            inFlight: state.inFlight - 1,
            listedBefore: state.listedBefore,
          );
  }
}

/// How long a run of creates waits on the uploads list before its first.
const _listedWait = Duration(seconds: 5);

/// What a run of creates waits on before its first: the uploads list read
/// to the end of its first page, since the first create takes what is
/// listed then as the sessions that are not its own ([UploadCreates]). A
/// run started where the list never loaded (the add sheet, a share) would
/// otherwise take an old empty session listed meanwhile for one of its
/// own. A list not read within [_listedWait] (failing, or in its retry
/// backoff) leaves the run to what is held.
Future<void> untilUploadsListed(Future<UploadsState> listed) async {
  try {
    await listed.timeout(_listedWait);
  } on Object {
    // Unread in time: the run starts from what is held.
  }
}

/// How long a chunk that failed on the wire waits before its [attempt]
/// (from 1) goes: 1 s, 2 s, 4 s. A provider so tests can make it zero.
final uploadRetryBackoffProvider = Provider<Duration Function(int attempt)>(
  (_) =>
      (attempt) => Duration(seconds: 1 << (attempt - 1)),
);

/// Local file paths retained for resuming a failed path-backed
/// transfer, keyed by upload id. Paths, never bytes: an audiobook-sized
/// share must not live in heap memory for the life of a retry
/// affordance.
final _retryPathsProvider = Provider<Map<String, String>>((_) => {});

/// Windowed read accessors retained for resuming a failed
/// reader-backed transfer (web picks and drops), keyed by upload id.
/// The accessor holds a browser file handle, not bytes.
final _retryReadersProvider =
    Provider<Map<String, Stream<List<int>> Function([int? start, int? end])>>(
      (_) => {},
    );

/// Accumulated pages of the caller's upload sessions and the caller's
/// quota snapshot.
class UploadsState {
  const UploadsState({
    required this.uploads,
    this.nextCursor,
    this.quota,
    this.loadingMore = false,
    this.readAt = const {},
  });

  final List<UploadSession> uploads;
  final String? nextCursor;

  /// The caller's own allowance, from the freshest page.
  final UploadQuota? quota;

  final bool loadingMore;

  /// When this client last read each row, by upload id, on its monotonic
  /// clock ([monotonicClockProvider]): a row's [UploadSession.idle] was the
  /// server's as of then, which is when its window is counted from.
  final Map<String, Duration> readAt;

  bool get hasMore => nextCursor != null;

  /// [nextCursor] is a getter because null is a cursor's own value: the
  /// end of the list.
  UploadsState copyWith({
    List<UploadSession>? uploads,
    String? Function()? nextCursor,
    UploadQuota? quota,
    bool? loadingMore,
    Map<String, Duration>? readAt,
  }) => UploadsState(
    uploads: uploads ?? this.uploads,
    nextCursor: nextCursor == null ? this.nextCursor : nextCursor(),
    quota: quota ?? this.quota,
    loadingMore: loadingMore ?? this.loadingMore,
    readAt: readAt ?? this.readAt,
  );
}

/// One listed session, with when this client read it.
typedef ListedUpload = ({UploadSession session, Duration readAt});

/// Lists upload sessions, refreshed in place (a sweep reads again what
/// is loaded, where the list stands), and drives the create, chunk,
/// complete flow.
class UploadsController extends AsyncNotifier<UploadsState>
    with RefreshedInPlace<ListedUpload, UploadsState> {
  static const pageSize = 50;

  /// Chunk size for the resumable transfer loop: 1 MiB. Also the most
  /// of any file that sits in memory at once - sources are lazy
  /// references windowed through here.
  static const chunkBytes = 1024 * 1024;

  /// The smallest a chunk shrinks to on a link that cannot move a whole
  /// one inside the stall: the piece the client hands its transport.
  static const minChunkBytes = 64 * 1024;

  /// Tries a chunk gets after a transient failure before the transfer
  /// stops.
  static const chunkRetries = 3;

  /// The send this client runs for each upload. A discard takes it away
  /// before its delete goes, which stops that send at its next step.
  final _sends = <String, Object>{};

  /// The caller's own allowance, from the freshest page read.
  UploadQuota? _quota;

  /// What the server answered, read by read, until the list shows it:
  /// the transfers it has caught up with are retired then, and not
  /// before, so no reader sees an entry gone while the old row shows.
  /// Only these rows: a row held may be this client's own copy.
  final _answered = <({List<UploadSession> rows, bool complete})>[];

  @override
  ProviderBase<Object?> get self => uploadsProvider;

  @override
  int get pageRows => pageSize;

  @override
  int? get walkLimit => 1;

  @override
  Object rowKey(ListedUpload row) => row.session.id;

  @override
  UploadsState shape(
    PagedRows<ListedUpload> held, {
    required bool loadingMore,
  }) => UploadsState(
    uploads: [for (final row in held.rows) row.session],
    nextCursor: held.nextCursor,
    quota: _quota,
    loadingMore: loadingMore,
    readAt: {for (final row in held.rows) row.session.id: row.readAt},
  );

  @override
  void startingOver() {
    _quota = null;
    _answered.clear();
  }

  @override
  Future<PagedRows<ListedUpload>> readRows({
    required int want,
    String? from,
    int? maxPages,
    bool Function()? stop,
  }) async {
    final repository = ref.read(repositoryProvider);
    final clock = ref.read(monotonicClockProvider);
    // A read the listing was replaced under (another account's, a list
    // started over) records nothing: its rows are dropped, and so is what
    // it says beside them.
    bool stands() => stop?.call() != true;
    final read = await walkRows<ListedUpload>(
      (cursor) async {
        final page = await repository.listUploads(
          cursor: cursor,
          limit: pageSize,
        );
        if (stands()) _quota = page.quota ?? _quota;
        final readAt = clock();
        return (
          rows: [
            for (final session in page.uploads)
              (session: session, readAt: readAt),
          ],
          nextCursor: page.nextCursor,
        );
      },
      want: want,
      from: from,
      maxPages: maxPages,
      stop: stop,
    );
    if (stands()) {
      _answered.add((
        rows: [for (final row in read.rows) row.session],
        complete: from == null && read.nextCursor == null,
      ));
    }
    return read;
  }

  @override
  Future<UploadsState> build() {
    // Keyed on the account: the repository moves only with the server,
    // and the next account starts from its own first page.
    final account = ref.watch(signedInAccountProvider);
    final repository = ref.watch(repositoryProvider);
    listenSelf((_, next) => _retireShown(next.value));
    return buildInPlace(source: (account, repository));
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached.
  Future<void> loadMore() => loadMoreInPlace();

  /// Retires what the reads the list now shows have caught up with, and
  /// lets go of every read up to the newest of them.
  void _retireShown(UploadsState? shown) {
    if (shown == null || _answered.isEmpty) return;
    final listed = Set<UploadSession>.identity()..addAll(shown.uploads);
    var through = -1;
    for (final (at, read) in _answered.indexed) {
      final rows = [
        for (final session in read.rows)
          if (listed.contains(session)) session,
      ];
      final empty = read.rows.isEmpty && read.complete && shown.uploads.isEmpty;
      if (rows.isEmpty && !empty) continue;
      through = at;
      _retireCaughtUp(
        rows,
        complete: read.complete && rows.length == read.rows.length,
      );
    }
    if (through >= 0) _answered.removeRange(0, through + 1);
  }

  /// Uploads one picked file, dispatching on how its bytes are
  /// reachable: path-backed sources stream from disk, reader-backed
  /// ones window through their lazy accessor. [batchId] and
  /// [batchPath] join the session to a batch; [identify] is the
  /// submission's identification choice, which a batch overrides with
  /// its own; [acceptBestMatch] likewise, and only music identified can
  /// act on it. Answers false for one discarded while it was sent, which
  /// is no failure and was not uploaded. [through] is the repository of
  /// the run it belongs to, whose account every call of it is made for;
  /// without one, the signed-in account's.
  Future<bool> uploadPicked(
    PickedAudioFile file, {
    required String mediaType,
    String? libraryPid,
    String? batchId,
    bool? identify,
    bool? acceptBestMatch,
    WaxDeckRepository? through,
  }) async {
    final path = file.path;
    if (path != null) {
      return uploadFromPath(
        fileName: file.name,
        path: path,
        mediaType: mediaType,
        libraryPid: libraryPid,
        batchId: batchId,
        batchPath: file.relativeDir,
        sizeBytes: file.size,
        identify: identify,
        acceptBestMatch: acceptBestMatch,
        through: through,
      );
    }
    final openRead = file.openRead;
    if (openRead == null) {
      throw StateError('picked file carries neither a path nor a reader');
    }
    return uploadFromReader(
      fileName: file.name,
      size: file.size,
      openRead: openRead,
      mediaType: mediaType,
      libraryPid: libraryPid,
      batchId: batchId,
      batchPath: file.relativeDir,
      identify: identify,
      acceptBestMatch: acceptBestMatch,
      through: through,
    );
  }

  /// Opens a session for one local file and streams it up in
  /// [chunkBytes] windows read straight from disk, so the file never
  /// sits whole in memory. A transfer that gives up stops in
  /// [liveTransfersProvider] and keeps the path for [retry]; the create
  /// failure itself propagates to the caller since no row exists yet.
  /// [sizeBytes] skips a redundant stat when the pick already measured
  /// the file. Answers false for one discarded while it was sent.
  /// [through] is [uploadPicked]'s.
  Future<bool> uploadFromPath({
    required String fileName,
    required String path,
    required String mediaType,
    String? libraryPid,
    String? batchId,
    String? batchPath,
    int? sizeBytes,
    bool? identify,
    bool? acceptBestMatch,
    WaxDeckRepository? through,
  }) async {
    final WaxDeckRepository repository =
        through ?? ref.read(repositoryProvider);
    final size = sizeBytes ?? await localFileLength(path);
    final session = await _open(
      repository,
      fileName: fileName,
      size: size,
      mediaType: mediaType,
      libraryPid: libraryPid,
      batchId: batchId,
      batchPath: batchPath,
      identify: identify,
      acceptBestMatch: acceptBestMatch,
    );
    _upsert(session);
    ref.read(_retryPathsProvider)[session.id] = path;
    return _asSend(
      session.id,
      (send) => _transferFromPath(
        repository,
        session.id,
        path,
        size,
        from: 0,
        send: send,
      ),
    );
  }

  /// Opens a session for a reader-backed source (web picks and drops)
  /// and streams it up in [chunkBytes] windows pulled lazily from the
  /// accessor - only the window in flight materializes. Failure
  /// handling matches [uploadFromPath], with the accessor retained
  /// for [retry]. [through] is [uploadPicked]'s.
  Future<bool> uploadFromReader({
    required String fileName,
    required int size,
    required Stream<List<int>> Function([int? start, int? end]) openRead,
    required String mediaType,
    String? libraryPid,
    String? batchId,
    String? batchPath,
    bool? identify,
    bool? acceptBestMatch,
    WaxDeckRepository? through,
  }) async {
    final WaxDeckRepository repository =
        through ?? ref.read(repositoryProvider);
    final session = await _open(
      repository,
      fileName: fileName,
      size: size,
      mediaType: mediaType,
      libraryPid: libraryPid,
      batchId: batchId,
      batchPath: batchPath,
      identify: identify,
      acceptBestMatch: acceptBestMatch,
    );
    _upsert(session);
    ref.read(_retryReadersProvider)[session.id] = openRead;
    return _asSend(
      session.id,
      (send) => _transferFromReader(
        repository,
        session.id,
        openRead,
        size,
        from: 0,
        send: send,
      ),
    );
  }

  /// Creates a session, counted in [uploadCreatesProvider] until its
  /// transfer has started: before that the row has no live entry, and the
  /// server's event for the create can list it first.
  Future<UploadSession> _open(
    WaxDeckRepository repository, {
    required String fileName,
    required int size,
    required String mediaType,
    required String? libraryPid,
    required String? batchId,
    required String? batchPath,
    required bool? identify,
    required bool? acceptBestMatch,
  }) async {
    // What is listed now: the caller that started the run waited for the
    // list ([untilUploadsListed]).
    final creates = ref.read(uploadCreatesProvider.notifier)
      ..begin([
        for (final u in state.value?.uploads ?? const <UploadSession>[]) u.id,
      ]);
    try {
      final session = await repository.createUpload(
        fileName: fileName,
        sizeBytes: size,
        mediaType: mediaType,
        libraryPid: libraryPid,
        batchId: batchId,
        batchPath: _cleanBatchPath(batchId, batchPath),
        identify: identify,
        acceptBestMatch: acceptBestMatch,
      );
      _emit(session.id, const TransferStarted(0));
      return session;
    } finally {
      // Whatever this controller's state does meanwhile: a count left up
      // would keep every run after this one from taking its own snapshot.
      creates.end();
    }
  }

  /// batchPath only travels with a batch, and an empty hint rides as
  /// absent.
  static String? _cleanBatchPath(String? batchId, String? batchPath) {
    if (batchId == null || batchPath == null || batchPath.isEmpty) return null;
    return batchPath;
  }

  /// Resumes a stopped transfer from what the server already received.
  /// Does nothing while one runs for the session (a second loop would
  /// race the first for the same offsets) or once it finished. A session
  /// that settled meanwhile (sealed from another device, discarded,
  /// expired) has nothing left to send: its entry and source go, and its
  /// row reads what the server says.
  Future<void> retry(String uploadId) async {
    final live = ref.read(liveTransfersProvider)[uploadId];
    if (live != null && live.status != TransferStatus.stopped) return;
    final path = ref.read(_retryPathsProvider)[uploadId];
    final openRead = ref.read(_retryReadersProvider)[uploadId];
    if (path == null && openRead == null) return;
    // Running before the first await, so a second tap meanwhile is
    // refused too.
    await _asSend(uploadId, (send) async {
      _emit(uploadId, TransferStarted(live?.sent ?? 0));
      final UploadSession session;
      final int size;
      final repository = ref.read(repositoryProvider);
      try {
        session = await repository.getUpload(uploadId);
        if (session.state != 'receiving') {
          _forgetSource(uploadId);
          _emit(uploadId, const Ended());
          _upsert(session);
          return false;
        }
        size = path != null ? await localFileLength(path) : session.sizeBytes;
      } on WaxDeckApiException catch (e) {
        if (!_sending(uploadId, send)) return false;
        if (e.code == 'not-found') {
          // Gone from the server: nothing is left to send it to, so the
          // entry, its source and its row go, and the caller says why.
          _forgetSource(uploadId);
          _emit(uploadId, const Ended());
          _drop(uploadId);
        } else {
          _emit(uploadId, Stopped(e));
        }
        rethrow;
      } catch (e) {
        if (!_sending(uploadId, send)) return false;
        _emit(uploadId, Stopped(e));
        rethrow;
      }
      // Discarded during the reads: a loop now would start it again.
      if (!_sending(uploadId, send)) return false;
      return path != null
          ? _transferFromPath(
              repository,
              uploadId,
              path,
              size,
              from: session.receivedBytes,
              send: send,
            )
          : _transferFromReader(
              repository,
              uploadId,
              openRead!,
              size,
              from: session.receivedBytes,
              send: send,
            );
    });
  }

  /// Discards a session and its staged bytes. A send of it here stops
  /// before the delete goes, so what that send meets meanwhile is no
  /// failure; a delete that fails leaves it stopped, for Retry.
  Future<void> discard(String uploadId) async {
    _sends.remove(uploadId);
    try {
      await ref.read(repositoryProvider).deleteUpload(uploadId);
    } on Object catch (e) {
      if (ref.mounted &&
          ref.read(liveTransfersProvider)[uploadId]?.status ==
              TransferStatus.running) {
        _emit(uploadId, Stopped(e));
      }
      rethrow;
    }
    _forgetSource(uploadId);
    _emit(uploadId, const Ended());
    if (!ref.mounted) return;
    ref.invalidateSelf();
  }

  Future<bool> _transferFromPath(
    WaxDeckRepository repository,
    String uploadId,
    String path,
    int size, {
    required int from,
    required Object send,
  }) => _transferWindows(
    repository,
    uploadId,
    size,
    from: from,
    send: send,
    read: (offset, want) => readLocalFileRange(path, offset, want),
    onSealed: () => ref.read(_retryPathsProvider).remove(uploadId),
  );

  Future<bool> _transferFromReader(
    WaxDeckRepository repository,
    String uploadId,
    Stream<List<int>> Function([int? start, int? end]) openRead,
    int size, {
    required int from,
    required Object send,
  }) => _transferWindows(
    repository,
    uploadId,
    size,
    from: from,
    send: send,
    read: (offset, want) => _collectRange(openRead, offset, offset + want),
    onSealed: () => ref.read(_retryReadersProvider).remove(uploadId),
  );

  /// The shared transfer loop: reads [chunkBytes] windows from the
  /// source (smaller once one could not move inside the stall), appends
  /// each at its offset, then seals the session. A chunk that fails on
  /// the wire is tried again [chunkRetries] times, each after asking the
  /// server where it stands; the transfer stops only once those are
  /// spent or the server refuses outright. A discard takes its [send]
  /// away, and the loop stops with it: nothing more is sent or applied,
  /// and it answers false.
  Future<bool> _transferWindows(
    WaxDeckRepository repository,
    String uploadId,
    int size, {
    required int from,
    required Future<Uint8List> Function(int offset, int want) read,
    required void Function() onSealed,
    required Object send,
  }) async {
    bool sending() => _sending(uploadId, send);
    final backoff = ref.read(uploadRetryBackoffProvider);
    final clock = ref.read(monotonicClockProvider);
    _emit(uploadId, TransferStarted(from));
    var sealing = false;
    var sealFrom = Duration.zero;
    try {
      var offset = from;
      var chunkSize = chunkBytes;
      var failures = 0;
      var conflictResynced = false;
      var resync = false;
      while (offset < size) {
        try {
          if (resync) {
            // Covers a chunk the server stored whose answer was lost,
            // which resending at the old offset would turn into a
            // conflict.
            offset = (await repository.getUpload(uploadId)).receivedBytes;
            resync = false;
            if (offset >= size) break;
          }
          final want = (size - offset).clamp(0, chunkSize);
          final window = await read(offset, want);
          if (window.isEmpty) {
            throw StateError('the picked file shrank mid-upload');
          }
          if (!sending()) return false;
          final session = await repository.putUploadData(
            uploadId,
            offset: offset,
            bytes: window,
          );
          if (!sending()) return false;
          offset += window.length;
          failures = 0;
          conflictResynced = false;
          _upsert(session);
          _emit(uploadId, ChunkAcked(offset));
        } catch (e) {
          // A send a discard took away reports nothing more, a try neither.
          if (!sending()) return false;
          if (_transient(e) && failures < chunkRetries) {
            failures++;
            // Cut for not moving: the link cannot drain this much inside
            // the stall, and the stall's check queues behind it. Smaller
            // from here on.
            if (e is WaxDeckApiException && e.code == 'transport-timeout') {
              chunkSize = (chunkSize ~/ 2).clamp(minChunkBytes, chunkBytes);
            }
            _emit(uploadId, const ChunkRetrying());
            await Future<void>.delayed(backoff(failures));
            resync = true;
            continue;
          }
          if (e is WaxDeckApiException &&
              e.code == 'conflict' &&
              !conflictResynced) {
            conflictResynced = true;
            resync = true;
            continue;
          }
          rethrow;
        }
      }
      if (!sending()) return false;
      sealing = true;
      _emit(uploadId, const Sealing());
      sealFrom = clock();
      final sealed = await repository.completeUpload(uploadId);
      onSealed();
      _upsert(sealed);
      _emit(uploadId, const Sealed());
      return true;
    } catch (e) {
      if (!sending()) return false;
      // A seal the server refused for bytes no retry can mend (they do
      // not read as audio, or miss their hash) ended the session there,
      // so the row goes rather than offering a Retry that cannot work.
      // The refusal's reason says so; without one the session is asked,
      // and one that sealed (its answer lost on the wire) or is still
      // being sealed there is no failure.
      if (sealing && e is WaxDeckApiException) {
        final after = _endsSession(e)
            ? (gone: true, settled: null)
            : await _afterSeal(
                repository,
                uploadId,
                backoff: backoff,
                clock: clock,
                until: sealFrom + WaxDeckClient.longOperationBudget,
                sending: sending,
              );
        if (!sending()) return false;
        if (after.settled case final session?) {
          onSealed();
          _upsert(session);
          _emit(uploadId, const Sealed());
          return true;
        }
        if (after.gone) {
          onSealed();
          _drop(uploadId);
          _emit(uploadId, const SealRefused());
          rethrow;
        }
      }
      // Stopped whatever else threw - a server refusal, but also a
      // source that stopped answering (a SAF document moved
      // mid-transfer arrives as a PlatformException, a deleted local
      // file as a FileSystemException, a shrunk one as the StateError
      // above). Otherwise the row sits in "uploading" forever with no
      // Retry.
      _emit(uploadId, Stopped(e));
      rethrow;
    }
  }

  /// Whether a chunk failure is the wire rather than an answer: no
  /// response, a server error, or a busy catalog. A request refused unsent
  /// for an account this client no longer holds is none: it can never go,
  /// so the row stops as failed, and leaves with that account's list.
  static bool _transient(Object e) => switch (e) {
    AccountNotHeldException() => false,
    WaxDeckApiException(statusCode: null) => true,
    WaxDeckApiException(statusCode: final status?) when status >= 500 => true,
    WaxDeckApiException(:final code) when code == 'catalog-busy' => true,
    _ => false,
  };

  /// Retires the finished and stopped transfers a fresh page has caught
  /// up with: listed past receiving, or gone from a list read to its end.
  /// A page that still says receiving was read before the seal answered,
  /// or leaves a stopped transfer its Retry. A stopped one that goes takes
  /// its source with it.
  void _retireCaughtUp(List<UploadSession> listed, {bool complete = false}) {
    if (!ref.mounted) return;
    final states = {for (final u in listed) u.id: u.state};
    for (final MapEntry(key: id, value: live)
        in ref.read(liveTransfersProvider).entries) {
      final stopped = live.status == TransferStatus.stopped;
      if (!live.finished && !stopped) continue;
      final state = states[id];
      if (state == null ? complete : state != 'receiving') {
        if (stopped) _forgetSource(id);
        _emit(id, const Ended());
      }
    }
  }

  /// Lets go of what [retry] would send [uploadId] from.
  void _forgetSource(String uploadId) {
    if (!ref.mounted) return;
    ref.read(_retryPathsProvider).remove(uploadId);
    ref.read(_retryReadersProvider).remove(uploadId);
  }

  void _emit(String uploadId, TransferEvent event) {
    if (!ref.mounted) return;
    ref.read(liveTransfersProvider.notifier).apply(uploadId, event);
  }

  /// Whether a refused seal's reason is one that ends the session.
  static bool _endsSession(WaxDeckApiException e) =>
      switch (e.params?['reason']) {
        'unreadable' || 'checksum-mismatch' => true,
        _ => false,
      };

  /// Where a session stands after a seal that did not answer success:
  /// [gone] once the server no longer holds it, [settled] once it is past
  /// receiving (the seal ran), neither once it waits for a seal or refuses
  /// the read. One the server is still sealing (every byte in, idle zero,
  /// which holds only while a live seal holds the session), or that the
  /// wire keeps from answering, is read again after a wait until [until],
  /// the end of the budget the seal had while its caller was connected.
  /// The row says the server cannot be reached from the first read the
  /// wire fails to the first answer.
  Future<({bool gone, UploadSession? settled})> _afterSeal(
    WaxDeckRepository repository,
    String uploadId, {
    required Duration Function(int attempt) backoff,
    required Duration Function() clock,
    required Duration until,
    required bool Function() sending,
  }) async {
    var unreachable = false;
    void sayUnreachable(bool now) {
      if (now == unreachable || !sending()) return;
      unreachable = now;
      _emit(uploadId, now ? const SealUnreachable() : const Sealing());
    }

    for (var check = 1; ; check++) {
      try {
        final session = await repository.getUpload(uploadId);
        sayUnreachable(false);
        if (session.state != 'receiving') {
          return (gone: false, settled: session);
        }
        final sealingThere =
            session.receivedBytes == session.sizeBytes &&
            session.idle == Duration.zero;
        if (!sealingThere) return (gone: false, settled: null);
      } on WaxDeckApiException catch (e) {
        if (e.code == 'not-found') return (gone: true, settled: null);
        if (!_transient(e)) return (gone: false, settled: null);
        sayUnreachable(true);
      }
      if (clock() >= until || !sending()) {
        return (gone: false, settled: null);
      }
      await Future<void>.delayed(backoff(check.clamp(1, chunkRetries)));
    }
  }

  /// Runs [body] as this client's send of [uploadId]: taken before [body]
  /// starts, let go however it ends, and away early only by a discard.
  Future<bool> _asSend(
    String uploadId,
    Future<bool> Function(Object send) body,
  ) async {
    final send = _sends[uploadId] = Object();
    try {
      return await body(send);
    } finally {
      if (identical(_sends[uploadId], send)) _sends.remove(uploadId);
    }
  }

  /// Whether [send] is still this client's send of [uploadId]: a discard
  /// takes it away.
  bool _sending(String uploadId, Object send) =>
      ref.mounted &&
      identical(_sends[uploadId], send) &&
      ref.read(liveTransfersProvider).containsKey(uploadId);

  /// Reads [uploadIds] again, each alone: rows sent from elsewhere whose
  /// window ran out, which only a fresh read can say went quiet. A row the
  /// server no longer has goes; one that cannot be read now stays as it
  /// was, and so does the rest of the list, pages Load more brought
  /// included.
  Future<void> readAgain(Iterable<String> uploadIds) async {
    // Called from a timer, which can land while this rebuilds: asked
    // again later.
    if (!ref.mounted) return;
    final repository = ref.read(repositoryProvider);
    final clock = ref.read(monotonicClockProvider);
    for (final id in uploadIds) {
      final UploadSession session;
      try {
        session = await repository.getUpload(id);
      } on WaxDeckApiException catch (e) {
        if (e.code == 'not-found') _drop(id);
        continue;
      }
      if (!ref.mounted) return;
      final current = state.value;
      if (current == null || !current.uploads.any((u) => u.id == id)) {
        continue;
      }
      final readAt = clock();
      rewriteInPlace(
        (rows) => [
          for (final row in rows)
            row.session.id == id ? (session: session, readAt: readAt) : row,
        ],
      );
      _retireCaughtUp([session]);
    }
  }

  void _drop(String uploadId) {
    if (!ref.mounted) return;
    rewriteInPlace(
      (rows) => [
        for (final row in rows)
          if (row.session.id != uploadId) row,
      ],
    );
  }

  /// Collects one `[start, end)` window from a lazy read accessor.
  static Future<Uint8List> _collectRange(
    Stream<List<int>> Function([int? start, int? end]) openRead,
    int start,
    int end,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in openRead(start, end)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _upsert(UploadSession session) {
    if (!ref.mounted) return;
    final row = (session: session, readAt: ref.read(monotonicClockProvider)());
    rewriteInPlace((rows) {
      final present = rows.any((r) => r.session.id == session.id);
      return present
          ? [for (final r in rows) r.session.id == session.id ? row : r]
          : [row, ...rows];
    });
  }
}

final uploadsProvider = AsyncNotifierProvider<UploadsController, UploadsState>(
  UploadsController.new,
  retry: retryUnlessRefused,
);
