import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'queue_controller.dart';
import 'queue_persistence.dart';

/// What this account was playing, on any device, before now.
///
/// The server keeps a few ended sessions per user and prunes the rest,
/// so this is short and unpaged by design: a way back into what was
/// playing, not a listening log. Auto-disposing, because it is only
/// worth an answer while a surface is showing it.
final sessionHistoryProvider = FutureProvider.autoDispose
    .family<List<PlaybackSessionHistoryEntry>, void>((ref, _) async {
      return ref.watch(repositoryProvider).listPlaybackSessionHistory();
    });

/// The queue surface's way back to an earlier session.
///
/// Sessions rather than one offer, because they are not the same thing:
/// the deck bar's offer is about the launch that just happened, and this
/// is about the account. A listener who started something new and wants
/// the album from this morning back finds it here.
class SessionHistorySection extends ConsumerWidget {
  const SessionHistorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    // Failures are silent on purpose: this is an extra at the bottom of
    // the queue, and a launch offline should show a queue rather than an
    // error about a surface nobody asked for.
    final sessions =
        ref.watch(sessionHistoryProvider(null)).value ??
        const <PlaybackSessionHistoryEntry>[];
    final restorable = <PlaybackSessionHistoryEntry>[
      for (final session in sessions)
        if (session.entries.isNotEmpty) session,
    ];
    if (restorable.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WaxSpace.s16,
        WaxSpace.s24,
        WaxSpace.s16,
        WaxSpace.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.l10n.queueEarlier,
            style: WaxType.overline.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: WaxSpace.s8),
          for (final session in restorable)
            Padding(
              padding: const EdgeInsets.only(bottom: WaxSpace.s8),
              child: WaxTappable(
                label: context.l10n.queueRestoreSession(_title(session)),
                // Per session: the list holds several, and one
                // identifier across all of them is ambiguous to a
                // screen reader walking it and unusable to a test.
                semanticsId: SemanticsIds.queueRestoreSession(session.id),
                onPressed: () => _restore(context, ref, session),
                child: InkWell(
                  onTap: () => _restore(context, ref, session),
                  child: Padding(
                    padding: const EdgeInsets.all(WaxSpace.s8),
                    child: Row(
                      children: <Widget>[
                        WaxIcon(
                          WaxIcons.recent,
                          size: 16,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: WaxSpace.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _title(session),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WaxType.bodySmall.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (_caption(session).isNotEmpty)
                                Text(
                                  _caption(session),
                                  style: WaxType.caption.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Puts an earlier session back, and offers the way out.
  ///
  /// Unlike the deck bar's launch offer, this section is on screen while
  /// something is playing, so a tap here replaces a live queue. The
  /// queue layer keeps what it displaced for exactly this; without a way
  /// to ask for it back, a mis-tap in a list of old sessions would be a
  /// queue destroyed with no recourse.
  void _restore(
    BuildContext context,
    WidgetRef ref,
    PlaybackSessionHistoryEntry session,
  ) {
    final l10n = context.l10n;
    final playback = ref.read(nowPlayingProvider.notifier);
    final displaced = ref.read(queueControllerProvider).isNotEmpty;
    playback.restore(queueFromSession(session), offerUndo: displaced);
    if (!displaced) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // "Restored", because restore's contract is put-it-back,
          // paused: nothing is playing when this shows.
          content: Text(l10n.queueRestored(_title(session))),
          action: SnackBarAction(
            label: l10n.queueUndo,
            onPressed: playback.undoReplace,
          ),
        ),
      );
  }

  /// What the session was on when it stopped. The entry it stopped on,
  /// because that is what putting it back would play.
  String _title(PlaybackSessionHistoryEntry session) =>
      session.currentEntry?.title ?? '${session.entries.length} queued items';

  /// Empty for a lone entry from an endpoint that has since gone away,
  /// where there is nothing left to say and a blank line under the title
  /// would be a gap rather than a caption.
  String _caption(PlaybackSessionHistoryEntry session) => <String>[
    if (session.entries.length > 1) '${session.entries.length} items',
    if (session.endpointName != null) 'on ${session.endpointName}',
  ].join(' · ');
}
