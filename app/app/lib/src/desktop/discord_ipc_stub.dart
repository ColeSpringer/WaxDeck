/// The web build's Discord presence: none.
///
/// The endpoint is a socket on the machine Discord is running on, which
/// a browser tab has no way to reach and no business reaching. Keeping
/// the real client out of this compilation unit keeps `dart:io` out of
/// the wasm build.
library;

import 'discord_presence.dart';

DiscordPresencePort createDiscordPresencePort() => const NoDiscordPresence();

/// No cover lookups either: there is no presence to show one in.
Future<String?> coverArtFront(String mbid, {Uri? archive}) async => null;

Future<String?> Function(String mbid) coverArtLookup() => coverArtFront;
