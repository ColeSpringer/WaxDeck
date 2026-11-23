/// The web build's artwork store.
///
/// Little to implement: the browser attaches the session cookie, its
/// HTTP cache holds the bytes (the art endpoint sends a day of freshness
/// and a week of stale-while-revalidate for exactly this), and there is
/// no offline mode to pin for. What is left is asking for the right
/// size, which [NetworkArtworkStore] does, and remembering across a
/// reload which covers that cache holds an old copy of, which is what
/// `localStorage` is handed over for.
library;

import 'package:waxdeck_data/waxdeck_data.dart';

import '../settings/client_settings/client_settings_web.dart';
import 'artwork_store.dart';

ArtworkStore createArtworkStore({
  required String baseUrl,
  required ArtworkPinStore pins,
  String? Function()? token,
  TransferGate pinGate = const OpenGate(),
  required bool Function() reachable,
}) => NetworkArtworkStore(
  baseUrl: baseUrl,
  token: token,
  replaced: ReplacedCovers(storage: const BrowserLocalStorage()),
);
