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
/// Two families under one enum. The first four are the sync stream's
/// refetch hints: markers this client turns into a row for as long as
/// the session lasts, because nothing on the server keeps them. The rest
/// are the notification catalog's own events, which the server files in
/// an inbox and which word themselves from the same table the per-target
/// checklist reads.
///
/// A closed set rather than free text, so the destination is decided in
/// one place. A catalog event this build does not know still draws, in
/// the server's own words, with nowhere better to go than this screen.
enum NotificationKind {
  review('review', WaxIcons.check, WaxRoute.review),
  upload('upload', WaxIcons.add, WaxRoute.uploads),
  task('task', WaxIcons.refresh, WaxRoute.tasks),
  download('download', WaxIcons.downloads, WaxRoute.downloads),
  signupRequested('signup-requested', WaxIcons.add, WaxRoute.users),
  backupCompleted('backup-completed', WaxIcons.success, WaxRoute.backups),
  backupFailed('backup-failed', WaxIcons.warning, WaxRoute.backups),
  reviewReady('review-ready', WaxIcons.check, WaxRoute.review),
  feedDisabled('feed-disabled', WaxIcons.warning, WaxRoute.podcasts),
  episodeDownloaded('episode-downloaded', WaxIcons.podcasts, WaxRoute.podcasts),
  importCompleted('import-completed', WaxIcons.success, WaxRoute.review),
  playlistSynced('playlist-synced', WaxIcons.refresh, WaxRoute.playlists);

  const NotificationKind(this.token, this.glyph, this.location);

  /// The one name this kind has outside Dart: the server's event name,
  /// and what a row's identifier is built from. A Dart value's `name`
  /// would let a rename break the driver silently.
  final String token;

  final WaxGlyph glyph;

  /// Where tapping the row goes when the row names nowhere better.
  final String location;

  /// Whether this kind is a session-local refetch hint rather than a
  /// catalog event. The hints word themselves from the bell's own copy;
  /// the catalog events word themselves from the notify table.
  bool get isHint =>
      this == NotificationKind.review ||
      this == NotificationKind.upload ||
      this == NotificationKind.task ||
      this == NotificationKind.download;

  /// Whether news of this kind is about one entity rather than about a
  /// surface - which is what makes a pid worth recording, what
  /// [locationFor] opens, and what keeps two broken feeds two rows.
  bool get namesEntity =>
      this == NotificationKind.feedDisabled ||
      this == NotificationKind.episodeDownloaded ||
      this == NotificationKind.playlistSynced ||
      this == NotificationKind.importCompleted;

  /// The kind one sync marker means, or null where it means nothing
  /// worth telling anybody about.
  ///
  /// Hints only. The four announcement markers ride the same emit as the
  /// catalog event of the same name, and the inbox is where that lands:
  /// recording both would draw every one of them twice.
  static NotificationKind? forMarker(String event) {
    for (final kind in NotificationKind.values) {
      // Not the client's own: a future server marker called that would
      // otherwise mint a row worded as a finished download.
      if (kind == NotificationKind.download) continue;
      if (kind.isHint && kind.token == event) return kind;
    }
    return null;
  }

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
    NotificationKind.review ||
    NotificationKind.reviewReady => l10n.bellSurfaceReview,
    NotificationKind.upload => l10n.bellSurfaceUploads,
    NotificationKind.task => l10n.bellSurfaceTasks,
    NotificationKind.download => l10n.bellSurfaceDownloads,
    NotificationKind.signupRequested => l10n.bellSurfaceAccounts,
    NotificationKind.backupCompleted ||
    NotificationKind.backupFailed => l10n.bellSurfaceBackups,
    NotificationKind.feedDisabled ||
    NotificationKind.episodeDownloaded => l10n.bellSurfacePodcasts,
    NotificationKind.importCompleted => l10n.bellSurfaceImports,
    NotificationKind.playlistSynced => l10n.bellSurfacePlaylists,
  };

  /// The one sentence a hint row says, or null for a catalog event.
  ///
  /// The kind's own rather than the recorder's: the markers carry no
  /// detail, so holding it here lets a controller record a row with no
  /// table to word it. Null rather than a fallback, because a catalog
  /// event has better words waiting in the notify table and a wire
  /// token is not a sentence.
  String? hintMessageOf(AppLocalizations l10n) => switch (this) {
    NotificationKind.review => l10n.bellReviewChanged,
    NotificationKind.upload => l10n.bellUploadChanged,
    NotificationKind.task => l10n.bellTaskChanged,
    NotificationKind.download => l10n.bellDownloadFinished,
    _ => null,
  };

  /// Where a row goes: the entity the marker named where it named one,
  /// the kind's own surface otherwise. Only [namesEntity] kinds carry a
  /// pid, which is what makes kind and pid together a row's identity.
  String locationFor(String? pid) => switch (this) {
    NotificationKind.feedDisabled when pid != null => WaxRoute.show(pid),
    NotificationKind.episodeDownloaded when pid != null => WaxRoute.episode(
      pid,
    ),
    NotificationKind.playlistSynced when pid != null => WaxRoute.playlist(pid),
    NotificationKind.importCompleted when pid != null => WaxRoute.reviewEntry(
      pid,
    ),
    _ => location,
  };
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

  final DateTime at;

  /// The entity the row named, where it named one: the show whose feed
  /// was disabled, the episode that arrived. Null where the kind's own
  /// surface is the whole answer.
  final String? targetPid;

  /// Whether this has been dealt with: an inbox row stamped read, or a
  /// hint whose destination has been visited.
  final bool read;

  bool get fromInbox => id != null;

  String get location => kind?.locationFor(targetPid) ?? WaxRoute.notifications;

  WaxGlyph get glyph => kind?.glyph ?? WaxIcons.bell;

  /// What the row says. A hint says the bell's own sentence; a catalog
  /// event says what the per-target checklist calls it, and an event
  /// this build does not know says what the server called it.
  String messageOf(AppLocalizations l10n) =>
      kind?.hintMessageOf(l10n) ?? notifyTokenTitle(l10n, event, serverTitle);

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
  String detailOf(AppLocalizations l10n) =>
      serverBody.isNotEmpty ? serverBody : notifyTokenHelp(l10n, event, '');

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

/// The sync stream's refetch hints, for as long as the session lasts.
///
/// Session-scoped by design and not by omission: a marker says a surface
/// moved and nothing more, so there is nothing for the server to keep
/// and nothing a second device would want told to it. The catalog events
/// are the durable half and live in the inbox.
///
/// Newest first, capped, and deduplicated on the kind: the sync stream
/// coalesces changes into markers, so a scan opening forty review entries
/// arrives as a burst of identical markers. Forty rows saying the same
/// thing is a worse answer than one row saying it most recently.
class LocalNotifications extends Notifier<List<WaxNotification>> {
  /// How many rows the session list holds. A glance, not a log.
  static const int cap = 20;

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

  /// The instant the list was last opened, so the badge counts what has
  /// arrived since. Null until it has been opened at all, which is why a
  /// first launch with three notifications badges three.
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
  /// [target]: the same place, or somewhere inside it.
  ///
  /// The prefix half is what makes one rule cover every kind. Review
  /// news points at the queue and is dealt with by opening an entry in
  /// it; a show's news is dealt with by opening one of its episodes.
  /// Neither is the row's own location, and both are unmistakably "I
  /// went and looked".
  static bool under(String location, String target) =>
      location == target || location.startsWith('$target/');

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
  bool _dealtWith(String target) => _here == target;

  /// Where the visitor is, for the inbox half's own dismissal rule.
  String? get here => _here;

  /// How many rows arrived since the list was last opened.
  int get unseen {
    final seen = _seenAt;
    if (seen == null) return state.length;
    return state.where((n) => n.at.isAfter(seen)).length;
  }

  void record(NotificationKind kind, {required DateTime at, String? pid}) {
    final row = WaxNotification(
      kind: kind,
      event: kind.token,
      at: at,
      targetPid: pid,
    );
    // News about the screen in front of you is not news. Recording it
    // would badge the bell with a row whose only instruction is "go
    // where you already are", and there is nothing the reader could do
    // to make it go away.
    if (_dealtWith(row.location)) return;
    // Deduplicated on the target too: two shows whose feeds both failed
    // say the same sentence and must stay two rows.
    final kept = <WaxNotification>[
      row,
      for (final existing in state)
        if (existing.kind != kind || existing.targetPid != pid) existing,
    ];
    state = kept.length <= cap ? kept : kept.sublist(0, cap);
  }

  /// Marks everything currently held as seen. Run when the bell opens.
  void markSeen() {
    _seenAt = DateTime.now();
    // The badge is derived from state, so the notifier has to publish
    // something for a widget watching it to redraw. A new list of the
    // same rows is that something, and it is cheap: the rows are shared.
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

  /// Records what one sync marker means, or nothing: the hydrated kinds
  /// are this client's own writes coming back, and the announcements are
  /// the inbox's news, not a second copy of it.
  void recordServerEvent(ServerSyncEvent event, {DateTime? at}) {
    final kind = NotificationKind.forMarker(event.kind);
    if (kind == null) return;
    record(
      kind,
      at: at ?? DateTime.now(),
      pid: kind.namesEntity ? event.pid : null,
    );
  }

  /// Native only: web has no local download manager, so no transfer of
  /// its own to announce. Server-side fetches ride the stream above.
  void recordDownloadCompleted({DateTime? at}) {
    record(NotificationKind.download, at: at ?? DateTime.now());
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

  @override
  Future<InboxState> build() async {
    // No account, no inbox: signing out rebuilds this, and asking would
    // answer 401 on the way to the login screen.
    if (ref.watch(signedInAccountProvider) == null) {
      _held = InboxState.empty;
      return _held;
    }
    final repository = ref.watch(repositoryProvider);
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
    _dismiss(ref.read(localNotificationsProvider.notifier).here);
    return _held;
  }

  static WaxNotification _inboxRow(ServerNotification row) => WaxNotification(
    id: row.id,
    kind: NotificationKind.forEvent(row.event),
    event: row.event,
    serverTitle: row.title,
    serverBody: row.body,
    at: row.createdAt,
    targetPid: row.targetPid,
    read: row.read,
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
    ref.read(localNotificationsProvider.notifier).markSeen();
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
    await _quietly(() => ref.read(repositoryProvider).clearMyNotifications());
  }

  /// Removes one inbox row for good.
  Future<void> delete(String id) async {
    final wasUnread = _held.rows.any((row) => row.id == id && !row.read);
    _publish(<WaxNotification>[
      for (final row in _held.rows)
        if (row.id != id) row,
    ], _held.unread - (wasUnread ? 1 : 0));
    await _quietly(() => ref.read(repositoryProvider).deleteMyNotification(id));
  }

  /// Deals with the rows [location] answers: the hints it drops, the
  /// inbox rows it stamps read.
  ///
  /// A visited row leaves the bell and stays on the screen, greyed: the
  /// inbox is history, so the answer to "I already dealt with that" is
  /// to stop badging it rather than to forget it happened.
  void dismissUnder(String location) {
    ref.read(localNotificationsProvider.notifier).dismissUnder(location);
    _dismiss(location);
  }

  /// The inbox half of [dismissUnder], which the build also runs so an
  /// arrival that happened before the first read is not lost.
  void _dismiss(String? location) {
    if (location == null) return;
    final read = <String>[
      for (final row in _held.rows)
        if (!row.read && LocalNotifications.under(location, row.location))
          row.id!,
    ];
    if (read.isEmpty) return;
    _publish(<WaxNotification>[
      for (final row in _held.rows)
        if (read.contains(row.id)) row.asRead() else row,
    ], _held.unread - read.length);
    unawaited(
      _quietly(
        () => ref.read(repositoryProvider).markMyNotificationsRead(ids: read),
      ),
    );
  }

  /// Runs a write whose failure is not worth a message: the optimistic
  /// state already published is what the reader sees, and the next read
  /// of the inbox is what corrects it.
  Future<void> _quietly(Future<void> Function() write) async {
    try {
      await write();
    } on WaxDeckApiException {
      // Left to the next refetch.
    }
  }
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
