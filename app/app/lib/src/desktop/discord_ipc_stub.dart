/// The web build's Discord presence: none.
///
/// The endpoint is a socket on the machine Discord is running on, which
/// a browser tab has no way to reach and no business reaching. Keeping
/// the real client out of this compilation unit keeps `dart:io` out of
/// the wasm build.
library;

import 'discord_presence.dart';

DiscordPresencePort createDiscordPresencePort() => const NoDiscordPresence();
