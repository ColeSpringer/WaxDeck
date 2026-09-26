import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../home/pin_action.dart';
import '../home/pinned_controller.dart';
import '../l10n/l10n.dart';
import '../metadata/artwork_manager.dart';
import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'episode_actions.dart';
import 'mark_older_played_dialog.dart';
import 'podcast_shelves.dart';
import 'podcasts_controller.dart';

/// What a show's menus offer. The header's overflow and a show card's
/// sheet draw the same list, from [showActionsFor].
enum ShowAction { pin, refresh, markOlder, setCover }

/// The actions show [pid] offers this session, in menu order.
List<ShowAction> showActionsFor(
  WidgetRef ref,
  String pid, {
  required bool subscribed,
}) => <ShowAction>[
  // Pinned shows resolve through the caller's subscriptions, so only a
  // subscriber pins; one who unsubscribed keeps the row to unpin with.
  if (subscribed || ref.watch(pinnedEntitiesProvider).contains(pid))
    ShowAction.pin,
  ShowAction.refresh,
  if (subscribed) ShowAction.markOlder,
  // The session's managePodcasts is the server's effective answer,
  // administrators included.
  if (ref.watch(canManagePodcastsProvider)) ShowAction.setCover,
];

/// How an action reads in either menu. Null for the pin, whose words
/// follow its state, so each menu draws that row itself.
({String label, WaxGlyph glyph, String? semanticsId})? _describe(
  AppLocalizations l10n,
  ShowAction action,
) => switch (action) {
  ShowAction.pin => null,
  ShowAction.refresh => (
    label: l10n.podcastCheckForNew,
    glyph: WaxIcons.refresh,
    semanticsId: null,
  ),
  ShowAction.markOlder => (
    label: l10n.podcastMarkOlderPlayed,
    glyph: WaxIcons.check,
    semanticsId: SemanticsIds.markOlderPlayed,
  ),
  ShowAction.setCover => (
    label: l10n.podcastSetCover,
    glyph: WaxIcons.edit,
    semanticsId: SemanticsIds.showSetCover,
  ),
};

/// The show header's overflow entries.
List<WaxMenuItem<ShowAction>> showMenuItems(
  BuildContext context,
  WidgetRef ref,
  String pid, {
  required bool subscribed,
}) {
  final l10n = context.l10n;
  return <WaxMenuItem<ShowAction>>[
    for (final action in showActionsFor(ref, pid, subscribed: subscribed))
      if (_describe(l10n, action) case final entry?)
        WaxMenuItem<ShowAction>(
          value: action,
          label: entry.label,
          glyph: entry.glyph,
          semanticsId: entry.semanticsId,
        )
      else
        pinMenuItem<ShowAction>(
          context,
          ref,
          pid,
          value: action,
          semanticsId: SemanticsIds.showPin,
        ),
  ];
}

/// A show card's sheet: the header's list, drawn as rows.
Future<void> showShowMenuSheet(
  BuildContext context,
  WidgetRef ref,
  PodcastShow show, {
  required bool subscribed,
}) async {
  final l10n = context.l10n;
  final action = await showWaxOptionSheet<ShowAction>(
    context,
    builder: (sheetContext) => Consumer(
      builder: (_, sheetRef, _) {
        void choose(ShowAction action) =>
            Navigator.of(sheetContext).pop(action);
        return Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.itemMenuSheet(show.pid),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final action in showActionsFor(
                sheetRef,
                show.pid,
                subscribed: subscribed,
              ))
                if (_describe(l10n, action) case final entry?)
                  WaxOptionRow(
                    title: entry.label,
                    glyph: entry.glyph,
                    semanticsId: entry.semanticsId,
                    onTap: () => choose(action),
                  )
                else
                  pinSheetRow(sheetContext, sheetRef, (
                    pid: show.pid,
                    what: 'podcast',
                    name: show.title,
                  ), onTap: () => choose(action)),
            ],
          ),
        );
      },
    ),
  );
  if (action == null || !context.mounted) return;
  await runShowAction(
    context,
    ref,
    action,
    pid: show.pid,
    title: show.title,
    hasArtwork: show.artSource != null,
  );
}

/// Runs [action] on show [pid]. [title] is null while the show is still
/// loading; the pin's confirmation then names nothing rather than a
/// stand-in word.
Future<void> runShowAction(
  BuildContext context,
  WidgetRef ref,
  ShowAction action, {
  required String pid,
  required String? title,
  required bool hasArtwork,
}) async {
  switch (action) {
    case ShowAction.pin:
      await togglePin(context, ref, pid, label: title);
    case ShowAction.refresh:
      await _refresh(context, pid);
    case ShowAction.markOlder:
      await showDialog<void>(
        context: context,
        builder: (_) => MarkOlderPlayedDialog(pid: pid),
      );
    case ShowAction.setCover:
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ShowCoverSheet(
          pid: pid,
          title: title ?? pid,
          initialHasArtwork: hasArtwork,
        ),
      );
  }
}

Future<void> _refresh(BuildContext context, String pid) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  // The container rather than a widget's ref, which a card can outlive.
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final result = await container.read(repositoryProvider).refreshPodcast(pid);
    // New episodes change what the hub's tile and shelves say, and the
    // count a tile draws lives on the subscription row.
    container
      ..invalidate(episodesProvider(pid))
      ..invalidate(podcastDetailProvider(pid))
      ..invalidate(subscriptionsProvider)
      ..invalidate(upNextEpisodesProvider)
      ..invalidate(latestEpisodesProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.newEpisodes == 0
                ? l10n.podcastNoNewEpisodes
                : l10n.podcastNewEpisodes(result.newEpisodes),
          ),
        ),
      );
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
  }
}

/// The episode a show's own play starts: the newest not yet finished,
/// else the newest. [newestFirst] is the order the show's listing answers.
EpisodeSummary nextEpisodeOf(
  List<EpisodeSummary> newestFirst,
  PlayProgressView progress,
) => newestFirst.firstWhere(
  (episode) => !progress[episode.pid].played,
  orElse: () => newestFirst.first,
);

/// Plays show [showPid] from its cover: [nextEpisodeOf] its first page,
/// resumed at its checkpoint, or from the start when all were heard.
Future<void> playShowLatest(
  BuildContext context,
  WidgetRef ref,
  String showPid,
) async {
  // Read before the awaits: the card may be gone when the answer lands,
  // and the play is honoured anyway.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final repository = ref.read(repositoryProvider);
  final playback = ref.read(nowPlayingProvider.notifier);
  try {
    final page = await repository.listEpisodes(
      showPid,
      limit: EpisodesController.pageSize,
    );
    if (page.items.isEmpty) return;
    final states = await repository.listPlayStates(<String>[
      for (final episode in page.items) episode.pid,
    ]);
    final progress = PlayProgressView(<String, PlayProgress>{
      for (final state in states) state.pid: PlayProgress.of(state),
    });
    final episode = nextEpisodeOf(page.items, progress);
    if (!EpisodeActions.playable(episode)) {
      // Fetching first reports through the card, so it needs one. No show
      // pid: the hub draws no list of this show's to refresh.
      if (context.mounted) {
        await EpisodeActions(ref: ref).fetchAndWait(context, episode);
      }
      return;
    }
    // Only an explicit zero starts a heard episode over: a null resumes
    // its checkpoint, which sits short of the end.
    EpisodeActions.playOn(
      playback,
      episode,
      positionMs: progress[episode.pid].played ? 0 : null,
    );
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
  }
}

/// The show's cover, managed as the podcast entity: set, clear, and pin
/// through the entity artwork endpoints. A sheet rather than a route: the
/// cover has no address of its own.
class ShowCoverSheet extends ConsumerWidget {
  const ShowCoverSheet({
    super.key,
    required this.pid,
    required this.title,
    required this.initialHasArtwork,
  });

  final String pid;
  final String title;

  /// What the show detail knew when the sheet opened, so the first
  /// frame does not read "no cover" while the art-roles read is in flight.
  final bool initialHasArtwork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The art-roles read answers show pids too, so the manager knows
    // whether a cover stands before any write.
    final roles = ref.watch(itemArtRolesProvider(pid));
    final hasArtwork = roles.hasValue
        ? roles.value?.artSource != null
        : initialHasArtwork;
    return Padding(
      padding: EdgeInsets.only(
        left: WaxSpace.s16,
        right: WaxSpace.s16,
        top: WaxSpace.s16,
        bottom: WaxSpace.s16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: ArtworkManager(
          pid: pid,
          title: title,
          hasArtwork: hasArtwork,
          entityType: 'podcast',
          onChanged: () => ref.invalidate(podcastDetailProvider(pid)),
        ),
      ),
    );
  }
}
