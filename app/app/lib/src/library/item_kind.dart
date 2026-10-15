import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../books/books_controller.dart';
import '../connect/queue_gateway.dart';
import '../home/home_shelves.dart';
import '../l10n/l10n.dart';
import '../metadata/metadata_controller.dart';
import '../music/album_detail.dart';
import '../music/music_controllers.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../radio/radio_controller.dart';
import '../settings/settings_registry.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';

/// How often the dialog asks after a running kind change, and how many
/// times before it lets the change carry on unwatched: a part is a file
/// read, so even a long book is seconds, and a minute is a stall.
const kindChangePoll = Duration(milliseconds: 500);
const kindChangePolls = 120;

/// The most items one kind change may name, the request's own limit.
const kindChangeMaxItems = 500;

/// Asks before turning [pids] into [to] (`audiobook` or `music`), runs
/// the change with the dialog showing it, and goes to what they became:
/// the book, or the album the first part landed on. Tracks named
/// together whose tags name one book become that one book. More [pids]
/// than one change may name (an album's, the one caller naming several)
/// are refused here rather than sent in part.
Future<void> confirmSetKind(
  BuildContext context, {
  required List<String> pids,
  required String to,
}) async {
  final l10n = context.l10n;
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = container.read(shellMessengerProvider.notifier);
  final router = GoRouter.of(context);
  final outcome = await showDialog<_KindOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SetKindDialog(pids: pids, to: to),
  );
  if (outcome == null) return;
  final error = outcome.error;
  if (error != null) {
    messenger.show(explainRefusal(l10n, error));
    return;
  }
  final job = outcome.job!;
  void invalidate() {
    container
      ..invalidate(musicItemsProvider)
      ..invalidate(albumDetailProvider)
      ..invalidate(bookDetailProvider)
      ..invalidate(booksProvider)
      ..invalidate(mayCurateItemProvider);
    for (final provider in homeShelfProviders) {
      container.invalidate(provider);
    }
  }

  switch (job.state) {
    case 'done':
      break;
    case 'failed' || 'crashed' || 'canceled':
      // What it did before it ended stands: a part it folded away is
      // let go of as on success, and why it stopped is what is said, in
      // the server's words, as a failed job carries no code to translate.
      await _letGoOfFolded(container, job.result);
      invalidate();
      final why = job.error?.trim() ?? '';
      messenger.show(
        why.isEmpty ? l10n.libraryKindFailed : l10n.libraryKindFailedWhy(why),
      );
      return;
    default:
      // Running, or a state this build does not know, which the
      // contract says is not finished yet.
      invalidate();
      if (container.read(isAdminProvider)) {
        messenger.show(
          l10n.libraryKindStillRunning,
          actionLabel: l10n.bookToolTasks,
          onAction: () => router.pushInShell<void>(WaxRoute.tasks),
          actionSemanticsId: SemanticsIds.openTasks,
          persist: true,
        );
      } else {
        messenger.show(l10n.libraryKindQueued);
      }
      return;
  }
  final result = job.result ?? const <String, Object?>{};
  if (_unchanged(result)) {
    // Every item named already had the kind (a view drawn before another
    // device changed it), which the server skips rather than refuses.
    invalidate();
    messenger.show(
      to == 'audiobook'
          ? l10n.libraryKindAlreadyBook(pids.length)
          : l10n.libraryKindAlreadyMusic(pids.length),
    );
    return;
  }
  final notes = <String>[];
  final failures = result['writeBackFailures'];
  if (failures is List && failures.isNotEmpty) {
    notes.add(l10n.metadataWriteBackWarning);
  }
  if (await _letGoOfFolded(container, result)) {
    notes.add(l10n.libraryKindStoppedPlaying);
  }
  if (_joinedUnseen(result)) notes.add(l10n.libraryKindJoinedUnseen);
  if (notes.isNotEmpty) messenger.show(notes.join('\n'));
  // Where to go is read before the listings are dropped, so the screen
  // still showing the old kind does not refetch it and draw its error
  // while the destination loads.
  final destination = await _destination(container, _landedPid(result), to);
  invalidate();
  if (destination != null) router.go(destination);
}

/// Lets go of what [result] says was folded away, gone under either
/// prefix: the queue drops it, and where it was playing it stops and
/// goes too, what followed it waiting rather than starting. Answers
/// whether that stopped playback. A station tuned over the queue is
/// what plays then, not the queue's entry, and is left alone.
Future<bool> _letGoOfFolded(
  ProviderContainer container,
  Map<String, Object?>? result,
) async {
  final absorbed = result?['absorbed'];
  if (absorbed is! Map || absorbed.isEmpty) return false;
  final gone = {
    for (final pid in absorbed.keys)
      if (pid is String) pid.substring(pid.indexOf('-') + 1),
  };
  final current = container
      .read(queueControllerProvider.notifier)
      .dropItems(gone);
  if (!current || container.read(radioPlaybackProvider).station != null) {
    return false;
  }
  await container.read(queueGatewayProvider).stop();
  container.read(nowPlayingProvider.notifier).dropCurrent();
  return true;
}

/// The location of what the change made of [landed]: the book, or the
/// album its first part sits on (the track listing when it sits on none,
/// or cannot be read).
Future<String?> _destination(
  ProviderContainer container,
  String? landed,
  String to,
) async {
  if (landed == null) return null;
  if (to == 'audiobook') return WaxRoute.book(landed);
  try {
    final albumPid =
        (await container.read(repositoryProvider).getItem(landed)).albumPid;
    return albumPid == null
        ? WaxRoute.musicTracks
        : WaxRoute.musicBucket(MusicDimension.albums, albumPid);
  } on WaxDeckApiException {
    return WaxRoute.musicTracks;
  }
}

/// Whether a finished change converted, folded and created nothing: the
/// tally the server reports, empty in every part.
bool _unchanged(Map<String, Object?> result) => switch (result) {
  {
    'converted': List<Object?>(isEmpty: true),
    'absorbed': Map<Object?, Object?>(isEmpty: true),
    'created': List<Object?>(isEmpty: true),
  } =>
    true,
  _ => false,
};

/// The item the change landed the first named one on: the first
/// converted, else the first item an absorbed one went into that the
/// reader may open.
String? _landedPid(Map<String, Object?> result) {
  final converted = result['converted'];
  if (converted is List && converted.isNotEmpty) {
    return converted.first as String?;
  }
  final absorbed = result['absorbed'];
  if (absorbed is Map) {
    for (final to in absorbed.values) {
      if (to is String && to.isNotEmpty) return to;
    }
  }
  return null;
}

/// Whether the change folded something into an item in a library the
/// reader is not granted, which the server names by an empty string.
bool _joinedUnseen(Map<String, Object?> result) => switch (result['absorbed']) {
  final Map<Object?, Object?> absorbed => absorbed.values.contains(''),
  _ => false,
};

/// What the dialog came back with: the job as it last read, or the
/// refusal that kept it from starting.
class _KindOutcome {
  const _KindOutcome({this.job, this.error});

  final Job? job;
  final WaxDeckApiException? error;
}

class _SetKindDialog extends ConsumerStatefulWidget {
  const _SetKindDialog({required this.pids, required this.to});

  final List<String> pids;
  final String to;

  @override
  ConsumerState<_SetKindDialog> createState() => _SetKindDialogState();
}

class _SetKindDialogState extends ConsumerState<_SetKindDialog> {
  var _writeBack = false;
  var _running = false;

  bool get _toBook => widget.to == 'audiobook';

  bool get _tooMany => widget.pids.length > kindChangeMaxItems;

  Future<void> _run() async {
    setState(() => _running = true);
    final repository = ref.read(repositoryProvider);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context)!;
    // This dialog's own route, never what is on top: something can open
    // over it while the change runs (a shared link, a notice), and a pop
    // would close that instead and leave this one spinning.
    void close(_KindOutcome outcome) {
      if (!mounted || !route.isActive) return;
      if (route.isCurrent) {
        navigator.pop(outcome);
      } else {
        navigator.removeRoute(route, outcome);
      }
    }

    Job job;
    try {
      job = await repository.setItemKind(
        widget.pids,
        mediaType: widget.to,
        writeBack: _writeBack,
      );
    } on WaxDeckApiException catch (e) {
      close(_KindOutcome(error: e));
      return;
    }
    // Started: a poll that goes unanswered leaves the job as it last
    // read, still running, rather than reading as a refusal.
    for (var i = 0; !job.ended && i < kindChangePolls; i++) {
      await Future<void>.delayed(kindChangePoll);
      if (!mounted) return;
      try {
        job = await repository.getJob(job.pid);
      } on WaxDeckApiException {
        break;
      }
    }
    close(_KindOutcome(job: job));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Once started the change runs on the server whatever happens here,
    // so a back press must not close the dialog that reports it: the
    // listings, the queue and the person would never hear how it ended.
    return PopScope(canPop: !_running, child: _dialog(l10n));
  }

  Widget _dialog(AppLocalizations l10n) {
    return AlertDialog(
      title: Text(
        _toBook ? l10n.libraryKindToBookTitle : l10n.libraryKindToMusicTitle,
      ),
      content: _running
          ? Row(
              children: <Widget>[
                const WaxSpinner(),
                const SizedBox(width: WaxSpace.s12),
                Expanded(child: Text(l10n.libraryKindWorking)),
              ],
            )
          : _tooMany
          ? WaxProse(l10n.libraryKindAlbumTooLarge(kindChangeMaxItems))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                WaxProse(
                  _toBook
                      ? l10n.libraryKindToBookBody(widget.pids.length)
                      : l10n.libraryKindToMusicBody,
                ),
                const SizedBox(height: WaxSpace.s12),
                WaxSettingRow(
                  title: l10n.metadataWriteBackTitle,
                  help: l10n.libraryKindWriteBackHelp,
                  control: WaxSwitch(
                    label: l10n.metadataWriteBackTitle,
                    value: _writeBack,
                    semanticsId: SemanticsIds.kindWriteBack,
                    onChanged: (v) => setState(() => _writeBack = v),
                  ),
                ),
              ],
            ),
      actions: _running
          ? const <Widget>[]
          : _tooMany
          ? <Widget>[
              WaxButton(
                label: l10n.commonClose,
                kind: WaxButtonKind.text,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]
          : <Widget>[
              WaxButton(
                label: l10n.commonCancel,
                kind: WaxButtonKind.text,
                onPressed: () => Navigator.of(context).pop(),
              ),
              WaxButton(
                label: l10n.libraryKindConfirm,
                semanticsId: SemanticsIds.kindConfirm,
                onPressed: _run,
              ),
            ],
    );
  }
}
