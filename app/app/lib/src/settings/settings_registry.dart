import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxGlyph, WaxIcons;

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
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
///
/// What a section is called is copy and so is not a constructor argument:
/// the enum carries the two things that are the same in every language,
/// its location and its glyph, and [titleOf] and [blurbOf] read the rest
/// from the table.
enum SettingsSection {
  account('account', WaxIcons.settings),
  playback('playback', WaxIcons.play),
  library('library', WaxIcons.albums),
  downloads('downloads', WaxIcons.downloads),
  devices('devices', WaxIcons.cast),
  integrations('integrations', WaxIcons.share),
  appearance('appearance', WaxIcons.star),
  accessibility('accessibility', WaxIcons.headphones),
  server('server', WaxIcons.admin);

  const SettingsSection(this.segment, this.glyph);

  /// The path segment under `/settings`. A location, so a section is a
  /// link somebody can send - "it is in Settings, Playback" becomes a URL.
  final String segment;

  final WaxGlyph glyph;

  /// What the section is called, on the home list and as the title of its
  /// own screen. Exhaustive rather than a map, so a tenth section is a
  /// compile error here instead of a row with no name.
  String titleOf(AppLocalizations l10n) => switch (this) {
    SettingsSection.account => l10n.settingsSectionAccountTitle,
    SettingsSection.playback => l10n.settingsSectionPlaybackTitle,
    SettingsSection.library => l10n.settingsSectionLibraryTitle,
    SettingsSection.downloads => l10n.settingsSectionDownloadsTitle,
    SettingsSection.devices => l10n.settingsSectionDevicesTitle,
    SettingsSection.integrations => l10n.settingsSectionIntegrationsTitle,
    SettingsSection.appearance => l10n.settingsSectionAppearanceTitle,
    SettingsSection.accessibility => l10n.settingsSectionAccessibilityTitle,
    SettingsSection.server => l10n.settingsSectionServerTitle,
  };

  /// The line under the section's name on the settings home.
  String blurbOf(AppLocalizations l10n) => switch (this) {
    SettingsSection.account => l10n.settingsSectionAccountBlurb,
    SettingsSection.playback => l10n.settingsSectionPlaybackBlurb,
    SettingsSection.library => l10n.settingsSectionLibraryBlurb,
    SettingsSection.downloads => l10n.settingsSectionDownloadsBlurb,
    SettingsSection.devices => l10n.settingsSectionDevicesBlurb,
    SettingsSection.integrations => l10n.settingsSectionIntegrationsBlurb,
    SettingsSection.appearance => l10n.settingsSectionAppearanceBlurb,
    SettingsSection.accessibility => l10n.settingsSectionAccessibilityBlurb,
    SettingsSection.server => l10n.settingsSectionServerBlurb,
  };

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

/// The search words for one setting, out of the comma-separated string
/// the translator works on. Kept as written, since [foldForSearch] is
/// what makes a query reach them; spaces and a trailing comma go.
List<String> _words(String commaSeparated) => commaSeparated
    .split(',')
    .map((word) => word.trim())
    .where((word) => word.isNotEmpty)
    .toList(growable: false);

/// Every leaf setting this build ships.
///
/// Kept beside the sections rather than derived from the widgets,
/// because a widget tree cannot be searched before it is built and the
/// settings home has to answer a query without mounting nine screens.
/// `settings_registry_test.dart` is what stops the two drifting: it fails
/// on a registered setting no section draws.
///
/// Built per call rather than held: the list is forty-odd rows of string
/// reads, and holding one would mean holding the locale it was built in.
///
/// Most titles are the same key the control's own row draws, so a search
/// result and the setting it opens say the same thing. The exceptions
/// are the rows that ask a question rather than name a setting - the
/// shared-stats and Discord switches - the row that opens the admin
/// console, and About, whose row is titled by the account it describes.
/// Those name the setting here and read as themselves on screen.
List<SettingEntry> settingsEntries(AppLocalizations l10n) => <SettingEntry>[
  // Account
  SettingEntry(
    id: 'display-name',
    title: l10n.settingsDisplayNameTitle,
    section: SettingsSection.account,
    keywords: _words(l10n.settingsDisplayNameKeywords),
  ),
  SettingEntry(
    id: 'password',
    title: l10n.settingsPasswordTitle,
    section: SettingsSection.account,
    keywords: _words(l10n.settingsPasswordKeywords),
  ),
  SettingEntry(
    id: 'devices',
    title: l10n.settingsDevicesTitle,
    section: SettingsSection.account,
    keywords: _words(l10n.settingsDevicesKeywords),
  ),
  SettingEntry(
    id: 'app-passwords',
    title: l10n.settingsAppPasswordsTitle,
    section: SettingsSection.account,
    keywords: _words(l10n.settingsAppPasswordsKeywords),
  ),
  SettingEntry(
    id: 'timezone',
    handle: SemanticsIds.timezoneEdit,
    title: l10n.settingsTimezoneTitle,
    section: SettingsSection.account,
    keywords: _words(l10n.settingsTimezoneKeywords),
  ),
  SettingEntry(
    id: 'shared-stats',
    handle: SemanticsIds.sharedStatsSwitch,
    title: l10n.settingsSharedStatsTitle,
    section: SettingsSection.account,
    keywords: _words(l10n.settingsSharedStatsKeywords),
  ),
  SettingEntry(
    id: 'about',
    title: l10n.settingsAboutTitle,
    section: SettingsSection.account,
    // The defect log lives on the About page rather than as a control of
    // its own, so About is what a search for it has to find.
    keywords: _words(l10n.settingsAboutKeywords),
  ),

  // Playback
  SettingEntry(
    id: 'skip-back',
    title: l10n.settingsSkipBackTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsSkipBackKeywords),
  ),
  SettingEntry(
    id: 'skip-forward',
    title: l10n.settingsSkipForwardTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsSkipForwardKeywords),
  ),
  SettingEntry(
    id: 'podcast-speed',
    title: l10n.settingsPodcastSpeedTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsPodcastSpeedKeywords),
  ),
  SettingEntry(
    id: 'book-speed',
    title: l10n.settingsBookSpeedTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsBookSpeedKeywords),
  ),
  SettingEntry(
    id: 'smart-rewind',
    title: l10n.settingsSmartRewindTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsSmartRewindKeywords),
  ),
  SettingEntry(
    id: 'trim-default',
    title: l10n.settingsTrimDefaultTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsTrimDefaultKeywords),
  ),
  SettingEntry(
    id: 'boost-default',
    title: l10n.settingsBoostDefaultTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsBoostDefaultKeywords),
  ),
  SettingEntry(
    id: 'crossfade',
    title: l10n.settingsCrossfadeTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsCrossfadeKeywords),
  ),
  SettingEntry(
    id: 'replay-gain',
    title: l10n.settingsReplayGainTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsReplayGainKeywords),
  ),
  SettingEntry(
    id: 'preload-wifi',
    title: l10n.settingsPreloadWifiTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsPreloadWifiKeywords),
    nativeOnly: true,
  ),
  SettingEntry(
    id: 'autoplay',
    title: l10n.settingsAutoplayTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsAutoplayKeywords),
  ),
  SettingEntry(
    id: 'car-button',
    title: l10n.settingsCarButtonTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsCarButtonKeywords),
  ),
  SettingEntry(
    id: 'visualizer-idle',
    title: l10n.settingsVisualizerIdleTitle,
    section: SettingsSection.playback,
    keywords: _words(l10n.settingsVisualizerIdleKeywords),
    desktopOnly: true,
  ),

  // Library and metadata
  SettingEntry(
    id: 'technical-details',
    title: l10n.settingsTechnicalDetailsTitle,
    section: SettingsSection.library,
    keywords: _words(l10n.settingsTechnicalDetailsKeywords),
  ),
  SettingEntry(
    id: 'browse-unknown',
    title: l10n.settingsBrowseUnknownTitle,
    section: SettingsSection.library,
    keywords: _words(l10n.settingsBrowseUnknownKeywords),
  ),
  // One entry for the set: five near-identical results would bury
  // whatever else the word matched.
  SettingEntry(
    id: 'browse-sort-artists',
    title: l10n.settingsBrowseOrderTitle,
    section: SettingsSection.library,
    keywords: _words(l10n.settingsBrowseOrderKeywords),
  ),
  SettingEntry(
    id: 'identify-uploads',
    title: l10n.settingsIdentifyUploadsTitle,
    section: SettingsSection.library,
    keywords: _words(l10n.settingsIdentifyUploadsKeywords),
  ),
  SettingEntry(
    id: 'library-access',
    title: l10n.settingsLibraryAccessTitle,
    section: SettingsSection.library,
    keywords: _words(l10n.settingsLibraryAccessKeywords),
  ),

  // Downloads and storage
  SettingEntry(
    id: 'downloads-wifi',
    title: l10n.settingsDownloadsWifiTitle,
    section: SettingsSection.downloads,
    keywords: _words(l10n.settingsDownloadsWifiKeywords),
    nativeOnly: true,
  ),
  SettingEntry(
    id: 'auto-remove-finished',
    title: l10n.settingsAutoRemoveFinishedTitle,
    section: SettingsSection.downloads,
    keywords: _words(l10n.settingsAutoRemoveFinishedKeywords),
    nativeOnly: true,
  ),
  SettingEntry(
    id: 'downloads-manager',
    title: l10n.settingsDownloadsManagerTitle,
    section: SettingsSection.downloads,
    keywords: _words(l10n.settingsDownloadsManagerKeywords),
    nativeOnly: true,
  ),
  SettingEntry(
    id: 'artwork-cache',
    title: l10n.settingsArtworkCacheTitle,
    section: SettingsSection.downloads,
    keywords: _words(l10n.settingsArtworkCacheKeywords),
  ),

  // Devices and casting
  SettingEntry(
    id: 'endpoints',
    title: l10n.settingsEndpointsTitle,
    section: SettingsSection.devices,
    keywords: _words(l10n.settingsEndpointsKeywords),
  ),
  SettingEntry(
    id: 'cast-check',
    title: l10n.settingsCastCheckTitle,
    section: SettingsSection.devices,
    keywords: _words(l10n.settingsCastCheckKeywords),
  ),

  // Integrations
  SettingEntry(
    id: 'scrobbling',
    title: l10n.settingsScrobblingTitle,
    section: SettingsSection.integrations,
    keywords: _words(l10n.settingsScrobblingKeywords),
  ),
  SettingEntry(
    id: 'radio-scrobbling',
    handle: SemanticsIds.radioScrobbleSwitch,
    title: l10n.settingsRadioScrobblingTitle,
    section: SettingsSection.integrations,
    keywords: _words(l10n.settingsRadioScrobblingKeywords),
  ),
  SettingEntry(
    id: 'discord-presence',
    title: l10n.settingsDiscordPresenceTitle,
    section: SettingsSection.integrations,
    keywords: _words(l10n.settingsDiscordPresenceKeywords),
    desktopOnly: true,
  ),
  SettingEntry(
    id: 'notifications',
    title: l10n.settingsNotificationsTitle,
    section: SettingsSection.integrations,
    keywords: _words(l10n.settingsNotificationsKeywords),
  ),

  // Appearance
  SettingEntry(
    id: 'theme',
    handle: SemanticsIds.themeSelect,
    title: l10n.settingsThemeTitle,
    section: SettingsSection.appearance,
    keywords: _words(l10n.settingsThemeKeywords),
  ),
  SettingEntry(
    id: 'language',
    title: l10n.settingsLanguageTitle,
    section: SettingsSection.appearance,
    keywords: _words(l10n.settingsLanguageKeywords),
  ),
  SettingEntry(
    id: 'density',
    title: l10n.settingsDensityTitle,
    section: SettingsSection.appearance,
    keywords: _words(l10n.settingsDensityKeywords),
  ),
  SettingEntry(
    id: 'grid-size',
    title: l10n.settingsGridSizeTitle,
    section: SettingsSection.appearance,
    keywords: _words(l10n.settingsGridSizeKeywords),
  ),
  SettingEntry(
    id: 'artwork-glow',
    title: l10n.settingsArtworkGlowTitle,
    section: SettingsSection.appearance,
    keywords: _words(l10n.settingsArtworkGlowKeywords),
  ),
  SettingEntry(
    id: 'card-captions',
    title: l10n.settingsCardCaptionsTitle,
    section: SettingsSection.appearance,
    keywords: _words(l10n.settingsCardCaptionsKeywords),
  ),

  // Accessibility
  SettingEntry(
    id: 'reduce-motion',
    title: l10n.settingsReduceMotionTitle,
    section: SettingsSection.accessibility,
    keywords: _words(l10n.settingsReduceMotionKeywords),
  ),

  // Server
  SettingEntry(
    id: 'server-summary',
    title: l10n.settingsServerSummaryTitle,
    section: SettingsSection.server,
    keywords: _words(l10n.settingsServerSummaryKeywords),
    adminOnly: true,
  ),
  // The switches themselves live in the console now, but searching
  // settings for "read-only" or "signup" has to land somewhere, and the
  // row that opens the console is the honest destination: the query is
  // about the server, and this is the way to the server's own screens.
  SettingEntry(
    id: 'admin-console',
    title: l10n.settingsAdminConsoleTitle,
    section: SettingsSection.server,
    keywords: _words(l10n.settingsAdminConsoleKeywords),
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
  required AppLocalizations l10n,
  required bool isAdmin,
  required bool isNative,
  required bool isDesktop,
}) {
  final needle = foldForSearch(query.trim());
  if (needle.isEmpty) return const <SettingEntry>[];
  final starts = <SettingEntry>[];
  final contains = <SettingEntry>[];
  final byKeyword = <SettingEntry>[];
  for (final entry in settingsEntries(l10n)) {
    if (entry.adminOnly && !isAdmin) continue;
    if (entry.section.adminOnly && !isAdmin) continue;
    if (entry.nativeOnly && !isNative) continue;
    if (entry.desktopOnly && !isDesktop) continue;
    final title = foldForSearch(entry.title);
    if (title.startsWith(needle)) {
      starts.add(entry);
    } else if (title.contains(needle)) {
      contains.add(entry);
    } else if (entry.keywords.any((k) => foldForSearch(k).contains(needle)) ||
        foldForSearch(entry.section.titleOf(l10n)).contains(needle)) {
      byKeyword.add(entry);
    }
  }
  return <SettingEntry>[...starts, ...contains, ...byKeyword];
}
