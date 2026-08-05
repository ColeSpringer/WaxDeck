import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';
import 'indicators.dart';
import 'inputs.dart';

/// How much a table column matters when there is not room for all of
/// them.
enum WaxColumnPriority {
  /// Always drawn. On a phone this is the card's headline.
  primary,

  /// Drawn wherever the table is a table, and in the card's caption
  /// line below that.
  secondary,

  /// The detail channel: paths, ids, timestamps. Below `expanded` it
  /// moves into the row's detail sheet rather than onto the card.
  detail,
}

/// One column of a [WaxTable].
///
/// The cell builder returns a widget rather than a string so a column can
/// hold a switch, a chip, or a menu - which admin tables are mostly made
/// of - while [text] is what the compact card and the detail sheet read
/// when they need the value as a line of prose.
class WaxColumn<T> {
  const WaxColumn({
    required this.label,
    required this.cell,
    this.text,
    this.priority = WaxColumnPriority.secondary,
    this.width,
    this.numeric = false,
  });

  final String label;
  final Widget Function(BuildContext context, T row) cell;

  /// The cell as a line of text, for the compact card and the detail
  /// sheet. Columns whose cell is a control leave it null and are simply
  /// absent from both.
  final String Function(T row)? text;

  final WaxColumnPriority priority;

  /// A fixed width, for the columns that would otherwise be squeezed by
  /// a long title beside them. Null shares the remaining room.
  final double? width;

  /// Right-aligned, for counts and sizes.
  final bool numeric;
}

/// The admin table: a sticky header over rows, and a card list where
/// there is no room for columns.
///
/// The compact behaviour belongs to the component rather than to each
/// screen, because every screen would otherwise decide differently what
/// a phone gets. Columns declare a priority; below `expanded` each row
/// becomes a card carrying its primary and secondary fields, and the
/// whole record is one tap away in a detail sheet.
///
/// Truly tabular content that has to stay tabular (an audit detail, a
/// diff) is not this: it scrolls horizontally inside its own container.
class WaxTable<T> extends StatelessWidget {
  const WaxTable({
    required this.columns,
    required this.rows,
    required this.rowId,
    this.rowSemanticsId,
    this.rowDetailSemanticsId,
    this.onRowTap,
    this.trailing,
    this.empty,
    this.caption,
    super.key,
  });

  final List<WaxColumn<T>> columns;
  final List<T> rows;

  /// A stable identity per row, for keys and for the row's own handle.
  final String Function(T row) rowId;

  /// The e2e handle for one row, given its id.
  final String Function(String id)? rowSemanticsId;

  /// The handle for a row's detail control, given its id. Only the card
  /// layout draws one, and only where a detail column exists to show.
  final String Function(String id)? rowDetailSemanticsId;

  /// Opening a row. A table whose rows do nothing passes null, and the
  /// rows announce as content rather than as buttons.
  final void Function(T row)? onRowTap;

  /// A trailing control column (a menu, a delete). Outside [columns] so
  /// it never moves into the card body or the detail sheet.
  final Widget Function(BuildContext context, T row)? trailing;

  /// What to draw with no rows. A table with none and no empty state
  /// draws its header alone, which reads as broken.
  final Widget? empty;

  /// A line under the table: "first 50 shown", a total, a caveat.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    if (rows.isEmpty && empty != null) return empty!;
    final tabular = WaxSizeClass.of(context).hasSidebar;
    final body = tabular ? _table(context, colors) : _cards(context, colors);
    if (caption == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        body,
        Padding(
          padding: const EdgeInsets.only(top: WaxSpace.s8),
          child: Text(
            caption!,
            style: WaxType.caption.copyWith(color: colors.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, WaxColors colors) {
    final shown = columns;
    return Container(
      decoration: BoxDecoration(
        borderRadius: WaxRadius.card,
        border: Border.all(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          // Pinned by construction rather than by a scroll listener: the
          // page scrolls, not the table, so the header stays at the top
          // of its own box and the rows below it are ordinary children.
          // A table that scrolled inside the page would trap a wheel
          // gesture aimed at the page.
          Container(
            color: colors.surface2,
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s12,
              vertical: WaxSpace.s8,
            ),
            child: Row(
              children: <Widget>[
                for (final column in shown) _headerCell(colors, column),
                if (trailing != null) const SizedBox(width: WaxSpace.s40),
              ],
            ),
          ),
          for (final (index, row) in rows.indexed)
            _TableRow<T>(
              columns: shown,
              row: row,
              id: rowId(row),
              semanticsId: rowSemanticsId?.call(rowId(row)),
              onTap: onRowTap,
              trailing: trailing,
              striped: index.isOdd,
            ),
        ],
      ),
    );
  }

  Widget _headerCell(WaxColors colors, WaxColumn<T> column) {
    final label = Text(
      column.label,
      style: WaxType.overline.copyWith(color: colors.textSecondary),
      textAlign: column.numeric ? TextAlign.end : TextAlign.start,
      overflow: TextOverflow.ellipsis,
    );
    if (column.width != null) {
      return SizedBox(width: column.width, child: label);
    }
    return Expanded(child: label);
  }

  Widget _cards(BuildContext context, WaxColors colors) {
    return Column(
      children: <Widget>[
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: WaxSpace.s8),
            child: _RowCard<T>(
              columns: columns,
              row: row,
              id: rowId(row),
              semanticsId: rowSemanticsId?.call(rowId(row)),
              detailSemanticsId: rowDetailSemanticsId?.call(rowId(row)),
              onTap: onRowTap,
              trailing: trailing,
            ),
          ),
      ],
    );
  }
}

class _TableRow<T> extends StatelessWidget {
  const _TableRow({
    required this.columns,
    required this.row,
    required this.id,
    required this.striped,
    this.semanticsId,
    this.onTap,
    this.trailing,
  });

  final List<WaxColumn<T>> columns;
  final T row;
  final String id;
  final bool striped;
  final String? semanticsId;
  final void Function(T row)? onTap;
  final Widget Function(BuildContext context, T row)? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final content = Container(
      color: striped ? colors.surface1 : Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: WaxSpace.s12,
        vertical: WaxSpace.s8,
      ),
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: <Widget>[
          for (final column in columns) _cell(context, column),
          if (trailing != null)
            SizedBox(width: WaxSpace.s40, child: trailing!(context, row)),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(
        identifier: semanticsId,
        container: true,
        child: content,
      );
    }
    // The ink is this row's own: WaxTappable carries the ring, the
    // handle, and the keyboard activation and deliberately adds no
    // gesture, so a row that skipped this would announce as a button
    // and answer no pointer.
    return WaxTappable(
      label: id,
      semanticsId: semanticsId,
      borderRadius: BorderRadius.zero,
      surface: striped ? colors.surface1 : colors.canvas,
      onPressed: () => onTap!(row),
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: () => onTap!(row), child: content),
      ),
    );
  }

  Widget _cell(BuildContext context, WaxColumn<T> column) {
    final child = Align(
      alignment: column.numeric
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: column.cell(context, row),
    );
    if (column.width != null) {
      return SizedBox(width: column.width, child: child);
    }
    return Expanded(child: child);
  }
}

/// One row where the table cannot be a table: the primary field as a
/// headline, the secondary fields under it, and the whole record behind
/// a tap.
class _RowCard<T> extends StatelessWidget {
  const _RowCard({
    required this.columns,
    required this.row,
    required this.id,
    this.semanticsId,
    this.detailSemanticsId,
    this.onTap,
    this.trailing,
  });

  final List<WaxColumn<T>> columns;
  final T row;
  final String id;
  final String? semanticsId;
  final String? detailSemanticsId;
  final void Function(T row)? onTap;
  final Widget Function(BuildContext context, T row)? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final primary = columns.where(
      (c) => c.priority == WaxColumnPriority.primary,
    );
    final secondary = columns.where(
      (c) => c.priority == WaxColumnPriority.secondary,
    );
    // The detail channel, which has no room on a card. It is one tap
    // away rather than dropped: a column marked detail used to vanish
    // entirely below sidebar width, so a phone simply could not see it.
    final details = columns
        .where((c) => c.priority == WaxColumnPriority.detail)
        .toList();
    final card = Container(
      padding: const EdgeInsets.all(WaxSpace.s12),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: WaxRadius.card,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final column in primary)
                  DefaultTextStyle.merge(
                    style: WaxType.titleItem.copyWith(
                      color: colors.textPrimary,
                    ),
                    child: column.cell(context, row),
                  ),
                for (final column in secondary)
                  Padding(
                    padding: const EdgeInsets.only(top: WaxSpace.s4),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 96,
                          child: Text(
                            column.label,
                            style: WaxType.caption.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                        Expanded(child: column.cell(context, row)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (details.isNotEmpty)
            WaxIconButton(
              glyph: WaxIcons.info,
              label: 'Details for $id',
              size: 16,
              semanticsId: detailSemanticsId,
              onPressed: () => _showDetails(context, colors),
            ),
          if (trailing != null) trailing!(context, row),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(identifier: semanticsId, container: true, child: card);
    }
    return WaxTappable(
      label: id,
      semanticsId: semanticsId,
      borderRadius: WaxRadius.card,
      surface: colors.canvas,
      onPressed: () => onTap!(row),
      child: Material(
        color: Colors.transparent,
        borderRadius: WaxRadius.card,
        child: InkWell(
          onTap: () => onTap!(row),
          borderRadius: WaxRadius.card,
          child: card,
        ),
      ),
    );
  }
}

/// The whole record, for a card that cannot show it.
///
/// Every column, not only the detail ones: somebody who opened this
/// wants the row, and reading half of it here and half of it behind
/// them is worse than repeating four lines. [WaxColumn.text] is what
/// this reads, which is the field's whole purpose - a column whose cell
/// is a control has none and is simply absent, because a switch in a
/// read-only sheet is a control that lies.
extension _RowCardDetails<T> on _RowCard<T> {
  void _showDetails(BuildContext context, WaxColors colors) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface2,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WaxSpace.s20,
            0,
            WaxSpace.s20,
            WaxSpace.s24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final column in columns)
                if (column.text != null)
                  MonoDetailRow(label: column.label, value: column.text!(row)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashboard number: what it is, what it says, and where it goes.
///
/// The console's status row is made of these, and so is the stats screen
/// that had its own copy before this one existed.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    this.caption,
    this.glyph,
    this.tone,
    this.onTap,
    this.semanticsId,
    super.key,
  });

  final String label;
  final String value;

  /// A line under the number: what it means, or what to do about it.
  final String? caption;

  final WaxGlyph? glyph;

  /// The number's colour where it carries a verdict (a failing health
  /// score, a queue with work in it). Null draws it in the text colour,
  /// which is what most tiles want.
  final Color? tone;

  /// Where the tile doors into. A tile with nowhere to go is not
  /// tappable, and says so to a screen reader by not being a button.
  final VoidCallback? onTap;

  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final body = Container(
      padding: const EdgeInsets.all(WaxSpace.s16),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: WaxRadius.card,
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (glyph != null) ...<Widget>[
                WaxIcon(glyph!, size: 14, color: colors.textSecondary),
                const SizedBox(width: WaxSpace.s8),
              ],
              Expanded(
                child: Text(
                  label,
                  style: WaxType.overline.copyWith(color: colors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: WaxSpace.s8),
          Text(
            value,
            style: WaxType.titleEntity.copyWith(
              color: tone ?? colors.textPrimary,
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s4),
              child: Text(
                caption!,
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ),
        ],
      ),
    );
    // The whole tile reads as one thing either way: as a button when it
    // goes somewhere, and as a labelled value when it does not.
    if (onTap == null) {
      return Semantics(
        identifier: semanticsId,
        container: true,
        label: '$label, $value',
        excludeSemantics: true,
        child: body,
      );
    }
    return WaxTappable(
      label: '$label, $value',
      semanticsId: semanticsId,
      borderRadius: WaxRadius.card,
      onPressed: onTap,
      child: Material(
        color: Colors.transparent,
        borderRadius: WaxRadius.card,
        child: InkWell(onTap: onTap, borderRadius: WaxRadius.card, child: body),
      ),
    );
  }
}

/// The typed destructive confirmation: an action whose consequence
/// cannot be undone asks for the word back before it runs.
///
/// One implementation, because three screens had grown three of them and
/// the fourth would have grown a fourth. The confirm control stays
/// disabled until the typed text matches, so a muscle-memory double tap
/// through the dialog is not a delete.
Future<bool> showTypedConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmWord,
  required String confirmLabel,
  String? fieldSemanticsId,
  String? confirmSemanticsId,
  String? cancelSemanticsId,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _TypedConfirmDialog(
      title: title,
      message: message,
      confirmWord: confirmWord,
      confirmLabel: confirmLabel,
      fieldSemanticsId: fieldSemanticsId,
      confirmSemanticsId: confirmSemanticsId,
      cancelSemanticsId: cancelSemanticsId,
    ),
  );
  return confirmed ?? false;
}

class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmWord,
    required this.confirmLabel,
    this.fieldSemanticsId,
    this.confirmSemanticsId,
    this.cancelSemanticsId,
  });

  final String title;
  final String message;
  final String confirmWord;
  final String confirmLabel;
  final String? fieldSemanticsId;
  final String? confirmSemanticsId;
  final String? cancelSemanticsId;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return AlertDialog(
      backgroundColor: colors.surface2,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.message,
            style: WaxType.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: WaxSpace.s16),
          WaxTextField(
            label: 'Type ${widget.confirmWord} to confirm',
            controller: _controller,
            semanticsId: widget.fieldSemanticsId,
            onChanged: (value) {
              final matches = value.trim() == widget.confirmWord;
              if (matches != _matches) setState(() => _matches = matches);
            },
          ),
        ],
      ),
      actions: <Widget>[
        WaxButton(
          label: 'Cancel',
          kind: WaxButtonKind.text,
          semanticsId: widget.cancelSemanticsId,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        WaxButton(
          label: widget.confirmLabel,
          kind: WaxButtonKind.destructive,
          semanticsId: widget.confirmSemanticsId,
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}
