import 'database.dart';

/// Where a preference that belongs to this device - not to the account -
/// lives between launches.
///
/// The scope is the whole point. Locale and the shared-stats opt-out are
/// the account's and ride the server's preference document, so they
/// follow a listener to a new phone. A collapsed sidebar, a skip
/// interval sized for these headphones, a wifi-only switch about this
/// connection, the theme this screen draws: those describe the device in
/// front of the listener and would be wrong on the next one. Nothing
/// here ever syncs, and a sign-out leaves it standing (see
/// [ClientSettingKeys]).
///
/// Values are opaque strings. A caller that wants a bool or a list
/// encodes one, because the store has no way to be right about which is
/// which and a typed column per preference would mean a schema
/// migration per preference.
///
/// Implementations never throw. Persistence here is a convenience: the
/// worst failure is a preference that does not survive the launch, which
/// is not worth taking a screen down for.
abstract class ClientSettingsStore {
  /// The stored value for [key], or null when nothing was written.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing whatever was there.
  Future<void> write(String key, String value);

  /// Forgets [key], so the next read answers null and the caller falls
  /// back to its default.
  Future<void> remove(String key);
}

/// The keys in use, so the two implementations and their readers agree
/// on spelling and a grep finds every preference at once.
///
/// Namespaced because the web store shares `localStorage` with whatever
/// else the origin holds.
abstract final class ClientSettingKeys {
  /// Whether the desktop sidebar is collapsed to an icon rail.
  static const sidebarCollapsed = 'waxdeck.shell.sidebarCollapsed';

  /// How wide the review queue's list is beside the entry being read,
  /// in whole pixels; zero means the layout's own answer. Per device
  /// like the rail above it: where a seam sits is a choice about this
  /// window, and carrying it to a laptop half the width would only be
  /// re-clamped there.
  static const reviewListWidth = 'waxdeck.review.listWidth';

  /// The recent search queries, newest first, as a JSON string list.
  static const recentSearches = 'waxdeck.search.recent';

  /// When the most recently declined resume offer stopped, as an ISO
  /// instant. A watermark rather than an id: the history is newest
  /// first, so declining an offer declines everything at or before it -
  /// storing one id instead would offer the next-oldest session at the
  /// following launch, and the one after that at the one after, which is
  /// the "comes back with no explanation" the offer is supposed to end.
  /// A session that stops later is newer than the decision and is
  /// offered.
  ///
  /// Per device rather than per account on purpose: declining on the
  /// phone says nothing about what the desktop should offer, and the
  /// server's history is the same list for both.
  static const resumeDeclinedThrough = 'waxdeck.queue.resumeDeclinedThrough';

  /// How far the first-run tour got on this device, by stage name.
  ///
  /// The tour's entry condition - an administrator whose server has no
  /// libraries - stops being true at step one, so everything after it
  /// is progress rather than a state anything can re-derive. Held
  /// across launches because the console's own surface is the web,
  /// where a reload is one keystroke: without it, adding a library and
  /// refreshing ends the tour two steps early and for good, and
  /// skipping it on a server that still has no libraries un-skips it.
  ///
  /// Per device rather than per account, like the resume decision
  /// above: a tour is something a person walked through at a keyboard,
  /// not a property of the account. On the web that also scopes it to
  /// the server for free, storage being per origin; a native client
  /// re-pointed at a second, brand-new server would carry this one's
  /// answer over, which is a trade taken knowingly for a guided flow
  /// that is skippable in one tap.
  static const firstRunProgress = 'waxdeck.admin.firstRunProgress';

  /// How far the spoken-word transports jump, in seconds. Two keys and
  /// not one pair: the two are set independently and a listener who
  /// changes only the forward jump should not have the other rewritten
  /// beside it.
  static const skipBackSeconds = 'waxdeck.playback.skipBackSeconds';
  static const skipForwardSeconds = 'waxdeck.playback.skipForwardSeconds';

  /// The speed a show or a book plays at when it has none of its own.
  /// Per device because it is about the ears in front of it; the
  /// per-show and per-book values it backs are the account's and live on
  /// their own endpoints.
  static const podcastSpeed = 'waxdeck.playback.podcastSpeed';
  static const bookSpeed = 'waxdeck.playback.bookSpeed';

  /// Whether the one-line explanation behind each spoken-word effect
  /// has been shown on this device. Not a preference anybody sets: a
  /// note that a thing has been said once, so it is not said again.
  static const trimSilenceExplained = 'waxdeck.playback.trimExplained';
  static const voiceBoostExplained = 'waxdeck.playback.boostExplained';

  /// What the spoken-word effects do when a show or book has no stored
  /// choice of its own. Per device like the speed default beside them:
  /// they are about the ears and the speaker in front of this machine.
  static const trimSilenceDefault = 'waxdeck.playback.trimSilenceDefault';
  static const voiceBoostDefault = 'waxdeck.playback.voiceBoostDefault';

  /// How far a spoken-word resume steps back for context after a long
  /// enough pause. Per device because it is about how this listener
  /// listens on this machine: a phone picked up on a commute and a
  /// desktop left running overnight lose the thread differently.
  static const smartRewind = 'waxdeck.playback.smartRewind';

  /// Whether gapless preloading waits for an unmetered connection.
  static const preloadOnWifiOnly = 'waxdeck.playback.preloadOnWifiOnly';

  /// The streaming quality cap, split by connection: capping over the
  /// home Wi-Fi and capping on a phone plan are different decisions.
  /// Platforms that cannot tell a metered connection apart (desktop,
  /// web) store and resolve the Wi-Fi value alone.
  static const streamQualityWifi = 'waxdeck.playback.streamQualityWifi';
  static const streamQualityMetered = 'waxdeck.playback.streamQualityMetered';

  /// Whether a music queue that has run out keeps going with a mix
  /// seeded on what it ended on. Per device, like the rest of playback.
  static const keepPlayingSimilar = 'waxdeck.playback.keepPlayingSimilar';

  /// Whether downloads wait for an unmetered connection.
  static const downloadsOnWifiOnly = 'waxdeck.downloads.wifiOnly';

  /// Whether a finished episode's download is reclaimed on its own, and
  /// how long after. Per device because the files are.
  static const autoRemoveFinished = 'waxdeck.downloads.autoRemoveFinished';
  static const autoRemoveFinishedAfterHours =
      'waxdeck.downloads.autoRemoveFinishedAfterHours';

  /// Whether codec, bitrate, and provenance chips are drawn.
  static const technicalDetails = 'waxdeck.library.technicalDetails';

  /// Which theme this device draws, by [ThemePref] name; unset follows
  /// the system.
  ///
  /// Per device because a display theme describes the screen in front of
  /// the listener - the phone carried outdoors and the desktop in a dark
  /// room are not one choice. It was the account's, which meant a
  /// `light` picked once on the web followed the phone everywhere and
  /// the settings row said so.
  static const theme = 'waxdeck.appearance.theme';

  /// Whether the account's old theme has already been considered for
  /// [theme]. Written the first time the question is asked, whatever the
  /// answer was.
  ///
  /// A mark of its own rather than the presence of [theme]: a device that
  /// looked and found nothing to take stores no theme, and with nothing
  /// else written would look again at the next launch. That is the
  /// account driving the device, which is what moving the setting was
  /// for.
  static const themeAdopted = 'waxdeck.appearance.themeAdopted';

  /// How tightly rows pack, and how large artwork tiles are drawn.
  static const density = 'waxdeck.appearance.density';
  static const gridSize = 'waxdeck.appearance.gridSize';

  /// Whether player and header backdrops carry the artwork glow. Per
  /// device because it is about the panel: the same wash that reads as
  /// warmth on a good screen reads as a smear on a cheap one, and the
  /// listener with both is not choosing once for the pair.
  static const artworkGlow = 'waxdeck.appearance.artworkGlow';

  /// Whether a card's caption lines are always drawn or wait for a
  /// hover. Per device because hovering is: the choice means nothing on
  /// the phone signed in to the same account.
  static const cardCaptions = 'waxdeck.appearance.cardCaptions';

  /// An in-app override for the platform's reduce-motion setting. Only
  /// ever additive: it can turn animation off where the platform has it
  /// on, and never the other way, because the platform's answer is an
  /// accessibility need rather than a preference to overrule.
  static const reduceMotion = 'waxdeck.a11y.reduceMotion';

  /// Whether a desktop left alone with music playing opens the
  /// visualizer on its own. Per device because it is about the screen in
  /// front of the listener: the machine on a shelf across the room is
  /// the one this is for, and the laptop on their knees is not.
  static const visualizerWhenIdle = 'waxdeck.player.visualizerWhenIdle';

  /// Whether car mode gets a control of its own on the player rather
  /// than living in the overflow. Per device for the same reason: the
  /// phone that rides on a dashboard mount wants it and the desktop
  /// never does.
  static const carModeButton = 'waxdeck.player.carModeButton';

  /// Whether this desktop publishes "Listening to WaxDeck" to Discord,
  /// and which registered application it publishes as.
  ///
  /// Per device by nature rather than by policy: presence is set through
  /// the Discord client's own local socket, so it is a fact about the
  /// machine both programs are running on. The id is a public snowflake
  /// from the Discord developer portal, not a credential.
  static const discordPresence = 'waxdeck.integrations.discordPresence';
  static const discordApplicationId = 'waxdeck.integrations.discordAppId';
}

/// Per-device settings in the local mirror database (native builds).
///
/// Every call swallows database failures, because the port promises the
/// caller it will. A closed database, a locked file, a full disk: the
/// visible cost is a preference that does not survive the launch, and a
/// store that threw instead would take down a shell reading it during
/// startup. This is the same trade the queue store's caller makes for
/// the queue and the credential store makes for the token; the
/// difference is that here it lives in the store, so both
/// implementations of this port behave alike rather than only one of
/// them honoring the contract.
class DriftClientSettingsStore implements ClientSettingsStore {
  DriftClientSettingsStore(this.db);

  final MirrorDatabase db;

  @override
  Future<String?> read(String key) async {
    try {
      final row = await (db.select(
        db.clientSettings,
      )..where((t) => t.key.equals(key))).getSingleOrNull();
      return row?.value;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await db
          .into(db.clientSettings)
          .insertOnConflictUpdate(
            ClientSettingsCompanion.insert(key: key, value: value),
          );
    } catch (_) {
      // The preference holds in memory for this session either way; the
      // notifier that set it does not read back through here.
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await (db.delete(
        db.clientSettings,
      )..where((t) => t.key.equals(key))).go();
    } catch (_) {
      // A key that will not delete is a stale preference at the next
      // launch, not a reason to throw at this one.
    }
  }
}

/// Settings that live only as long as the process.
///
/// Used by tests, and by the web store when the browser will not hold a
/// value - a preference set in a private window is then good for the
/// session rather than being an error the caller has to handle.
class MemoryClientSettingsStore implements ClientSettingsStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
