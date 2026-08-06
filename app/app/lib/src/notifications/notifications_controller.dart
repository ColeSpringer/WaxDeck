import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../shell/routes.dart';

/// What a notification is about, and where it goes.
///
/// A closed set rather than free text, so the copy and the destination
/// are decided in one place and a kind this build does not know is
/// dropped rather than drawn as a row that goes nowhere.
enum NotificationKind {
  review('Review queue', WaxIcons.check, WaxRoute.review),
  upload('Uploads', WaxIcons.add, WaxRoute.uploads),
  task('Background tasks', WaxIcons.refresh, WaxRoute.tasks),
  feedDisabled('Podcasts', WaxIcons.warning, WaxRoute.podcasts),
  episodeDownloaded('Podcasts', WaxIcons.podcasts, WaxRoute.podcasts),
  importCompleted('Imports', WaxIcons.success, WaxRoute.uploads),
  download('Downloads', WaxIcons.downloads, WaxRoute.downloads);

  const NotificationKind(this.label, this.glyph, this.location);

  /// What the row's overline says: the surface, not the change.
  final String label;

  final WaxGlyph glyph;

  /// Where tapping the row goes when the row names nowhere better.
  final String location;
}

/// One thing the client saw happen while it was running.
class WaxNotification {
  const WaxNotification({
    required this.kind,
    required this.message,
    required this.at,
    this.locationOverride,
  });

  final NotificationKind kind;

  /// One sentence, in the app's own voice.
  final String message;

  final DateTime at;

  /// Where a row goes when the event named something more specific than
  /// its kind's surface: a disabled feed opens its own show.
  final String? locationOverride;

  String get location => locationOverride ?? kind.location;
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

  void record(
    NotificationKind kind,
    String message, {
    required DateTime at,
    String? location,
  }) {
    final row = WaxNotification(
      kind: kind,
      message: message,
      at: at,
      locationOverride: location,
    );
    // Deduplicated on the location too: two shows whose feeds both
    // failed say the same sentence and must stay two rows.
    final kept = <WaxNotification>[
      row,
      for (final existing in state)
        if (existing.kind != kind ||
            existing.message != message ||
            existing.location != row.location)
          existing,
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

  /// Records what one server-state change means, or nothing where it
  /// means nothing worth telling anybody about.
  ///
  /// The user stream is a state-change stream rather than an event log,
  /// so every kind that survives here is a marker: it names a surface
  /// that moved and carries no detail, which is exactly as much as the
  /// row claims. The hydrated kinds (a play state, a preference, a book's
  /// settings) are this client's own writes coming back as often as
  /// anybody else's, and a notification for "your position was saved" is
  /// noise with a bell on it.
  /// One switch rather than two, so a kind and what it says are decided
  /// in one place. Two of them meant an arm for every enum value
  /// including the ones this map cannot produce, and an arm that cannot
  /// run is an empty message waiting to be drawn by whoever adds the
  /// producer.
  void recordServerEvent(ServerSyncEvent event, {DateTime? at}) {
    final pid = event.pid;
    final (
      NotificationKind? kind,
      String message,
      String? location,
    ) = switch (event.kind) {
      'review' => (NotificationKind.review, 'The review queue changed.', null),
      'upload' => (NotificationKind.upload, 'An upload changed.', null),
      'task' => (NotificationKind.task, 'A background task changed.', null),
      // The announcements. Generic messages because a marker carries no
      // detail; the surface it opens has it.
      'feed-disabled' => (
        NotificationKind.feedDisabled,
        'A show kept failing to refresh and was disabled.',
        pid == null ? null : WaxRoute.show(pid),
      ),
      'import-completed' => (
        NotificationKind.importCompleted,
        'An upload was identified and added to the library.',
        null,
      ),
      'episode-downloaded' => (
        NotificationKind.episodeDownloaded,
        'A new episode finished downloading.',
        pid == null ? null : WaxRoute.episode(pid),
      ),
      _ => (null, '', null),
    };
    if (kind == null) return;
    record(kind, message, at: at ?? DateTime.now(), location: location);
  }

  /// Native only: web has no local download manager, so no transfer of
  /// its own to announce. Server-side fetches ride the stream above.
  void recordDownloadCompleted({DateTime? at}) {
    record(
      NotificationKind.download,
      'A download finished.',
      at: at ?? DateTime.now(),
    );
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
