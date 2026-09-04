import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../icons/wax_icon.dart';
import '../l10n/wax_l10n.dart';
import '../theme/wax_layout.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';
import 'tooltip.dart';

/// One place the shell can send a visitor, as plain data.
///
/// [name] is the destination's identity: the chrome selects and reports by
/// it, so a list rebuilt every frame still compares equal without the
/// caller holding indices. Nothing here is coloured by domain - an active
/// destination is amber in every one of them, because five differently
/// hued active tabs is the rainbow-nav trap.
@immutable
class WaxDestination {
  const WaxDestination({
    required this.name,
    required this.label,
    required this.glyph,
    this.semanticsId,
    this.badge,
    this.children = const <WaxDestination>[],
    this.discloseSemanticsId,
  });

  /// Stable identity, supplied by the caller ('home', 'podcasts').
  final String name;

  /// The visible label, and the accessible name wherever the label is
  /// not drawn (the icon rail, a collapsed sidebar).
  final String label;

  final WaxGlyph glyph;

  /// The e2e handle, supplied by the caller. See `semantics_slots.dart`
  /// for why the design system never invents one.
  final String? semanticsId;

  /// A count drawn on the glyph: queued downloads, unread notifications.
  final String? badge;

  /// The destination's own sub-destinations: the indexes under a domain
  /// hub. Only the sidebar draws them, indented beneath the parent row
  /// with a disclosure control of its own.
  ///
  /// This is not a [WaxNavGroup]. A group's header row is a label that
  /// only discloses, because its children are all there is; a parent
  /// destination is somewhere you can go, and its children are shortcuts
  /// into what is already on it. That is why the tabs, the rail, and a
  /// collapsed sidebar draw the parent alone and drop the children: they
  /// are one tap further on, not unreachable.
  final List<WaxDestination> children;

  /// The handle for the disclosure control beside a parent row. It is a
  /// separate control from the row - the row navigates, the chevron
  /// opens - so it takes a separate identifier.
  final String? discloseSemanticsId;
}

/// Whether [destination] is the one to light for [selected].
///
/// A destination holds the selection when it is selected itself, and also
/// when one of its sub-destinations is and that row is not on screen to
/// light instead. Every form but an open sidebar section is in the second
/// case: the tabs, the rail, and a collapsed sidebar draw a domain's hub
/// and not its indexes, so an index has to light the hub it belongs to or
/// a phone standing on Artists lights nothing at all.
bool _holdsSelection(
  WaxDestination destination,
  String? selected, {
  required bool childrenDrawn,
}) {
  if (destination.name == selected) return true;
  if (childrenDrawn) return false;
  return destination.children.any((child) => child.name == selected);
}

/// A secondary entry: a destination on its own, or a collapsible group of
/// them.
///
/// Secondary entries are the ones that are not tabs (settings, the
/// curation areas). They get labels and room in the sidebar, and the icon
/// rail reaches them through one overflow menu.
sealed class WaxNavEntry {
  const WaxNavEntry();
}

/// A single secondary destination.
class WaxNavLink extends WaxNavEntry {
  const WaxNavLink(this.destination);

  final WaxDestination destination;
}

/// A collapsible group of secondary destinations, drawn as one row that
/// discloses its children.
class WaxNavGroup extends WaxNavEntry {
  const WaxNavGroup({
    required this.name,
    required this.label,
    required this.glyph,
    required this.children,
    this.semanticsId,
  });

  /// The group's stable handle, in [WaxDestination.name]'s vocabulary.
  /// What the sidebar remembers a collapse against: keyed on [label],
  /// that decision belonged to whatever language it was made in.
  final String name;

  final String label;
  final WaxGlyph glyph;
  final List<WaxDestination> children;

  /// The handle for the disclosure row itself.
  final String? semanticsId;
}

/// Something the account menu *does*, as opposed to somewhere it goes.
///
/// Signing out is not a place, so it does not get to be a
/// [WaxDestination]: the menu reports the two apart and the shell wires
/// each to what it means.
@immutable
class WaxAccountAction {
  const WaxAccountAction({
    required this.name,
    required this.label,
    this.glyph,
    this.semanticsId,
  });

  /// Stable identity, reported back on selection.
  final String name;

  final String label;
  final WaxGlyph? glyph;
  final String? semanticsId;
}

/// The signed-in account, as the chrome draws it.
@immutable
class WaxAccount {
  const WaxAccount({
    required this.name,
    this.actions = const <WaxAccountAction>[],
    this.semanticsId,
  });

  /// The display name: the head of the menu, and the monogram's letter.
  final String name;

  final List<WaxAccountAction> actions;

  /// The handle for the trigger itself.
  final String? semanticsId;
}

/// How a navigation item is drawn.
enum _NavForm {
  /// A bottom tab: glyph over label, in a column.
  tab,

  /// An icon-only rail item, with the label as its tooltip.
  rail,

  /// A sidebar row: glyph beside label.
  row,
}

/// Where the label sits on a bottom tab, and whether it is drawn at all.
///
/// Text scaled past about 1.5 turns a two-line tab into a clipped one, so
/// the labels drop and the glyphs (which carry the same meaning, and keep
/// their accessible names) stand alone. That is reflow, not truncation:
/// nothing readable is cut off, and the bar keeps its 44 px targets.
bool _tabLabelsFit(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(WaxType.caption.fontSize ?? 12) <=
    18;

/// The one interactive navigation item, in all three forms.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.form,
    this.glyph,
    this.monogram,
    this.semanticsId,
    this.badge,
    this.trailing,
    this.indent = false,
  }) : assert(
         (glyph == null) != (monogram == null),
         'a nav item draws a glyph or a monogram, not both',
       );

  final String label;
  final WaxGlyph? glyph;

  /// The account's display name, drawn as an initial on a disc where a
  /// destination would draw its glyph.
  final String? monogram;

  final bool selected;
  final VoidCallback? onTap;
  final _NavForm form;
  final String? semanticsId;
  final String? badge;

  /// A disclosure chevron on a group row.
  final Widget? trailing;

  /// A child of an expanded group: inset so the hierarchy reads.
  final bool indent;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _focused = false;
  bool _hovered = false;

  /// Owned rather than left to the detector, so the semantics node can
  /// answer the platform's focus request itself.
  ///
  /// The node is excluded from semantics (one node per control is the
  /// contract the suite and assistive tech both steer by), and what that
  /// drops is the `focusable` flag the [Focus] inside would otherwise
  /// have contributed. Web turns that flag into a `tabindex`, so without
  /// it the whole chrome renders, announces, and cannot be reached from
  /// a keyboard at all. Declaring it here puts it back on the one node,
  /// and `onFocus` is what makes the platform's request land on the real
  /// focus node rather than nowhere.
  final FocusNode _focus = FocusNode(debugLabel: 'nav-item');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// The rail draws no label, so a tooltip is where a pointer user reads
  /// the name. Everywhere else the label is right there, and a tooltip
  /// repeating it is noise.
  Widget _maybeTooltip(Widget child) => widget.form == _NavForm.rail
      ? WaxTooltip(message: widget.label, child: child)
      : child;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    final enabled = widget.onTap != null;

    final Color foreground = !enabled
        ? colors.textDisabled
        : widget.selected
        ? colors.onAccentContainer
        : colors.textSecondary;
    final Color background = widget.selected
        ? colors.accentContainer
        : _hovered
        ? colors.surface2
        : Colors.transparent;

    Widget glyph = widget.monogram != null
        ? _Monogram(name: widget.monogram!)
        : WaxIcon(
            widget.glyph!,
            size: 22,
            color: foreground,
            active: widget.selected,
          );
    if (widget.badge != null) {
      glyph = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          glyph,
          Positioned(
            right: -6,
            top: -6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: WaxRadius.pill,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                  widget.badge!,
                  style: WaxType.caption.copyWith(
                    color: colors.onAccent,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final Widget content = switch (widget.form) {
      // Centred inside whatever height the bar gives it, so the whole
      // cell is the target rather than just the glyph and its label.
      _NavForm.tab => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // The pill is what carries selection on a tab: a filled shape
          // reads as selected in greyscale, where amber alone would not.
          AnimatedContainer(
            duration: motion.quick,
            curve: WaxMotion.emphasized,
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s16,
              vertical: WaxSpace.s4,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: WaxRadius.pill,
            ),
            child: glyph,
          ),
          if (_tabLabelsFit(context)) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WaxType.caption.copyWith(
                color: widget.selected ? colors.accent : colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
      _NavForm.rail => Center(
        child: AnimatedContainer(
          duration: motion.quick,
          curve: WaxMotion.emphasized,
          width: WaxSpace.s48,
          height: WaxSpace.touchTarget,
          decoration: BoxDecoration(
            color: background,
            borderRadius: WaxRadius.pill,
          ),
          child: Center(child: glyph),
        ),
      ),
      _NavForm.row => AnimatedContainer(
        duration: motion.quick,
        curve: WaxMotion.emphasized,
        constraints: const BoxConstraints(minHeight: WaxSpace.touchTarget),
        padding: EdgeInsetsDirectional.only(
          start: widget.indent ? WaxSpace.s32 : WaxSpace.s12,
          end: WaxSpace.s12,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: WaxRadius.thumb,
        ),
        child: Row(
          children: <Widget>[
            glyph,
            const SizedBox(width: WaxSpace.s12),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WaxType.label.copyWith(
                  color: widget.selected ? foreground : colors.textPrimary,
                ),
              ),
            ),
            ?widget.trailing,
          ],
        ),
      ),
    };

    return Semantics(
      identifier: widget.semanticsId,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      // The action rides the semantics node, so a screen reader's double
      // tap and the suite's click both land on the control rather than on
      // the canvas underneath it.
      excludeSemantics: true,
      onTap: widget.onTap,
      focusable: enabled,
      focused: _focused,
      onFocus: _focus.requestFocus,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: WaxFocusRing(
          focused: _focused,
          borderRadius: WaxRadius.thumb,
          surface: colors.canvas,
          child: _maybeTooltip(
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom tabs: the compact shell's navigation.
///
/// It sits below the deck bar and above the system inset, and it never
/// scrolls away, and it carries the domains and nothing else. The account
/// menu - which is the compact route to everything that is not a domain -
/// is in the top app bar, where the layout system puts it; it took a
/// fixed cell here for as long as the tab roots were screens with no bar
/// of their own to host it.
class WaxNavBar extends StatelessWidget {
  const WaxNavBar({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    this.semanticsId,
    super.key,
  });

  final List<WaxDestination> destinations;

  /// The name of the active destination, or null when the visitor is
  /// somewhere that is not one.
  final String? selected;

  final ValueChanged<String> onSelect;
  final String? semanticsId;

  /// The bar's own height, before the system inset. Grows with the text
  /// scale until the labels drop.
  static double heightFor(BuildContext context) {
    if (!_tabLabelsFit(context)) return WaxSpace.touchTarget + WaxSpace.s8;
    final label = MediaQuery.textScalerOf(
      context,
    ).scale(WaxType.caption.fontSize ?? 12);
    return WaxSpace.touchTarget + WaxSpace.s8 + label + 2;
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    return _NavRegion(
      semanticsId: semanticsId,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface1,
          border: Border(
            top: BorderSide(
              color: colors.hairline,
              width: layout.hairlineWidth,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: heightFor(context),
            child: Row(
              // Stretched, so each tab's target is its whole cell.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final destination in destinations)
                  Expanded(
                    child: _NavItem(
                      label: destination.label,
                      glyph: destination.glyph,
                      badge: destination.badge,
                      semanticsId: destination.semanticsId,
                      // A domain hub lights for its own indexes here: this form draws
                      // the hub and not them.
                      selected: _holdsSelection(
                        destination,
                        selected,
                        childrenDrawn: false,
                      ),
                      form: _NavForm.tab,
                      onTap: () => onSelect(destination.name),
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

/// The icon rail: the medium shell's navigation.
///
/// Icons only, with the labels as tooltips and accessible names. The
/// secondary entries live behind one overflow control, because a rail
/// this narrow has room for the domains and nothing else.
class WaxNavRail extends StatelessWidget {
  const WaxNavRail({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    this.secondary = const <WaxNavEntry>[],
    this.overflowLabel,
    this.overflowSemanticsId,
    this.account,
    this.semanticsId,
    super.key,
  });

  final List<WaxDestination> destinations;
  final String? selected;
  final ValueChanged<String> onSelect;
  final List<WaxNavEntry> secondary;

  /// The overflow trigger's accessible name. Null takes the design
  /// system's own.
  final String? overflowLabel;
  final String? overflowSemanticsId;

  /// The account control, under the overflow at the foot of the rail.
  final Widget? account;

  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    return _NavRegion(
      semanticsId: semanticsId,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface1,
          border: BorderDirectional(
            end: BorderSide(
              color: colors.hairline,
              width: layout.hairlineWidth,
            ),
          ),
        ),
        child: SafeArea(
          right: false,
          child: SizedBox(
            width: WaxShellMetrics.railWidth,
            child: Column(
              children: <Widget>[
                const SizedBox(height: WaxSpace.s12),
                for (final destination in destinations)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: WaxSpace.s4),
                    child: _NavItem(
                      label: destination.label,
                      glyph: destination.glyph,
                      badge: destination.badge,
                      semanticsId: destination.semanticsId,
                      // A domain hub lights for its own indexes here: this form draws
                      // the hub and not them.
                      selected: _holdsSelection(
                        destination,
                        selected,
                        childrenDrawn: false,
                      ),
                      form: _NavForm.rail,
                      onTap: () => onSelect(destination.name),
                    ),
                  ),
                const Spacer(),
                if (secondary.isNotEmpty)
                  WaxNavOverflowButton(
                    entries: secondary,
                    selected: selected,
                    onSelect: onSelect,
                    label: overflowLabel ?? context.waxL10n.commonMore,
                    semanticsId: overflowSemanticsId,
                  ),
                if (account != null) ...<Widget>[
                  const SizedBox(height: WaxSpace.s8),
                  account!,
                ],
                const SizedBox(height: WaxSpace.s12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a navigation menu reported: a destination to go to, or an
/// account action to run.
sealed class _MenuChoice {
  const _MenuChoice();
}

class _GoTo extends _MenuChoice {
  const _GoTo(this.name);

  final String name;
}

class _Run extends _MenuChoice {
  const _Run(this.name);

  final String name;
}

/// Opens a menu against the trigger, and answers what was chosen.
///
/// The trigger is the house icon button rather than a [PopupMenuButton]:
/// its own trigger draws a second semantics node for the same control,
/// and the suite steers by one handle per control.
Future<_MenuChoice?> _openMenu(
  BuildContext context,
  List<PopupMenuEntry<_MenuChoice>> items,
) {
  final trigger = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final origin = trigger.localToGlobal(Offset.zero, ancestor: overlay);
  return showMenu<_MenuChoice>(
    context: context,
    position: RelativeRect.fromLTRB(
      origin.dx,
      origin.dy,
      overlay.size.width - origin.dx - trigger.size.width,
      overlay.size.height - origin.dy,
    ),
    items: items,
  );
}

/// Secondary entries as menu rows: a group's children follow its label,
/// flattened, because a menu inside a menu is a worse answer than a
/// labelled run.
List<PopupMenuEntry<_MenuChoice>> _entryItems(
  BuildContext context,
  List<WaxNavEntry> entries,
  String? selected,
) {
  final colors = WaxColors.of(context);
  PopupMenuItem<_MenuChoice> item(WaxDestination destination) =>
      PopupMenuItem<_MenuChoice>(
        value: _GoTo(destination.name),
        child: Semantics(
          identifier: destination.semanticsId,
          selected: destination.name == selected,
          child: Text(destination.label),
        ),
      );
  return <PopupMenuEntry<_MenuChoice>>[
    for (final entry in entries)
      ...switch (entry) {
        WaxNavLink(:final destination) => <PopupMenuEntry<_MenuChoice>>[
          item(destination),
        ],
        WaxNavGroup() => <PopupMenuEntry<_MenuChoice>>[
          PopupMenuItem<_MenuChoice>(
            enabled: false,
            height: WaxSpace.s32,
            child: Text(
              entry.label,
              style: WaxType.overline.copyWith(color: colors.textTertiary),
            ),
          ),
          for (final destination in entry.children) item(destination),
        ],
      },
  ];
}

/// The secondary destinations as one menu, for chrome with no room to
/// list them.
class WaxNavOverflowButton extends StatelessWidget {
  const WaxNavOverflowButton({
    required this.entries,
    required this.onSelect,
    this.selected,
    this.label,
    this.semanticsId,
    super.key,
  });

  final List<WaxNavEntry> entries;
  final ValueChanged<String> onSelect;
  final String? selected;

  /// The trigger's accessible name. Null takes the design system's own.
  final String? label;
  final String? semanticsId;

  Future<void> _open(BuildContext context) async {
    final chosen = await _openMenu(
      context,
      _entryItems(context, entries, selected),
    );
    if (chosen is _GoTo) onSelect(chosen.name);
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => WaxIconButton(
      glyph: WaxIcons.more,
      label: label ?? context.waxL10n.commonMore,
      size: 22,
      semanticsId: semanticsId,
      onPressed: () => _open(context),
    ),
  );
}

/// The account control: who is signed in, and everything the chrome has
/// no room to list.
///
/// On compact this is the only way to reach the secondary destinations -
/// a phone's tab bar holds the domains and nothing else - so the caller
/// hands it whatever the surrounding chrome is not already listing, plus
/// the account's own actions. A monogram rather than a glyph: the design
/// system has no person icon, and the first letter of the name is the
/// more personal answer anyway.
class WaxAccountButton extends StatelessWidget {
  const WaxAccountButton({
    required this.account,
    required this.onAction,
    this.entries = const <WaxNavEntry>[],
    this.onSelect,
    this.selected,
    this.labelled = false,
    this.label,
    super.key,
  });

  final WaxAccount account;
  final ValueChanged<String> onAction;

  /// Destinations the surrounding chrome does not list.
  final List<WaxNavEntry> entries;
  final ValueChanged<String>? onSelect;
  final String? selected;

  /// Draws the label under the monogram, the way a bottom tab does.
  final bool labelled;

  /// The accessible name, and the visible label where one is drawn.
  /// Null takes the design system's own.
  final String? label;

  Future<void> _open(BuildContext context) async {
    final colors = WaxColors.of(context);
    final items = <PopupMenuEntry<_MenuChoice>>[
      // A session can be authenticated with no user payload, and an
      // empty row at the head of the menu says less than no row at all.
      if (account.name.trim().isNotEmpty)
        PopupMenuItem<_MenuChoice>(
          enabled: false,
          height: WaxSpace.s32,
          child: Text(
            account.name,
            style: WaxType.label.copyWith(color: colors.textPrimary),
          ),
        ),
      ..._entryItems(context, entries, selected),
      if (account.actions.isNotEmpty) const PopupMenuDivider(),
      for (final action in account.actions)
        PopupMenuItem<_MenuChoice>(
          value: _Run(action.name),
          child: Semantics(
            identifier: action.semanticsId,
            child: Row(
              children: <Widget>[
                if (action.glyph != null) ...<Widget>[
                  WaxIcon(action.glyph!, size: 18, color: colors.textSecondary),
                  const SizedBox(width: WaxSpace.s12),
                ],
                Text(action.label),
              ],
            ),
          ),
        ),
    ];
    final chosen = await _openMenu(context, items);
    switch (chosen) {
      case _GoTo(:final name):
        onSelect?.call(name);
      case _Run(:final name):
        onAction(name);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => _NavItem(
      label: label ?? context.waxL10n.navAccount,
      monogram: account.name,
      semanticsId: account.semanticsId,
      selected: false,
      form: labelled ? _NavForm.tab : _NavForm.rail,
      onTap: () => _open(context),
    ),
  );
}

/// The account's initial on a tinted disc.
///
/// A name with no letters in it still has to draw something, so the
/// fallback is the domain-neutral listener glyph rather than an empty
/// circle. The usable-initial rule is `ArtworkImage`'s, deliberately: a
/// name of "..." or "_sam" yields punctuation, and punctuation on a disc
/// is worse than a glyph that is at least true.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.name});

  final String name;

  /// Bigger than the 22 px glyph a destination draws, deliberately.
  ///
  /// At 24 with a 12 px letter this was the smallest thing in a bar whose
  /// neighbours draw 20 to 22 px glyphs in 44 px boxes, and it is the one
  /// control somebody has to find without already knowing where it is.
  /// A disc reads smaller than a glyph of the same box anyway, because
  /// the letter inside it is what carries the meaning; 32 puts the letter
  /// at 16 and still leaves six pixels a side inside the touch target.
  static const double size = 32;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final trimmed = name.trim();
    // The first grapheme cluster, not the first code unit: a name
    // beginning with an emoji or anything outside the basic plane is two
    // code units, and taking one of them draws a lone surrogate.
    final letter = trimmed.isEmpty
        ? ''
        : trimmed.characters.first.toUpperCase();
    final usable = RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(letter);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accentContainer,
        shape: BoxShape.circle,
      ),
      child: !usable
          ? WaxIcon(
              WaxIcons.headphones,
              size: size * 0.6,
              // The disc's own on-colour, matching the letter below: the
              // row's glyph tint is not a pair the contrast matrix
              // enumerates against this fill.
              color: colors.onAccentContainer,
            )
          : Text(
              letter,
              maxLines: 1,
              softWrap: false,
              // Upper-casing can lengthen a cluster (ß becomes SS), and
              // the disc is a fixed width: clip rather than paint over it.
              overflow: TextOverflow.clip,
              style: WaxType.label.copyWith(
                color: colors.onAccentContainer,
                fontSize: size * 0.5,
              ),
            ),
    );
  }
}

/// The sidebar: the expanded and wide shell's navigation.
///
/// Sections with text labels, collapsible groups for the secondary areas,
/// and a toggle down to an icon rail's width. [header] is the brand block
/// today and the search field once search exists.
class WaxSidebar extends StatefulWidget {
  const WaxSidebar({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    this.secondary = const <WaxNavEntry>[],
    this.header,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.collapseSemanticsId,
    this.account,
    this.semanticsId,
    super.key,
  });

  final List<WaxDestination> destinations;
  final String? selected;
  final ValueChanged<String> onSelect;
  final List<WaxNavEntry> secondary;

  /// The account control, in the footer beside the collapse toggle. The
  /// sidebar lists the secondary destinations itself, so here the menu
  /// carries the account and nothing else.
  final Widget? account;

  /// Drawn above the destinations. Dropped while collapsed, where there
  /// is no room for it.
  final Widget? header;

  /// Collapsed to an icon rail's width. The state belongs to the shell,
  /// which persists it.
  final bool collapsed;

  final VoidCallback? onToggleCollapsed;
  final String? collapseSemanticsId;
  final String? semanticsId;

  @override
  State<WaxSidebar> createState() => _WaxSidebarState();
}

class _WaxSidebarState extends State<WaxSidebar> {
  /// What a visitor has decided about a group. A group holding the
  /// active destination opens by default, not by floor, or it could not
  /// be closed from inside. Keyed by name: a translated key forgets.
  final Map<String, bool> _disclosed = <String, bool>{};

  bool _isOpen(WaxNavGroup group) =>
      _disclosed[group.name] ??
      group.children.any((child) => child.name == widget.selected);

  /// A parent destination opens on its own while it or one of its
  /// children is where the visitor is, and closes when they leave - until
  /// they say otherwise, after which their answer stands.
  bool _isParentOpen(WaxDestination parent) =>
      _disclosed[parent.name] ??
      (parent.name == widget.selected ||
          parent.children.any((child) => child.name == widget.selected));

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    final collapsed = widget.collapsed;

    return _NavRegion(
      semanticsId: widget.semanticsId,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface1,
          border: BorderDirectional(
            end: BorderSide(
              color: colors.hairline,
              width: layout.hairlineWidth,
            ),
          ),
        ),
        child: SafeArea(
          right: false,
          child: SizedBox(
            width: collapsed
                ? WaxShellMetrics.railWidth
                : WaxShellMetrics.sidebarWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.header != null && !collapsed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WaxSpace.s16,
                      WaxSpace.s16,
                      WaxSpace.s12,
                      WaxSpace.s8,
                    ),
                    child: widget.header,
                  )
                else
                  const SizedBox(height: WaxSpace.s12),
                Expanded(
                  // The list scrolls: a long secondary section on a short
                  // window would otherwise overflow rather than reach.
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WaxSpace.s8,
                    ),
                    children: <Widget>[
                      for (final destination in widget.destinations)
                        ..._destinationRows(destination, collapsed: collapsed),
                      if (widget.secondary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: WaxSpace.s8,
                          ),
                          child: Divider(
                            color: colors.hairline,
                            height: layout.hairlineWidth,
                          ),
                        ),
                      for (final entry in widget.secondary)
                        ...switch (entry) {
                          WaxNavLink(:final destination) => <Widget>[
                            _sidebarItem(destination, collapsed: collapsed),
                          ],
                          WaxNavGroup() => _group(entry, collapsed: collapsed),
                        },
                    ],
                  ),
                ),
                if (widget.account != null || widget.onToggleCollapsed != null)
                  Padding(
                    padding: const EdgeInsets.all(WaxSpace.s8),
                    // Collapsed there is one column and no room to pair
                    // them, so they stack; expanded the account leads and
                    // the toggle sits at the far edge, which with only
                    // one of the two present is just that one at its own
                    // end.
                    child: Flex(
                      direction: collapsed ? Axis.vertical : Axis.horizontal,
                      mainAxisAlignment: switch ((
                        collapsed,
                        widget.account == null,
                      )) {
                        (true, _) => MainAxisAlignment.center,
                        (false, true) => MainAxisAlignment.end,
                        (false, false) => MainAxisAlignment.spaceBetween,
                      },
                      children: <Widget>[
                        ?widget.account,
                        if (widget.onToggleCollapsed != null)
                          WaxIconButton(
                            glyph: collapsed ? WaxIcons.forward : WaxIcons.back,
                            label: collapsed
                                ? context.waxL10n.navExpandSidebar
                                : context.waxL10n.navCollapseSidebar,
                            semanticsId: widget.collapseSemanticsId,
                            onPressed: widget.onToggleCollapsed,
                          ),
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

  /// One primary destination: a row, plus its sub-destinations when it
  /// has any and the sidebar has room to indent them.
  List<Widget> _destinationRows(
    WaxDestination destination, {
    required bool collapsed,
  }) {
    if (destination.children.isEmpty || collapsed) {
      return <Widget>[_sidebarItem(destination, collapsed: collapsed)];
    }
    final open = _isParentOpen(destination);
    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: _sidebarItem(destination, collapsed: false)),
          // Beside the row rather than inside it. The row excludes its own
          // subtree from semantics so it announces once, which would
          // swallow a nested control whole; and the two do different
          // things, so a screen reader should find two.
          WaxIconButton(
            glyph: open ? WaxIcons.collapse : WaxIcons.forward,
            label: open
                ? context.waxL10n.navCollapseSection(destination.label)
                : context.waxL10n.navExpandSection(destination.label),
            size: 16,
            semanticsId: destination.discloseSemanticsId,
            onPressed: () =>
                setState(() => _disclosed[destination.name] = !open),
          ),
        ],
      ),
      if (open)
        for (final child in destination.children)
          _sidebarItem(child, collapsed: false, indent: true),
    ];
  }

  Widget _sidebarItem(
    WaxDestination destination, {
    required bool collapsed,
    bool indent = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: _NavItem(
      label: destination.label,
      glyph: destination.glyph,
      badge: destination.badge,
      semanticsId: destination.semanticsId,
      // The children are drawn only when this row is a disclosed parent
      // in an expanded sidebar; anywhere else the parent lights for them.
      selected: _holdsSelection(
        destination,
        widget.selected,
        childrenDrawn: !collapsed && _isParentOpen(destination),
      ),
      form: collapsed ? _NavForm.rail : _NavForm.row,
      indent: indent && !collapsed,
      onTap: () => widget.onSelect(destination.name),
    ),
  );

  List<Widget> _group(WaxNavGroup group, {required bool collapsed}) {
    // Collapsed, there is no room to disclose anything: the group's
    // children flatten into the rail so none of them becomes unreachable.
    if (collapsed) {
      return <Widget>[
        for (final child in group.children)
          _sidebarItem(child, collapsed: true),
      ];
    }
    final open = _isOpen(group);
    return <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: _NavItem(
          label: group.label,
          glyph: group.glyph,
          semanticsId: group.semanticsId,
          selected: false,
          form: _NavForm.row,
          trailing: WaxIcon(
            open ? WaxIcons.collapse : WaxIcons.forward,
            size: 16,
            color: WaxColors.of(context).textTertiary,
          ),
          onTap: () => setState(() => _disclosed[group.name] = !open),
        ),
      ),
      if (open)
        for (final child in group.children)
          _sidebarItem(child, collapsed: false, indent: true),
    ];
  }
}

/// The navigation landmark, named once for assistive technology.
class _NavRegion extends StatelessWidget {
  const _NavRegion({required this.child, this.semanticsId});

  final Widget child;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: semanticsId,
    container: true,
    explicitChildNodes: true,
    label: context.waxL10n.navMain,
    // Its own Material, so each piece of chrome stands alone: the ink and
    // menu machinery underneath the house controls needs one, and the
    // caller's content pane is not it.
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// The shell's frame: navigation chrome for the window's size class,
/// around a content pane the caller supplies.
///
/// The frame owns where things sit, never what they are: [content] is the
/// active screen (a branch navigator in the app), [bottom] is the deck
/// bar's place, and [panel] the right panel's. Every adaptive decision
/// here keys off the size class, so a narrow desktop window behaves like
/// a phone.
class WaxShellFrame extends StatefulWidget {
  const WaxShellFrame({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    required this.content,
    this.secondary = const <WaxNavEntry>[],
    this.sidebarHeader,
    this.sizeClass,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.bottom,
    this.panel,
    this.banners = const <Widget>[],
    this.account,
    this.onAccountAction,
    this.navSemanticsId,
    this.collapseSemanticsId,
    this.overflowSemanticsId,
    this.skipSemanticsId,
    super.key,
  }) : assert(
         account == null || onAccountAction != null,
         'an account menu whose actions go nowhere is a dead control',
       );

  /// The primary destinations: the domains, which are tabs at every
  /// width.
  final List<WaxDestination> destinations;

  final String? selected;
  final ValueChanged<String> onSelect;

  /// The active screen.
  final Widget content;

  /// Destinations that are not tabs: settings, curation, administration.
  ///
  /// The sidebar lists them and the rail reaches them through one
  /// overflow menu. Compact's tab bar has room for the domains and
  /// nothing else, and the frame draws no account control there at all:
  /// below rail width the avatar belongs in the screen's own top app bar,
  /// which is where the caller puts it, and it carries these with it.
  final List<WaxNavEntry> secondary;

  final Widget? sidebarHeader;

  /// Defaults to the class of the current window.
  final WaxSizeClass? sizeClass;

  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  /// The deck bar. Full width below everything, except on compact where
  /// it sits above the tabs.
  final Widget? bottom;

  /// The right panel. Docked beside the content on [WaxSizeClass.wide]
  /// and laid over its trailing edge on [WaxSizeClass.expanded]; below
  /// that there is no room for one, and the frame ignores it rather than
  /// squeezing the content pane down to nothing.
  final Widget? panel;

  /// Standing messages about the app's own state, above the content and
  /// below the chrome: they belong to the whole app, and a screen that
  /// scrolls must not be able to scroll one out of sight.
  final List<Widget> banners;

  /// The signed-in account, for the chrome that draws one: the rail's
  /// footer and the sidebar's. Compact draws none - the screen's app bar
  /// has it - so a frame given an account below rail width simply does
  /// not use it.
  final WaxAccount? account;

  final ValueChanged<String>? onAccountAction;

  final String? navSemanticsId;
  final String? collapseSemanticsId;
  final String? overflowSemanticsId;

  /// The handle for the skip link, which the frame draws wherever the
  /// chrome comes before the content.
  final String? skipSemanticsId;

  @override
  State<WaxShellFrame> createState() => _WaxShellFrameState();
}

class _WaxShellFrameState extends State<WaxShellFrame> {
  /// The content's own scope, so the skip link has somewhere to send
  /// focus.
  ///
  /// `parentScope` rather than the default closed loop: routes escape
  /// their own scope at the edge, and a scope that looped here would trap
  /// tab traversal inside the page and put the chrome out of reach.
  final FocusScopeNode _content = FocusScopeNode(
    debugLabel: 'shell-content',
    traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  /// Hands focus to the content.
  ///
  /// Focusing the scope alone would not do it: a scope with nothing
  /// focused yet takes the focus itself and leaves the visitor one more
  /// keystroke from the page, which is the keystroke this control
  /// exists to save. So the traversal policy names where the page starts
  /// (whatever a route already had focused, or its first control) and
  /// that is what is focused; the region itself is the fallback for a
  /// page with nothing focusable in it at all.
  void _skipToContent() {
    final policy = FocusTraversalGroup.maybeOf(context);
    (policy?.findFirstFocus(_content) ?? _content).requestFocus();
  }

  Widget? _accountButton({
    required bool labelled,
    required bool listsSecondary,
  }) {
    final account = widget.account;
    if (account == null) return null;
    return WaxAccountButton(
      account: account,
      onAction: widget.onAccountAction!,
      entries: listsSecondary ? const <WaxNavEntry>[] : widget.secondary,
      onSelect: widget.onSelect,
      selected: widget.selected,
      labelled: labelled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = widget.destinations;
    final secondary = widget.secondary;
    final selected = widget.selected;
    final onSelect = widget.onSelect;
    final bottom = widget.bottom;
    final panel = widget.panel;
    final banners = widget.banners;
    final sizeClass = widget.sizeClass ?? WaxSizeClass.of(context);
    final colors = WaxColors.of(context);

    // The content is its own semantics region, and that is load-bearing
    // rather than decorative. Every route inside it carries a
    // `ModalBarrier`, which wraps itself in `BlockSemantics` - "excludes
    // the semantics of all widgets painted before it in the same semantic
    // container" - so a pane sharing this frame's container would erase
    // the chrome painted ahead of it: the sidebar and the rail would
    // render and expose nothing at all, to a screen reader or to the
    // suite. A boundary ends that walk (`isBlockingPreviousSibling`
    // stops at `isSemanticBoundary`), and it is the one main region the
    // accessibility spec asks for besides.
    Widget region(Widget child) => Semantics(
      container: true,
      explicitChildNodes: true,
      child: ColoredBox(color: colors.canvas, child: child),
    );

    // The banners ride with the content rather than above the whole
    // frame: the chrome is where a visitor is going, and pushing the
    // sidebar and the rail down every time the socket blinks would move
    // the navigation under their cursor.
    Widget withBanners(Widget content) => banners.isEmpty
        ? content
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ...banners,
              Expanded(child: content),
            ],
          );

    // Traversal order is shell, then content, then deck bar, which is the
    // order the children are listed in below.
    Widget middle = FocusScope(node: _content, child: region(widget.content));
    if (panel != null) {
      if (sizeClass.docksPanel) {
        middle = Row(
          children: <Widget>[
            Expanded(child: middle),
            SizedBox(width: WaxShellMetrics.rightPanelWidth, child: panel),
          ],
        );
      } else if (sizeClass.hasSidebar) {
        // One step narrower there is not room for both at full width, so
        // the panel lies over the content's trailing edge. No scrim: the
        // page underneath stays readable and usable, which is the whole
        // reason this is a panel and not a sheet. It is painted after the
        // pane, so the modal barriers inside routed content cannot block
        // its semantics.
        middle = Stack(
          children: <Widget>[
            Positioned.fill(child: middle),
            PositionedDirectional(
              top: 0,
              bottom: 0,
              end: 0,
              width: WaxShellMetrics.rightPanelWidth,
              child: panel,
            ),
          ],
        );
      }
    }
    final pane = Expanded(child: withBanners(middle));

    final Widget body = switch (sizeClass) {
      WaxSizeClass.compact => Column(
        children: <Widget>[
          pane,
          ?bottom,
          WaxNavBar(
            destinations: destinations,
            selected: selected,
            onSelect: onSelect,
            semanticsId: widget.navSemanticsId,
          ),
        ],
      ),
      WaxSizeClass.medium => Column(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                WaxNavRail(
                  destinations: destinations,
                  selected: selected,
                  onSelect: onSelect,
                  secondary: secondary,
                  account: _accountButton(
                    labelled: false,
                    // The rail's own overflow lists them.
                    listsSecondary: true,
                  ),
                  semanticsId: widget.navSemanticsId,
                  overflowSemanticsId: widget.overflowSemanticsId,
                ),
                pane,
              ],
            ),
          ),
          ?bottom,
        ],
      ),
      WaxSizeClass.expanded || WaxSizeClass.wide => Column(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                WaxSidebar(
                  destinations: destinations,
                  selected: selected,
                  onSelect: onSelect,
                  secondary: secondary,
                  header: widget.sidebarHeader,
                  collapsed: widget.collapsed,
                  onToggleCollapsed: widget.onToggleCollapsed,
                  collapseSemanticsId: widget.collapseSemanticsId,
                  account: _accountButton(
                    labelled: false,
                    listsSecondary: true,
                  ),
                  semanticsId: widget.navSemanticsId,
                ),
                pane,
              ],
            ),
          ),
          ?bottom,
        ],
      ),
    };

    // The skip link exists where the chrome comes before the content in
    // the reading order, so it is drawn everywhere but compact: a phone
    // reads the content first and its tabs last, and a link that skips
    // forward to what is already first is noise in a screen reader's
    // path.
    //
    // Both halves carry a sort key. A key sorts a node only against
    // siblings whose keys are compatible, and geometry decides the rest,
    // so keying one of the two would leave the order to whichever
    // rectangle a knot sort happened to walk first.
    if (sizeClass.isCompact) {
      return ColoredBox(color: colors.canvas, child: body);
    }
    return ColoredBox(
      color: colors.canvas,
      child: Stack(
        children: <Widget>[
          Semantics(
            container: true,
            // Paired with `container`, as everywhere else in the frame: a
            // node that annotates rather than contains would let a future
            // descendant merge its label into the whole frame's node.
            explicitChildNodes: true,
            sortKey: const OrdinalSortKey(1),
            child: body,
          ),
          // Painted last so a focused link is drawn over the chrome, and
          // sorted first so it is the first thing in the reading order:
          // the order a screen reader walks, and the order the web build
          // lays its elements out in. Directional, because the chrome it
          // skips is at the start edge and that is the right-hand side in
          // a right-to-left locale.
          PositionedDirectional(
            top: 0,
            start: 0,
            child: Semantics(
              container: true,
              sortKey: const OrdinalSortKey(0),
              child: _SkipLink(
                onSkip: _skipToContent,
                semanticsId: widget.skipSemanticsId,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The first thing in the reading order: a link past the navigation to
/// the content.
///
/// Unfocused it is one pixel in the leading corner; focused it grows to
/// its pill and is drawn. Not zero: a zero-size render object leaves the
/// semantics tree, which takes the link out of the tab order, which is
/// the one thing this control cannot afford. And not full-size either,
/// which is what it used to be - on web the semantics tree is real DOM,
/// and an element with a tap action takes the browser's click for its
/// whole box whatever Flutter's own hit test says about it. At the
/// leading corner that box is over the sidebar header, so a field there
/// could be seen and could not be clicked.
///
/// What it is first *for* is the reading order, which is where the
/// chrome comes before the content. Framework tab traversal is the
/// other way around: a route owns focus from its first frame and a tab
/// leaves it only at the scope edge, so on a keyboard the page comes
/// first and the chrome follows it, and there is nothing to skip.
class _SkipLink extends StatefulWidget {
  const _SkipLink({required this.onSkip, this.semanticsId});

  final VoidCallback onSkip;
  final String? semanticsId;

  @override
  State<_SkipLink> createState() => _SkipLinkState();
}

class _SkipLinkState extends State<_SkipLink> {
  bool _focused = false;

  /// Owned for the same reason [_NavItem] owns one: the platform's focus
  /// request has to reach a real node.
  final FocusNode _focus = FocusNode(debugLabel: 'skip-link');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Semantics(
      identifier: widget.semanticsId,
      button: true,
      label: context.waxL10n.navSkipToContent,
      excludeSemantics: true,
      onTap: widget.onSkip,
      focusable: true,
      focused: _focused,
      onFocus: _focus.requestFocus,
      // Above the detector, not below it: the detector's outermost
      // render object is an opaque `MouseRegion`, whose `hitTest`
      // answers for the whole box whatever sits beneath it, and this box
      // is painted last in the frame's stack. Ignoring from inside left
      // roughly 140 by 48 of dead corner over the content pane - at rail
      // width that is exactly where a screen's back button sits.
      //
      // The clip is the other half of the same problem, for the platform
      // that does not ask Flutter: the semantics element web renders for
      // this node is sized to the box, so the box is what has to shrink.
      child: IgnorePointer(
        ignoring: !_focused,
        child: _SkipLinkBox(
          collapsed: !_focused,
          child: FocusableActionDetector(
            focusNode: _focus,
            mouseCursor: SystemMouseCursors.click,
            onShowFocusHighlight: (value) => setState(() => _focused = value),
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onSkip();
                  return null;
                },
              ),
            },
            child: Padding(
              padding: const EdgeInsets.all(WaxSpace.s8),
              child: WaxFocusRing(
                focused: _focused,
                borderRadius: WaxRadius.pill,
                surface: colors.canvas,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onSkip,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _focused ? colors.accentContainer : null,
                      borderRadius: WaxRadius.pill,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WaxSpace.s16,
                        vertical: WaxSpace.s8,
                      ),
                      child: Text(
                        context.waxL10n.navSkipToContent,
                        style: WaxType.label.copyWith(
                          color: _focused
                              ? colors.onAccentContainer
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays the skip link out at its natural size and reports one pixel
/// while it is collapsed.
///
/// A plain `SizedBox` around it would lay the pill out at one pixel and
/// wrap the label to nothing; this lets the child measure itself, paints
/// it, and only lies about the size - which is what both the semantics
/// rect and the parent's clip are read from. Focused, it is an ordinary
/// pass-through.
class _SkipLinkBox extends SingleChildRenderObjectWidget {
  const _SkipLinkBox({required this.collapsed, required super.child});

  final bool collapsed;

  @override
  _RenderSkipLinkBox createRenderObject(BuildContext context) =>
      _RenderSkipLinkBox(collapsed);

  @override
  void updateRenderObject(BuildContext context, _RenderSkipLinkBox render) {
    render.collapsed = collapsed;
  }
}

class _RenderSkipLinkBox extends RenderProxyBox {
  _RenderSkipLinkBox(this._collapsed);

  bool _collapsed;

  bool get collapsed => _collapsed;
  set collapsed(bool value) {
    if (_collapsed == value) return;
    _collapsed = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    // Loosened, so the pill lays out at the width it wants rather than
    // at the one this box is about to report.
    child!.layout(constraints.loosen(), parentUsesSize: true);
    size = _collapsed ? const Size(1, 1) : child!.size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Drawn only when it is real. Collapsed it is a pixel, and painting
    // a pill through a one-pixel box would leave a sliver of it visible
    // in the corner of every screen.
    if (_collapsed) return;
    super.paint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _collapsed ? false : super.hitTestChildren(result, position: position);
}
