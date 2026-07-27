import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'artwork_providers.dart';

/// A cover that fills its box, asks the store for the size it turned out
/// to be, and falls back to [placeholder].
///
/// For the screens that predate the design system. Anything rebuilt on
/// `waxdeck_ui` draws through [ArtworkImage] instead, which knows its own
/// extent and does not need to measure; this measures because the
/// screens it serves put artwork in an `Expanded` or a `ClipRRect` and
/// let the layout decide. Both end up asking the same store for the same
/// rung, which is the point: no screen fetches full-size artwork for a
/// 48-pixel row, and no native request goes out without a credential.
class ArtworkBox extends ConsumerWidget {
  const ArtworkBox({
    required this.artUrl,
    required this.placeholder,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String? artUrl;

  /// Drawn when there is no artwork and when the fetch fails: a missing
  /// cover is a state to answer, not an error to report.
  final Widget placeholder;

  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(artworkStoreProvider).source(artUrl);
    if (source == null) return placeholder;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        final extent = math.max(
          constraints.hasBoundedWidth ? constraints.maxWidth : 0.0,
          constraints.hasBoundedHeight ? constraints.maxHeight : 0.0,
        );
        // An unbounded box (a row that sizes to its content) has no
        // extent to measure; the smallest rung is the honest guess, and
        // every caller here is bounded anyway.
        final px = extent <= 0 ? 64 : (extent * ratio).ceil();
        final image = source(px);
        if (image == null) return placeholder;
        return Image(
          image: image,
          fit: fit,
          errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
              placeholder,
        );
      },
    );
  }
}
