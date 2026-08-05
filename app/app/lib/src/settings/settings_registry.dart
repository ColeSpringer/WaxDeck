import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxGlyph, WaxIcons;

import '../auth/auth_controller.dart';
import '../shell/semantics_ids.dart';

/// Whether the signed-in account administers this server.
///
/// One reading of the role, because three surfaces now gate on it (the
/// Server section, the technical-details default, and settings search)
/// and three spellings of `roles.contains` is three chances to check the
/// wrong string.
final isAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(authControllerProvider).value?.user;
  return user?.roles.contains('admin') ?? false;
});

/// The settings sections, in the order the home screen lists them.
///
/// Account is first because it is the one everybody opens, and Server is
/// last because most accounts never see it. The eight in between are the
/// layout blueprint's own, unchanged.
enum SettingsSection {
  account(
    'account',
    'Account',
    'You, your devices, and how you sign in',
    WaxIcons.settings,
  ),
  playback(
    'playback',
    'Playback',
    'Speeds, skips, casting, and what plays next',
    WaxIcons.play,
  ),
  library(
    'library',
    'Library and metadata',
    'What browsing shows you, and what you can see',
    WaxIcons.albums,
  ),
  downloads(
    'downloads',
    'Downloads and storage',
    'What this device keeps offline, and how much room it takes',
    WaxIcons.downloads,
  ),
  devices(
    'devices',
    'Devices and casting',
    'Where else your listening can come out',
    WaxIcons.cast,
  ),
  integrations(
    'integrations',
    'Integrations',
    'Scrobbling, other apps, and notifications',
    WaxIcons.share,
  ),
  appearance(
    'appearance',
    'Appearance',
    'Theme, density, and how large artwork is drawn',
    WaxIcons.star,
  ),
  accessibility(
    'accessibility',
    'Accessibility',
    'Motion, and how the app reads out',
    WaxIcons.headphones,
  ),
  server(
    'server',
    'Server',
    'This instance, for administrators',
    WaxIcons.admin,
  );

  const SettingsSection(this.segment, this.title, this.blurb, this.glyph);

  /// The path segment under `/settings`. A location, so a section is a
  /// link somebody can send - "it is in Settings, Playback" becomes a URL.
  final String segment;

  final String title;

  /// The line under the section's name on the settings home.
  final String blurb;

  final WaxGlyph glyph;

  /// Administrators only. The section is not merely empty for everyone
  /// else: it is absent from the list and from search.
  bool get adminOnly => this == SettingsSection.server;

  static SettingsSection? bySegment(String segment) {
    for (final section in SettingsSection.values) {
      if (section.segment == segment) return section;
    }
    return null;
  }
}

/// One leaf setting, as the search field and the command palette see it.
///
/// The registry exists because a settings surface with nine sections is
/// one nobody can navigate by memory: the field at the top of the
/// settings home is how a listener finds "crossfade" without knowing it
/// lives under Playback. Every control on every section has an entry, and
/// a test holds the two together.
class SettingEntry {
  const SettingEntry({
    required this.id,
    required this.title,
    required this.section,
    this.keywords = const <String>[],
    this.handle,
    this.adminOnly = false,
    this.nativeOnly = false,
    this.desktopOnly = false,
  });

  /// A stable handle, also this setting's e2e identifier suffix. Renaming
  /// one is a contract change the same way a semantics id is.
  final String id;

  /// What the row says. Matched first and matched whole, so typing a
  /// setting's name finds it above anything that merely mentions it.
  final String title;

  final SettingsSection section;

  /// The words somebody would search by that are not in the title.
  /// "Gapless" for the preload switch, "level" and "loudness" for
  /// ReplayGain: the vocabulary other apps use for the same thing, so
  /// arriving from one of them still lands.
  final List<String> keywords;

  /// The semantics identifier of the control that proves this setting is
  /// drawn, where it is not `setting-<id>`.
  ///
  /// Most settings carry the handle the registry names. The exceptions
  /// are controls older than the registry, which e2e specs already steer
  /// by, and the entries that name a group rather than one control - a
  /// list of devices, a set of app passwords. Declared here rather than
  /// left implicit because `settings_registry_test.dart` presses each
  /// one: a registered setting no section draws is a search result that
  /// opens a section it is not in.
  final String? handle;

  /// The identifier a test looks for.
  String get semanticsId => handle ?? SemanticsIds.setting(id);

  final bool adminOnly;

  /// Absent on web, where there is no download manager and no metered
  /// connection worth asking about.
  final bool nativeOnly;

  /// Absent anywhere that is not a desktop: a machine somebody walks
  /// away from with the music still playing. A phone locks its screen
  /// and a browser tab is not a room's stereo, so the one setting this
  /// covers would be a switch with nothing behind it on both.
  final bool desktopOnly;
}

/// Every leaf setting this build ships.
///
/// Kept beside the sections rather than derived from the widgets,
/// because a widget tree cannot be searched before it is built and the
/// settings home has to answer a query without mounting nine screens.
/// `settings_registry_test.dart` is what stops the two drifting: it fails
/// on a registered setting no section draws.
const settingsRegistry = <SettingEntry>[
  // Account
  SettingEntry(
    id: 'display-name',
    title: 'Display name',
    section: SettingsSection.account,
    keywords: <String>['username', 'profile', 'who'],
  ),
  SettingEntry(
    id: 'password',
    title: 'Change password',
    section: SettingsSection.account,
    keywords: <String>['security', 'sign in', 'login'],
  ),
  SettingEntry(
    id: 'devices',
    title: 'Signed-in devices',
    section: SettingsSection.account,
    keywords: <String>['sessions', 'revoke', 'sign out', 'logout'],
  ),
  SettingEntry(
    id: 'app-passwords',
    title: 'App passwords',
    section: SettingsSection.account,
    keywords: <String>['subsonic', 'gpodder', 'token', 'third party'],
  ),
  SettingEntry(
    id: 'timezone',
    handle: SemanticsIds.timezoneEdit,
    title: 'Timezone',
    section: SettingsSection.account,
    keywords: <String>['stats', 'calendar', 'streak'],
  ),
  SettingEntry(
    id: 'shared-stats',
    handle: SemanticsIds.sharedStatsSwitch,
    title: 'Server-wide stats',
    section: SettingsSection.account,
    keywords: <String>['year in review', 'privacy', 'opt out'],
  ),
  SettingEntry(
    id: 'about',
    title: 'About WaxDeck',
    section: SettingsSection.account,
    keywords: <String>['version', 'licenses', 'open source', 'build'],
  ),

  // Playback
  SettingEntry(
    id: 'skip-back',
    title: 'Skip back by',
    section: SettingsSection.playback,
    keywords: <String>['rewind', 'seconds', 'podcast', 'audiobook'],
  ),
  SettingEntry(
    id: 'skip-forward',
    title: 'Skip forward by',
    section: SettingsSection.playback,
    keywords: <String>['seconds', 'podcast', 'audiobook', 'ad'],
  ),
  SettingEntry(
    id: 'podcast-speed',
    title: 'Podcast speed',
    section: SettingsSection.playback,
    keywords: <String>['rate', 'faster', 'default'],
  ),
  SettingEntry(
    id: 'book-speed',
    title: 'Audiobook speed',
    section: SettingsSection.playback,
    keywords: <String>['rate', 'faster', 'default', 'narration'],
  ),
  SettingEntry(
    id: 'smart-rewind',
    title: 'Rewind on resume',
    section: SettingsSection.playback,
    keywords: <String>['smart rewind', 'back', 'context', 'podcast', 'book'],
  ),
  SettingEntry(
    id: 'trim-default',
    title: 'Trim silence by default',
    section: SettingsSection.playback,
    keywords: <String>['silence', 'skip', 'spoken word', 'podcast', 'book'],
  ),
  SettingEntry(
    id: 'boost-default',
    title: 'Voice boost by default',
    section: SettingsSection.playback,
    keywords: <String>['loudness', 'normalize', 'volume', 'speech', 'quiet'],
  ),
  SettingEntry(
    id: 'crossfade',
    title: 'Casting crossfade',
    section: SettingsSection.playback,
    keywords: <String>['fade', 'gapless', 'seam', 'chromecast'],
  ),
  SettingEntry(
    id: 'replay-gain',
    title: 'Level casting volume',
    section: SettingsSection.playback,
    keywords: <String>['replaygain', 'loudness', 'normalize', 'gain'],
  ),
  SettingEntry(
    id: 'preload-wifi',
    title: 'Prepare the next track on wifi only',
    section: SettingsSection.playback,
    keywords: <String>['gapless', 'preload', 'data', 'metered', 'mobile'],
    nativeOnly: true,
  ),
  SettingEntry(
    id: 'car-button',
    title: 'Car mode button',
    section: SettingsSection.playback,
    keywords: <String>['driving', 'large', 'dashboard', 'player'],
  ),
  SettingEntry(
    id: 'visualizer-idle',
    title: 'Open the visualizer when idle',
    section: SettingsSection.playback,
    keywords: <String>['screensaver', 'waveform', 'platter', 'away'],
    desktopOnly: true,
  ),

  // Library and metadata
  SettingEntry(
    id: 'technical-details',
    title: 'Show technical details',
    section: SettingsSection.library,
    keywords: <String>['codec', 'bitrate', 'format', 'flac', 'provenance'],
  ),
  SettingEntry(
    id: 'library-access',
    title: 'What I can see',
    section: SettingsSection.library,
    keywords: <String>['permissions', 'libraries', 'access'],
  ),

  // Downloads and storage
  SettingEntry(
    id: 'downloads-wifi',
    title: 'Download on wifi only',
    section: SettingsSection.downloads,
    keywords: <String>['data', 'metered', 'mobile', 'cellular'],
    nativeOnly: true,
  ),
  SettingEntry(
    id: 'downloads-manager',
    title: 'Manage downloads',
    section: SettingsSection.downloads,
    keywords: <String>['offline', 'storage', 'space', 'remove'],
    nativeOnly: true,
  ),
  SettingEntry(
    id: 'artwork-cache',
    title: 'Artwork cache',
    section: SettingsSection.downloads,
    keywords: <String>['covers', 'images', 'clear', 'space'],
  ),

  // Devices and casting
  SettingEntry(
    id: 'endpoints',
    title: 'Playback endpoints',
    section: SettingsSection.devices,
    keywords: <String>['cast', 'chromecast', 'dlna', 'speaker', 'connect'],
  ),
  SettingEntry(
    id: 'cast-check',
    title: 'Connection check',
    section: SettingsSection.devices,
    keywords: <String>['preflight', 'diagnose', 'reachable', 'cast'],
  ),

  // Integrations
  SettingEntry(
    id: 'scrobbling',
    title: 'Scrobbling',
    section: SettingsSection.integrations,
    keywords: <String>['last.fm', 'lastfm', 'listenbrainz'],
  ),
  SettingEntry(
    id: 'radio-scrobbling',
    handle: SemanticsIds.radioScrobbleSwitch,
    title: 'Scrobble radio',
    section: SettingsSection.integrations,
    keywords: <String>['last.fm', 'listenbrainz', 'station', 'stream'],
  ),
  SettingEntry(
    id: 'discord-presence',
    title: 'Show what I am listening to on Discord',
    section: SettingsSection.integrations,
    keywords: <String>['discord', 'rich presence', 'status', 'listening to'],
    desktopOnly: true,
  ),
  SettingEntry(
    id: 'notifications',
    title: 'Notification targets',
    section: SettingsSection.integrations,
    keywords: <String>['ntfy', 'webhook', 'discord', 'push', 'alerts'],
  ),

  // Appearance
  SettingEntry(
    id: 'theme',
    handle: SemanticsIds.themeSelect,
    title: 'Theme',
    section: SettingsSection.appearance,
    keywords: <String>['dark', 'light', 'oled', 'black'],
  ),
  SettingEntry(
    id: 'density',
    title: 'Density',
    section: SettingsSection.appearance,
    keywords: <String>['compact', 'comfortable', 'spacing', 'rows'],
  ),
  SettingEntry(
    id: 'grid-size',
    title: 'Artwork size',
    section: SettingsSection.appearance,
    keywords: <String>['grid', 'tiles', 'covers', 'large', 'small'],
  ),

  // Accessibility
  SettingEntry(
    id: 'reduce-motion',
    title: 'Reduce motion',
    section: SettingsSection.accessibility,
    keywords: <String>['animation', 'transitions', 'vestibular'],
  ),

  // Server
  SettingEntry(
    id: 'server-summary',
    title: 'This server',
    section: SettingsSection.server,
    keywords: <String>['version', 'uptime', 'build'],
    adminOnly: true,
  ),
  // The switches themselves live in the console now, but searching
  // settings for "read-only" or "signup" has to land somewhere, and the
  // row that opens the console is the honest destination: the query is
  // about the server, and this is the way to the server's own screens.
  SettingEntry(
    id: 'admin-console',
    title: 'Admin console',
    section: SettingsSection.server,
    keywords: <String>[
      'read-only',
      'signup',
      'libraries',
      'users',
      'backups',
      'schedules',
      'trash',
      'audit',
      'transcoding',
      'genres',
    ],
    adminOnly: true,
  ),
];

/// Settings matching [query], best match first.
///
/// The ranking is three tiers and no scoring: a title that starts with
/// the query, then a title that contains it, then a keyword match. A
/// fuzzy score would put "Density" above "Display name" for "d" on a
/// tie-break nobody could predict, and this list is short enough that
/// the honest ordering is the useful one.
///
/// [isAdmin], [isNative], and [isDesktop] drop what this caller cannot
/// reach, rather than offering a row that opens a section without it.
List<SettingEntry> searchSettings(
  String query, {
  required bool isAdmin,
  required bool isNative,
  required bool isDesktop,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const <SettingEntry>[];
  final starts = <SettingEntry>[];
  final contains = <SettingEntry>[];
  final byKeyword = <SettingEntry>[];
  for (final entry in settingsRegistry) {
    if (entry.adminOnly && !isAdmin) continue;
    if (entry.section.adminOnly && !isAdmin) continue;
    if (entry.nativeOnly && !isNative) continue;
    if (entry.desktopOnly && !isDesktop) continue;
    final title = entry.title.toLowerCase();
    if (title.startsWith(needle)) {
      starts.add(entry);
    } else if (title.contains(needle)) {
      contains.add(entry);
    } else if (entry.keywords.any((k) => k.contains(needle)) ||
        entry.section.title.toLowerCase().contains(needle)) {
      byKeyword.add(entry);
    }
  }
  return <SettingEntry>[...starts, ...contains, ...byKeyword];
}
