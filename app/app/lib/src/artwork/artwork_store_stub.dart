/// The web build's artwork store.
///
/// Nothing to implement: the browser attaches the session cookie, its
/// HTTP cache holds the bytes (the art endpoint sends a day of freshness
/// and a week of stale-while-revalidate for exactly this), and there is
/// no offline mode to pin for. What is left is asking for the right
/// size, which [NetworkArtworkStore] does.
library;

import 'package:waxdeck_data/waxdeck_data.dart';

import 'artwork_store.dart';

ArtworkStore createArtworkStore({
  required String baseUrl,
  required ArtworkPinStore pins,
  String? Function()? token,
}) => NetworkArtworkStore(baseUrl: baseUrl, token: token);
