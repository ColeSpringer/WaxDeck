import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../player/now_playing_controller.dart';
import '../player/now_playing_slot.dart';
import '../player/play_progress.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import 'item_menu.dart';

/// Starts or resumes [item] where it stands, going nowhere: the one play
/// verb behind every shelf's cover play, the Continue listening shelves'
/// tap, and the item menu's Play and Resume.
///
/// What this app already holds carries on in place (see [resumeInPlace]);
/// anything else starts through [playHomeItem].
void playOrResumeItem(
  WidgetRef ref,
  ItemSummary item,
  PlayProgress progress, {
  bool fromMirror = false,
}) {
  if (resumeInPlace(ref, item.pid, finished: progress.finished)) return;
  playHomeItem(ref, item, progress, fromMirror: fromMirror);
}

/// Whether [playOrResumeItem] on [item] at [progress] carries on a saved
/// place, which is what a "Resume" label promises: spoken word part way
/// through. A fresh track start goes to its head, so a track reads Play.
bool playResumes(ItemSummary item, PlayProgress progress) =>
    item.mediaType != MediaType.music && progress.inProgress;

/// The label a card's cover play carries: Resume for an [item] that
/// [playResumes], nothing for one that starts afresh.
String? resumeLabel(
  AppLocalizations l10n,
  ItemSummary item,
  PlayProgress progress,
) => playResumes(item, progress) ? l10n.libraryResumeItem(item.title) : null;

/// Opens the menu behind a card's kebab: pin, and for a book its play,
/// labelled Resume when [playResumes]. [withOpen] adds the item's own
/// screen, for a shelf whose tap resumes instead of opening it.
Future<void> showItemCardMenu(
  BuildContext context,
  WidgetRef ref,
  ItemSummary item,
  PlayProgress progress, {
  bool withOpen = false,
}) => showItemMenuForSummary(
  context,
  ref,
  item,
  withPin: true,
  onPlay: item.mediaType == MediaType.audiobook
      ? (ref) => playOrResumeItem(ref, item, progress)
      : null,
  inProgress: playResumes(item, progress),
  withOpen: withOpen,
);

/// Carries [pid] on when it is what this app already holds, answering
/// whether it did: the current entry plays on without a new start, live
/// or still loading (the press folds into the load), and an entry a
/// station parked comes back at its checkpoint with its queue, as the
/// deck's Resume does. A start that failed starts afresh.
///
/// A finished item never resumes: a session parked at its end would play
/// its last second and stop again, so it starts from its head instead.
bool resumeInPlace(WidgetRef ref, String pid, {required bool finished}) {
  if (finished) return false;
  final playback = ref.read(nowPlayingProvider.notifier);
  if (ref.read(nowPlayingSlotProvider) case ItemSlot(
    :final now,
  ) when now.entry?.pid == pid && (now.session != null || now.loading)) {
    unawaited(playback.transportPlay());
    return true;
  }
  if (ref.read(parkedEntryProvider)?.entry.pid == pid) {
    unawaited(
      playback.playEntryAt(ref.read(queueControllerProvider).currentIndex),
    );
    return true;
  }
  return false;
}

/// Plays one shelf item where it stands, going nowhere.
///
/// The start behind [playOrResumeItem], and behind `openHomeItem`'s track
/// arm. Playback lands in the dock whatever raised it; the deck bar is the
/// way into the full player.
///
/// One item, and it says so: a shelf is a dozen unrelated covers rather
/// than a running order, and queueing the shelf would fill the queue with
/// a view. A book names itself as the source instead, because its parts
/// roll inside the session and there is nothing else in the queue for
/// them to be.
///
/// The session reads the item's checkpoint (the newest, with its smart
/// rewind) unless [fromMirror] says [progress] came off this device's
/// mirror, the Downloaded shelf's, which is the one a caller holds
/// with no server to ask; that one carries spoken word on, and a track
/// starts at its head as every track does. A finished item starts from
/// its head.
void playHomeItem(
  WidgetRef ref,
  ItemSummary item,
  PlayProgress progress, {
  bool fromMirror = false,
}) {
  ref
      .read(nowPlayingProvider.notifier)
      .play(
        <ItemSummary>[item],
        source: QueueSource(
          kind: item.mediaType == MediaType.audiobook
              ? QueueSourceKind.book
              : QueueSourceKind.single,
          label: item.title,
          pid: item.pid,
        ),
        positionMs: progress.finished
            ? 0
            : (fromMirror && playResumes(item, progress)
                  ? progress.positionMs
                  : null),
      );
}
