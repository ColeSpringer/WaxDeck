import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../l10n/wax_l10n.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// The page scaffold every screen sits in.
///
/// It owns the large-title app bar (which collapses on scroll), the
/// gutters for the current size class, and the landmark structure
/// assistive technology navigates by: a header, one main region, and a
/// deck bar the shell supplies.
class WaxScaffold extends StatelessWidget {
  const WaxScaffold({
    required this.title,
    this.body,
    this.slivers,
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
         (body == null) != (slivers == null),
         'give WaxScaffold a body or slivers, not both',
       );

  final String title;

  /// A single box child, for screens that are a column of content.
  final Widget? body;

  /// Slivers, for screens that page: a grid or list belongs here, where
  /// it can build lazily. A list inside [body] gets unbounded height and
  /// has to shrink-wrap, which builds every row on the first frame and
  /// is the opposite of what the artwork grids need.
  final List<Widget>? slivers;
  final List<Widget> actions;

  /// Supplied on pushed screens. Canonical destinations never show one:
  /// they are reached from navigation, not from a stack.
  final VoidCallback? onBack;

  /// The e2e handle for the back control, supplied by the caller.
  final String? backSemanticsId;

  /// Hubs use the large collapsing title; drilled-in screens use the
  /// compact bar so the content starts higher.
  final bool largeTitle;

  /// The deck bar slot, filled by the shell.
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
  /// and which nothing here consumes (the shell puts its `SafeArea`
  /// around its chrome, not around the content pane).
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
      child: Scaffold(
        backgroundColor: colors.canvas,
        body: Column(
          children: <Widget>[
            Expanded(
              child: scrollable(
                CustomScrollView(
                  controller: controller,
                  // A pull needs somewhere to pull from: a page shorter
                  // than its viewport does not scroll, and a scroll view
                  // that cannot scroll never reports the overscroll the
                  // indicator arms on. An empty home is exactly that page.
                  physics: onRefresh == null
                      ? null
                      : const AlwaysScrollableScrollPhysics(),
                  slivers: <Widget>[
                    SliverAppBar(
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
                              expandedTitleScale: _titleScale(context),
                              titlePadding: EdgeInsetsDirectional.only(
                                start: onBack == null
                                    ? sizeClass.gutter.horizontal / 2
                                    : WaxSpace.s48,
                                bottom: WaxSpace.s12,
                              ),
                              title: Text(
                                title,
                                style:
                                    (sizeClass.hasSidebar
                                            ? WaxType.titleScreenDesktop
                                            : WaxType.titleScreen)
                                        .copyWith(color: colors.textPrimary),
                              ),
                            )
                          : null,
                      actions: <Widget>[
                        ...actions,
                        SizedBox(width: sizeClass.gutter.horizontal / 2),
                      ],
                    ),
                    if (body != null) SliverToBoxAdapter(child: body),
                    ...?slivers,
                  ],
                ),
              ),
            ),
            ?bottom,
          ],
        ),
        floatingActionButton: floating,
      ),
    );
  }
}
