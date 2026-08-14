import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// What a notification is about, and where it goes.
///
/// A closed set rather than free text, so the copy and the destination
/// are decided in one place and a kind this build does not know is
/// dropped rather than drawn as a row that goes nowhere.
enum NotificationKind {
  review('review', WaxIcons.check, WaxRoute.review),
  upload('upload', WaxIcons.add, WaxRoute.uploads),
  task('task', WaxIcons.refresh, WaxRoute.tasks),
  feedDisabled('feed-disabled', WaxIcons.warning, WaxRoute.podcasts),
  episodeDownloaded('episode-downloaded', WaxIcons.podcasts, WaxRoute.podcasts),
  importCompleted('import-completed', WaxIcons.success, WaxRoute.uploads),
  download('download', WaxIcons.downloads, WaxRoute.downloads);

  const NotificationKind(this.token, this.glyph, this.location);

  /// The one name this kind has outside Dart: the server's event name,
  /// and what a row's identifier is built from. A Dart value's `name`
  /// would let a rename break the driver silently.
  final String token;

  final WaxGlyph glyph;

  /// Where tapping the row goes when the row names nowhere better.
  final String location;

  /// Whether news of this kind is about one entity rather than about a
  /// surface - which is what makes a pid worth recording, what
  /// [locationFor] opens, and what keeps two broken feeds two rows.
  bool get namesEntity =>
      this == NotificationKind.feedDisabled ||
      this == NotificationKind.episodeDownloaded;

  /// The kind one server event means, or null where it means nothing
  /// worth telling anybody about. Matched on [token], so the vocabulary
  /// lives on the values rather than in a switch beside them.
  static NotificationKind? forEvent(String event) {
    for (final kind in NotificationKind.values) {
      // Not the client's own: a future server event called that would
      // otherwise mint a row worded as a finished download.
      if (kind == NotificationKind.download) continue;
      if (kind.token == event) return kind;
    }
    return null;
  }

  /// What the row's overline says: the surface, not the change.
  String labelOf(AppLocalizations l10n) => switch (this) {
    NotificationKind.review => l10n.bellSurfaceReview,
    NotificationKind.upload => l10n.bellSurfaceUploads,
    NotificationKind.task => l10n.bellSurfaceTasks,
    NotificationKind.feedDisabled ||
    NotificationKind.episodeDownloaded => l10n.bellSurfacePodcasts,
    NotificationKind.importCompleted => l10n.bellSurfaceImports,
    NotificationKind.download => l10n.bellSurfaceDownloads,
  };

  /// The one sentence a row of this kind says. The kind's own rather
  /// than the recorder's: the markers carry no detail, so holding it
  /// here lets a controller record a row with no table to word it.
  String messageOf(AppLocalizations l10n) => switch (this) {
    NotificationKind.review => l10n.bellReviewChanged,
    NotificationKind.upload => l10n.bellUploadChanged,
    NotificationKind.task => l10n.bellTaskChanged,
    NotificationKind.feedDisabled => l10n.bellFeedDisabled,
    NotificationKind.episodeDownloaded => l10n.bellEpisodeDownloaded,
    NotificationKind.importCompleted => l10n.bellImportCompleted,
    NotificationKind.download => l10n.bellDownloadFinished,
  };

  /// Where a row goes: the entity the marker named where it named one,
  /// the kind's own surface otherwise. Only [namesEntity] kinds carry a
  /// pid, which is what makes kind and pid together a row's identity.
  String locationFor(String? pid) => switch (this) {
    NotificationKind.feedDisabled when pid != null => WaxRoute.show(pid),
    NotificationKind.episodeDownloaded when pid != null => WaxRoute.episode(
      pid,
    ),
    _ => location,
  };
}

/// One thing the client saw happen while it was running.
class WaxNotification {
  const WaxNotification({required this.kind, required this.at, this.targetPid});

  final NotificationKind kind;

  final DateTime at;

  /// The entity the marker named, where it named one: the show whose
  /// feed was disabled, the episode that arrived. Null where the kind's
  /// own surface is the whole answer.
  final String? targetPid;

  String get location => kind.locationFor(targetPid);

  /// What this row is about rather than where it sits. Two templates,
  /// because the stand-in for a missing pid is vocabulary the driver
  /// writes too, and the registry is where that lives (rule 8).
  String get semanticsId {
    final pid = targetPid;
    return pid == null
        ? SemanticsIds.notificationRowPlain(kind.token)
        : SemanticsIds.notificationRow(kind.token, pid);
  }
}

/// What this client has seen happen this session.
///
/// Session-scoped by design and not by omission: there is no notification
/// history endpoint, and inventing one client-side would mean a list that
/// is complete on the device that was open and empty on the one that was
/// not - which reads as "nothing happened" rather than as "I was not
/// there". The list says what it knows, and a launch starts it empty.
///
/// Newest first, capped, and deduplicated on the kind: the sync stream
/// coalesces changes into markers, so a scan opening forty review entries
/// arrives as a burst of identical markers. Forty rows saying the same
/// thing is a worse answer than one row saying it most recently.
class NotificationsController extends Notifier<List<WaxNotification>> {
  /// How many rows the bell holds. A glance, not a log.
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

  /// How many rows arrived since the bell was last opened.
  int get unseen {
    final seen = _seenAt;
    if (seen == null) return state.length;
    return state.where((n) => n.at.isAfter(seen)).length;
  }

  void record(NotificationKind kind, {required DateTime at, String? pid}) {
    final row = WaxNotification(kind: kind, at: at, targetPid: pid);
    // Deduplicated on the target too: two shows whose feeds both failed
    // say the same sentence and must stay two rows.
    final kept = <WaxNotification>[
      row,
      for (final existing in state)
        if (existing.kind != kind || existing.targetPid != pid) existing,
    ];
    state = kept.length <= cap ? kept : kept.sublist(0, cap);
  }

  /// Marks everything currently held as seen. Run when the panel opens.
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

  /// Records what one server-state change means, or nothing: the
  /// hydrated kinds are this client's own writes coming back, which is
  /// noise with a bell on it. What a kind says is the kind's own.
  void recordServerEvent(ServerSyncEvent event, {DateTime? at}) {
    final kind = NotificationKind.forEvent(event.kind);
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

final notificationsProvider =
    NotifierProvider<NotificationsController, List<WaxNotification>>(
      NotificationsController.new,
    );

/// How many rows have arrived since the bell was last opened.
final unseenNotificationsProvider = Provider<int>((ref) {
  // Watched rather than read, so the badge follows both a new row and a
  // panel being opened.
  ref.watch(notificationsProvider);
  return ref.watch(notificationsProvider.notifier).unseen;
});
