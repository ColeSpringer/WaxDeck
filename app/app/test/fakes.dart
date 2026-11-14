import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'fakes/admin_fake.dart';
import 'fakes/auth_fake.dart';
import 'fakes/books_fake.dart';
import 'fakes/discovery_fake.dart';
import 'fakes/enrichment_fake.dart';
import 'fakes/health_fake.dart';
import 'fakes/library_fake.dart';
import 'fakes/media_urls_fake.dart';
import 'fakes/metadata_fake.dart';
import 'fakes/notifications_fake.dart';
import 'fakes/organize_fake.dart';
import 'fakes/playback_fake.dart';
import 'fakes/player_fake.dart';
import 'fakes/playlists_fake.dart';
import 'fakes/podcasts_fake.dart';
import 'fakes/radio_fake.dart';
import 'fakes/review_fake.dart';
import 'fakes/scrobbling_fake.dart';
import 'fakes/shares_fake.dart';
import 'fakes/similarity_fake.dart';
import 'fakes/state.dart';
import 'fakes/stats_fake.dart';
import 'fakes/sync_fake.dart';
import 'fakes/system_fake.dart';
import 'fakes/tools_fake.dart';
import 'fakes/uploads_fake.dart';
import 'fakes/users_fake.dart';

export 'fakes/admin_fake.dart';
export 'fakes/auth_fake.dart';
export 'fakes/books_fake.dart';
export 'fakes/discovery_fake.dart';
export 'fakes/enrichment_fake.dart';
export 'fakes/health_fake.dart';
export 'fakes/library_fake.dart';
export 'fakes/media_urls_fake.dart';
export 'fakes/metadata_fake.dart';
export 'fakes/models.dart';
export 'fakes/notifications_fake.dart';
export 'fakes/organize_fake.dart';
export 'fakes/playback_fake.dart';
export 'fakes/player_fake.dart';
export 'fakes/playlists_fake.dart';
export 'fakes/podcasts_fake.dart';
export 'fakes/radio_fake.dart';
export 'fakes/review_fake.dart';
export 'fakes/scrobbling_fake.dart';
export 'fakes/shares_fake.dart';
export 'fakes/similarity_fake.dart';
export 'fakes/state.dart';
export 'fakes/stats_fake.dart';
export 'fakes/sync_fake.dart';
export 'fakes/system_fake.dart';
export 'fakes/tools_fake.dart';
export 'fakes/uploads_fake.dart';
export 'fakes/users_fake.dart';

/// The words a shell message would draw, for a test asserting one
/// without a widget tree to draw it in.
///
/// English, which is the locale a test host builds in. Through
/// `resolve` rather than off a field, because a message raised from a
/// notifier carries what to say rather than the sentence - and there is
/// no reading of one that does not name a locale.
String? shellMessageText(ShellMessage? message) =>
    message?.resolve(AppLocalizationsEn());

/// The last message the app [tester] pumped raised to the shell, which a
/// test host does not draw.
ShellMessage? raisedMessage(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(Navigator).first),
  listen: false,
).read(shellMessengerProvider);

/// Presses the action on the last message raised to the shell, as the
/// shell's bar would.
Future<void> pressRaisedAction(WidgetTester tester) async {
  raisedMessage(tester)!.onAction!();
  await tester.pumpAndSettle();
}

/// In-memory repository for widget tests. Pagination uses the item index as
/// the cursor, which is enough to exercise keyset-style paging end to end.
class FakeRepository extends FakeRepositoryState
    with
        FakeSystem,
        FakeAuth,
        FakeUsers,
        FakeLibrary,
        FakePodcasts,
        FakeBooks,
        FakePlaylists,
        FakeRadio,
        FakeScrobbling,
        FakeNotifications,
        FakePlayback,
        FakePlayer,
        FakeSync,
        FakeAdmin,
        FakeReview,
        FakeUploads,
        FakeMetadata,
        FakeHealth,
        FakeOrganize,
        FakeTools,
        FakeEnrichment,
        FakeDiscovery,
        FakeStats,
        FakeShares,
        FakeSimilarity,
        FakeMediaUrls
    implements WaxDeckRepository {
  FakeRepository({
    super.sessionState,
    super.items,
    super.recentlyPlayed,
    super.bootstrapNeeded,
    super.sessions,
    super.providers,
  });
}

/// A downloads port over a map of what is "on disk", for the playback
/// and downloads-manager tests.
///
/// The verbs record rather than pretend: a screen under test asserts
/// against [removed], [canceled], [paused], and [downloaded] instead of
/// against a filesystem this has none of.
class FakeDownloads implements DownloadManagerPort {
  FakeDownloads({
    Map<String, LocalPlayback>? local,
    List<DownloadedItem>? items,
  }) : byPid = local ?? <String, LocalPlayback>{},
       _items = items ?? <DownloadedItem>[];

  final Map<String, LocalPlayback> byPid;
  List<DownloadedItem> _items;

  final removed = <String>[];
  final canceled = <String>[];
  final paused = <String>[];
  final resumed = <String>[];
  final downloaded = <String>[];

  /// What [pause] answers; false is an item with nothing left to fetch.
  bool pausable = true;

  final _progress = StreamController<DownloadProgress>.broadcast();

  /// The fraction last emitted per pid, which a pause and a resume repeat.
  final _fractions = <String, double>{};

  void emit(DownloadProgress progress) {
    _fractions[progress.pid] = progress.fraction;
    _progress.add(progress);
  }

  void setStored(List<DownloadedItem> items) => _items = items;

  /// Held open, [stored] waits on it: a reload in flight is what a
  /// screen's refresh test is about.
  Completer<void>? storedGate;

  @override
  Future<LocalPlayback?> localFor(String pid) async => byPid[pid];

  @override
  Future<bool> isComplete(String pid) async => byPid.containsKey(pid);

  /// Set, [download] records the call and then throws it.
  Object? downloadError;

  @override
  Future<void> download(String pid) async {
    downloaded.add(pid);
    // The real manager throws reading the item's info, before it holds
    // anything a cancel would stop.
    if (downloadError case final error?) throw error;
    _fetching.add(pid);
  }

  /// How many removals are in flight at once. The real port refuses to
  /// unlink a file another row still references, so two removals racing
  /// each other both see the other's row and leave the bytes behind;
  /// `removeAll` is sequential for that reason and every other caller
  /// has to be too.
  int inFlightRemovals = 0;
  int peakConcurrentRemovals = 0;

  /// Held open, [remove] waits on it; set, [remove] throws it.
  Completer<void>? removeGate;
  Object? removeError;

  @override
  Future<void> remove(String pid) async {
    // Only when set: awaiting a null adds a turn other tests' timing sees.
    if (removeGate case final gate?) await gate.future;
    if (removeError case final error?) throw error;
    inFlightRemovals++;
    peakConcurrentRemovals = math.max(peakConcurrentRemovals, inFlightRemovals);
    // A suspension point, so an unserialized caller genuinely overlaps
    // here rather than running to completion synchronously.
    await Future<void>.delayed(Duration.zero);
    removed.add(pid);
    final held = _drop(pid);
    byPid.remove(pid);
    _items = _items.where((i) => i.pid != pid).toList();
    inFlightRemovals--;
    if (held) _stopped(pid);
  }

  /// Asked for and not yet canceled or removed: what the manager would
  /// still hold records of.
  final _fetching = <String>{};

  /// Whether [pid] was held, letting go of its fetch.
  bool _drop(String pid) =>
      _fetching.remove(pid) ||
      byPid.containsKey(pid) ||
      _items.any((i) => i.pid == pid);

  /// What the real manager says of an item a cancel or removal dropped.
  void _stopped(String pid) {
    if (_progress.isClosed) return;
    _progress.add(
      DownloadProgress(pid: pid, fraction: 0, complete: false, stopped: true),
    );
  }

  /// Frees as [remove] does and answers no covers: what a real manager
  /// decides is the data package's own to test, against its own chain.
  @override
  Future<List<OwedPin>?> freeOwed(String pid) async {
    await remove(pid);
    return const <OwedPin>[];
  }

  @override
  Future<List<DownloadedItem>> stored() async {
    await storedGate?.future;
    return _items;
  }

  @override
  Future<DownloadedItem?> storedItem(String pid) async =>
      _items.where((i) => i.pid == pid).firstOrNull;

  /// The same operation as [remove] in the real manager, minus the wait.
  @override
  Future<void> cancel(String pid) async {
    canceled.add(pid);
    final held = _drop(pid);
    byPid.remove(pid);
    _items = _items.where((i) => i.pid != pid).toList();
    if (held) _stopped(pid);
  }

  @override
  Future<bool> pause(String pid) async {
    paused.add(pid);
    if (!pausable) return false;
    _markPaused(pid, paused: true);
    return true;
  }

  @override
  Future<void> resume(String pid) async {
    resumed.add(pid);
    _markPaused(pid, paused: false);
  }

  /// What the real manager keeps and says of a pause or its resume.
  void _markPaused(String pid, {required bool paused}) {
    _items = <DownloadedItem>[
      for (final i in _items)
        i.pid == pid
            ? DownloadedItem(
                pid: i.pid,
                sizeBytes: i.sizeBytes,
                files: i.files,
                complete: i.complete,
                paused: paused,
                active: !paused,
              )
            : i,
    ];
    if (_progress.isClosed) return;
    _progress.add(
      DownloadProgress(
        pid: pid,
        fraction: _fractions[pid] ?? 0,
        complete: false,
        paused: paused,
      ),
    );
  }

  @override
  Stream<DownloadProgress> get progress => _progress.stream;

  final _rationale = StreamController<void>.broadcast();
  var notificationRequests = 0;

  /// What the real manager does once a run when Android allows a reason.
  void explainNotifications() => _rationale.add(null);

  @override
  Stream<void> get notificationRationale => _rationale.stream;

  @override
  Future<void> requestNotificationPermission() async => notificationRequests++;

  void dispose() {
    _progress.close();
    _rationale.close();
  }
}

/// One downloaded file "on disk", for [FakeDownloads].
LocalPlayback testLocal(
  String path, {
  int? durationMs,
  int? spanStartMs,
  int? spanEndMs,
}) => LocalPlayback(
  parts: <LocalPart>[LocalPart(path: path, durationMs: durationMs)],
  spanStartMs: spanStartMs,
  spanEndMs: spanEndMs,
);

/// A multi-part book "on disk": equal parts of [partMs] each, named after
/// their index.
LocalPlayback testLocalParts(
  int count, {
  int partMs = 60000,
  String prefix = '/downloads/part',
  bool durations = true,
}) => LocalPlayback(
  parts: <LocalPart>[
    for (var i = 0; i < count; i++)
      LocalPart(path: '$prefix$i.flac', durationMs: durations ? partMs : null),
  ],
);

/// An artwork store that records what was pinned and unpinned and reaches
/// no network. For the surfaces whose contract is a pair of calls.
class FakeArtworkStore extends ArtworkStore {
  final List<String> pinned = <String>[];
  final List<String> unpinned = <String>[];

  /// The cover URL each [pinForOffline] was handed, by pid.
  final Map<String, String?> pinnedUrls = <String, String?>{};

  /// Every URL a surface asked for artwork at, so a test can see which
  /// origin a picture is being fetched from.
  final List<String> requested = <String>[];

  /// Every URL something asked this store to forget, for the invalidations
  /// that happen behind a stable URL: a cover write, a station's logo
  /// re-pointed.
  final List<String> evicted = <String>[];

  @override
  String get baseUrl => '';

  @override
  ImageProvider? imageFor(String? artUrl, int px) {
    if (artUrl != null) requested.add(artUrl);
    return null;
  }

  /// Bytes this store hands back per URL. Empty by default, which is
  /// the offline case every surface has to render anyway.
  final Map<String, Uint8List> bytes = <String, Uint8List>{};

  /// Every (url, px) a caller asked for the actual bytes of, which is
  /// the palette, a cast copy, and a share card rather than anything
  /// that paints.
  final List<({String url, int px})> byteRequests = <({String url, int px})>[];

  @override
  Future<Uint8List?> bytesFor(String artUrl, int px) async {
    byteRequests.add((url: artUrl, px: px));
    return bytes[artUrl];
  }

  /// Every (url, px) a scroll asked this store to warm ahead of itself.
  final List<({String url, int px})> warmed = <({String url, int px})>[];

  @override
  Future<void> warm(String artUrl, int px) async =>
      warmed.add((url: artUrl, px: px));

  @override
  Future<void> pinForOffline(String pid, String? artUrl) async {
    pinned.add(pid);
    pinnedUrls[pid] = artUrl;
  }

  @override
  Future<void> unpin(String pid) async => unpinned.add(pid);

  /// The covers each exact unpin was told of, by pid; the pid also lands in
  /// [unpinned], since its covers were taken.
  final unpinnedExactly = <String, List<OwedPin>>{};

  @override
  Future<void> unpinExact(String pid, List<OwedPin> owed) async {
    unpinned.add(pid);
    unpinnedExactly[pid] = owed;
  }

  @override
  Future<void> evict(String artUrl) async => evicted.add(artUrl);

  var forgotten = 0;

  @override
  Future<void> forgetEverything() async => forgotten++;

  @override
  void dispose() {}
}

/// A channel that never reaches a server: connecting fails immediately,
/// which is exactly what airplane mode looks like to the engine.
class _DeadChannel extends EventsChannel {
  _DeadChannel({
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://unreachable', authToken: null);

  @override
  Future<void> connect() => Future.error(Exception('unreachable'));

  @override
  Future<void> close() async {}
}

/// The factory tests hand the engine so it always lands offline.
EventsChannelFactory deadChannelFactory() {
  return ({required onFrame, required onDone, required subscribe}) =>
      _DeadChannel(onFrame: onFrame, onDone: onDone, subscribe: subscribe);
}

/// The network under an event socket: each connect attempt opens a
/// [LinkedChannel] over it, which comes up while [reachable]. The server
/// behind it answers a subscribe that presents a cursor as WaxDeck's does,
/// with an invalidation of each topic it presents one for.
class FakeLink {
  bool reachable = true;

  /// What each attempt fails with while set, as a server that answers the
  /// upgrade without taking it.
  Object? refusal;

  final attempts = <LinkedChannel>[];

  EventsChannelFactory get factory =>
      ({required onFrame, required onDone, required subscribe}) {
        final channel = LinkedChannel._(
          this,
          onFrame: onFrame,
          onDone: onDone,
          subscribe: subscribe,
        );
        attempts.add(channel);
        return channel;
      };
}

/// One socket over a [FakeLink], which goes down when the test says so,
/// closed with the code it names.
class LinkedChannel extends EventsChannel {
  LinkedChannel._(
    this._link, {
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://linked', authToken: null);

  final FakeLink _link;
  int? _code;
  bool _up = false;

  /// Every frame sent on it, in order.
  final sent = <String>[];

  @override
  int? get closeCode => _code;

  @override
  Future<void> connect() async {
    if (_link.refusal case final refusal?) throw refusal;
    if (!_link.reachable) throw Exception('unreachable');
    _up = true;
    final subscribed = jsonDecode(await subscribe()) as Map<String, Object?>;
    final topics = [
      if (subscribed['catalogSince'] != null) 'catalog',
      if (subscribed['serverSince'] != null) 'user',
    ];
    // Over the wire, so after the connect has resolved.
    if (topics.isEmpty) return;
    Timer.run(() {
      for (final topic in topics) {
        if (_up) onFrame(jsonEncode({'type': 'invalidate', 'topic': topic}));
      }
    });
  }

  @override
  bool send(String frame) {
    if (!_up) return false;
    sent.add(frame);
    return true;
  }

  @override
  Future<void> close() async => _up = false;

  void drop(int? code) {
    _code = code;
    _up = false;
    onDone();
  }
}
