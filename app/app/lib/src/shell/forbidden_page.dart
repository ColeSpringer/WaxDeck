import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'routes.dart';

/// What a shareable location draws for an account that may not have it.
///
/// A refusal in `build` rather than a redirect in the router, which is
/// the decision these locations share: the web build puts a location in
/// the URL, so every one of them is somebody's pasted link, and a
/// redirect answers that link by landing them somewhere else without a
/// word - which reads as a broken link rather than as a refusal. This
/// says what happened and offers the way back, and the location keeps
/// its meaning for the account that shared it.
///
/// One page rather than one per area: the album editor wrote the first
/// and the admin console the second, and they had already drifted on
/// whether the refusal carried a handle at all.
class ForbiddenPage extends StatelessWidget {
  const ForbiddenPage({
    required this.pageTitle,
    required this.heading,
    required this.glyph,
    this.message,
    this.fallback = WaxRoute.home,
    this.semanticsId,
    super.key,
  });

  /// What the bar says: the area, not the refusal. The same page answers
  /// every location in it.
  final String pageTitle;

  /// What the refusal says, and why when the heading cannot.
  final String heading;
  final String? message;

  final WaxGlyph glyph;

  /// Where back goes when nothing was pushed - which is the case a
  /// pasted link makes.
  final String fallback;

  final String? semanticsId;

  @override
  Widget build(BuildContext context) => WaxScaffold(
    title: pageTitle,
    largeTitle: false,
    semanticsId: semanticsId,
    onBack: () => context.leave(fallback: fallback),
    slivers: <Widget>[
      SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(title: heading, message: message, glyph: glyph),
      ),
    ],
  );
}

/// What a location [ForbiddenPage] guards draws while the session that
/// decides it is still being read: the page's frame and a ghost, so an
/// account that may have it never sees the refusal first.
class SessionPendingPage extends StatelessWidget {
  const SessionPendingPage({
    required this.pageTitle,
    this.fallback = WaxRoute.home,
    super.key,
  });

  /// The same bar the refusal and the screen draw, so nothing above the
  /// content moves when the answer lands.
  final String pageTitle;

  final String fallback;

  @override
  Widget build(BuildContext context) => WaxScaffold(
    title: pageTitle,
    largeTitle: false,
    onBack: () => context.leave(fallback: fallback),
    slivers: const <Widget>[
      SliverFillRemaining(
        hasScrollBody: false,
        child: SkeletonShapes(shape: SkeletonShape.list),
      ),
    ],
  );
}
