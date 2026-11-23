import 'package:material_ui/material_ui.dart';

import '../icons/wax_icon.dart';
import '../l10n/wax_l10n.dart';
import '../theme/plain_text_style.dart';
import '../theme/wax_layout.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// Where an app draws its messages on each of its pages, the way a
/// Material Scaffold draws the snack bars of the messenger above it:
/// every [WaxScaffold] under this hands its page to [present], inside the
/// page's own semantics, and is drawn as [present] returns it; and its
/// floating button to [clear], since a message rests above that button as
/// a floating snack bar rested above Material's.
class WaxPageMessages extends InheritedWidget {
  const WaxPageMessages({
    required this.present,
    this.clear,
    required super.child,
    super.key,
  });

  /// [page] with the app's messages drawn over it.
  final Widget Function(Widget page) present;

  /// [button], along the bottom of a page, as something the app's
  /// messages rest above. Null leaves it as it is.
  final Widget Function(Widget button)? clear;

  /// [page] as the [WaxPageMessages] above [context] presents it; [page]
  /// itself with none.
  static Widget around(BuildContext context, Widget page) {
    final scope = context.dependOnInheritedWidgetOfExactType<WaxPageMessages>();
    return scope == null ? page : scope.present(page);
  }

  /// [button] as the [WaxPageMessages] above [context] has messages clear
  /// it; [button] itself with none.
  static Widget clearing(BuildContext context, Widget button) {
    final clear = context
        .dependOnInheritedWidgetOfExactType<WaxPageMessages>()
        ?.clear;
    return clear == null ? button : clear(button);
  }

  @override
  bool updateShouldNotify(WaxPageMessages oldWidget) =>
      present != oldWidget.present || clear != oldWidget.clear;
}

/// The page scaffold every screen sits in.
///
/// It owns the large-title app bar (which collapses on scroll), the
/// gutters for the current size class, and the landmark structure
/// assistive technology navigates by: a header, one main region, and a
/// deck bar the shell supplies. The app's messages are drawn over it
/// through the [WaxPageMessages] above it.
class WaxScaffold extends StatelessWidget {
  const WaxScaffold({
    required this.title,
    this.body,
    this.slivers,
    this.fill,
    this.actions = const <Widget>[],
    this.onBack,
    this.backSemanticsId,
    this.largeTitle = true,
    this.bottom,
    this.floating,
    this.controller,
    this.onRefresh,
    this.semanticsId,
    super.key,
  }) : assert(
         (body != null ? 1 : 0) +
                 (slivers != null ? 1 : 0) +
                 (fill != null ? 1 : 0) ==
             1,
         'give WaxScaffold a body, slivers or a fill, one of them',
       );

  final String title;

  /// A single box child, for screens that are a column of content.
  final Widget? body;

  /// Slivers, for screens that page: a grid or list belongs here, where
  /// it can build lazily. A list inside [body] gets unbounded height and
  /// has to shrink-wrap, which builds every row on the first frame and
  /// is the opposite of what the artwork grids need.
  final List<Widget>? slivers;

  /// A box filling the page below its bar, for a screen whose content
  /// scrolls inside panes of its own. It is laid out against the page's
  /// sides and foot and handed the window's insets on those edges, for
  /// whatever of it stands against each to take: a [WaxFootBar] along
  /// its foot runs its surface under them, as a [WaxFootedPane] places
  /// one.
  ///
  /// Taking them is the fill's duty, not the page's: a part against an
  /// edge that takes none of its inset draws under the gesture bar or a
  /// cutout. A [SafeArea], a [WaxFootedPane] and [WaxInsetsTaken] (for
  /// a part something else stands between it and the edge) are how.
  final Widget? fill;
  final List<Widget> actions;

  /// Supplied on every screen but a root of the navigation, however it was
  /// reached. A root is where a visitor starts from and has nothing behind
  /// it, so it draws no arrow; which screens are roots is the app's call.
  final VoidCallback? onBack;

  /// The e2e handle for the back control, supplied by the caller.
  final String? backSemanticsId;

  /// Hubs use the large collapsing title; drilled-in screens use the
  /// compact bar so the content starts higher.
  final bool largeTitle;

  /// A bar along the page's foot, below its scroll. It stands against the
  /// bottom edge, so it takes the window's bottom inset itself.
  final Widget? bottom;

  final Widget? floating;

  /// The page's scroll position, for the screens that move it themselves:
  /// an index rail jumping to a letter, a restored offset. Screens that
  /// only scroll by hand leave it null and let the scaffold own one.
  final ScrollController? controller;

  /// Pull to refresh, on the screens whose content is a live read of
  /// somebody else's state. Absent everywhere else: a gesture that
  /// refetches what the invalidation channel already keeps current is a
  /// control with nothing to do, and drawing one implies the page goes
  /// stale.
  final Future<void> Function()? onRefresh;

  final String? semanticsId;

  /// How much of the top of the page the pinned bar occupies.
  ///
  /// For anything laid over the scaffold rather than inside it - an index
  /// screen's alphabet rail is the one so far. Two things go into it and
  /// both have been got wrong: the large title's expanded height, and the
  /// window's top inset, which a `primary` [SliverAppBar] adds to itself
  /// wherever it reaches the page; under the shell's banners it does not,
  /// as they have taken it.
  static double barHeight(BuildContext context, {bool largeTitle = true}) =>
      MediaQuery.paddingOf(context).top +
      (largeTitle ? largeTitleHeight(context) : kToolbarHeight);

  /// A window with no room to spend on chrome. A phone on its side is
  /// 844 wide and 390 tall: wide enough to read as a large size class,
  /// short enough that a deep band and a scaled title take a fifth of
  /// what is left.
  static const double _shortWindow = 600;

  /// How tall the large title's band is, before the window's top inset.
  ///
  /// Narrow *or* short, because a phone pays for this twice: the bar is
  /// `primary`, so it adds the status-bar inset on top of itself, and on
  /// a 640 dp screen a fixed 112 put a fifth of the window above the
  /// first row of content. Both, because the size class is a width and
  /// answers `expanded` for a phone in landscape - the shallowest window
  /// the app is ever drawn in. A shallow band still sits low and large,
  /// which is the app's own chrome, but its title holds one size rather
  /// than scaling as it collapses: there is no longer enough travel for
  /// a scale to read as anything but a wobble.
  static double largeTitleHeight(BuildContext context) =>
      _shallow(context) ? shallowTitleHeight : deepTitleHeight;

  /// The band's two depths, named so a test and a rail can say which one
  /// they expect rather than repeating a number.
  static const double shallowTitleHeight = 72;
  static const double deepTitleHeight = 112;

  /// How much bigger the title draws fully expanded. Material's own
  /// default is 1.5, which needs a band deep enough to fall through.
  static double _titleScale(BuildContext context) =>
      _shallow(context) ? 1 : 1.5;

  static bool _shallow(BuildContext context) =>
      WaxSizeClass.of(context).isCompact ||
      MediaQuery.sizeOf(context).height < _shortWindow;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);

    // The indicator wraps the scroll view rather than riding as a sliver
    // so it hangs below the pinned bar rather than under it, and it is
    // absent entirely without a handler: an always-present
    // RefreshIndicator with a no-op callback still swallows an overscroll
    // and draws an arrow that resolves into nothing.
    Widget scrollable(Widget child) => onRefresh == null
        ? child
        : RefreshIndicator(
            onRefresh: onRefresh!,
            color: colors.accent,
            backgroundColor: colors.surface1,
            child: child,
          );

    return Semantics(
      identifier: semanticsId,
      child: WaxPageMessages.around(
        context,
        Scaffold(
          backgroundColor: colors.canvas,
          // Under the Scaffold's own Material, whose default text style eases
          // into a new theme: a bare Text in the body would draw the old ink.
          body: WaxPlainTextStyle(
            child: Column(
              children: <Widget>[
                Expanded(
                  // The page takes the side insets, and the bottom one
                  // unless its own bar below does; the bar on top takes
                  // the top. What the page holds is handed none of them,
                  // so a list in it pads its ends and indents its rows by
                  // none again. A fill is handed the sides and the bottom
                  // instead, for its parts to take.
                  child: SafeArea(
                    top: false,
                    left: fill == null,
                    right: fill == null,
                    bottom: fill == null && bottom == null,
                    child: Builder(
                      builder: (context) {
                        final page = MediaQuery.of(context);
                        // A fill leaves its bar the side insets: the toolbar
                        // takes them itself, the large title is kept inside
                        // them here.
                        final rtl =
                            Directionality.of(context) == TextDirection.rtl;
                        final startInset = rtl
                            ? page.padding.right
                            : page.padding.left;
                        final endInset = rtl
                            ? page.padding.left
                            : page.padding.right;
                        return MediaQuery(
                          data: page.removePadding(
                            removeTop: true,
                            removeBottom: fill == null || bottom != null,
                          ),
                          child: scrollable(
                            CustomScrollView(
                              controller: controller,
                              // A pull needs somewhere to pull from: a page
                              // shorter than its viewport does not scroll,
                              // and a scroll view that cannot scroll never
                              // reports the overscroll the indicator arms
                              // on. An empty home is exactly that page.
                              physics: onRefresh == null
                                  ? null
                                  : const AlwaysScrollableScrollPhysics(),
                              slivers: <Widget>[
                                MediaQuery(
                                  data: page,
                                  child: SliverAppBar(
                                    pinned: true,
                                    expandedHeight: largeTitle
                                        ? largeTitleHeight(context)
                                        : null,
                                    backgroundColor: colors.canvas,
                                    surfaceTintColor: Colors.transparent,
                                    automaticallyImplyLeading: false,
                                    leading: onBack == null
                                        ? null
                                        : WaxIconButton(
                                            glyph: WaxIcons.back,
                                            label: context.waxL10n.scaffoldBack,
                                            onPressed: onBack,
                                            semanticsId: backSemanticsId,
                                          ),
                                    titleSpacing: onBack == null
                                        ? sizeClass.gutter.horizontal / 2
                                        : 0,
                                    title: largeTitle
                                        ? null
                                        : Text(
                                            title,
                                            style: WaxType.titleScreen.copyWith(
                                              color: colors.textPrimary,
                                            ),
                                          ),
                                    flexibleSpace: largeTitle
                                        ? FlexibleSpaceBar(
                                            expandedTitleScale: _titleScale(
                                              context,
                                            ),
                                            titlePadding:
                                                EdgeInsetsDirectional.only(
                                                  start:
                                                      (onBack == null
                                                          ? sizeClass
                                                                    .gutter
                                                                    .horizontal /
                                                                2
                                                          : WaxSpace.s48) +
                                                      startInset,
                                                  end: endInset,
                                                  bottom: WaxSpace.s12,
                                                ),
                                            title: Text(
                                              title,
                                              style:
                                                  (sizeClass.hasSidebar
                                                          ? WaxType
                                                                .titleScreenDesktop
                                                          : WaxType.titleScreen)
                                                      .copyWith(
                                                        color:
                                                            colors.textPrimary,
                                                      ),
                                            ),
                                          )
                                        : null,
                                    actions: <Widget>[
                                      ...actions,
                                      SizedBox(
                                        width: sizeClass.gutter.horizontal / 2,
                                      ),
                                    ],
                                  ),
                                ),
                                if (body != null)
                                  SliverToBoxAdapter(child: body),
                                ...?slivers,
                                if (fill case final fill?)
                                  SliverFillRemaining(
                                    hasScrollBody: true,
                                    child: fill,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                ?bottom,
              ],
            ),
          ),
          floatingActionButton: switch (floating) {
            null => null,
            // Keyed after the button, so the Scaffold still swaps two
            // buttons as two; a key of its own, as the button's may be
            // global.
            final button => KeyedSubtree(
              key: switch (button.key) {
                null => null,
                final key => ValueKey<Key>(key),
              },
              child: WaxPageMessages.clearing(
                context,
                WaxPlainTextStyle(child: button),
              ),
            ),
          },
        ),
      ),
    );
  }
}

/// A bar along the foot of a page or a pane: a save bar, a decision bar.
///
/// Its surface spans the box it is given and its contents keep inside the
/// window's insets it is handed, as the deck bar's and the tabs' do. A
/// [WaxFootedPane] places it against the foot it stands on.
class WaxFootBar extends StatelessWidget {
  const WaxFootBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(
          top: BorderSide(color: colors.hairline, width: layout.hairlineWidth),
        ),
      ),
      // Across the whole foot, whatever its contents measure.
      child: SizedBox(
        width: double.infinity,
        child: SafeArea(top: false, child: child),
      ),
    );
  }
}

/// A page or a pane whose foot is a bar, in a [WaxScaffold.fill] or a
/// sheet: [foot] stands against the bottom and the sides it spans and is
/// handed their insets, to take under its surface; [body] above it takes
/// the side insets, and the bottom one when there is no [foot].
class WaxFootedPane extends StatelessWidget {
  const WaxFootedPane({required this.body, this.foot, super.key});

  final Widget body;

  /// Null while there is no bar to draw: a load, a failure.
  final Widget? foot;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Expanded(
        child: WaxInsetsTaken(
          bottom: foot != null,
          child: SafeArea(top: false, child: body),
        ),
      ),
      ?foot,
    ],
  );
}

/// [child] told the window's insets on the given edges are spent, because
/// something between it and that edge has taken them: the pane beside a
/// list at its start, a list beside a pane at its end, what stands above a
/// bar at its bottom.
class WaxInsetsTaken extends StatelessWidget {
  const WaxInsetsTaken({
    this.start = false,
    this.end = false,
    this.bottom = false,
    required this.child,
    super.key,
  });

  final bool start;
  final bool end;
  final bool bottom;
  final Widget child;

  // Off the view padding too, as the shell frame's are: the engine leaves
  // the part of an inset a keyboard covers out of the padding alone.
  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final left = rtl ? end : start;
    final right = rtl ? start : end;
    return MediaQuery(
      data: MediaQuery.of(context)
          .removePadding(
            removeLeft: left,
            removeRight: right,
            removeBottom: bottom,
          )
          .removeViewPadding(
            removeLeft: left,
            removeRight: right,
            removeBottom: bottom,
          ),
      child: child,
    );
  }
}
