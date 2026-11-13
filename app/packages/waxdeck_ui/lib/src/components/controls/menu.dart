import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../icons/wax_icon.dart';
import '../../l10n/wax_l10n.dart';
import '../../tokens/colors.dart';
import '../../tokens/spacing.dart';
import '../../tokens/typography.dart';
import '../secondary_tap.dart';
import 'icon_button.dart';

/// One row of a [WaxMenuButton].
@immutable
class WaxMenuItem<T> {
  const WaxMenuItem({
    required this.value,
    required this.label,
    this.glyph,
    this.selected = false,
    this.destructive = false,
    this.enabled = true,
    this.help,
    this.semanticsId,
  });

  /// What the button reports when this row is chosen.
  final T value;

  final String label;
  final WaxGlyph? glyph;

  /// A dimmer second line under the label, for a row whose state needs a
  /// sentence - most often why it is disabled.
  ///
  /// A line rather than a [Tooltip]: a tooltip on a disabled row never
  /// appears on touch at all, and the reason has to be readable on a
  /// phone. It is folded into the row's own accessible name for the same
  /// reason - the name and the reason are one thing to hear.
  final String? help;

  /// Drawn checked, for the rows that are a standing choice (a sort
  /// order) rather than a verb.
  final bool selected;

  /// Deletes and revokes, in the error colour.
  final bool destructive;

  final bool enabled;

  /// This row's own handle. A menu row is a control, so it gets one of
  /// its own rather than being found by its text.
  final String? semanticsId;
}

/// A menu row's ink: [on] normally, and the disabled tone for a row that
/// is showing but cannot be chosen.
///
/// The rows set their colours explicitly, so `PopupMenuItem`'s own
/// disabled styling - which works through the inherited text style -
/// never reaches them, and a disabled row would otherwise look exactly
/// like one that works.
Color _menuInk<T>(WaxColors colors, WaxMenuItem<T> item, {required Color on}) {
  if (!item.enabled) return colors.textDisabled;
  return item.destructive ? colors.error : on;
}

/// Opens [items] under [context]'s box and answers what was chosen; shared so
/// a secondary-tap surface raises the same menu as its overflow button.
/// [onShown] runs once, when the menu has been read ([WaxMenuButton.onShown]).
Future<T?> showWaxMenu<T>(
  BuildContext context,
  List<WaxMenuItem<T>> items, {
  String? emptyLabel,
  String? emptySemanticsId,
  VoidCallback? onShown,
}) async {
  var read = false;
  final VoidCallback? markRead = onShown == null
      ? null
      : () {
          if (read) return;
          read = true;
          onShown();
        };
  final colors = WaxColors.of(context);
  final trigger = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final origin = trigger.localToGlobal(Offset.zero, ancestor: overlay);
  // Held across the whole route, not just while the pointer rests on the
  // trigger: the menu's own modal barrier takes the pointer away from
  // whatever was suppressing the browser's, so without this the browser
  // menu comes back the instant WaxDeck's own appears.
  final chosen = await waxWithoutBrowserMenu(
    () => showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + trigger.size.height,
        overlay.size.width - origin.dx - trigger.size.width,
        overlay.size.height - origin.dy,
      ),
      items: <PopupMenuEntry<T>>[
        if (items.isEmpty && emptyLabel != null)
          PopupMenuItem<T>(
            enabled: false,
            // Addressable like every other row: "the menu is open and
            // holds nothing" is a state a driver has to be able to see,
            // and it is the only one with no row to look for.
            child: _readBy(
              markRead,
              Semantics(
                identifier: emptySemanticsId,
                child: Text(
                  emptyLabel,
                  style: WaxType.body.copyWith(color: colors.textTertiary),
                ),
              ),
            ),
          ),
        for (final (index, item) in items.indexed)
          PopupMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            // A help line makes the row two lines tall, and a popup row
            // states its own height or clips.
            height: item.help == null
                ? kMinInteractiveDimension
                : kMinInteractiveDimension + WaxSpace.s16,
            // The first row watches for the read: an entry of its own
            // would shift every row's staggered fade.
            child: _readBy(
              index == 0 ? markRead : null,
              Semantics(
                identifier: item.semanticsId,
                selected: item.selected,
                enabled: item.enabled,
                // The reason reads with the name rather than as a node
                // after it, so the text below is excluded when it is the
                // container speaking for both.
                label: item.help == null ? null : '${item.label}. ${item.help}',
                child: ExcludeSemantics(
                  excluding: item.help != null,
                  child: Row(
                    children: <Widget>[
                      if (item.glyph != null) ...<Widget>[
                        WaxIcon(
                          item.glyph!,
                          size: 16,
                          color: _menuInk(
                            colors,
                            item,
                            on: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: WaxSpace.s12),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.label,
                              style: WaxType.body.copyWith(
                                color: _menuInk(
                                  colors,
                                  item,
                                  on: colors.textPrimary,
                                ),
                              ),
                            ),
                            if (item.help != null)
                              Text(
                                item.help!,
                                style: WaxType.caption.copyWith(
                                  color: item.enabled
                                      ? colors.textTertiary
                                      : colors.textDisabled,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (item.selected)
                        WaxIcon(
                          WaxIcons.check,
                          size: 16,
                          // Greyed with the rest of the row. A full-strength
                          // accent tick on a disabled row reads as the one
                          // live thing in it.
                          color: _menuInk(colors, item, on: colors.accent),
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
  // A choice proves the rows were read, however soon it came.
  if (chosen != null) markRead?.call();
  return chosen;
}

Widget _readBy(VoidCallback? onRead, Widget row) =>
    onRead == null ? row : _MenuRead(onRead: onRead, child: row);

/// How long a menu has to be up, and fully drawn, to count as read: its
/// entrance's own length, which reduced motion cuts to a frame.
const _menuReadAfter = Duration(milliseconds: 300);

/// Reports [onRead] once its menu has finished appearing and been up for
/// [_menuReadAfter]. Dismissing reverses the entrance, so a menu closed
/// sooner never reports.
class _MenuRead extends StatefulWidget {
  const _MenuRead({required this.onRead, required this.child});

  final VoidCallback onRead;
  final Widget child;

  @override
  State<_MenuRead> createState() => _MenuReadState();
}

class _MenuReadState extends State<_MenuRead>
    with SingleTickerProviderStateMixin {
  // Preserved, or reduced motion would run this clock at a twentieth.
  late final AnimationController _up = AnimationController(
    vsync: this,
    duration: _menuReadAfter,
    animationBehavior: AnimationBehavior.preserve,
  );
  Animation<double>? _entrance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance != null) return;
    _entrance = ModalRoute.of(context)!.animation!..addStatusListener(_check);
    _up
      ..addStatusListener(_check)
      ..forward();
  }

  void _check(AnimationStatus _) {
    if (!_up.isCompleted || !_entrance!.isCompleted) return;
    _entrance!.removeStatusListener(_check);
    widget.onRead();
  }

  @override
  void dispose() {
    _entrance?.removeStatusListener(_check);
    _up.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// An overflow menu behind one icon button.
///
/// The trigger is the house icon button rather than a [PopupMenuButton],
/// for the reason the chrome's own overflow already follows: a
/// PopupMenuButton draws a second semantics node for the same control,
/// and the suite steers by one handle per control.
class WaxMenuButton<T> extends StatelessWidget {
  const WaxMenuButton({
    required this.items,
    required this.onSelected,
    this.glyph = WaxIcons.more,
    this.label,
    this.semanticsId,
    this.size = 20,
    this.badge,
    this.onShown,
    this.emptyLabel,
    this.emptySemanticsId,
    super.key,
  });

  final List<WaxMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final WaxGlyph glyph;

  /// The trigger's accessible name. Null takes the design system's
  /// own word for an overflow.
  final String? label;
  final String? semanticsId;
  final double size;

  /// A count drawn on the trigger's glyph, for a menu whose whole point
  /// is how much is waiting in it.
  final String? badge;

  /// Run once the menu has been read: up and fully drawn for as long as its
  /// entrance takes, or chosen from. It can run after this button has left
  /// the tree, so it must not lean on the button's context.
  final VoidCallback? onShown;

  /// What an empty menu says. Without one an empty menu disables its
  /// trigger, which is right for an overflow of verbs and wrong for a
  /// list that is legitimately empty and worth saying so.
  final String? emptyLabel;

  /// A handle on [emptyLabel]'s row, for a menu whose empty state a test
  /// has to be able to tell from a menu that never opened.
  final String? emptySemanticsId;

  Future<void> _open(BuildContext context) async {
    final chosen = await showWaxMenu<T>(
      context,
      items,
      emptyLabel: emptyLabel,
      emptySemanticsId: emptySemanticsId,
      onShown: onShown,
    );
    // A button that has left the tree has nobody left to act on a choice.
    if (chosen != null && context.mounted) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) => Builder(
    // Its own context, so the menu positions against this button rather
    // than against whatever laid the bar out.
    builder: (context) => WaxIconButton(
      glyph: glyph,
      label: label ?? context.waxL10n.commonMore,
      size: size,
      badge: badge,
      semanticsId: semanticsId,
      onPressed: items.isEmpty && emptyLabel == null
          ? null
          : () => _open(context),
    ),
  );
}
