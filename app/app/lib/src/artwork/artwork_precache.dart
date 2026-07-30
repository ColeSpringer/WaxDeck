import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artwork_providers.dart';
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
class ArtworkPrecacher {
  ArtworkPrecacher(this.store);

  final ArtworkStore store;

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
  void warmAhead({required List<String?> urls, required int px}) {
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

/// The precacher for one scrolling surface, alive as long as the screen
/// watching it is: a warm run in flight when a screen leaves has nothing
/// left to warm for.
final artworkPrecacherProvider = Provider.autoDispose<ArtworkPrecacher>((ref) {
  final precacher = ArtworkPrecacher(ref.watch(artworkStoreProvider));
  ref.onDispose(precacher.dispose);
  return precacher;
});
