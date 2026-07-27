import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../theme/wax_layout.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// One place the shell can send a visitor, as plain data.
///
/// [name] is the destination's identity: the chrome selects and reports by
/// it, so a list rebuilt every frame still compares equal without the
/// caller holding indices. Nothing here is coloured by domain — an active
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
    required this.label,
    required this.glyph,
    required this.children,
    this.semanticsId,
  });

  final String label;
  final WaxGlyph glyph;
  final List<WaxDestination> children;

  /// The handle for the disclosure row itself.
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
    required this.glyph,
    required this.selected,
    required this.onTap,
    required this.form,
    this.semanticsId,
    this.badge,
    this.trailing,
    this.indent = false,
  });

  final String label;
  final WaxGlyph glyph;
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

  /// The rail draws no label, so a tooltip is where a pointer user reads
  /// the name. Everywhere else the label is right there, and a tooltip
  /// repeating it is noise.
  Widget _maybeTooltip(Widget child) => widget.form == _NavForm.rail
      ? Tooltip(message: widget.label, child: child)
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

    Widget glyph = WaxIcon(
      widget.glyph,
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
        padding: EdgeInsets.only(
          left: widget.indent ? WaxSpace.s32 : WaxSpace.s12,
          right: WaxSpace.s12,
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
      child: FocusableActionDetector(
        enabled: enabled,
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
/// scrolls away.
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
                      selected: destination.name == selected,
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
    this.overflowLabel = 'More',
    this.overflowSemanticsId,
    this.semanticsId,
    super.key,
  });

  final List<WaxDestination> destinations;
  final String? selected;
  final ValueChanged<String> onSelect;
  final List<WaxNavEntry> secondary;
  final String overflowLabel;
  final String? overflowSemanticsId;
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
                      selected: destination.name == selected,
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
                    label: overflowLabel,
                    semanticsId: overflowSemanticsId,
                  ),
                const SizedBox(height: WaxSpace.s12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The secondary destinations as one menu, for chrome with no room to
/// list them.
class WaxNavOverflowButton extends StatelessWidget {
  const WaxNavOverflowButton({
    required this.entries,
    required this.onSelect,
    this.selected,
    this.label = 'More',
    this.semanticsId,
    super.key,
  });

  final List<WaxNavEntry> entries;
  final ValueChanged<String> onSelect;
  final String? selected;
  final String label;
  final String? semanticsId;

  /// Opens the menu against the trigger, and reports what was chosen.
  ///
  /// The trigger is the house icon button rather than a
  /// [PopupMenuButton]: its own trigger draws a second semantics node
  /// for the same control, and the suite steers by one handle per
  /// control.
  Future<void> _open(BuildContext context) async {
    final trigger = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final origin = trigger.localToGlobal(Offset.zero, ancestor: overlay);
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        overlay.size.width - origin.dx - trigger.size.width,
        overlay.size.height - origin.dy,
      ),
      items: _items(context),
    );
    if (chosen != null) onSelect(chosen);
  }

  List<PopupMenuEntry<String>> _items(BuildContext context) {
    final colors = WaxColors.of(context);
    return <PopupMenuEntry<String>>[
      for (final entry in entries)
        ...switch (entry) {
          WaxNavLink(:final destination) => <PopupMenuEntry<String>>[
            _menuItem(destination),
          ],
          // A group's children follow its label, flattened: a menu inside
          // a menu is a worse answer than a labelled run.
          WaxNavGroup() => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              enabled: false,
              height: WaxSpace.s32,
              child: Text(
                entry.label,
                style: WaxType.overline.copyWith(color: colors.textTertiary),
              ),
            ),
            for (final destination in entry.children) _menuItem(destination),
          ],
        },
    ];
  }

  PopupMenuItem<String> _menuItem(WaxDestination destination) =>
      PopupMenuItem<String>(
        value: destination.name,
        child: Semantics(
          identifier: destination.semanticsId,
          selected: destination.name == selected,
          child: Text(destination.label),
        ),
      );

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => WaxIconButton(
      glyph: WaxIcons.more,
      label: label,
      size: 22,
      semanticsId: semanticsId,
      onPressed: () => _open(context),
    ),
  );
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
    this.semanticsId,
    super.key,
  });

  final List<WaxDestination> destinations;
  final String? selected;
  final ValueChanged<String> onSelect;
  final List<WaxNavEntry> secondary;

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
  /// What a visitor has decided about a group, where they have decided
  /// anything. A group holding the active destination opens on its own, so
  /// arriving by URL never hides where you are — but that has to be a
  /// default rather than a floor, or the row cannot be closed from inside
  /// the very group whose child is selected.
  final Map<String, bool> _disclosed = <String, bool>{};

  bool _isOpen(WaxNavGroup group) =>
      _disclosed[group.label] ??
      group.children.any((child) => child.name == widget.selected);

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
                        _sidebarItem(destination, collapsed: collapsed),
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
                if (widget.onToggleCollapsed != null)
                  Padding(
                    padding: const EdgeInsets.all(WaxSpace.s8),
                    child: Align(
                      alignment: collapsed
                          ? Alignment.center
                          : AlignmentDirectional.centerEnd,
                      child: WaxIconButton(
                        glyph: collapsed ? WaxIcons.forward : WaxIcons.back,
                        label: collapsed
                            ? 'Expand sidebar'
                            : 'Collapse sidebar',
                        semanticsId: widget.collapseSemanticsId,
                        onPressed: widget.onToggleCollapsed,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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
      selected: destination.name == widget.selected,
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
          onTap: () => setState(() => _disclosed[group.label] = !open),
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
    label: 'Main navigation',
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
class WaxShellFrame extends StatelessWidget {
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
    this.navSemanticsId,
    this.collapseSemanticsId,
    this.overflowSemanticsId,
    super.key,
  });

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
  /// overflow menu. Compact draws none of them: a phone's bar has room
  /// for the domains and nothing else, so a compact shell reaches the
  /// rest through the app bar its screens own.
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

  final String? navSemanticsId;
  final String? collapseSemanticsId;
  final String? overflowSemanticsId;

  @override
  Widget build(BuildContext context) {
    final sizeClass = this.sizeClass ?? WaxSizeClass.of(context);
    final colors = WaxColors.of(context);

    // The content is its own semantics region, and that is load-bearing
    // rather than decorative. Every route inside it carries a
    // `ModalBarrier`, which wraps itself in `BlockSemantics` — "excludes
    // the semantics of all widgets painted before it in the same semantic
    // container" — so a pane sharing this frame's container would erase
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
    Widget middle = region(content);
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
              child: panel!,
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
            semanticsId: navSemanticsId,
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
                  semanticsId: navSemanticsId,
                  overflowSemanticsId: overflowSemanticsId,
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
                  header: sidebarHeader,
                  collapsed: collapsed,
                  onToggleCollapsed: onToggleCollapsed,
                  collapseSemanticsId: collapseSemanticsId,
                  semanticsId: navSemanticsId,
                ),
                pane,
              ],
            ),
          ),
          ?bottom,
        ],
      ),
    };

    return ColoredBox(color: colors.canvas, child: body);
  }
}
