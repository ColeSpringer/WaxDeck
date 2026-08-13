import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../connect/cast_preflight.dart';
import '../connect/device_picker.dart';
import '../music/music_controllers.dart';
import '../player/smart_rewind.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'about_screen.dart';
import 'account_sections.dart';
import 'client_prefs.dart';
import 'integrations_sections.dart';
import 'listening_sections.dart';
import 'prefs_controller.dart';
import 'settings_registry.dart';

/// One settings section, at its own location. A drilled-in screen rather
/// than a pane swap, leaving to the settings home even when opened cold,
/// so a shared link to Playback has somewhere to go back to.
class SettingsSectionScreen extends ConsumerWidget {
  const SettingsSectionScreen({required this.section, super.key});

  final SettingsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final isAdmin = ref.watch(isAdminProvider);
    return WaxScaffold(
      title: section.title,
      largeTitle: false,
      // No identifier of its own: the obvious one is the row's, and one
      // id naming two things means a retried click meant for the row
      // lands in the screen it already opened. The URL proves it.
      onBack: () => context.leave(fallback: WaxRoute.settings),
      slivers: <Widget>[
        SliverPadding(
          padding:
              sizeClass.gutter + const EdgeInsets.only(bottom: WaxSpace.s32),
          sliver: SliverToBoxAdapter(
            // Past the reading width a row's sentence and its control
            // drift too far apart to read as one. `ReadingColumn` and not
            // `ConstrainedBox`, which a sliver resolves back to full.
            child: ReadingColumn(
              child: switch (section) {
                SettingsSection.account => const AccountSectionBody(),
                SettingsSection.playback => const _PlaybackBody(),
                SettingsSection.library => const _LibraryBody(),
                SettingsSection.downloads => const _DownloadsBody(),
                SettingsSection.devices => const _DevicesBody(),
                SettingsSection.integrations => const _IntegrationsBody(),
                SettingsSection.appearance => const _AppearanceBody(),
                SettingsSection.accessibility => const _AccessibilityBody(),
                // Not merely empty for a member: the section is absent
                // from the list and from search, so arriving here at all
                // means a hand-typed URL or a role that changed under an
                // open tab.
                SettingsSection.server =>
                  isAdmin
                      ? const _ServerBody()
                      : const EmptyState(
                          title: 'Administrators only',
                          message: 'This section is about the server itself.',
                          glyph: WaxIcons.admin,
                        ),
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A heading over a run of related rows.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      // Top only: the header owns the space under itself, and a screen
      // adding its own on top of that is what makes one section sit
      // differently from the next.
      Padding(
        padding: EdgeInsets.only(top: WaxLayout.of(context).sectionGap),
        child: SectionHeader(title: title),
      ),
      ...children,
    ],
  );
}

// --- Playback ----------------------------------------------------------------

class _PlaybackBody extends ConsumerWidget {
  const _PlaybackBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsControllerProvider).value;
    final prefsController = ref.read(prefsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: 'Spoken word',
          children: <Widget>[
            WaxSettingRow(
              title: 'Skip back by',
              help: 'How far the back control jumps on a podcast or a book',
              control: WaxChoice<int>(
                value: ref.watch(skipBackSecondsProvider),
                options: SkipBackSeconds.options,
                labelFor: spellSeconds,
                label: 'Skip back by',
                semanticsId: SemanticsIds.setting('skip-back'),
                optionSemanticsIdFor: (seconds) =>
                    SemanticsIds.settingOption('skip-back', seconds),
                onChanged: ref.read(skipBackSecondsProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Skip forward by',
              help: 'How far the forward control jumps',
              control: WaxChoice<int>(
                value: ref.watch(skipForwardSecondsProvider),
                options: SkipForwardSeconds.options,
                labelFor: spellSeconds,
                label: 'Skip forward by',
                semanticsId: SemanticsIds.setting('skip-forward'),
                onChanged: ref.read(skipForwardSecondsProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Podcast speed',
              help: 'The speed a show plays at until you set one for it',
              control: WaxChoice<double>(
                value: ref.watch(podcastSpeedProvider),
                options: SpeedSetting.options,
                labelFor: spellSpeed,
                label: 'Podcast speed',
                semanticsId: SemanticsIds.setting('podcast-speed'),
                onChanged: ref.read(podcastSpeedProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Audiobook speed',
              help: 'The speed a book plays at until you set one for it',
              control: WaxChoice<double>(
                value: ref.watch(bookSpeedProvider),
                options: SpeedSetting.options,
                labelFor: spellSpeed,
                label: 'Audiobook speed',
                semanticsId: SemanticsIds.setting('book-speed'),
                onChanged: ref.read(bookSpeedProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Rewind on resume',
              help:
                  'Steps back a little when you come back to a show or a '
                  'book after a break, so you land before the sentence you '
                  'lost',
              control: WaxChoice<SmartRewind>(
                value: ref.watch(smartRewindProvider),
                options: SmartRewind.values,
                labelFor: (value) => value.label,
                label: 'Rewind on resume',
                semanticsId: SemanticsIds.setting('smart-rewind'),
                onChanged: ref.read(smartRewindProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Trim silence by default',
              help:
                  'Shows and books with no stored choice of their own '
                  'open with silence trimming on',
              control: WaxSwitch(
                value: ref.watch(trimSilenceDefaultProvider),
                label: 'Trim silence by default',
                semanticsId: SemanticsIds.setting('trim-default'),
                onChanged: ref.read(trimSilenceDefaultProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Voice boost by default',
              help:
                  'Shows and books with no stored choice of their own '
                  'open with loudness normalization on',
              control: WaxSwitch(
                value: ref.watch(voiceBoostDefaultProvider),
                label: 'Voice boost by default',
                semanticsId: SemanticsIds.setting('boost-default'),
                onChanged: ref.read(voiceBoostDefaultProvider.notifier).set,
              ),
            ),
          ],
        ),
        _Group(
          title: 'The player',
          children: <Widget>[
            WaxSettingRow(
              title: 'Car mode button',
              help:
                  'Puts car mode on the player itself instead of inside '
                  'its menu',
              control: WaxSwitch(
                value: ref.watch(carModeButtonProvider),
                label: 'Car mode button',
                semanticsId: SemanticsIds.setting('car-button'),
                onChanged: ref.read(carModeButtonProvider.notifier).set,
              ),
            ),
            // Desktop alone: this is a machine left playing in a room,
            // which a phone or a tab is not. Absent rather than
            // disabled, since a switch with nothing behind it lies.
            if (ref.watch(desktopProvider))
              WaxSettingRow(
                title: 'Open the visualizer when idle',
                help:
                    'Fills the screen with the track once music has been '
                    'playing untouched for a few minutes',
                control: WaxSwitch(
                  value: ref.watch(visualizerWhenIdleProvider),
                  label: 'Open the visualizer when idle',
                  semanticsId: SemanticsIds.setting('visualizer-idle'),
                  onChanged: ref.read(visualizerWhenIdleProvider.notifier).set,
                ),
              ),
          ],
        ),
        _Group(
          // Named for what it applies to rather than for what it is.
          // Nothing local reads either value yet, and a "Crossfade"
          // heading over a control that does nothing on this device is
          // the kind of promise a settings screen must not make.
          title: 'Casting',
          children: <Widget>[
            WaxSettingRow(
              title: 'Casting crossfade',
              help: 'Fades one track into the next when casting a queue',
              control: WaxChoice<double>(
                value: prefs?.crossfadeSeconds ?? 0,
                options: const <double>[0, 2, 4, 6, 8, 12],
                labelFor: (seconds) =>
                    seconds == 0 ? 'Off' : spellSeconds(seconds.round()),
                label: 'Casting crossfade',
                semanticsId: SemanticsIds.setting('crossfade'),
                // Rounded: the options are doubles, and a spec names 6.
                optionSemanticsIdFor: (seconds) =>
                    SemanticsIds.settingOption('crossfade', seconds.round()),
                onChanged: prefs == null
                    ? null
                    : prefsController.setCrossfadeSeconds,
              ),
            ),
            WaxSettingRow(
              title: 'Level casting volume',
              help:
                  'Plays a cast queue at one loudness, where the files '
                  'have been analyzed',
              control: WaxSwitch(
                value: prefs?.replayGain ?? false,
                label: 'Level casting volume',
                semanticsId: SemanticsIds.setting('replay-gain'),
                onChanged: prefs == null ? null : prefsController.setReplayGain,
              ),
            ),
          ],
        ),
        _Group(
          title: 'Starting on its own',
          children: <Widget>[
            WaxSettingRow(
              title: 'Start playing without asking',
              help:
                  'Lets a queue another device hands over start here. Off '
                  'means it arrives ready and waits to be tapped',
              control: WaxSwitch(
                value: prefs?.autoplay ?? true,
                label: 'Start playing without asking',
                semanticsId: SemanticsIds.setting('autoplay'),
                onChanged: prefs == null ? null : prefsController.setAutoplay,
              ),
            ),
          ],
        ),
        if (!kIsWeb)
          _Group(
            title: 'Data',
            children: <Widget>[
              WaxSettingRow(
                title: 'Prepare the next track on wifi only',
                help:
                    'Gapless playback buffers the next track early; this '
                    'holds that back on mobile data',
                control: WaxSwitch(
                  value: ref.watch(preloadOnWifiOnlyProvider),
                  label: 'Prepare the next track on wifi only',
                  semanticsId: SemanticsIds.setting('preload-wifi'),
                  onChanged: ref.read(preloadOnWifiOnlyProvider.notifier).set,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// --- Library and metadata ----------------------------------------------------

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsControllerProvider).value;
    final prefsController = ref.read(prefsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: 'Browsing',
          children: <Widget>[
            WaxSettingRow(
              title: 'Show technical details',
              help: 'Draws codec and format chips beside what they describe',
              control: WaxSwitch(
                value: ref.watch(technicalDetailsProvider),
                label: 'Show technical details',
                semanticsId: SemanticsIds.setting('technical-details'),
                onChanged: ref.read(technicalDetailsProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Show unknown groups',
              help:
                  'Lists the group for what has no genre, no album, or no '
                  'year of its own',
              control: WaxSwitch(
                value: prefs?.browseShowUnknown ?? true,
                label: 'Show unknown groups',
                semanticsId: SemanticsIds.setting('browse-unknown'),
                onChanged: prefs == null
                    ? null
                    : prefsController.setBrowseShowUnknown,
              ),
            ),
          ],
        ),
        _Group(
          title: 'Default order',
          children: <Widget>[
            for (final dimension in MusicDimension.values)
              WaxSettingRow(
                title: dimension.label,
                help:
                    'The order the ${dimension.label.toLowerCase()} '
                    'index opens in',
                control: WaxChoice<FacetSort>(
                  value:
                      prefs?.browseSortFor(dimension.wireName) ??
                      defaultBrowseSort(dimension),
                  options: FacetSort.values,
                  labelFor: browseSortLabel,
                  label: '${dimension.label} order',
                  semanticsId: SemanticsIds.setting(
                    'browse-sort-${dimension.segment}',
                  ),
                  onChanged: prefs == null
                      ? null
                      : (value) => prefsController.setBrowseSort(
                          dimension.wireName,
                          value,
                        ),
                ),
              ),
          ],
        ),
        _Group(
          title: 'Adding to the library',
          children: <Widget>[
            WaxSettingRow(
              title: 'Identify uploads',
              help:
                  'Matches what you add against MusicBrainz. Off adds it '
                  'with the tags it has, without review',
              control: WaxSwitch(
                value: !(prefs?.identifyOptOut ?? false),
                label: 'Identify uploads',
                semanticsId: SemanticsIds.setting('identify-uploads'),
                onChanged: prefs == null
                    ? null
                    : (on) => prefsController.setIdentifyOptOut(!on),
              ),
            ),
          ],
        ),
        const _Group(title: 'Access', children: <Widget>[_LibraryAccessRow()]),
      ],
    );
  }
}

/// What this account can see, read-only, so a household member can
/// answer "why can I not find that album" without asking. The grant is
/// the administrator's, so a control here would be a refusal waiting.
class _LibraryAccessRow extends ConsumerWidget {
  const _LibraryAccessRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(myAccountProvider);
    final help = switch (account) {
      AsyncData(:final value) => switch (value.libraryAccess.mode) {
        'all' => 'You can see every library on this server',
        _ =>
          'You can see '
              '${value.libraryAccess.libraryPids.length} of this '
              "server's libraries",
      },
      AsyncError() => 'Could not read your access',
      _ => 'Checking',
    };
    return Semantics(
      identifier: SemanticsIds.setting('library-access'),
      child: WaxSettingRow(
        title: 'What I can see',
        help: help,
        glyph: WaxIcons.albums,
        control: const SizedBox.shrink(),
      ),
    );
  }
}

// --- Downloads and storage ---------------------------------------------------

class _DownloadsBody extends ConsumerWidget {
  const _DownloadsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!kIsWeb) ...<Widget>[
          _Group(
            title: 'Downloads',
            children: <Widget>[
              WaxSettingRow(
                title: 'Download on wifi only',
                help:
                    'Holds transfers until this device is on wifi, rather '
                    'than failing them',
                control: WaxSwitch(
                  value: ref.watch(downloadsOnWifiOnlyProvider),
                  label: 'Download on wifi only',
                  semanticsId: SemanticsIds.setting('downloads-wifi'),
                  onChanged: ref.read(downloadsOnWifiOnlyProvider.notifier).set,
                ),
              ),
              WaxSettingRow(
                title: 'Remove finished episodes',
                help:
                    'Reclaims a downloaded episode once it has been '
                    'finished for a while. Books and albums are left alone',
                control: WaxSwitch(
                  value: ref.watch(autoRemoveFinishedProvider),
                  label: 'Remove finished episodes',
                  semanticsId: SemanticsIds.setting('auto-remove-finished'),
                  onChanged: ref.read(autoRemoveFinishedProvider.notifier).set,
                ),
              ),
              // Only where it decides something.
              if (ref.watch(autoRemoveFinishedProvider))
                WaxSettingRow(
                  title: 'Wait before removing',
                  help: 'How long a finished episode stays before it goes',
                  control: WaxChoice<int>(
                    value: ref.watch(autoRemoveFinishedAfterHoursProvider),
                    options: AutoRemoveFinishedAfterHours.options,
                    labelFor: spellHours,
                    label: 'Wait before removing',
                    semanticsId: SemanticsIds.setting('auto-remove-after'),
                    onChanged: ref
                        .read(autoRemoveFinishedAfterHoursProvider.notifier)
                        .set,
                  ),
                ),
              WaxOptionRow(
                title: 'Manage downloads',
                subtitle: 'What this device holds offline, and how to free it',
                glyph: WaxIcons.downloads,
                semanticsId: SemanticsIds.setting('downloads-manager'),
                trailing: const WaxIcon(WaxIcons.forward, size: 16),
                onTap: () => context.go(WaxRoute.downloads),
              ),
            ],
          ),
        ],
        const _Group(title: 'Storage', children: <Widget>[_ArtworkCacheRow()]),
      ],
    );
  }
}

/// Clearing the artwork cache. No size beside it: the cache manager
/// reports no total, and a number derived from the pins WaxDeck knows
/// would understate the disk - worse than none, for a row about space.
class _ArtworkCacheRow extends ConsumerStatefulWidget {
  const _ArtworkCacheRow();

  @override
  ConsumerState<_ArtworkCacheRow> createState() => _ArtworkCacheRowState();
}

class _ArtworkCacheRowState extends ConsumerState<_ArtworkCacheRow> {
  bool _clearing = false;

  Future<void> _clear() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _clearing = true);
    try {
      await ref.read(artworkStoreProvider).forgetEverything();
      ref.read(paletteCacheProvider).clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Artwork cache cleared')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => WaxSettingRow(
    title: 'Artwork cache',
    help: 'Covers are re-fetched as they are needed again',
    glyph: WaxIcons.albums,
    control: WaxButton(
      label: 'Clear',
      kind: WaxButtonKind.tonal,
      onPressed: _clearing ? null : () => _clear(),
      semanticsId: SemanticsIds.setting('artwork-cache'),
    ),
  );
}

// --- Devices and casting -----------------------------------------------------

class _DevicesBody extends ConsumerWidget {
  const _DevicesBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: 'Where sound comes out',
          children: <Widget>[
            WaxOptionRow(
              title: 'Playback endpoints',
              subtitle: 'Cast targets, renderers, and your other devices',
              glyph: WaxIcons.cast,
              semanticsId: SemanticsIds.setting('endpoints'),
              trailing: const WaxIcon(WaxIcons.forward, size: 16),
              // The same picker the deck bar opens, from the same
              // source: nothing local is being sent, so this lists and
              // controls rather than hands anything over.
              onTap: () => showDevicePicker(context, from: CastSource.here),
            ),
            WaxOptionRow(
              title: 'Connection check',
              subtitle: 'Whether a cast device can reach this server',
              glyph: WaxIcons.warning,
              semanticsId: SemanticsIds.setting('cast-check'),
              trailing: const WaxIcon(WaxIcons.forward, size: 16),
              onTap: () => showCastPreflight(context),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Integrations ------------------------------------------------------------

class _IntegrationsBody extends ConsumerWidget {
  const _IntegrationsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsControllerProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The registry names the group; the controls inside it keep the
        // per-service handles the e2e suite already steers by.
        Semantics(
          identifier: SemanticsIds.setting('scrobbling'),
          child: const ScrobblingSection(),
        ),
        _Group(
          title: 'What gets scrobbled',
          children: <Widget>[
            WaxSettingRow(
              title: 'Scrobble radio',
              help:
                  'Radio segments report as tracks where a station names '
                  'them honestly',
              control: WaxSwitch(
                value: !(prefs?.radioScrobbleOptOut ?? false),
                label: 'Scrobble radio',
                semanticsId: SemanticsIds.radioScrobbleSwitch,
                onChanged: prefs == null
                    ? null
                    : (on) => ref
                          .read(prefsControllerProvider.notifier)
                          .setRadioScrobbleOptOut(!on),
              ),
            ),
          ],
        ),
        // Desktop alone: presence is published through the Discord app's
        // own socket on this machine, so a phone or a browser tab has
        // nothing to publish it to. Absent rather than disabled, the way
        // the idle visualizer is.
        if (ref.watch(desktopProvider)) ...<Widget>[
          const SizedBox(height: WaxSpace.s24),
          const DiscordPresenceSection(),
        ],
        const SizedBox(height: WaxSpace.s24),
        Semantics(
          identifier: SemanticsIds.setting('notifications'),
          child: const PersonalNotificationTargetsSection(),
        ),
      ],
    );
  }
}

// --- Appearance --------------------------------------------------------------

class _AppearanceBody extends ConsumerWidget {
  const _AppearanceBody();

  static String _themeLabel(ThemePref theme) => switch (theme) {
    ThemePref.system => 'Match the system',
    ThemePref.dark => 'Dark',
    ThemePref.light => 'Light',
    ThemePref.oled => 'OLED black',
  };

  static String _densityLabel(WaxDensity density) => switch (density) {
    WaxDensity.comfortable => 'Comfortable',
    WaxDensity.compact => 'Compact',
  };

  static String _gridLabel(WaxGridSize size) => switch (size) {
    WaxGridSize.small => 'Small',
    WaxGridSize.medium => 'Medium',
    WaxGridSize.large => 'Large',
  };

  static String _captionLabel(WaxCaptionMode mode) => switch (mode) {
    WaxCaptionMode.always => 'Always',
    WaxCaptionMode.onHover => 'On hover',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsControllerProvider).value;
    // The hardware question, not the this-second one: a touchscreen
    // laptop is in touch highlight mode for as long as the last input
    // was a finger, and greying the row there would be the app telling
    // a machine with a mouse on it that it has no pointer.
    final hasPointer = ref.watch(mouseConnectedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: 'Theme',
          children: <Widget>[
            WaxSettingRow(
              title: 'Theme',
              // The one Appearance setting that follows the account
              // rather than the device, which is why it says so.
              help: 'Follows you to your other devices',
              control: WaxChoice<ThemePref>(
                value: prefs?.theme ?? ThemePref.system,
                options: ThemePref.values,
                labelFor: _themeLabel,
                label: 'Theme',
                semanticsId: SemanticsIds.themeSelect,
                onChanged: prefs == null
                    ? null
                    : ref.read(prefsControllerProvider.notifier).setTheme,
              ),
            ),
          ],
        ),
        _Group(
          title: 'This device',
          children: <Widget>[
            WaxSettingRow(
              title: 'Density',
              help: 'How tightly rows pack; text size stays the system\'s',
              control: WaxChoice<WaxDensity>(
                value: ref.watch(densityProvider),
                options: WaxDensity.values,
                labelFor: _densityLabel,
                label: 'Density',
                semanticsId: SemanticsIds.setting('density'),
                onChanged: ref.read(densityProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Artwork size',
              help: 'How large covers are drawn in grids',
              control: WaxChoice<WaxGridSize>(
                value: ref.watch(gridSizeProvider),
                options: WaxGridSize.values,
                labelFor: _gridLabel,
                label: 'Artwork size',
                semanticsId: SemanticsIds.setting('grid-size'),
                onChanged: ref.read(gridSizeProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Artwork glow',
              help: 'The colour a cover casts behind the player',
              control: WaxSwitch(
                value: ref.watch(artworkGlowProvider),
                label: 'Artwork glow',
                semanticsId: SemanticsIds.setting('artwork-glow'),
                onChanged: ref.read(artworkGlowProvider.notifier).set,
              ),
            ),
            WaxSettingRow(
              title: 'Card captions',
              // Hover is the only way back to a hidden caption, so with
              // no pointer the choice is refused rather than taken and
              // quietly ignored, and the help line says why.
              help: hasPointer
                  ? 'The lines under a cover in a grid'
                  : 'Always shown: hiding them needs a pointer to bring '
                        'them back',
              control: WaxChoice<WaxCaptionMode>(
                value: ref.watch(cardCaptionsProvider),
                options: WaxCaptionMode.values,
                labelFor: _captionLabel,
                label: 'Card captions',
                semanticsId: SemanticsIds.setting('card-captions'),
                onChanged: hasPointer
                    ? ref.read(cardCaptionsProvider.notifier).set
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Accessibility -----------------------------------------------------------

class _AccessibilityBody extends ConsumerWidget {
  const _AccessibilityBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platformReduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: 'Motion',
          children: <Widget>[
            WaxSettingRow(
              title: 'Reduce motion',
              // Says what it is doing when the platform already asked for
              // this, rather than sitting on with no effect and looking
              // broken. The switch stays live: turning it off here does
              // not put motion back, and the line is what explains that.
              help: platformReduced && !ref.watch(reduceMotionProvider)
                  ? 'Already reduced: this device asks every app for less '
                        'motion'
                  : 'Stills transitions and the playing indicator',
              control: WaxSwitch(
                value: ref.watch(reduceMotionProvider),
                label: 'Reduce motion',
                semanticsId: SemanticsIds.setting('reduce-motion'),
                onChanged: ref.read(reduceMotionProvider.notifier).set,
              ),
            ),
          ],
        ),
        _Group(
          title: 'Screen readers',
          children: <Widget>[
            WaxOptionRow(
              title: 'How WaxDeck reads out',
              subtitle:
                  'Every control is named, the queue reorders from the '
                  'keyboard, and the deck bar is one landmark',
              glyph: WaxIcons.headphones,
            ),
          ],
        ),
      ],
    );
  }
}

// --- Server ------------------------------------------------------------------

class _ServerBody extends ConsumerWidget {
  const _ServerBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: 'This server',
          children: <Widget>[
            const AboutRow(semanticsId: SemanticsIds.serverSummary),
            // A door rather than a control panel: the switches that used
            // to sit here are decisions about the server, and belong
            // beside the other ones.
            WaxOptionRow(
              title: 'Open the admin console',
              subtitle: 'Libraries, users, scans, backups, and the audit log',
              glyph: WaxIcons.admin,
              trailing: const WaxIcon(WaxIcons.forward, size: 16),
              semanticsId: SemanticsIds.setting('admin-console'),
              onTap: () => context.go(WaxRoute.admin),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),
        const SimilarityStatusSection(),
      ],
    );
  }
}
