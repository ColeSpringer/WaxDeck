import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../home/home_shelves.dart';
import '../queue/queue_recheck.dart';
import 'catalog_reads.dart';
import 'refresh_pacing.dart';

/// The one path by which a catalog write made on this device says it
/// landed, so every read of the catalog a screen holds open follows it:
/// the list under the editor, the index under that, the shelf on
/// another tab.
///
/// It holds the container, not a `ref`: the answer to a write can land
/// after the screen that asked has gone, so a write site reads
/// [catalogWritesProvider] before its await and calls [landed] on what
/// it read.
class CatalogWrites {
  CatalogWrites(this._container);

  final ProviderContainer _container;

  void Function()? _owePass;

  /// The session's binder leaves its paced catalog pass here while it is
  /// mounted: [owe] asks it for the one more pass a write is owed.
  void bindPass(void Function() owe) => _owePass = owe;

  /// Takes [owe] back, unless a later binder has bound its own since.
  void unbindPass(void Function() owe) {
    if (identical(_owePass, owe)) _owePass = null;
  }

  /// A catalog write the server has answered. Every registered read is
  /// swept at once, each paged listing through the extent it has loaded,
  /// since the write can be on any row of it; then one more pass is owed
  /// for once the server has caught up, since what it answers this
  /// instant can lag the write (see `PacedRefresh.owe`). With no session
  /// bound the sweep is all there is.
  ///
  /// [artUrls] are covers whose bytes the write replaced under the same
  /// URL. Each is evicted first, so a read the sweep prompts asks for
  /// the new bytes: the store notes a replacement before its first
  /// await, and the files it drops after that are nothing to wait for.
  void landed({Set<String> artUrls = const {}}) {
    if (artUrls.isNotEmpty) {
      final store = _container.read(artworkStoreProvider);
      final palettes = _container.read(paletteCacheProvider);
      for (final url in artUrls) {
        // What it does after noting the replacement (file drops, a
        // re-pin) fails alone: the sweep has already asked again.
        unawaited(
          store.evict(url).catchError((Object error) {
            debugPrint('cover write: the cached cover did not clear: $error');
          }),
        );
        // The colour read off those bytes is as stale as they are.
        palettes.forget(url);
      }
    }
    _container.read(catalogFanOutProvider).sweep(CatalogRefresh.loaded);
    // Home's probe is outside the registry for what a pass of a scan
    // would cost it. A write is one read, and can empty the library or
    // end its emptiness. One on its first build is left to finish, and
    // asked by the pass owed below.
    _container.read(probeFanOutProvider).sweep();
    // Nor are the reads a pass leaves until a run goes quiet, for what
    // each costs on a pass. A write is one read of each.
    _container.read(catalogQuietFanOutProvider).sweep();
    // Nor is what playback holds of the queue's items, looked up once a
    // run goes quiet, which a scan can put off for as long as it runs. A
    // write is one lookup, to name them as they are now, and one more
    // with the pass owed below.
    unawaited(_container.read(queueRecheckProvider).redraw());
    _owePass?.call();
  }
}

/// Home's probe as a fan-out of its own, shared by a write and the
/// session's passes so either applies what the other left deferred.
final probeFanOutProvider = Provider<InvalidationFanOut>((ref) {
  final container = ref.container;
  return InvalidationFanOut(
    container: container,
    firstBuilds: container.observers
        .whereType<FirstBuildObserver>()
        .firstOrNull,
    providers: [libraryHasAnythingProvider],
  );
});

final catalogWritesProvider = Provider<CatalogWrites>(
  (ref) => CatalogWrites(ref.container),
);
