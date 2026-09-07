import 'dart:async';

import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'artwork_store.dart';

/// Fetches the artwork a scroll is about to reach, and only that.
///
/// Warming puts bytes on the device - in the browser's cache, in the
/// native disk cache - without decoding a picture. The decode belongs to
/// whatever ends up painting, at the size it paints; a warm that guessed
/// the size slightly wrong would leave a second decoded copy in memory
/// rather than saving anything. The guess only has to land on the right
/// size rung, and the rungs are far enough apart that a grid's cell
/// width is a good enough guess.
///
/// Warming happens when a scroll stops, never during one: a fling needs
/// its frames more than the next screenful needs its covers, and a
/// hundred fetches started under one is how a scroll janks.
///
/// A scrolling screen owns one and disposes it with itself, rather than
/// watching one from a provider: a warm in flight when the screen leaves
/// has nothing left to warm for, and an auto-disposing provider is
/// released by a scheduler rather than by the widget - which in a widget
/// test is a timer outliving the tree it belonged to.
class ArtworkPrecacher {
  ArtworkPrecacher();

  int _generation = 0;
  bool _disposed = false;

  /// How many warms are in flight at once.
  ///
  /// One at a time would put two dozen round trips end to end, which on
  /// anything but a local server is slower than the scroll it is trying
  /// to get ahead of. A handful, rather than all of them, because the
  /// covers on screen are asking through the same connections and must
  /// never queue behind the ones that are not.
  static const int _inFlight = 3;

  /// Warms [urls] - the covers just past the viewport, which the caller
  /// is the one able to name, since it is the one that knows where its
  /// viewport ends. A second call supersedes the first: the scroll
  /// moved, and where it stopped is a better guess than where it stopped
  /// before.
  ///
  /// The store is handed over per call rather than held: it is rebuilt
  /// when the server address moves, and a warm holding the old one would
  /// fetch from an origin nothing draws from any more.
  void warmAhead({
    required ArtworkStore store,
    required List<String?> urls,
    required int px,
  }) {
    if (_disposed || urls.isEmpty) return;
    final generation = ++_generation;
    unawaited(() async {
      for (var i = 0; i < urls.length; i += _inFlight) {
        if (_disposed || generation != _generation) return;
        final batch = <Future<void>>[];
        for (var j = i; j < i + _inFlight && j < urls.length; j++) {
          final url = urls[j];
          if (url == null || url.isEmpty) continue;
          batch.add(store.warm(url, px));
        }
        try {
          await Future.wait(batch);
        } catch (_) {
          // Nothing is awaiting this loop, so an escaping error would be
          // an unhandled one. A cover that would not warm is a cover
          // that gets fetched when it is drawn.
        }
      }
    }());
  }

  void dispose() => _disposed = true;
}

/// How far past the built rows a warm reaches, in viewports.
///
/// Two, which is about what one flick covers: far enough that a scroll
/// resumed in the same direction lands on warm covers, near enough that
/// a stop halfway down a long list does not fetch a hundred pictures
/// nobody looks at. Provisional until the perf run measures it.
const int _viewportsAhead = 2;

/// Warms the covers of the rows just past the viewport.
///
/// The caller passes what only it knows: how many rows there are and the
/// art URL for each; where the viewport ends comes off [metrics]. The
/// rows on screen are already being fetched by themselves, so the warm
/// starts one past the last of them - estimated, since the slivers above
/// the list count toward the offset and put the estimate a header's
/// worth past the true edge, which the reach below swallows. Read off
/// the metrics each time rather than remembered, because a remembered
/// edge outlives the list it measured: a reload or a re-sorted index
/// starts its rows at zero again.
void warmArtworkAhead({
  required BuildContext context,
  required ArtworkPrecacher precacher,
  required ArtworkStore store,
  required ScrollMetrics metrics,
  required int count,
  required String? Function(int index) urlAt,
}) {
  final pitch = MediaListRow.heightFor(context);
  if (pitch <= 0 || count == 0) return;
  final from =
      ((metrics.pixels + metrics.viewportDimension) / pitch).floor() + 1;
  if (from >= count) return;
  final rows = ((metrics.viewportDimension / pitch).ceil() * _viewportsAhead)
      .clamp(1, count - from);
  // The rung the row will paint at, which is the whole point of naming a
  // size here: a warm at another one puts a second copy on the device
  // and saves the draw nothing.
  final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  precacher.warmAhead(
    store: store,
    urls: <String?>[for (var i = from; i < from + rows; i++) urlAt(i)],
    px: (MediaListRow.defaultArtSize * ratio).ceil(),
  );
}
