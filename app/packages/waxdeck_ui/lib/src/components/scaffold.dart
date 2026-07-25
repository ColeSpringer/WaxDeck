import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
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

  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);

    return Semantics(
      identifier: semanticsId,
      child: Scaffold(
        backgroundColor: colors.canvas,
        body: Column(
          children: <Widget>[
            Expanded(
              child: CustomScrollView(
                slivers: <Widget>[
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: largeTitle ? 112 : null,
                    backgroundColor: colors.canvas,
                    surfaceTintColor: Colors.transparent,
                    automaticallyImplyLeading: false,
                    leading: onBack == null
                        ? null
                        : WaxIconButton(
                            glyph: WaxIcons.back,
                            label: 'Back',
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
                            titlePadding: EdgeInsets.only(
                              left: onBack == null
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
            ?bottom,
          ],
        ),
        floatingActionButton: floating,
      ),
    );
  }
}
