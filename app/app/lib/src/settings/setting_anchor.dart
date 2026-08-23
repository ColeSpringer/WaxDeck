import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Landing on a setting rather than on the section it lives in.
///
/// A settings search result carries the setting's own id in the location
/// it opens (`/settings/<section>?setting=<id>`), and a section arriving
/// with one has to take the reader to that row: the sections are long,
/// and a result that lands at the top reads as "search found nothing"
/// for anything past the first screenful.
///
/// Two pieces. [WantedSetting] publishes the arriving id once, at the
/// top of the section; [SettingAnchor] wraps each row that has an id, and
/// the one whose id matches scrolls itself in and glows briefly.
///
/// Deliberately not a registry of `GlobalKey`s keyed by setting id. Two
/// subtrees can hold the same row at once - go_router mounts the
/// incoming and outgoing screen together through a transition - and two
/// live widgets sharing one GlobalKey is a crash, not a near miss. A row
/// that recognises itself has the same effect with nothing to collide.

/// The setting the current location asked for, published to the rows
/// under it. Null when the section was opened for its own sake.
class WantedSetting extends InheritedWidget {
  const WantedSetting({required this.id, required super.child, super.key});

  final String? id;

  /// The wanted id, or null. Returns null outside a section, which is
  /// what makes [SettingAnchor] safe to use on a screen that has no
  /// arriving id at all.
  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WantedSetting>()?.id;

  @override
  bool updateShouldNotify(WantedSetting oldWidget) => oldWidget.id != id;
}

/// One settings row that knows its own id, so an arriving `?setting=`
/// can land on it.
///
/// [id] is the registry's, which is also the suffix of the row's
/// semantics identifier - one handle for the search result, the anchor,
/// and the e2e suite, so a rename moves all three together.
///
/// A row nobody asked for draws its child and nothing else - no ticker,
/// no wrapper, no rebuild - so wrapping is free where it does not apply.
class SettingAnchor extends StatefulWidget {
  const SettingAnchor({required this.id, required this.child, super.key});

  final String id;
  final Widget child;

  @override
  State<SettingAnchor> createState() => _SettingAnchorState();
}

class _SettingAnchorState extends State<SettingAnchor>
    with SingleTickerProviderStateMixin {
  /// How long the arriving row stays marked. Also the window the row
  /// keeps itself in view over, which is the part that has to outlast a
  /// section still filling in: several of them draw rows behind a
  /// request, and every one that lands above this row pushes it down
  /// after the first scroll has already finished.
  static const Duration _marked = Duration(milliseconds: 1400);

  /// Whether the location currently naming this row has already been
  /// landed on. Not "has ever landed": go_router keys a page by its path
  /// and a query is neither a path nor a path parameter, so arriving at
  /// the same section with a different `?setting=` reuses this State.
  /// Latched while this row is the one named and released when it is
  /// not, so searching for the same setting twice lands twice and a
  /// rebuild under one arrival - a switch toggled, a theme change - does
  /// not drag the reader back.
  bool _landed = false;

  /// Built on the first landing and not before: most rows never land, and
  /// a ticker, a controller and a wrapper each are what "wrapping is
  /// free" would otherwise cost forty-odd times per section.
  AnimationController? _glow;

  /// Where this row sits in the scrollable's own content, which moves
  /// only when something above it grows. Scrolling does not change it, so
  /// comparing it frame to frame separates "the view is animating toward
  /// me" from "the content under me shifted".
  double? _revealed;

  /// The scroll's duration, read from the theme at landing time because
  /// the follow below runs outside build.
  Duration _travel = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLanding();
  }

  @override
  void didUpdateWidget(SettingAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Anchors are unkeyed, so a section that draws a row conditionally
    // reconciles this State against whichever anchor now holds its slot.
    // Without this the latch would belong to the old id and the new row
    // would never land.
    // _syncLanding releases the latch itself when the id it now holds is
    // not the one being asked for, which is what the swap always looks
    // like from here.
    if (oldWidget.id != widget.id) _syncLanding();
  }

  void _syncLanding() {
    if (WantedSetting.of(context) != widget.id) {
      _landed = false;
      _glow?.reset();
      return;
    }
    if (_landed) return;
    _landed = true;
    _revealed = null;
    _travel = WaxMotion.of(context).standard;
    (_glow ??= AnimationController(vsync: this, duration: _marked)
        ..addListener(_follow))
      ..reset()
      ..forward();
  }

  /// Keeps the row in view for as long as it is marked.
  ///
  /// Once is not enough. The row's box exists on the first layout, so the
  /// first scroll is right about where the row is then - but a section
  /// whose earlier groups are still filling in moves it afterwards, and a
  /// reader who was taken to the right place and then left somewhere else
  /// is back to the bug this exists for. Driven off the mark's own
  /// controller, which is what guarantees a frame to check on and bounds
  /// the chasing to the moment the reader is being shown something.
  void _follow() {
    if (!mounted) return;
    final at = _revealOffset();
    if (at == null) return;
    if (_revealed != null && (at - _revealed!).abs() < 0.5) return;
    _revealed = at;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: _travel,
      curve: WaxMotion.emphasized,
    );
  }

  /// This row's offset within the scrollable's content, or null when
  /// there is nothing to scroll. Nothing to scroll is not a failure; the
  /// row is already as visible as it gets.
  ///
  /// Measured against the viewport and then undone by the scroll offset,
  /// so what comes back describes where the row sits in the content
  /// rather than where it currently sits on screen - which is the only
  /// form a scroll under way cannot keep changing.
  double? _revealOffset() {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null || !scrollable.position.hasPixels) return null;
    final box = context.findRenderObject();
    final viewport = scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    return scrollable.position.pixels +
        box.localToGlobal(Offset.zero, ancestor: viewport).dy;
  }

  @override
  void dispose() {
    _glow?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = _glow;
    if (glow == null) return widget.child;
    final colors = WaxColors.of(context);
    final still = !WaxMotion.of(context).animationsEnabled;
    return AnimatedBuilder(
      animation: glow,
      builder: (context, child) {
        // Up over the first fifth and away over the rest: a mark that
        // says "here" and then stops competing with the row it marked.
        // Reduced motion gets the same mark held flat and then dropped,
        // since a wash that pulses is the one thing the preference asks
        // this row not to do.
        final t = glow.value;
        final strength = still
            ? (t < 1 ? 1.0 : 0.0)
            : (t < 0.2 ? t / 0.2 : 1 - (t - 0.2) / 0.8);
        if (strength <= 0) return child!;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accentContainer.withValues(alpha: 0.7 * strength),
            borderRadius: BorderRadius.circular(WaxRadius.r10),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
