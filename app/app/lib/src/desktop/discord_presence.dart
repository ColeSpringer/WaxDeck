/// "Listening to WaxDeck" on a desktop where the Discord client is
/// running.
///
/// The port and its view data. The transport is a small pure-Dart IPC
/// client (`discord_ipc_io.dart`) rather than a plugin: the endpoint is
/// a Unix socket or a named pipe, the protocol is a handshake and one
/// command as JSON frames, and every published binding for it wraps a
/// native library or a Rust bridge to do the same thing.
library;

/// What Discord shows while WaxDeck plays.
class DiscordActivity {
  const DiscordActivity({
    required this.title,
    this.artist,
    this.album,
    this.start,
    this.end,
    this.largeImageUrl,
  });

  /// The line Discord calls `details`. What is playing.
  final String title;

  /// The line under it. Who it is by.
  final String? artist;

  /// The hover text on the cover.
  final String? album;

  /// When this item started and when it will finish, which is what
  /// Discord draws its progress bar from. Absent for a station, which
  /// has neither.
  final DateTime? start;
  final DateTime? end;

  /// The album's cover as a public URL, or null for [kDiscordCoverAsset].
  final String? largeImageUrl;

  DiscordActivity withCover(String? url) => DiscordActivity(
    title: title,
    artist: artist,
    album: album,
    start: start,
    end: end,
    largeImageUrl: url,
  );
}

/// Publishing presence to a Discord client on this machine.
abstract interface class DiscordPresencePort {
  /// Connects to the local Discord client as [applicationId], or answers
  /// false where there is none to connect to - no Discord running, not a
  /// desktop, or an id the client rejected.
  Future<bool> connect(String applicationId);

  /// Shows [activity], or clears the status when null.
  Future<void> publish(DiscordActivity? activity);

  Future<void> close();

  /// Whether an image URL is still sent; false once Discord refused one.
  bool get takesImageUrls;

  /// Called when Discord refused an image URL: the activity it came with
  /// is worth sending again, which is the caller's to pace.
  set onImageRefused(void Function()? callback);
}

/// The port where presence cannot be published: web, and both mobiles.
class NoDiscordPresence implements DiscordPresencePort {
  const NoDiscordPresence();

  @override
  bool get takesImageUrls => false;

  @override
  set onImageRefused(void Function()? callback) {}

  @override
  Future<bool> connect(String applicationId) async => false;

  @override
  Future<void> publish(DiscordActivity? activity) async {}

  @override
  Future<void> close() async {}
}

/// WaxDeck's own registered Discord application.
///
/// A public snowflake, not a credential: it rides in the presence
/// payload of everyone who turns this on, and identifying the
/// application is the whole of what it does. The name registered against
/// it is what Discord prints after "Listening to", and the images
/// uploaded against it are what [kDiscordCoverAsset] names.
///
/// The setting beside this overrides it, for somebody who would rather
/// publish as an application of their own. Empty there means this.
const String kWaxDeckDiscordApplicationId = '1534302390650405078';

/// Which application presence publishes as, given what the setting says.
///
/// The setting is an override and empty is the ordinary case, so this is
/// the one place that decides - a switch turned on with nothing else
/// touched has to publish, and reading the field as "off" would make the
/// feature look broken to everybody who never opens the second control.
String discordApplicationId(String override) {
  final chosen = override.trim();
  return chosen.isEmpty ? kWaxDeckDiscordApplicationId : chosen;
}

/// The image Discord draws when an album has no public cover: a key into
/// the assets uploaded beside the application id. Library art cannot be
/// used, since Discord fetches images through its own proxy.
const String kDiscordCoverAsset = 'waxdeck';

/// How often presence may be republished.
///
/// Discord's own documented ceiling is about one activity update every
/// fifteen seconds; past it updates are dropped rather than queued, so
/// the one that matters - the track that just started - would be the one
/// lost. The binder coalesces to this and always sends the newest state.
const Duration kDiscordUpdateInterval = Duration(seconds: 15);
