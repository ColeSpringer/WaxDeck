import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../settings/notify_labels.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// What a notification is about, and where it goes.
///
/// Two families under one enum. The first is this device's own finished
/// transfer, a row for as long as the session lasts because nothing on
/// the server keeps it. The rest are the notification catalog's own
/// events, which the server files in an inbox and which word themselves
/// from the same table the per-target checklist reads. The sync stream's
/// review, upload and task markers refetch their surfaces and mint no row.
///
/// A closed set rather than free text, so the destination is decided in
/// one place. A catalog event this build does not know still draws, in
/// the server's own words, with nowhere better to go than this screen.
enum NotificationKind {
  download('download', WaxIcons.downloads, WaxRoute.downloads),
  signupRequested(
    'signup-requested',
    WaxIcons.hourglass,
    WaxRoute.userRequests,
  ),
  backupCompleted('backup-completed', WaxIcons.success, WaxRoute.backups),
  backupFailed('backup-failed', WaxIcons.warning, WaxRoute.backups),
  catalogReset('catalog-reset', WaxIcons.warning, WaxRoute.libraries),
  reviewReady('review-ready', WaxIcons.hourglass, WaxRoute.review),
  feedDisabled('feed-disabled', WaxIcons.warning, WaxRoute.podcasts),
  subscriptionFailed(
    'subscription-failed',
    WaxIcons.warning,
    WaxRoute.podcasts,
  ),
  gpodderDeviceRemoved(
    'gpodder-device-removed',
    WaxIcons.podcasts,
    WaxRoute.podcasts,
  ),
  episodeDownloaded('episode-downloaded', WaxIcons.podcasts, WaxRoute.podcasts),
  episodeArrived('episode-arrived', WaxIcons.podcasts, WaxRoute.podcasts),
  importCompleted('import-completed', WaxIcons.success, WaxRoute.review),
  playlistSynced('playlist-synced', WaxIcons.refresh, WaxRoute.playlists),
  jobFinished('job-finished', WaxIcons.success, WaxRoute.tasks),
  jobFailed('job-failed', WaxIcons.warning, WaxRoute.tasks),
  toolTaskFailed('tool-task-failed', WaxIcons.warning, WaxRoute.tasks),
  healthFixFinished('health-fix-finished', WaxIcons.success, WaxRoute.health);

  const NotificationKind(this.token, this.glyph, this.location);

  /// The one name this kind has outside Dart: the server's event name,
  /// and what a row's identifier is built from. A Dart value's `name`
  /// would let a rename break the driver silently.
  final String token;

  final WaxGlyph glyph;

  /// Where tapping the row goes when the row names nowhere better.
  final String location;

  /// Whether this kind is a session-local row rather than a catalog
  /// event. It words itself from the bell's own copy; the catalog events
  /// word themselves from the notify table.
  bool get isHint => this == NotificationKind.download;

  /// Whether the row is a queue of work somebody answers, which is
  /// what a resolve means for it: the check glyph marks the queue as
  /// done, where another kind resolved by a deletion keeps its own.
  bool get isQueue =>
      this == NotificationKind.reviewReady ||
      this == NotificationKind.signupRequested;

  /// Whether news of this kind is about one entity rather than about a
  /// surface - which is what makes a pid worth recording, what
  /// [locationFor] opens, and what keeps two broken feeds two rows.
  bool get namesEntity =>
      this == NotificationKind.feedDisabled ||
      this == NotificationKind.episodeArrived ||
      this == NotificationKind.episodeDownloaded ||
      this == NotificationKind.playlistSynced ||
      this == NotificationKind.importCompleted;

  /// The kind one catalog event means, or null for an event this build
  /// does not know.
  static NotificationKind? forEvent(String event) {
    for (final kind in NotificationKind.values) {
      if (!kind.isHint && kind.token == event) return kind;
    }
    return null;
  }

  /// What the row's overline says: the surface, not the change.
  String labelOf(AppLocalizations l10n) => switch (this) {
    NotificationKind.reviewReady => l10n.bellSurfaceReview,
    NotificationKind.download => l10n.bellSurfaceDownloads,
    NotificationKind.signupRequested => l10n.bellSurfaceAccounts,
    NotificationKind.backupCompleted ||
    NotificationKind.backupFailed => l10n.bellSurfaceBackups,
    NotificationKind.catalogReset => l10n.bellSurfaceLibraries,
    NotificationKind.feedDisabled ||
    NotificationKind.subscriptionFailed ||
    NotificationKind.gpodderDeviceRemoved ||
    NotificationKind.episodeArrived ||
    NotificationKind.episodeDownloaded => l10n.bellSurfacePodcasts,
    NotificationKind.importCompleted => l10n.bellSurfaceImports,
    NotificationKind.playlistSynced => l10n.bellSurfacePlaylists,
    NotificationKind.jobFinished ||
    NotificationKind.jobFailed ||
    NotificationKind.toolTaskFailed => l10n.bellSurfaceTasks,
    NotificationKind.healthFixFinished => l10n.bellSurfaceHealth,
  };

  /// The one sentence a hint row says, or null for a catalog event.
  ///
  /// The kind's own rather than the recorder's, so a controller can
  /// record a row with no table to word it. Null rather than a fallback,
  /// because a catalog event has better words waiting in the notify
  /// table and a wire token is not a sentence.
  String? hintMessageOf(AppLocalizations l10n) => switch (this) {
    NotificationKind.download => l10n.bellDownloadFinished,
    _ => null,
  };

  /// Where a row goes: the entity the marker named where it named one,
  /// the kind's own surface otherwise. Only [namesEntity] kinds carry a
  /// pid, which is what makes kind and pid together a row's identity.
  String locationFor(String? pid) => switch (this) {
    NotificationKind.feedDisabled ||
    NotificationKind.episodeArrived when pid != null => WaxRoute.show(pid),
    NotificationKind.episodeDownloaded when pid != null => WaxRoute.episode(
      pid,
    ),
    NotificationKind.playlistSynced when pid != null => WaxRoute.playlist(pid),
    NotificationKind.importCompleted when pid != null => WaxRoute.reviewEntry(
      pid,
    ),
    _ => location,
  };

  /// The entity a visit at [location] is at or under, for the kinds whose
  /// rows point at one; null for every other kind and for a location
  /// outside the entity's own. What lets a visit settle a row this client
  /// never loaded, by the pid the address names.
  String? entityAt(String location) {
    if (!namesEntity) return null;
    const probe = '\u0000';
    final parts = locationFor(probe).split(probe);
    final path = Uri.parse(location).path;
    if (parts.length != 2 || !path.startsWith(parts.first)) return null;
    final pid = path.substring(parts.first.length).split('/').first;
    return pid.isEmpty ? null : pid;
  }
}

/// One thing worth telling somebody about.
///
/// Either an inbox row the server kept, which carries an [id] and
/// survives a relaunch, or a session-local hint this client minted from
/// a sync marker, which does not.
class WaxNotification {
  const WaxNotification({
    required this.at,
    this.id,
    this.kind,
    this.event = '',
    this.serverTitle = '',
    this.serverBody = '',
    this.targetPid,
    this.read = false,
    this.count = 1,
    this.resolved = false,
  });

  /// The inbox row this is, or null for a session-local hint.
  final String? id;

  /// Null only for a catalog event this build does not know.
  final NotificationKind? kind;

  /// The wire token, which is what words an unknown event's row and what
  /// its identifier is built from.
  final String event;

  /// The server's own English, drawn only where [kind] is null.
  final String serverTitle;
  final String serverBody;

  /// The row's latest occurrence, which is when it is drawn and what the
  /// merge orders by: a keyed row that folds a new occurrence rises under
  /// the same id.
  final DateTime at;

  /// How many occurrences the row folds.
  final int count;

  /// Whether what the row reports has been dealt with: a queue emptied, a
  /// signup decided, the playlist or subscription it names deleted. A
  /// resolved row never navigates.
  final bool resolved;

  /// The entity the row named, where it named one: the show whose feed
  /// was disabled, the episode that arrived. Null where the kind's own
  /// surface is the whole answer.
  final String? targetPid;

  /// Whether this has been dealt with: an inbox row stamped read, or a
  /// hint whose destination has been visited.
  final bool read;

  bool get fromInbox => id != null;

  String get location => kind?.locationFor(targetPid) ?? WaxRoute.notifications;

  /// The check means done, so only a queue that was answered wears it.
  WaxGlyph get glyph => resolved && (kind?.isQueue ?? false)
      ? WaxIcons.check
      : kind?.glyph ?? WaxIcons.bell;

  /// What the row says. A hint says the bell's own sentence; a catalog
  /// event says what the per-target checklist calls it, and an event
  /// this build does not know says what the server called it.
  String messageOf(AppLocalizations l10n) =>
      kind?.hintMessageOf(l10n) ??
      notifyRowTitle(
        l10n,
        event,
        serverTitle,
        count: count,
        resolved: resolved,
      );

  /// What the bell's line says after the surface: the count where the row
  /// folded, the server's detail where it did not, so two rows of one
  /// event read differently.
  String bellLineOf(AppLocalizations l10n) =>
      kind == null ||
          kind!.isHint ||
          resolved ||
          count > 1 ||
          serverBody.isEmpty
      ? messageOf(l10n)
      : serverBody;

  /// The line under the message: what happened, in the server's own
  /// words.
  ///
  /// The server's rather than the catalogue's, and this way round on
  /// purpose. The heading says which kind of thing happened and stays
  /// localized; the body is the only place the *which one* lives - the
  /// episode, the show and its failure count, the playlist and what
  /// moved in it - so drawing the catalogue's generic help instead
  /// would render five episodes from five shows as five identical rows.
  /// Empty for a row the server sent no body for, and the catalogue's
  /// help is what fills that in.
  String detailOf(AppLocalizations l10n) {
    // A queue that was answered says so in its heading; the body names the
    // last entry that waited in it, which would contradict "cleared".
    if (resolved && (kind?.isQueue ?? false)) return '';
    return serverBody.isNotEmpty
        ? serverBody
        : notifyTokenHelp(l10n, event, '');
  }

  /// The overline: which surface this is about, or the raw token for an
  /// event with no surface this build knows.
  String surfaceOf(AppLocalizations l10n) => kind?.labelOf(l10n) ?? event;

  WaxNotification asRead() => WaxNotification(
    at: at,
    id: id,
    kind: kind,
    event: event,
    serverTitle: serverTitle,
    serverBody: serverBody,
    targetPid: targetPid,
    read: true,
    count: count,
    resolved: resolved,
  );

  /// What this row is about rather than where it sits. Two templates,
  /// because the stand-in for a missing pid is vocabulary the driver
  /// writes too, and the registry is where that lives (rule 8).
  ///
  /// An inbox row is addressed by its own id, not by what it is about:
  /// the inbox keeps ninety days, so two nightly backups and two
  /// failures of one feed are all legitimately on the list at once, and
  /// anything coarser would be one handle naming several rows. A hint
  /// keeps the (kind, pid) form, which is unique because the session
  /// list deduplicates on exactly that pair.
  String get semanticsId {
    final row = id;
    if (row != null) {
      return SemanticsIds.notificationRow(kind?.token ?? event, row);
    }
    final token = kind?.token ?? event;
    final pid = targetPid;
    return pid == null
        ? SemanticsIds.notificationRowPlain(token)
        : SemanticsIds.notificationRow(token, pid);
  }
}

/// What only this device knows, for as long as the session lasts: its own
/// finished transfer.
///
/// Session-scoped by design and not by omission: nothing on the server
/// describes it, and nothing a second device would want told to it. The
/// catalog events are the durable half and live in the inbox.
///
/// One row, the latest: a sweep finishing forty downloads is one thing to
/// say, most recently.
class LocalNotifications extends Notifier<List<WaxNotification>> {
  @override
  List<WaxNotification> build() {
    // Rebuilt when the account changes, which is what empties the list:
    // what the previous session observed is not this one's, and the next
    // person to sign in on this device saw none of it. Watched rather
    // than cleared from the binder's disposal, because a disposal
    // callback may not modify another provider at all - riverpod asserts
    // on it in debug and swallows it in release.
    ref.watch(signedInAccountProvider);
    _seenAt = null;
    return const <WaxNotification>[];
  }

  /// How far down the list the reader has been shown: the newest hint
  /// the bell has drawn them, so the badge counts what has arrived
  /// since. The newest hint drawn rather than the instant it was drawn
  /// at, because those differ by whatever landed between the build and
  /// the press, and that difference is news nobody was shown. Null
  /// until the bell has drawn a hint - an inbox row carries a read
  /// stamp of its own and never moves this one - which is why a first
  /// launch with three hints badges three.
  DateTime? _seenAt;

  /// When the list was last looked at, for the view that draws a hint's
  /// read state from it. A hint has nowhere durable to record one, so
  /// "seen" is the whole of what read can mean for it.
  DateTime? get seenAt => _seenAt;

  /// Where the visitor is, as the router last reported it. Null before
  /// the first navigation, which is a launch that has not been anywhere
  /// yet.
  String? _here;

  /// Whether standing at [location] deals with news pointing at
  /// [target]: the same place, or somewhere inside it, carrying every
  /// query parameter [target] names.
  ///
  /// The prefix half is what makes one rule cover every kind. Review
  /// news points at the queue and is dealt with by opening an entry in
  /// it; a show's news is dealt with by opening one of its episodes.
  /// Neither is the row's own location, and both are unmistakably "I
  /// went and looked". A query names a view of a screen (the signup
  /// requests), which the screen's other views do not deal with.
  static bool under(String location, String target) {
    final at = Uri.parse(location);
    final to = Uri.parse(target);
    return (at.path == to.path || at.path.startsWith('${to.path}/')) &&
        _carries(at, to);
  }

  /// Whether [at] carries every query parameter [target] names, each with
  /// the same value.
  static bool _carries(Uri at, Uri target) => target.queryParameters.entries
      .every((p) => at.queryParameters[p.key] == p.value);

  /// Whether the visitor is already looking at exactly what [target]
  /// names.
  ///
  /// Exact, where [dismissUnder] is a prefix. The two rules are asking
  /// different questions: "I went and looked" is answered by arriving
  /// anywhere inside the thing, while "this is not news, it is the
  /// screen in front of me" is only true of the screen itself. Matching
  /// downward on insert would swallow news about a show while its
  /// reader was looking at a different one, since a row with no pid
  /// points at the bare surface those all sit under - and swallowed is
  /// worse than a badge, because nothing brings it back.
  bool _dealtWith(String target) {
    final here = _here;
    if (here == null) return false;
    final at = Uri.parse(here);
    final to = Uri.parse(target);
    return at.path == to.path && _carries(at, to);
  }

  /// Where the visitor is, for the inbox half's own dismissal rule.
  String? get here => _here;

  /// How many rows arrived since the list was last opened.
  int get unseen {
    final seen = _seenAt;
    if (seen == null) return state.length;
    return state.where((n) => n.at.isAfter(seen)).length;
  }

  /// Marks seen exactly the news the bell drew, once its menu has been
  /// read. Stamped from the newest drawn row rather than the clock, so
  /// a hint landing after the build stays unseen; inbox rows have their own.
  void markSeen(Iterable<WaxNotification> drawn) {
    var latest = _seenAt;
    for (final row in drawn) {
      if (row.fromInbox) continue;
      if (latest == null || row.at.isAfter(latest)) latest = row.at;
    }
    if (latest == _seenAt) return;
    _seenAt = latest;
    // The badge is derived from state, so the notifier has to publish
    // something for a widget watching it to redraw. A new list of the
    // same rows is that something, and it is cheap: the rows are shared.
    state = <WaxNotification>[...state];
  }

  /// Marks every hint seen, drawn or not: reading everything is what
  /// the reader asked for, where opening the bell only says what it
  /// managed to show them.
  void markAllSeen() {
    _seenAt = DateTime.now();
    state = <WaxNotification>[...state];
  }

  void clear() {
    _seenAt = null;
    state = const <WaxNotification>[];
  }

  /// Drops the rows [location] deals with, and remembers where the
  /// visitor now is.
  ///
  /// A notification is dealt with when its destination is visited. That
  /// is the whole rule, and it is the router that knows when it
  /// happens - which is what makes it hold for every way of getting
  /// there: a row in the bell, a row on the notifications screen, a
  /// link, the sidebar, or a search result. Rows the visit does not
  /// answer stay, and a later event for the same thing arrives as a new
  /// row, because news arriving after you looked is news.
  void dismissUnder(String location) {
    _here = location;
    final kept = <WaxNotification>[
      for (final row in state)
        if (!under(location, row.location)) row,
    ];
    if (kept.length == state.length) return;
    state = kept;
  }

  /// Native only: web has no local download manager, so no transfer of
  /// its own to announce. Server-side fetches ride the stream above.
  void recordDownloadCompleted({DateTime? at}) {
    final row = WaxNotification(
      kind: NotificationKind.download,
      event: NotificationKind.download.token,
      at: at ?? DateTime.now(),
    );
    // News about the screen in front of you is not news. Recording it
    // would badge the bell with a row whose only instruction is "go
    // where you already are", and there is nothing the reader could do
    // to make it go away.
    if (_dealtWith(row.location)) return;
    state = <WaxNotification>[row];
  }
}

final localNotificationsProvider =
    NotifierProvider<LocalNotifications, List<WaxNotification>>(
      LocalNotifications.new,
    );

/// The account's inbox, as one read of it left it.
class InboxState {
  const InboxState({required this.rows, required this.unread});

  static const empty = InboxState(rows: <WaxNotification>[], unread: 0);

  final List<WaxNotification> rows;

  /// Unread rows across the whole inbox, not just the page held here.
  final int unread;
}

/// The account's inbox, and the writes that change it.
///
/// The read never fails loudly, and never blanks what it already had: a
/// server that cannot be reached leaves the rows it last saw standing
/// rather than putting an empty bell where a dozen unread rows were.
/// Riverpod would otherwise retry a thrown read ten times over thirteen
/// seconds and report loading in between, which for a surface that is
/// only ever a peek is a worse answer than showing what is known.
///
/// Deliberately not merged with the session's hints here: this half is
/// asynchronous, and a hint that had to wait for a round trip to badge
/// the bell would be slower than the thing it is announcing.
class NotificationsController extends AsyncNotifier<InboxState> {
  /// How much of the inbox one read holds. The screen is a list, not an
  /// archive; older rows are pruned server-side anyway.
  static const int pageSize = 50;

  /// The last state anybody published, which is what a failed or
  /// overtaken read falls back to.
  InboxState _held = InboxState.empty;

  /// Bumped by every optimistic write. A read that started before one
  /// landed is answering a question that has since changed - it would
  /// put back rows the writer just deleted or re-mark ones it just
  /// read - so it discards its page and keeps what the writer left.
  int _writes = 0;

  /// The by-event writes that reached past the held page since the inbox
  /// last changed. One call settles every unread row of its events, hidden
  /// ones included, so asking again is noise until a marker's refetch or
  /// Mark all read changes what the server holds.
  final Set<String> _reached = <String>{};

  /// Set by this controller's own read-back, which is not the inbox
  /// changing.
  bool _readingBack = false;

  @override
  Future<InboxState> build() async {
    // No account, no inbox: signing out rebuilds this, and asking would
    // answer 401 on the way to the login screen.
    if (ref.watch(signedInAccountProvider) == null) {
      _held = InboxState.empty;
      return _held;
    }
    final repository = ref.watch(repositoryProvider);
    if (!_readingBack) _reached.clear();
    _readingBack = false;
    final epoch = _writes;
    final ServerNotificationPage page;
    try {
      page = await repository.listMyNotifications(limit: pageSize);
    } on Object {
      // Offline, a server too old to hold an inbox, or a payload this
      // build cannot read. Every one of them is a peek that failed, and
      // what was last known is a better answer than nothing.
      return _held;
    }
    if (epoch != _writes) return _held;
    _held = InboxState(
      rows: page.notifications.map(_inboxRow).toList(growable: false),
      unread: page.unreadCount,
    );
    // Where the visitor already is, applied to what just arrived. The
    // router announces an arrival once, and a cold start into a deep
    // link announces it while this is still loading - so without this
    // the one arrival every session has would leave its row unread.
    _dismiss(ref.read(localNotificationsProvider.notifier).here, visit: false);
    return _held;
  }

  static WaxNotification _inboxRow(ServerNotification row) => WaxNotification(
    id: row.id,
    kind: NotificationKind.forEvent(row.event),
    event: row.event,
    serverTitle: row.title,
    serverBody: row.body,
    at: row.updatedAt,
    targetPid: row.targetPid,
    read: row.read,
    count: row.count,
    resolved: row.resolvedAt != null,
  );

  /// Publishes without a refetch, so an optimistic write shows at once
  /// and the server call settles behind it.
  void _publish(List<WaxNotification> rows, int unread) {
    _writes++;
    _held = InboxState(
      rows: List<WaxNotification>.unmodifiable(rows),
      unread: unread < 0 ? 0 : unread,
    );
    state = AsyncData(_held);
  }

  /// Marks every unread inbox row read, and the session's hints seen.
  Future<void> markAllRead() async {
    ref.read(localNotificationsProvider.notifier).markAllSeen();
    _reached.clear();
    if (_held.unread == 0) return;
    _publish(<WaxNotification>[for (final row in _held.rows) row.asRead()], 0);
    await _quietly(
      () => ref.read(repositoryProvider).markMyNotificationsRead(),
    );
  }

  /// Empties both halves: the inbox on the server, and this session's
  /// hints. Destructive and irreversible, so the affordance that calls
  /// it confirms first.
  Future<void> clear() async {
    ref.read(localNotificationsProvider.notifier).clear();
    _publish(const <WaxNotification>[], 0);
    await _quietly(
      () => ref.read(repositoryProvider).clearMyNotifications(),
      readBack: true,
    );
  }

  /// Removes the resolved rows, which carry no news nobody has acted on.
  Future<void> clearCompleted() async {
    final gone = <WaxNotification>[
      for (final row in _held.rows)
        if (row.resolved) row,
    ];
    if (gone.isEmpty) return;
    _publish(<WaxNotification>[
      for (final row in _held.rows)
        if (!row.resolved) row,
    ], _held.unread - gone.where((row) => !row.read).length);
    await _quietly(
      () => ref.read(repositoryProvider).clearMyNotifications(resolved: true),
      readBack: true,
    );
  }

  /// Removes one inbox row for good.
  Future<void> delete(String id) async {
    final wasUnread = _held.rows.any((row) => row.id == id && !row.read);
    _publish(<WaxNotification>[
      for (final row in _held.rows)
        if (row.id != id) row,
    ], _held.unread - (wasUnread ? 1 : 0));
    await _quietly(
      () => ref.read(repositoryProvider).deleteMyNotification(id),
      readBack: true,
    );
  }

  /// Deals with the rows [location] answers: the hints it drops, the
  /// inbox rows it stamps read.
  ///
  /// A visited row leaves the bell and stays on the screen, greyed: the
  /// inbox is history, so the answer to "I already dealt with that" is
  /// to stop badging it rather than to forget it happened.
  void dismissUnder(String location) {
    ref.read(localNotificationsProvider.notifier).dismissUnder(location);
    _dismiss(location, visit: true);
  }

  /// The inbox half of [dismissUnder], which the build also runs so an
  /// arrival that happened before the first read is not lost.
  ///
  /// The loaded rows the visit answers read at once; the server is told
  /// by event, so a row past the page held here settles too, and the
  /// count is read back when such a row may have been among them. Only a
  /// visit reaches past the page: a refetch re-applying where the visitor
  /// already is would otherwise ask again on every read.
  void _dismiss(String? location, {required bool visit}) {
    if (location == null) return;
    final answered = <WaxNotification>[
      for (final row in _held.rows)
        if (!row.read && LocalNotifications.under(location, row.location)) row,
    ];
    final loadedUnread = _held.rows.where((row) => !row.read).length;
    final unloaded = visit && _held.unread > loadedUnread;
    final all = _readsByEvent(location);
    // What is sent: the calls that settle a row held here, and, past the
    // page, each call not yet made since the inbox last changed.
    final reads = <_EventRead>[
      for (final read in all)
        if (answered.any(read.covers) ||
            (unloaded && !_reached.contains(read.key)))
          read,
    ];
    if (answered.isEmpty && reads.isEmpty) return;
    final reachedPast = unloaded && reads.any((r) => !_reached.contains(r.key));
    _reached.addAll(reads.map((read) => read.key));
    if (answered.isNotEmpty) {
      final read = answered.map((row) => row.id).toSet();
      _publish(<WaxNotification>[
        for (final row in _held.rows)
          if (read.contains(row.id)) row.asRead() else row,
      ], _held.unread - read.length);
    }
    // Rows the by-event calls do not name still go by id: the ones that
    // point at a surface the kind's own address does not reach.
    final covered = <String>{
      for (final row in answered)
        if (reads.any((read) => read.covers(row))) row.id!,
    };
    final byId = <String>[
      for (final row in answered)
        if (!covered.contains(row.id)) row.id!,
    ];
    unawaited(_settle(reads, byId, refetch: reachedPast));
  }

  /// The by-event writes a visit at [location] calls for: one for every
  /// kind that points at a surface the visit is at or under, and one per
  /// entity the visit is at, for the kinds whose rows point at one.
  List<_EventRead> _readsByEvent(String location) {
    final surface = <String>[];
    final entities = <String, List<String>>{};
    for (final kind in NotificationKind.values) {
      if (kind.isHint) continue;
      if (kind.namesEntity) {
        final pid = kind.entityAt(location);
        if (pid != null) {
          entities.putIfAbsent(pid, () => <String>[]).add(kind.token);
        }
      } else if (LocalNotifications.under(location, kind.location)) {
        surface.add(kind.token);
      }
    }
    return <_EventRead>[
      if (surface.isNotEmpty) _EventRead(surface),
      for (final entry in entities.entries) _EventRead(entry.value, entry.key),
    ];
  }

  Future<void> _settle(
    List<_EventRead> reads,
    List<String> ids, {
    required bool refetch,
  }) async {
    final repository = ref.read(repositoryProvider);
    for (final read in reads) {
      final sent = await _quietly(
        () => repository.markMyNotificationsRead(
          events: read.events,
          targetPid: read.pid,
        ),
      );
      // Marked on asking so a second visit does not repeat a call in
      // flight; a refused one is asked again on the next visit.
      if (!sent) _reached.remove(read.key);
    }
    if (ids.isNotEmpty) {
      await _quietly(() => repository.markMyNotificationsRead(ids: ids));
    }
    if (refetch && ref.mounted) {
      _readingBack = true;
      ref.invalidateSelf();
    }
  }

  /// Runs a write whose failure is not worth a message: the optimistic
  /// state already published is what the reader sees, and the next read
  /// of the inbox is what corrects it.
  ///
  /// [readBack] reads the inbox again when the write fails, for the
  /// writes that took rows out of the list and the badge on a guess: a
  /// refused clear would otherwise leave both wrong until the next marker.
  ///
  /// Answers whether the write went through.
  Future<bool> _quietly(
    Future<void> Function() write, {
    bool readBack = false,
  }) async {
    try {
      await write();
      return true;
    } on WaxDeckApiException {
      if (readBack && ref.mounted) {
        _readingBack = true;
        ref.invalidateSelf();
      }
      return false;
    }
  }
}

/// One by-event mark-read: the events, and the entity they are narrowed to
/// where the visit was at one.
class _EventRead {
  const _EventRead(this.events, [this.pid]);

  final List<String> events;
  final String? pid;

  /// Whether the server settles [row] by this call.
  bool covers(WaxNotification row) =>
      events.contains(row.event) && (pid == null || row.targetPid == pid);

  /// What makes two calls the same call.
  String get key => '${events.join(',')}|${pid ?? ''}';
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, InboxState>(
      NotificationsController.new,
      // Nothing here throws - a failed read keeps what it had - and a
      // ladder of ten attempts over thirteen seconds would be the wrong
      // answer for a peek even if it did. The binder's marker is the
      // recovery.
      retry: (_, _) => null,
    );

/// What the bell and the notifications screen draw: the account's inbox
/// merged with this session's own hints, newest first.
class NotificationsView {
  const NotificationsView({
    required this.rows,
    required this.unreadInbox,
    required this.unseenLocal,
  });

  final List<WaxNotification> rows;

  /// Unread rows across the whole inbox, not just the page held here.
  final int unreadInbox;

  final int unseenLocal;

  /// The badge: what has not been dealt with, from either half.
  int get badge => unreadInbox + unseenLocal;

  /// The peek: what has not been dealt with, from either half. A hint
  /// is dealt with by looking at the bell, which is the whole of what
  /// reading one can mean; an inbox row by going where it points or by
  /// saying so.
  List<WaxNotification> get pending =>
      rows.where((row) => !row.read).toList(growable: false);
}

/// The two halves as one list, newest first.
///
/// A plain provider over both, rather than one async read that owns
/// them: the hints are synchronous, and merging here is what lets a
/// finished download badge the bell in the frame it finished in.
final notificationsViewProvider = Provider<NotificationsView>((ref) {
  final inbox = ref.watch(notificationsProvider).value ?? InboxState.empty;
  final hints = ref.watch(localNotificationsProvider);
  final notifier = ref.watch(localNotificationsProvider.notifier);
  // A hint has no read stamp of its own to carry - nothing on the
  // server keeps one - so "seen" is where its read state comes from,
  // which is what lets the screen draw both halves under one rule.
  final seen = notifier.seenAt;
  final rows = <WaxNotification>[
    ...inbox.rows,
    for (final hint in hints)
      if (seen != null && !hint.at.isAfter(seen)) hint.asRead() else hint,
  ]..sort((a, b) => b.at.compareTo(a.at));
  return NotificationsView(
    rows: List<WaxNotification>.unmodifiable(rows),
    unreadInbox: inbox.unread,
    unseenLocal: notifier.unseen,
  );
});

/// What the bell holds right now.
final notificationRowsProvider = Provider<List<WaxNotification>>(
  (ref) => ref.watch(notificationsViewProvider).pending,
);

/// How many rows have not been dealt with, in either half.
final unseenNotificationsProvider = Provider<int>(
  (ref) => ref.watch(notificationsViewProvider).badge,
);
