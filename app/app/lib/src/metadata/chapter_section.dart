import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../books/books_controller.dart';
import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import 'metadata_controller.dart';
import 'metadata_form.dart';

/// The chapter editor on a single-file audiobook: rows staged into the
/// editor's one draft and committed by the save bar through the
/// chapters endpoint. Multi-file books are left out deliberately - the
/// server can split a flat list across parts, but their marks are the
/// merge tool's part boundaries, and hand-editing those is a decision
/// this pane should not smuggle in.
class MetadataChaptersSection extends ConsumerWidget {
  const MetadataChaptersSection({
    super.key,
    required this.pid,
    required this.state,
    required this.draft,
    required this.busy,
    required this.onToggleLock,
  });

  final String pid;
  final MetadataEditorState state;
  final MetadataDraft draft;
  final bool busy;

  /// Flips the `chapters` artifact lock. The lock is what a saved
  /// chapter list writes by default, so without this toggle the second
  /// edit's only door is the global Force switch - every scalar row
  /// has the same affordance for the same reason.
  final VoidCallback onToggleLock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    // The part count is the book read's; the editor's own read does not
    // carry it. Absent (still loading, or failed) draws nothing: a
    // section that may not apply is better missing than flickering in.
    final book = ref.watch(bookDetailProvider(pid)).value;
    if (book == null || book.parts.length > 1) {
      return const SizedBox.shrink();
    }
    final rows = draft.chapterRows(state.metadata.chapters);
    final invalid = !draft.chapterRowsValid;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: SemanticsIds.bookChapterEditor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: WaxSpace.s32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: SectionHeader(
                  title: l10n.bookChaptersTitle,
                  overline: l10n.bookChaptersOverline(rows.length),
                ),
              ),
              Builder(
                builder: (context) {
                  final colors = WaxColors.of(context);
                  final locked = state.isLocked('chapters');
                  return WaxIconButton(
                    glyph: locked ? WaxIcons.lock : WaxIcons.lockOpen,
                    label: locked
                        ? l10n.metadataUnlockField(l10n.bookChaptersTitle)
                        : l10n.metadataLockField(l10n.bookChaptersTitle),
                    active: locked,
                    size: 16,
                    color: locked ? colors.accent : null,
                    semanticsId: SemanticsIds.fieldLock('chapters'),
                    onPressed: busy ? null : onToggleLock,
                  );
                },
              ),
            ],
          ),
          Text(
            l10n.bookChapterEditorHelp,
            style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: WaxSpace.s12),
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            _ChapterRow(
              key: ValueKey(rows[i].id),
              index: i,
              row: rows[i],
              busy: busy,
              onRemove: () => draft.removeChapterRow(rows[i]),
            ),
            const SizedBox(height: WaxSpace.s8),
          ],
          if (invalid)
            WaxBanner(
              message: l10n.bookChapterEditorInvalid,
              tone: WaxBannerTone.caution,
            ),
          const SizedBox(height: WaxSpace.s8),
          Wrap(
            spacing: WaxSpace.s8,
            runSpacing: WaxSpace.s8,
            children: <Widget>[
              WaxButton(
                label: l10n.bookChapterEditorAdd,
                kind: WaxButtonKind.tonal,
                icon: WaxIcons.add,
                semanticsId: SemanticsIds.bookChapterEditorAdd,
                onPressed: busy ? null : draft.addChapterRow,
              ),
              // Only while there is something to hand back: with no
              // rows the empty list is already what is staged, and on a
              // book with no stored chapters the restore would stage a
              // write that changes nothing.
              if (rows.isNotEmpty)
                WaxButton(
                  label: l10n.bookChapterEditorRestore,
                  kind: WaxButtonKind.text,
                  semanticsId: SemanticsIds.bookChapterEditorRestore,
                  onPressed: busy ? null : draft.restoreEmbeddedChapters,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    super.key,
    required this.index,
    required this.row,
    required this.busy,
    required this.onRemove,
  });

  /// The row's place in the list, which is the index the wire model
  /// carries; identity for the widget tree is the row's own id.
  final int index;

  final MetadataChapterRow row;
  final bool busy;
  final VoidCallback onRemove;

  static const _startWidth = 110.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        SizedBox(
          width: _startWidth,
          child: WaxTextField(
            label: l10n.bookChapterEditorStartLabel,
            controller: row.startController,
            semanticsId: SemanticsIds.bookChapterEditorStart(index),
          ),
        ),
        const SizedBox(width: WaxSpace.s8),
        Expanded(
          child: WaxTextField(
            label: l10n.bookChapterEditorTitleLabel,
            hint: l10n.bookChapterFallback(index + 1),
            controller: row.titleController,
            semanticsId: SemanticsIds.bookChapterEditorTitle(index),
          ),
        ),
        const SizedBox(width: WaxSpace.s8),
        Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s8),
          child: WaxIconButton(
            glyph: WaxIcons.delete,
            label: l10n.bookChapterEditorRemove,
            size: 16,
            semanticsId: SemanticsIds.bookChapterEditorRemove(index),
            onPressed: busy ? null : onRemove,
          ),
        ),
      ],
    );
  }
}
