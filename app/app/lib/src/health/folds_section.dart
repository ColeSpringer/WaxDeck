import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../music/music_controllers.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'health_controller.dart';

/// The names merges folded into an entry, grouped by type: each the
/// spelling files may still carry and the entry it files under, which a
/// row opens. Unfolding one releases it for the files the library reads
/// as new or changed from then on.
class FoldsSection extends ConsumerWidget {
  const FoldsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folds = ref.watch(foldsProvider);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: WaxSpace.s32),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.foldsSection,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: l10n.adminFoldsTitle,
              overline: l10n.adminFoldsOverline,
            ),
            switch (folds) {
              AsyncData(:final value)
                  when value.folds.isEmpty && !value.hasMore =>
                EmptyState(
                  glyph: WaxIcons.success,
                  title: l10n.adminFoldsEmptyTitle,
                  message: l10n.adminFoldsEmptyMessage,
                ),
              AsyncData(:final value) => _FoldGroups(state: value),
              AsyncError(:final error) => ErrorState(
                title: l10n.adminFoldsError,
                message: context.explain(error),
                onRetry: () => ref.invalidate(foldsProvider),
                retrySemanticsId: SemanticsIds.foldsRetry,
              ),
              _ => const SkeletonShapes(shape: SkeletonShape.list),
            },
          ],
        ),
      ),
    );
  }
}

class _FoldGroups extends ConsumerWidget {
  const _FoldGroups({required this.state});

  final FoldsState state;

  static String _heading(AppLocalizations l10n, String type) => switch (type) {
    'album' => l10n.adminFoldsGroupAlbum,
    'artist' => l10n.adminFoldsGroupArtist,
    'genre' => l10n.adminFoldsGroupGenre,
    'release-group' => l10n.adminFoldsGroupReleaseGroup,
    'series' => l10n.adminFoldsGroupSeries,
    _ => type,
  };

  /// Where an entry of a type opens, from the pid form the server lists:
  /// a release group and a genre open their listings. Null for a type
  /// this build does not know.
  static String Function(String pid)? _entryOf(String type) => switch (type) {
    'artist' => (pid) => WaxRoute.musicBucket(MusicDimension.artists, pid),
    'album' => (pid) => WaxRoute.musicBucket(MusicDimension.albums, pid),
    'release-group' => (pid) => WaxRoute.musicBucket(
      MusicDimension.releaseGroups,
      pid,
    ),
    'genre' => (pid) => WaxRoute.musicBucket(MusicDimension.genres, pid),
    'series' => WaxRoute.bookSeries,
    _ => null,
  };

  /// What kind of entry a fold files under, a genre's by its facet.
  static String _kind(AppLocalizations l10n, EntityFold fold) =>
      switch (fold.entityType) {
        'album' => l10n.adminFoldsKindAlbum,
        'artist' => l10n.adminFoldsKindArtist,
        'genre' when fold.facet == 'mood' => l10n.adminFoldsKindMood,
        'genre' => l10n.adminFoldsKindGenre,
        'release-group' => l10n.adminFoldsKindReleaseGroup,
        'series' => l10n.adminFoldsKindSeries,
        _ => fold.entityType,
      };

  /// What tells a fold apart from another that spells alike: a genre's
  /// facet, an album's folder within its library, or, for an album fold
  /// no file places any longer, when it was folded. Null when it carries
  /// none.
  static String? _apart(AppLocalizations l10n, EntityFold fold) {
    if (fold.entityType == 'genre' && fold.facet != null) {
      return _kind(l10n, fold);
    }
    return switch ((fold.folder, fold.library)) {
      (final folder?, final library?) => l10n.adminFoldsInFolder(
        folder,
        library,
      ),
      (null, final library?) => l10n.adminFoldsInLibrary(library),
      _ when fold.entityType == 'album' => _foldedAt(l10n, fold),
      _ => null,
    };
  }

  static String _foldedAt(AppLocalizations l10n, EntityFold fold) =>
      l10n.adminFoldsFoldedAt(l10n.formatStamp(fold.createdAt));

  /// [_apart] for each of a group's rows, by key, numbered in the
  /// listing's order where rows still read alike, as copies of one
  /// release folded by the same merge do once no file places them.
  static Map<String, String?> _apartAll(
    AppLocalizations l10n,
    List<EntityFold> rows,
  ) {
    final apart = {for (final fold in rows) fold.key: _apart(l10n, fold)};
    final alike = <(String, String?), List<EntityFold>>{};
    for (final fold in rows) {
      (alike[(fold.spelling, apart[fold.key])] ??= <EntityFold>[]).add(fold);
    }
    for (final same in alike.values.where((same) => same.length > 1)) {
      for (final (i, fold) in same.indexed) {
        apart[fold.key] = l10n.adminFoldsApartOf(
          apart[fold.key] ?? _foldedAt(l10n, fold),
          i + 1,
          same.length,
        );
      }
    }
    return apart;
  }

  /// A fold named for the unfold that releases it: quoted, and told apart
  /// from another of its spelling by [apart].
  static String _which(AppLocalizations l10n, EntityFold fold, String? apart) =>
      switch (apart) {
        final apart? => l10n.adminFoldsQuotedApart(fold.spelling, apart),
        null => l10n.adminFoldsQuoted(fold.spelling),
      };

  /// Opens an entry, then reads the list again: a merge or a locked
  /// rename made from there folds names too.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String location,
    EntityFold fold,
  ) async {
    await context.push(location, extra: fold.entityName);
    if (context.mounted) ref.invalidate(foldsProvider);
  }

  Future<void> _unfold(
    BuildContext context,
    EntityFold fold,
    String? apart,
  ) async {
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    final which = _which(l10n, fold, apart);
    // The section can go while the dialog is up; the container outlives it.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = container.read(shellMessengerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminFoldsUnfoldTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Which fold, where two spell alike.
            if (apart != null)
              Padding(
                padding: const EdgeInsets.only(bottom: WaxSpace.s8),
                child: Text(
                  which,
                  style: WaxType.titleItem.copyWith(color: colors.textPrimary),
                ),
              ),
            WaxProse(
              l10n.adminFoldsUnfoldBody(
                l10n.adminFoldsQuoted(fold.spelling),
                fold.entityName,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: l10n.adminFoldsUnfoldAction,
            kind: WaxButtonKind.destructive,
            semanticsId: SemanticsIds.foldUnfoldConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await container
          .read(repositoryProvider)
          .unfoldEntities(entityType: fold.entityType, keys: [fold.key]);
      messenger.show(l10n.adminFoldsUnfolded(which));
    } on WaxDeckApiException catch (e) {
      if (e.code != 'not-found') {
        messenger.show(explainError(l10n, e));
        return;
      }
      messenger.show(l10n.adminFoldsAlreadyUnfolded);
    }
    // The server holds the fold no longer either way. The rows read so far
    // stay, page two's included, where a listing is still up.
    if (!container.exists(foldsProvider)) return;
    try {
      await container.read(foldsProvider.notifier).drop(fold);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _more(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(foldsProvider.notifier).loadMore();
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    // In the listing's order: by type, then key.
    final byType = <String, List<EntityFold>>{};
    for (final fold in state.folds) {
      (byType[fold.entityType] ??= <EntityFold>[]).add(fold);
    }
    final apartOf = {
      for (final MapEntry(key: type, value: rows) in byType.entries)
        type: _apartAll(l10n, rows),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final MapEntry(key: type, value: rows) in byType.entries)
          Semantics(
            key: ValueKey(type),
            container: true,
            explicitChildNodes: true,
            identifier: SemanticsIds.foldGroup(type),
            child: Padding(
              padding: const EdgeInsets.only(bottom: WaxSpace.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: WaxSpace.s8),
                    child: Text(
                      _heading(l10n, type),
                      style: WaxType.overline.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  WaxTable<EntityFold>(
                    rows: rows,
                    rowId: (fold) => fold.key,
                    rowSemanticsId: (key) => SemanticsIds.foldRow(type, key),
                    rowDetailSemanticsId: (key) =>
                        SemanticsIds.foldDetail(type, key),
                    onRowTap: switch (_entryOf(type)) {
                      final entry? => (fold) => _open(
                        context,
                        ref,
                        entry(fold.entityPid),
                        fold,
                      ),
                      null => null,
                    },
                    // A row reads out as its spelling, what tells it
                    // apart, and the entry it files under.
                    rowLabel: (fold) => [
                      fold.spelling,
                      ?apartOf[type]![fold.key],
                      l10n.adminFoldsEntry(fold.entityName, _kind(l10n, fold)),
                    ].join(', '),
                    columns: <WaxColumn<EntityFold>>[
                      WaxColumn<EntityFold>(
                        label: l10n.adminFoldsColumnSpelling,
                        priority: WaxColumnPriority.primary,
                        text: (fold) => [
                          fold.spelling,
                          ?apartOf[type]![fold.key],
                        ].join(', '),
                        cell: (context, fold) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              fold.spelling,
                              style: WaxType.titleItem.copyWith(
                                color: colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (apartOf[type]![fold.key] case final apart?)
                              Text(
                                apart,
                                style: WaxType.caption.copyWith(
                                  color: colors.textTertiary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      WaxColumn<EntityFold>(
                        label: l10n.adminFoldsColumnFilesUnder,
                        text: (fold) => fold.entityName,
                        cell: (context, fold) => Text(
                          fold.entityName,
                          style: WaxType.bodySmall.copyWith(
                            color: colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      WaxColumn<EntityFold>(
                        label: l10n.adminFoldsColumnSince,
                        priority: WaxColumnPriority.detail,
                        width: 128,
                        text: (fold) => l10n.formatDate(fold.createdAt),
                        cell: (context, fold) => Text(
                          l10n.formatDate(fold.createdAt),
                          style: WaxType.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                    trailing: (context, fold) => WaxIconButton(
                      glyph: WaxIcons.detach,
                      label: l10n.adminFoldsUnfold(
                        _which(l10n, fold, apartOf[type]![fold.key]),
                      ),
                      semanticsId: SemanticsIds.foldUnfold(type, fold.key),
                      onPressed: () =>
                          _unfold(context, fold, apartOf[type]![fold.key]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (state.hasMore)
          WaxButton(
            label: state.loadingMore ? l10n.commonLoading : l10n.healthLoadMore,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.caretDown,
            semanticsId: SemanticsIds.foldsMore,
            onPressed: state.loadingMore ? null : () => _more(context, ref),
          ),
      ],
    );
  }
}
