import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/wax_icon.dart';
import '../theme/wax_layout.dart';
import '../tokens/colors.dart';
import '../tokens/elevation.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'cards.dart';
import 'controls.dart';
import 'inputs.dart';
import 'states.dart';

/// One thing the palette can run. It draws these and reports the [id] of
/// whichever was chosen; what that means belongs to the caller.
class WaxPaletteEntry {
  const WaxPaletteEntry({
    required this.id,
    required this.label,
    this.detail,
    this.glyph,
    this.shortcut,
    this.semanticsId,
  });

  /// Unique across every group: the highlight is tracked by it.
  final String id;

  final String label;

  /// The line under the name.
  final String? detail;

  final WaxGlyph? glyph;

  /// Already spelled for this platform by the caller.
  final String? shortcut;

  final String? semanticsId;
}

/// A titled run of entries. An empty group is dropped rather than drawn
/// as a heading over nothing.
class WaxPaletteGroup {
  const WaxPaletteGroup({required this.title, required this.entries});

  final String title;
  final List<WaxPaletteEntry> entries;
}

/// One input over grouped results. The field keeps focus, the arrows
/// move a highlight through the flattened rows (wrapping), Enter runs it,
/// Esc closes, and hover follows so a click and a keypress cannot
/// disagree.
///
/// The highlight is drawn rather than focused: moving focus per keystroke
/// would take it off the field. Rows still announce themselves, and say
/// which one is selected.
class WaxCommandPalette extends StatefulWidget {
  const WaxCommandPalette({
    required this.groups,
    required this.onQueryChanged,
    required this.onRun,
    this.onClose,
    this.hint = 'Search, or type a command',
    this.label = 'Command palette',
    this.busy = false,
    this.emptyTitle = 'Nothing matches',
    this.emptyMessage = 'Try fewer words, or a different one.',
    this.width = 560,
    this.maxHeight = 440,
    this.semanticsId,
    this.fieldSemanticsId,
    super.key,
  });

  final List<WaxPaletteGroup> groups;

  /// Every keystroke; debouncing is the caller's business.
  final ValueChanged<String> onQueryChanged;

  final ValueChanged<String> onRun;

  final VoidCallback? onClose;

  final String hint;

  /// The field's accessible name, and the palette's own.
  final String label;

  /// Draws pending results. Rows in hand stay up meanwhile, so the list
  /// does not flicker once per character.
  final bool busy;

  final String emptyTitle;
  final String emptyMessage;

  final double width;
  final double maxHeight;

  final String? semanticsId;
  final String? fieldSemanticsId;

  @override
  State<WaxCommandPalette> createState() => _WaxCommandPaletteState();
}

class _WaxCommandPaletteState extends State<WaxCommandPalette> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'wax-palette-field');
  final ScrollController _scroll = ScrollController();

  /// A key per row position, for scrolling the highlight into view. By
  /// position rather than by id: a duplicate id would hand one global key
  /// to two places, which is a framework assertion.
  final List<GlobalKey> _rowKeys = <GlobalKey>[];

  String? _selected;

  List<WaxPaletteEntry> get _flat => <WaxPaletteEntry>[
    for (final group in widget.groups) ...group.entries,
  ];

  static String? _firstId(List<WaxPaletteEntry> entries) =>
      entries.isEmpty ? null : entries.first.id;

  @override
  void initState() {
    super.initState();
    _selected = _firstId(_flat);
  }

  @override
  void didUpdateWidget(WaxCommandPalette old) {
    super.didUpdateWidget(old);
    final entries = _flat;
    // A slow library answer must not steal a choice already made with the
    // arrows. Assigned rather than set: a build follows immediately.
    if (_selected != null && entries.any((e) => e.id == _selected)) return;
    _selected = _firstId(entries);
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    widget.onQueryChanged(value);
  }

  /// Wraps at both ends: stopping dead reads as a broken key.
  void _move(int delta) {
    final entries = _flat;
    if (entries.isEmpty) return;
    final at = entries.indexWhere((e) => e.id == _selected);
    final next = at < 0 ? 0 : (at + delta + entries.length) % entries.length;
    setState(() => _selected = entries[next].id);
    _reveal(next);
  }

  /// A highlight below the fold is a selection nobody can see.
  void _reveal(int index) {
    final motion = WaxMotion.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= _rowKeys.length) return;
      final row = _rowKeys[index].currentContext;
      if (row == null) return;
      Scrollable.ensureVisible(
        row,
        alignment: 0.5,
        duration: motion.quick,
        curve: WaxMotion.emphasized,
      );
    });
  }

  void _run(String? id) {
    if (id == null) return;
    widget.onRun(id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final entries = _flat;
    while (_rowKeys.length < entries.length) {
      _rowKeys.add(GlobalKey());
    }
    assert(
      entries.map((e) => e.id).toSet().length == entries.length,
      'a palette entry id has to be unique across every group: the '
      'highlight is tracked by it and the caller is told which one ran',
    );

    return Semantics(
      identifier: widget.semanticsId,
      container: true,
      explicitChildNodes: true,
      label: widget.label,
      child: CallbackShortcuts(
        // Above the field: a single-line field does nothing with the
        // vertical arrows, and Esc must close from wherever the caret is.
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              widget.onClose?.call(),
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.width,
            maxHeight: widget.maxHeight,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface3,
              borderRadius: WaxRadius.sheet,
              border: Border.all(color: colors.hairline),
              boxShadow: WaxElevation.overlay(Theme.of(context).brightness),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(WaxSpace.s12),
                    child: SearchField(
                      controller: _query,
                      focusNode: _focus,
                      autofocus: true,
                      hint: widget.hint,
                      label: widget.label,
                      onChanged: _onChanged,
                      // Focus back first: submitting a search field
                      // drops it by convention, and a palette that
                      // survives its own Enter would lose the arrows.
                      onSubmitted: (_) {
                        _focus.requestFocus();
                        _run(_selected);
                      },
                      semanticsId: widget.fieldSemanticsId,
                    ),
                  ),
                  if (entries.isEmpty)
                    Flexible(child: _empty(context))
                  else
                    Flexible(child: _results(context, entries)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WaxSpace.s16),
    child: widget.busy
        ? const SkeletonShapes(shape: SkeletonShape.list)
        : EmptyState(
            title: widget.emptyTitle,
            message: widget.emptyMessage,
            glyph: WaxIcons.search,
          ),
  );

  Widget _results(BuildContext context, List<WaxPaletteEntry> entries) {
    final colors = WaxColors.of(context);
    var index = -1;
    return ListView(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: WaxSpace.s8),
      children: <Widget>[
        for (final group in widget.groups)
          if (group.entries.isNotEmpty) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WaxSpace.s16,
                WaxSpace.s8,
                WaxSpace.s16,
                WaxSpace.s4,
              ),
              child: Text(
                group.title.toUpperCase(),
                style: WaxType.overline.copyWith(color: colors.textTertiary),
              ),
            ),
            for (final entry in group.entries)
              KeyedSubtree(
                key: _rowKeys[index += 1],
                child: MouseRegion(
                  // `onHover`, not `onEnter`: a row that arrived under a
                  // pointer that never moved is not a choice, and would
                  // pin the highlight where the palette opens.
                  onHover: (_) {
                    if (_selected == entry.id) return;
                    setState(() => _selected = entry.id);
                  },
                  child: WaxOptionRow(
                    title: entry.label,
                    subtitle: entry.detail,
                    glyph: entry.glyph,
                    selected: entry.id == _selected,
                    semanticsId: entry.semanticsId,
                    trailing: entry.shortcut == null
                        ? null
                        : Text(
                            entry.shortcut!,
                            style: WaxType.monoData.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                    onTap: () => _run(entry.id),
                  ),
                ),
              ),
          ],
      ],
    );
  }
}

/// One line of the keyboard reference.
class WaxShortcutRow {
  const WaxShortcutRow({
    required this.label,
    required this.keys,
    this.semanticsId,
  });

  final String label;

  /// Already spelled for this platform ("Ctrl K", "⌘ K").
  final String keys;

  final String? semanticsId;
}

/// A titled run of shortcut rows.
class WaxShortcutGroup {
  const WaxShortcutGroup({required this.title, required this.rows});

  final String title;
  final List<WaxShortcutRow> rows;
}

/// The keyboard reference, grouped, keys in the readout face. It draws
/// what the caller hands it and invents nothing.
class WaxShortcutSheet extends StatelessWidget {
  const WaxShortcutSheet({
    required this.groups,
    this.title = 'Keyboard shortcuts',
    this.onClose,
    this.width = 520,
    this.maxHeight = 520,
    this.semanticsId,
    this.closeSemanticsId,
    super.key,
  });

  final List<WaxShortcutGroup> groups;
  final String title;
  final VoidCallback? onClose;
  final double width;
  final double maxHeight;
  final String? semanticsId;
  final String? closeSemanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);

    return Semantics(
      identifier: semanticsId,
      container: true,
      explicitChildNodes: true,
      label: title,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface3,
            borderRadius: WaxRadius.sheet,
            border: Border.all(color: colors.hairline),
            boxShadow: WaxElevation.overlay(Theme.of(context).brightness),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WaxSpace.s20,
                    WaxSpace.s16,
                    WaxSpace.s8,
                    WaxSpace.s8,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: WaxType.headline.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (onClose != null)
                        WaxIconButton(
                          glyph: WaxIcons.close,
                          label: 'Close',
                          size: 18,
                          onPressed: onClose,
                          semanticsId: closeSemanticsId,
                        ),
                    ],
                  ),
                ),
                Divider(color: colors.hairline, height: layout.hairlineWidth),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: WaxSpace.s16),
                    children: <Widget>[
                      for (final group in groups)
                        if (group.rows.isNotEmpty) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              WaxSpace.s20,
                              WaxSpace.s16,
                              WaxSpace.s20,
                              WaxSpace.s4,
                            ),
                            child: Text(
                              group.title.toUpperCase(),
                              style: WaxType.overline.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                          for (final row in group.rows)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: WaxSpace.s20,
                                vertical: WaxSpace.s8,
                              ),
                              // One node per line, so the page reads a
                              // row at a time.
                              child: Semantics(
                                identifier: row.semanticsId,
                                label: '${row.label}, ${row.keys}',
                                excludeSemantics: true,
                                child: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        row.label,
                                        style: WaxType.body.copyWith(
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: WaxSpace.s16),
                                    _Keys(keys: row.keys),
                                  ],
                                ),
                              ),
                            ),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A keystroke drawn the way it is printed on the key.
class _Keys extends StatelessWidget {
  const _Keys({required this.keys});

  final String keys;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WaxSpace.s8,
        vertical: WaxSpace.s4,
      ),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: WaxRadius.chip,
        border: Border.all(color: colors.hairline),
      ),
      child: Text(
        keys,
        style: WaxType.monoData.copyWith(color: colors.textSecondary),
      ),
    );
  }
}
