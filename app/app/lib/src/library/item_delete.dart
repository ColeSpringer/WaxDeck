import 'dart:async';

import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../home/home_shelves.dart';
import '../music/entity_facts.dart';
import '../music/music_controllers.dart';
import '../shell/navigation_history.dart';
import '../shell/router.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';

/// Whether this account is offered destructive catalog verbs.
///
/// The server enforces the permission either way; this is what decides
/// whether the affordance is drawn at all, which is the house rule for
/// permission-gated actions - hidden, never disabled. The session's
/// `delete` is the server's *effective* answer (administrators always
/// hold it); the role check is the fallback for a server too old to
/// report the field, where only administrators could delete anyway.
bool canDeleteItems(WidgetRef ref) {
  final user = ref.watch(authControllerProvider).value?.user;
  if (user == null) return false;
  return user.canDelete || user.roles.contains('admin');
}

/// Previews a deletion with a dry run, then performs the mode the
/// listener picked.
///
/// A function rather than a widget, because each surface that offers the
/// verb draws it in its own shape: a row of a track's sheet, a row of the
/// player's overflow menu, a row of a book screen's overflow, a copy's
/// button on the Details sheet, and (through [confirmDeleteItems]) a row
/// of an album screen's overflow.
/// Takes no `ref` on purpose: the work outlives the widget that asked
/// for it, so it goes through the container rather than through a
/// caller's provider dependencies - which is the whole point of the
/// capture below.
///
/// With [filePids] it deletes those files of the item rather than the
/// whole item (a copy, from the Details sheet), and the item stays.
///
/// [onDeleted] runs once what was asked for is gone (every file went and
/// no item stays on a file the deletion left), so a screen showing the
/// item can leave it, and only where the page on top is then one of the
/// item's own, told by its location: the page the delete was asked from,
/// the item's book, editor or episode, or the full player while it plays
/// the item. A visitor who went elsewhere while the server answered keeps
/// their screen, and back and a tab tap leave the item's pages out either
/// way. Whatever was opened over the page meanwhile closes first, and
/// once the leave has landed, the flow steps off the page too where it is
/// still one of the item's own (a caller that only closed what lay over
/// it, as the full player does).
Future<void> confirmDeleteItem(
  BuildContext context, {
  required String pid,
  List<String>? filePids,
  VoidCallback? onDeleted,
}) => _confirmDelete(
  context,
  pids: [pid],
  filePids: filePids,
  onDeleted: onDeleted,
);

/// The most items one delete may name, the request's own limit.
const itemDeleteMaxItems = 500;

/// [confirmDeleteItem] for several items at once: an album's tracks, or
/// every track one file holds. [pages] are locations that go with them
/// (an album's screen and its editor): forgotten with the items' own, and
/// counted among them for [onDeleted].
Future<void> confirmDeleteItems(
  BuildContext context, {
  required List<String> pids,
  List<String> pages = const <String>[],
  VoidCallback? onDeleted,
}) => _confirmDelete(context, pids: pids, pages: pages, onDeleted: onDeleted);

Future<void> _confirmDelete(
  BuildContext context, {
  required List<String> pids,
  List<String>? filePids,
  List<String> pages = const <String>[],
  VoidCallback? onDeleted,
  PageId? asked,
}) async {
  // Read here: it is wanted after an await, and a context is not read
  // across one.
  final l10n = context.l10n;
  // The router outlives the screen; the page the delete is asked from is
  // the caller's own, told by where it is, whatever is on top by now.
  final router = GoRouter.maybeOf(context);
  final from =
      asked ?? (router == null || onDeleted == null ? null : pageIn(context));
  // The container rather than `ref`, for the same reason the mark-older
  // dialog holds one: the deletion happens whether or not the screen
  // that offered it is still mounted when the server answers, and the
  // listings showing what just went have to be told regardless.
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = container.read(shellMessengerProvider);
  final repo = container.read(repositoryProvider);
  // Permanent deletion is admin-only on the server whatever the delete
  // right says, so the radio for it is drawn only where it can succeed
  // - hidden, never disabled, and never a 403 for the option offered.
  final allowPermanent =
      container
          .read(authControllerProvider)
          .value
          ?.user
          ?.roles
          .contains('admin') ??
      false;
  Future<DeleteItemsResult> delete({String? mode, bool dryRun = false}) =>
      filePids == null
      ? repo.deleteLibraryItems(pids: pids, mode: mode, dryRun: dryRun)
      : repo.deleteItemFiles(
          pid: pids.single,
          filePids: filePids,
          mode: mode,
          dryRun: dryRun,
        );
  // What a files delete changes is the item's file list and its copies.
  void rereadFiles() {
    if (filePids == null) return;
    container
      ..invalidate(itemFilesProvider(pids.single))
      ..invalidate(itemDetailProvider(pids.single));
  }

  final DeleteItemsResult plan;
  try {
    plan = await delete(dryRun: true);
  } on WaxDeckApiException catch (e) {
    // A track cut from one file with others goes with them or not at
    // all; the refusal names them, and they are offered with the tracks
    // asked for rather than left a dead end. Only to a delete of items:
    // one of files was asked for those files, never for items.
    final rip = filePids == null ? _ripTracks(e) : const <String>[];
    final all = [
      ...pids,
      for (final pid in rip)
        if (!pids.contains(pid)) pid,
    ];
    // No track beyond those asked for - no list, or one naming only
    // them - leaves nothing to offer: the same delete again would be
    // refused again, so the refusal is said as it stands.
    if (all.length == pids.length || !context.mounted) {
      if (e.isRefusal) rereadFiles();
      messenger.show(explainError(l10n, e), channel: ShellChannel.itemDelete);
      return;
    }
    // More than one delete may name is not offered: it would only be
    // refused after the listener agreed to it.
    if (all.length > itemDeleteMaxItems) {
      messenger.show(
        l10n.libraryDeleteRipTooMany(itemDeleteMaxItems),
        channel: ShellChannel.itemDelete,
      );
      return;
    }
    final whole = await showDialog<bool>(
      context: context,
      builder: (_) => _WholeFileDialog(
        chosen: pids.length,
        extra: all.length - pids.length,
      ),
    );
    if (whole == true && context.mounted) {
      await _confirmDelete(
        context,
        pids: all,
        pages: pages,
        onDeleted: onDeleted,
        asked: from,
      );
    }
    return;
  }
  if (!context.mounted) return;
  final mode = await showDialog<String>(
    context: context,
    builder: (_) =>
        _DeleteItemsDialog(plan: plan, allowPermanent: allowPermanent),
  );
  if (mode == null) return;
  try {
    final result = await delete(mode: mode);
    rereadFiles();
    // The listings that could be showing what just went: the music
    // listing this was opened from, and the home shelves, which draw
    // the same items from the other side. The catalog invalidation is
    // on its way too, and arrives whenever the socket does; this is
    // what makes the row leave now rather than shortly.
    container.invalidate(musicItemsProvider);
    for (final provider in homeShelfProviders) {
      container.invalidate(provider);
    }
    // What went, then how many stayed, then the server's sentences: a
    // copy that took a deleted file's place, which keeps the item where
    // the listing still shows it, and each file that stayed and why.
    final permanent = result.mode == 'permanent';
    final went = permanent ? result.deleted : result.trashed;
    final tried = went + result.failed;
    messenger.show(
      [
        permanent
            ? l10n.libraryDeletePermanentDone(went)
            : l10n.libraryDeleteTrashDone(went),
        if (result.failed > 0)
          permanent
              ? l10n.libraryDeletePermanentPartial(result.failed, tried)
              : l10n.libraryDeleteTrashPartial(result.failed, tried),
        ...result.warnings,
      ].join('\n'),
    );
    // A file that stayed, or an item a file keeps, leaves what was asked
    // for in the library, and a screen showing it with it.
    if (result.failed == 0 && !result.entries.any((e) => e.itemSurvives)) {
      final history = container.read(waxHistoryProvider);
      // Decided from where a step on its way lands (a collapse of the
      // player, say), as natively it would have landed already.
      if (history?.landing case final landing?) await landing;
      final own = _ownPages(container, pids: pids, pages: pages, from: from);
      // Left only from the item's own page: one the visitor moved to
      // while the server answered is theirs. Without a router there is
      // no other screen.
      final onScreen =
          onDeleted != null && (router == null || own(pageOnTop(router)));
      // What was opened over the page meanwhile closes first, or the
      // leave would close that instead of the page.
      if (onScreen && history != null && history.pagelessOnTop) {
        await history.closePageless();
      }
      // Left first: how the page pops is read off the visit on screen.
      if (onScreen) {
        onDeleted();
      } else {
        // Waiting under what the visitor opened over them, the items'
        // pages are taken out, so closing that shows what lay under them.
        history?.takeOutFromUnder(
          (location, _) => _isOwnLocation(location, pids: pids, pages: pages),
        );
      }
      _forgetItems(container, pids, pages);
      if (onScreen && history != null && router != null) {
        unawaited(_leaveItemPage(history, router, own));
      }
    }
  } on WaxDeckApiException catch (e) {
    // A refusal is the server's answer about the item as it stands, and
    // the list the file was picked from may be older: a copy deleted
    // elsewhere leaves it rather than refusing every tap.
    if (e.isRefusal) rereadFiles();
    messenger.show(explainError(l10n, e), channel: ShellChannel.itemDelete);
  }
}

/// Drops where back could return to an item that is gone, wherever the
/// delete was asked from: its book, its editor, its episode page, and
/// [pages], which go with the items. An episode is also visited beneath
/// its show, which a pid cannot name, so it goes by the tail of its path.
void _forgetItems(
  ProviderContainer container,
  List<String> pids,
  List<String> pages,
) {
  final history = container.read(waxHistoryProvider);
  if (history == null) return;
  for (final pid in pids.toSet()) {
    history
      ..forget(WaxRoute.book(pid))
      ..forget(WaxRoute.metadata(pid))
      ..forget(WaxRoute.episode(pid), anywhere: true);
  }
  for (final page in pages) {
    history.forget(page);
  }
}

/// Whether a page is one of the deleted [pids]' own: the page the delete
/// was asked from ([from]), an item's book, editor or episode (the places
/// [_forgetItems] drops), one of [pages], or the full player while it
/// plays one of the items, asked from or not.
bool Function(PageId? page) _ownPages(
  ProviderContainer container, {
  required List<String> pids,
  required List<String> pages,
  required PageId? from,
}) => (page) {
  if (page == null) return false;
  final path = Uri.parse(page.location).path;
  if (path == WaxRoute.nowPlaying) {
    return pids.contains(container.read(nowPlayingProvider).item?.pid);
  }
  return page == from ||
      _isOwnLocation(page.location, pids: pids, pages: pages);
};

/// Whether [location] is a page of one of [pids], or at or beneath one
/// of [pages], which go with them.
bool _isOwnLocation(
  String location, {
  required List<String> pids,
  required List<String> pages,
}) {
  final path = Uri.parse(location).path;
  bool under(String root) => path == root || path.startsWith('$root/');
  return pids.any((pid) => _isItemPage(path, pid)) ||
      pages.any((page) => under(Uri.parse(page).path));
}

/// Leaves the page on screen too when it is one of the deleted items' own
/// ([own]), which a caller that only closed what lay over it (the full
/// player's collapse) lands on: back to what was beneath it, as the arrow
/// goes.
Future<void> _leaveItemPage(
  WaxHistory history,
  GoRouter router,
  bool Function(PageId? page) own,
) async {
  // Through the browser the leave lands later, and may have gone past it.
  if (history.landing case final landing?) await landing;
  if (own(pageOnTop(router))) history.back();
}

/// Whether [path] is a page of the item [pid].
bool _isItemPage(String path, String pid) {
  bool under(String root) => path == root || path.startsWith('$root/');
  final episode = WaxRoute.episode(pid);
  return under(WaxRoute.book(pid)) ||
      under(WaxRoute.metadata(pid)) ||
      path.endsWith(episode) ||
      path.contains('$episode/');
}

/// The tracks a refusal says go together with the one named - every
/// track one file holds - or none for any other refusal.
List<String> _ripTracks(WaxDeckApiException e) {
  final tracks = e.params?['tracks'];
  if (e.code != 'invalid-request' ||
      e.params?['reason'] != 'cue-rip' ||
      tracks == null) {
    return const [];
  }
  return [
    for (final pid in tracks.split(','))
      if (pid.isNotEmpty) pid,
  ];
}

/// Offers the tracks asked for together with every other track their
/// files hold, after a delete naming some of a file's tracks was refused;
/// true goes on to delete them all.
class _WholeFileDialog extends StatelessWidget {
  const _WholeFileDialog({required this.chosen, required this.extra});

  /// How many tracks were picked, and how many more (never none) share
  /// their files.
  final int chosen, extra;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Scrolls rather than overflows on a short window.
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.libraryDeleteRipTitle),
      content: WaxProse(l10n.libraryDeleteRipShared(chosen, extra)),
      actions: [
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        WaxButton(
          label: l10n.libraryDeleteRipAction(chosen + extra),
          semanticsId: SemanticsIds.itemDeleteRip,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// Preview from the dry run plus the trash-or-permanent choice.
class _DeleteItemsDialog extends StatefulWidget {
  const _DeleteItemsDialog({required this.plan, required this.allowPermanent});

  final DeleteItemsResult plan;

  /// Whether the permanent mode is offered at all; the server refuses
  /// it to everyone but administrators.
  final bool allowPermanent;

  @override
  State<_DeleteItemsDialog> createState() => _DeleteItemsDialogState();
}

class _DeleteItemsDialogState extends State<_DeleteItemsDialog> {
  var _mode = 'trash';

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final l10n = context.l10n;
    // Where each file is in its library, which tells two files of one
    // name apart; a plan that carries no paths names them alone.
    final names = [
      for (final entry in plan.entries)
        if (entry.paths.isNotEmpty)
          ...entry.paths
        else
          for (final file in entry.fileList) file.name,
    ];
    // The covers, lyrics and other files named for those files, which go
    // with them.
    final sidecars = [for (final entry in plan.entries) ...entry.sidecars];
    // Scrolls rather than overflows on a short window, so every choice
    // stays reachable.
    return AlertDialog(
      key: const Key('item-delete-dialog'),
      scrollable: true,
      title: Text(l10n.libraryDeleteTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WaxProse(
            l10n.libraryDeletePreview(
              plan.totalFiles,
              l10n.formatBytes(plan.totalBytes),
            ),
            key: const Key('item-delete-preview'),
          ),
          // Which files go: the first few, then how many more.
          if (names.isNotEmpty)
            _PathList(
              paths: names,
              identifier: SemanticsIds.itemDeletePaths,
              spoken: l10n.libraryDeletePreviewFiles,
            ),
          if (sidecars.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s8),
              child: _PathList(
                paths: sidecars,
                identifier: SemanticsIds.itemDeleteSidecars,
                spoken: l10n.libraryDeletePreviewSidecars,
                heading: l10n.libraryDeleteSidecarsHeading(sidecars.length),
              ),
            ),
          if (plan.entries.isNotEmpty &&
              plan.entries.every((e) => e.itemSurvives)) ...<Widget>[
            const SizedBox(height: WaxSpace.s8),
            WaxProse(l10n.libraryDeleteKeepsItem),
          ],
          const SizedBox(height: WaxSpace.s8),
          WaxRadioGroup<String>(
            value: _mode,
            onChanged: (value) => setState(() => _mode = value),
            options: <WaxRadioOption<String>>[
              WaxRadioOption<String>(
                value: 'trash',
                label: l10n.libraryDeleteModeTrash,
                help: l10n.libraryDeleteModeTrashHelp,
                semanticsId: SemanticsIds.itemDeleteMode('trash'),
              ),
              if (widget.allowPermanent)
                WaxRadioOption<String>(
                  value: 'permanent',
                  label: l10n.libraryDeleteModePermanent,
                  help: l10n.libraryDeleteModePermanentHelp,
                  semanticsId: SemanticsIds.itemDeleteMode('permanent'),
                ),
            ],
          ),
        ],
      ),
      actions: [
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: l10n.libraryDeleteAction,
          kind: WaxButtonKind.destructive,
          semanticsId: SemanticsIds.itemDeleteConfirm,
          onPressed: () => Navigator.of(context).pop(_mode),
        ),
      ],
    );
  }
}

/// Library paths as the delete dialog lists them: the first few as rows,
/// then how many more, with a line over them where there is one. Read out
/// whole as one sentence, which a list of paths is not, and no longer than
/// the list drawn.
class _PathList extends StatelessWidget {
  const _PathList({
    required this.paths,
    required this.identifier,
    required this.spoken,
    this.heading,
  });

  final List<String> paths;
  final String identifier;

  /// The sentence a screen reader gets: how many paths, then the rows drawn.
  final String Function(int count, String list) spoken;

  final String? heading;

  /// How many paths are named before the rest are counted.
  static const _named = 5;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final more = paths.length > _named
        ? l10n.libraryDeleteMoreFiles(paths.length - _named)
        : null;
    return Semantics(
      identifier: identifier,
      label: spoken(paths.length, [...paths.take(_named), ?more].join(', ')),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading case final line?)
            Text(
              line,
              style: WaxType.caption.copyWith(
                color: WaxColors.of(context).textSecondary,
              ),
            ),
          // Keyed by place as well as by path: one path comes twice when an
          // item and a copy of it sit in two libraries laid out alike.
          for (final (i, path) in paths.take(_named).indexed)
            Text(
              path,
              key: ValueKey('$i:$path'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WaxType.monoData,
            ),
          if (more != null) Text(more),
        ],
      ),
    );
  }
}
