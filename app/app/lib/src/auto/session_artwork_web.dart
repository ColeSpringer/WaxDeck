/// The web build's cover for the browser's MediaSession.
///
/// Nothing to fetch and nothing to write: the page and the art endpoint
/// share an origin, the credential is a cookie the browser attaches for
/// itself, and MediaSession takes a URL. Asking for a rung is the only
/// decision left.
library;

import '../artwork/artwork_store.dart';
import 'session_artwork.dart';

/// The cover URL for the lock screen and the browser's own transport, or
/// null when the item has no artwork.
Future<Uri?> mediaSessionArtUri(ArtworkStore store, String? artUrl) async {
  if (artUrl == null || artUrl.isEmpty) return null;
  final sized = isWaxDeckUrl(artUrl, store.baseUrl) && !isUnsizedArtUrl(artUrl)
      ? sizedArtUrl(artUrl, kMediaSessionArtRung)
      : artUrl;
  return Uri.tryParse(sized);
}

/// Forgets covers written for items that are no longer playing. Nothing
/// is written on web, so there is nothing to forget.
Future<void> forgetMediaSessionArt() async {}
