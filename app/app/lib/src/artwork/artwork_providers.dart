import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../providers.dart';
import '../sync/sync_providers.dart';
import 'artwork_store.dart';
import 'artwork_store_io.dart'
    if (dart.library.js_interop) 'artwork_store_stub.dart';

/// The artwork slots an item holds at its own level, and where the
/// cover it resolves came from.
///
/// Shared rather than private to the artwork manager: the full-screen
/// player draws the same mark under the same cover, and the read behind
/// it is a row lookup on the server rather than an image decode, so two
/// surfaces watching one family is one request and not two.
final itemArtRolesProvider = FutureProvider.autoDispose
    .family<ArtRoles, String>(
      (ref, pid) => ref.watch(repositoryProvider).getItemArtRoles(pid),
    );

/// Where offline artwork is recorded. Native only: the web build has no
/// mirror and no offline mode to pin for.
final artworkPinStoreProvider = Provider<ArtworkPinStore>((ref) {
  final db = ref.watch(mirrorDatabaseProvider);
  return db == null ? const NoArtworkPinStore() : DriftArtworkPinStore(db);
});

/// The one artwork store. Screens ask it for a [WaxArtwork] and hand
/// that to the design system, which decides what size to ask for.
final artworkStoreProvider = Provider<ArtworkStore>((ref) {
  final store = createArtworkStore(
    baseUrl: waxDeckBaseUrl,
    pins: ref.watch(artworkPinStoreProvider),
    // Read per request rather than captured: the token rotates, and a
    // store holding the one it was built with would start answering 401
    // in the middle of a session.
    token: () => ref.read(repositoryProvider).authToken,
  );
  ref.onDispose(store.dispose);
  return store;
});

/// Bounds Flutter's decoded-image cache to what this app actually draws.
///
/// The defaults (100 MB, 1000 entries) were sized for apps that show a
/// handful of images. WaxDeck shows a grid of them, and the arithmetic
/// runs the other way: a cell painted at 336 pixels holds about 450 KB
/// decoded, a phone screenful is a dozen cells, a wide desktop window is
/// forty. Keeping about four screenfuls plus a player hero is what makes
/// a scroll back up repaint instead of refetch, and it is a different
/// number on a phone than on a desktop.
void applyArtworkImageCacheBounds({bool? web, TargetPlatform? platform}) {
  final (int megabytes, int entries) = artworkImageCacheBounds(
    web: web ?? kIsWeb,
    platform: platform ?? defaultTargetPlatform,
  );
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSizeBytes = megabytes * 1024 * 1024;
  cache.maximumSize = entries;
}

/// The bounds themselves, so they can be read without a binding.
(int megabytes, int entries) artworkImageCacheBounds({
  required bool web,
  required TargetPlatform platform,
}) {
  // The web build is desktop-shaped, but it pays for its pixels out of a
  // wasm heap it shares with everything else it is running.
  if (web) return (96, 600);
  return switch (platform) {
    // A phone: a dozen cells a screen, but at pixel ratio 3, so each one
    // costs more than a desktop's does.
    TargetPlatform.android => (64, 400),
    // Desktop windows are wide, and a library on one gets scrolled a
    // long way before it gets scrolled back.
    _ => (160, 800),
  };
}
