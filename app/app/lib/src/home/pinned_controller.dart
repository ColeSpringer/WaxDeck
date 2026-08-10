import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../settings/prefs_controller.dart';

/// What this listener has pinned to home, in shelf order.
///
/// A pin follows the account rather than the device, for the reason the
/// radio dial's does: pinning a record on the
/// desktop and not finding it on the phone reads as the pin having
/// failed. So the list lives in the preference document, and this
/// notifier is the radio dial's twin over the other field.
///
/// State is synchronous, like the dial's: the shelf draws what is loaded
/// and nothing while the document is still in flight.
class PinnedEntities extends Notifier<List<String>> {
  /// What the document may hold, from the contract's `maxItems`. The
  /// shelf draws all of them, so unlike the dial there is no second,
  /// smaller presentation cap: a pinned shelf that silently stopped at
  /// twelve would be a pin that appears to have done nothing.
  static const limit = 64;

  /// One rule about what the list may hold: no duplicates, no blanks,
  /// never past what the document allows. Everything that builds one goes
  /// through it, so another client's document obeys it too.
  static List<String> _clean(Iterable<String> pids) {
    final seen = <String>{};
    final kept = <String>[];
    for (final pid in pids) {
      if (pid.isEmpty || !seen.add(pid)) continue;
      kept.add(pid);
      if (kept.length == limit) break;
    }
    return kept;
  }

  @override
  List<String> build() {
    // Watched, so a pin made on another device lands here: the server
    // emits a prefs event and the document is refetched. Whatever the
    // document says replaces optimistic state, which is what keeps the
    // server the authority rather than this notifier.
    final prefs = ref.watch(prefsControllerProvider).value;
    return _clean(prefs?.pinned ?? const <String>[]);
  }

  /// By contents, not by identity.
  ///
  /// [build] mints a fresh list every run and a List's `==` is identity,
  /// so the default would report a change on every prefs write - a theme
  /// toggle, a crossfade, a browse sort - and each of those would re-run
  /// [pinnedCardsProvider], which is a network read of up to 64 pids. It
  /// also fires twice per pin: once optimistically and once when the
  /// stored document comes back saying the same thing.
  @override
  bool updateShouldNotify(List<String> previous, List<String> next) =>
      !listEquals(previous, next);

  bool contains(String pid) => state.contains(pid);

  bool get full => state.length >= limit;

  /// Pins or unpins. A pin goes on the end, so the shelf's order is the
  /// order things were pinned in and does not reshuffle under a thumb.
  ///
  /// Answers null when the change landed, or the message to show when it
  /// did not: a full list, or the server's refusal. Returned rather than
  /// thrown because the callers are menu rows, which are not places an
  /// unhandled rejection can be seen.
  ///
  /// Optimistic, because a pin that waits for a round trip reads as a
  /// dropped tap; a refused write puts the old list back.
  Future<String?> toggle(String pid) async {
    final before = state;
    final pinned = state.contains(pid);
    if (!pinned && full) {
      return 'Home holds $limit pins. Unpin something to make room.';
    }
    state = pinned
        ? <String>[
            for (final entry in state)
              if (entry != pid) entry,
          ]
        : _clean([...state, pid]);
    try {
      await ref.read(prefsControllerProvider.notifier).setPinned(state);
      return null;
    } on Object catch (e) {
      // Everything, not only the server's own refusal. The write goes
      // through the whole prefs chain - a session load, a fetch of the
      // current document, then the PUT - and only a Dio failure is
      // translated on the way out; a decode error or a timeout arrives
      // untranslated. Caught narrowly, those would leave the shelf
      // showing a pin that was never stored (so the next toggle writes
      // from the wrong base) and escape into an unhandled zone error,
      // because every caller invokes this unawaited.
      if (ref.mounted) state = before;
      return e is WaxDeckApiException ? e.message : 'That pin was not saved.';
    }
  }

  /// Drops exactly [departed] from the document: the pids the resolver
  /// named gone-for-everyone, which are the only slots safe to reclaim
  /// unasked. A merely-unresolved pid is never passed here - the server
  /// leaves it unnamed precisely because it may come back - so a shelf
  /// read against a half-loaded library still prunes nothing.
  ///
  /// A failed write puts the list back, the way [toggle] does. Nothing
  /// else would: the preference controller only advances its own state
  /// on success, so a shortened list that stayed would disagree with
  /// the stored document for the rest of the session - and the next
  /// pin, which writes the whole list from here, would commit the drop
  /// that failed.
  Future<void> prune(List<String> departed) async {
    final gone = departed.toSet();
    final before = state;
    final next = <String>[
      for (final pid in before)
        if (!gone.contains(pid)) pid,
    ];
    if (next.length == before.length) return;
    state = next;
    try {
      await ref.read(prefsControllerProvider.notifier).setPinned(next);
    } on Object {
      if (ref.mounted) state = before;
    }
  }
}

final pinnedEntitiesProvider = NotifierProvider<PinnedEntities, List<String>>(
  PinnedEntities.new,
);

/// The pinned entities that still resolve, as cards, in shelf order.
///
/// The pids are handles, not snapshots, so drawing them means asking the
/// server what they are now. The endpoint drops what it cannot answer
/// for - deleted, merged away, unsubscribed, outside the caller's
/// libraries - and separately names the subset that is gone for
/// everyone. Only that named subset is pruned from the document: a pid
/// that merely failed to resolve stays, because a list read while the
/// library is still loading must not prune itself against an empty
/// answer, and the server withholds the name in exactly those states.
final pinnedCardsProvider = FutureProvider.autoDispose<List<EntityCard>>((
  ref,
) async {
  final pinned = ref.watch(pinnedEntitiesProvider);
  if (pinned.isEmpty) return const <EntityCard>[];
  final resolution = await ref
      .watch(repositoryProvider)
      .resolveEntities(pinned);
  if (resolution.departed.isNotEmpty) {
    // After this build settles, not during it: the prune rewrites the
    // pinned list, which this provider watches, and a rebuild kicked
    // off mid-build is a provider-lifecycle error. The re-resolve it
    // triggers asks without the pruned pids and answers no departed,
    // so the loop closes in one extra read. Mounted-guarded, because
    // this provider auto-disposes and a ref past its life throws.
    unawaited(
      Future<void>.microtask(() async {
        if (!ref.mounted) return;
        await ref
            .read(pinnedEntitiesProvider.notifier)
            .prune(resolution.departed);
      }),
    );
  }
  return resolution.cards;
});
