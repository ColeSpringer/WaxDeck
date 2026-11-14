import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_palette.dart';
import '../artwork/artwork_providers.dart';
import '../connect/cast_preflight.dart';
import '../connect/device_picker.dart';
import '../l10n/l10n.dart';
import '../music/music_controllers.dart';
import '../player/smart_rewind.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/server_health.dart';
import '../shell/shell_messages.dart';
import 'about_screen.dart';
import 'account_sections.dart';
import 'client_prefs.dart';
import 'integrations_sections.dart';
import 'listening_sections.dart';
import 'prefs_controller.dart';
import 'save_setting.dart';
import 'setting_anchor.dart';
import 'settings_registry.dart';

/// One settings section, at its own location. A drilled-in screen rather
/// than a pane swap, leaving to the settings home even when opened cold,
/// so a shared link to Playback has somewhere to go back to.
class SettingsSectionScreen extends ConsumerWidget {
  const SettingsSectionScreen({required this.section, this.setting, super.key});

  final SettingsSection section;

  /// The row a settings search result asked to land on, from the
  /// location's `?setting=`. Null when the section was opened for its
  /// own sake; an id no row here carries lands nowhere in particular,
  /// which is the top of the section.
  final String? setting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sizeClass = WaxSizeClass.of(context);
    final admin = ref.watch(adminAccessProvider);
    return WaxScaffold(
      title: section.titleOf(l10n),
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
              child: WantedSetting(
                id: setting,
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
                  SettingsSection.server => switch (admin) {
                    AdminAccess.granted => const _ServerBody(),
                    AdminAccess.resolving => const SkeletonShapes(
                      shape: SkeletonShape.list,
                    ),
                    AdminAccess.refused => EmptyState(
                      title: l10n.settingsServerAdminOnlyTitle,
                      glyph: WaxIcons.admin,
                    ),
                  },
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Why engine settings are disabled or waiting, when several rows would
/// say the same thing: each group holding one of them says it once, under
/// its heading, and the rows stay quiet.
enum EngineReason { none, away, lacking }

/// The reason two or more of the rows ([offers], one per row) would share
/// on this server, or null when no reason touches more than one row. A
/// row alone in its reason keeps its own line.
EngineReason? sharedEngineReason(
  ServerStreaming? streaming,
  List<bool Function(ServerStreaming)> offers,
) {
  if (offers.length < 2) return null;
  return switch (streaming) {
    ServerStreaming(configured: false) => EngineReason.none,
    ServerStreaming(connected: false) => EngineReason.away,
    final engine? when offers.where((o) => !o(engine)).length >= 2 =>
      EngineReason.lacking,
    _ => null,
  };
}

/// A setting the streaming engine serves, shaped by what the server says
/// of it: on a server without one its control is drawn disabled; while one
/// is away the control stays live, since the choice applies once it
/// answers; an engine that answers without the feature ([offers] false)
/// disables it too, with [lacking] unless [shared] says it for every row
/// at once. No engine and an engine away are never the row's to say: the
/// caller draws that once under the group heading. With nothing said yet,
/// or by a server too old to say, the row is as it always was.
({String? help, bool offered}) engineRow(
  ServerStreaming? streaming, {
  required bool Function(ServerStreaming) offers,
  String? help,
  required String lacking,
  EngineReason? shared,
}) => switch (streaming) {
  ServerStreaming(configured: false) => (help: null, offered: false),
  ServerStreaming(connected: false) => (help: help, offered: true),
  final engine? when !offers(engine) => (
    help: shared == EngineReason.lacking ? null : lacking,
    offered: false,
  ),
  _ => (help: help, offered: true),
};

/// The gapless switch's help. A switch that is on and doing nothing has
/// to say why, and which why. The engine's whys (none, away, no rendered
/// queues) are its group's line, as for crossfade and levelling beside
/// it; what is left is [status], what the last mint or load said, which
/// health cannot give: the server momentarily too busy, this browser
/// unable to play one, or nothing rendered being anything this browser
/// decodes. Only some of those go away on their own, so one sentence for
/// all of them would send somebody to change a setting that is not the
/// problem.
String? webGaplessHelp(
  AppLocalizations l10n,
  ServerStreaming? streaming,
  String? status,
) => switch (streaming) {
  ServerStreaming(configured: false) ||
  ServerStreaming(connected: false) ||
  ServerStreaming(timelines: false) => null,
  _ => switch (status) {
    null => null,
    'transcode-limited' => l10n.settingsWebGaplessBusy,
    'gapless-unsupported' => l10n.settingsWebGaplessBrowser,
    'gapless-format' => l10n.settingsWebGaplessFormat,
    _ => l10n.settingsWebGaplessUnavailable,
  },
};

/// A heading over a run of related rows, and the one line under it when
/// a [note] says why several of them are disabled or waiting. With no
/// [title] the rows keep the group's spacing and go unheaded.
class _Group extends StatelessWidget {
  const _Group({required this.children, this.title, this.note});

  final String? title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SettingGroupFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Top only: the header owns the space under itself, and a screen
        // adding its own on top of that is what makes one section sit
        // differently from the next.
        Padding(
          padding: EdgeInsets.only(top: WaxLayout.of(context).sectionGap),
          child: switch (title) {
            final title? => SectionHeader(title: title),
            null => null,
          },
        ),
        if (note case final note?)
          SettingGroupNote(
            child: Padding(
              padding: const EdgeInsets.only(bottom: WaxSpace.s8),
              child: WaxProse(
                note,
                style: WaxType.bodySmall.copyWith(
                  color: WaxColors.of(context).textTertiary,
                ),
              ),
            ),
          ),
        ...children,
      ],
    ),
  );
}

/// Whether every id in [ids] anchors a row one of [groups] draws.
bool _drawsEvery(List<Widget> groups, Iterable<String> ids) => {
  for (final group in groups.whereType<_Group>())
    for (final row in group.children.whereType<SettingAnchor>()) row.id,
}.containsAll(ids);

// --- Playback ----------------------------------------------------------------

class _PlaybackBody extends ConsumerWidget {
  const _PlaybackBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // The design system spells a duration the same way everywhere it is
    // read out, and a skip interval is one of those.
    final wax = context.waxL10n;
    final prefs = ref.watch(prefsControllerProvider).value;
    final prefsController = ref.read(prefsControllerProvider.notifier);
    final streaming = ref.watch(serverStreamingProvider);
    final mobile = ref.watch(mobileProvider);
    // The rows a feature of the engine serves, by setting id, with what
    // each needs of it, group by group: `shared`, each group's line and
    // each row read them here, and an id no row draws fails the assert
    // under the column.
    final spoken = <String, bool Function(ServerStreaming)>{
      // Trimming reads the silence the engine's analysis finds.
      'trim-default': (engine) => engine.fileTools,
      'boost-default': (engine) => engine.voiceBoost,
    };
    // Crossfade and levelling shape the queue the engine renders as one
    // stream, which is also what the browser's gapless switch plays.
    final casting = <String, bool Function(ServerStreaming)>{
      'crossfade': (engine) => engine.timelines,
      'replay-gain': (engine) => engine.timelines,
      if (kIsWeb) 'web-gapless': (engine) => engine.timelines,
    };
    final needs = {...spoken, ...casting};
    final shared = sharedEngineReason(streaming, needs.values.toList());
    // A reason the rows share is said once in each group holding one of
    // them, under its heading, where a search landing on a row can read
    // it; a group whose rows the engine serves in full says nothing.
    String? noteFor(Iterable<bool Function(ServerStreaming)> rows) =>
        switch ((shared, streaming)) {
          (EngineReason.none, _) => l10n.settingsNeedsEngine,
          (EngineReason.away, _) => l10n.settingsEngineUnreachable,
          (EngineReason.lacking, final engine?)
              when rows.any((offers) => !offers(engine)) =>
            l10n.settingsEngineLacksThese,
          _ => null,
        };
    ({String? help, bool offered}) rowFor(String id, [String? help]) =>
        engineRow(
          streaming,
          offers: needs[id]!,
          help: help,
          lacking: l10n.settingsEngineLacksThis,
          shared: shared,
        );
    final trim = rowFor('trim-default');
    final boost = rowFor('boost-default');
    final crossfade = rowFor('crossfade', l10n.settingsCrossfadeHelp);
    final replayGain = rowFor('replay-gain');
    final webGapless = kIsWeb ? rowFor('web-gapless') : null;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: l10n.settingsGroupSpokenWord,
          note: noteFor(spoken.values),
          children: <Widget>[
            // The engine's rows first, right under the line that says why
            // they are disabled, so a search landing on one shows it.
            SettingAnchor(
              id: 'trim-default',
              child: WaxSettingRow(
                title: l10n.settingsTrimDefaultTitle,
                help: trim.help,
                control: WaxSwitch(
                  value: ref.watch(trimSilenceDefaultProvider),
                  label: l10n.settingsTrimDefaultTitle,
                  semanticsId: SemanticsIds.setting('trim-default'),
                  onChanged: trim.offered
                      ? ref.read(trimSilenceDefaultProvider.notifier).set
                      : null,
                ),
              ),
            ),
            SettingAnchor(
              id: 'boost-default',
              child: WaxSettingRow(
                title: l10n.settingsBoostDefaultTitle,
                help: boost.help,
                control: WaxSwitch(
                  value: ref.watch(voiceBoostDefaultProvider),
                  label: l10n.settingsBoostDefaultTitle,
                  semanticsId: SemanticsIds.setting('boost-default'),
                  onChanged: boost.offered
                      ? ref.read(voiceBoostDefaultProvider.notifier).set
                      : null,
                ),
              ),
            ),
            SettingAnchor(
              id: 'skip-back',
              child: WaxSettingRow(
                title: l10n.settingsSkipBackTitle,
                control: WaxChoice<int>(
                  value: ref.watch(skipBackSecondsProvider),
                  options: SkipBackSeconds.options,
                  labelFor: (seconds) =>
                      wax.spellDuration(Duration(seconds: seconds)),
                  label: l10n.settingsSkipBackTitle,
                  semanticsId: SemanticsIds.setting('skip-back'),
                  optionSemanticsIdFor: (seconds) =>
                      SemanticsIds.settingOption('skip-back', seconds),
                  onChanged: ref.read(skipBackSecondsProvider.notifier).set,
                ),
              ),
            ),
            SettingAnchor(
              id: 'skip-forward',
              child: WaxSettingRow(
                title: l10n.settingsSkipForwardTitle,
                control: WaxChoice<int>(
                  value: ref.watch(skipForwardSecondsProvider),
                  options: SkipForwardSeconds.options,
                  labelFor: (seconds) =>
                      wax.spellDuration(Duration(seconds: seconds)),
                  label: l10n.settingsSkipForwardTitle,
                  semanticsId: SemanticsIds.setting('skip-forward'),
                  onChanged: ref.read(skipForwardSecondsProvider.notifier).set,
                ),
              ),
            ),
            SettingAnchor(
              id: 'podcast-speed',
              child: WaxSettingRow(
                title: l10n.settingsPodcastSpeedTitle,
                control: WaxChoice<double>(
                  value: ref.watch(podcastSpeedProvider),
                  options: SpeedSetting.options,
                  labelFor: l10n.formatSpeed,
                  label: l10n.settingsPodcastSpeedTitle,
                  semanticsId: SemanticsIds.setting('podcast-speed'),
                  onChanged: ref.read(podcastSpeedProvider.notifier).set,
                ),
              ),
            ),
            SettingAnchor(
              id: 'book-speed',
              child: WaxSettingRow(
                title: l10n.settingsBookSpeedTitle,
                control: WaxChoice<double>(
                  value: ref.watch(bookSpeedProvider),
                  options: SpeedSetting.options,
                  labelFor: l10n.formatSpeed,
                  label: l10n.settingsBookSpeedTitle,
                  semanticsId: SemanticsIds.setting('book-speed'),
                  onChanged: ref.read(bookSpeedProvider.notifier).set,
                ),
              ),
            ),
            SettingAnchor(
              id: 'smart-rewind',
              child: WaxSettingRow(
                title: l10n.settingsSmartRewindTitle,
                control: WaxChoice<SmartRewind>(
                  value: ref.watch(smartRewindProvider),
                  options: SmartRewind.values,
                  labelFor: (value) => value.labelOf(l10n),
                  label: l10n.settingsSmartRewindTitle,
                  semanticsId: SemanticsIds.setting('smart-rewind'),
                  onChanged: ref.read(smartRewindProvider.notifier).set,
                ),
              ),
            ),
          ],
        ),
        _Group(
          title: l10n.settingsGroupPlayer,
          children: <Widget>[
            // Here rather than under "Starting on its own": that group
            // is the gestureless-start gate for a Connect handover, and
            // two adjacent switches - one "let another device start me",
            // one "keep going when the queue ends" - would read as two
            // words for the same thing. This one is about continuing.
            SettingAnchor(
              id: 'keep-playing-similar',
              child: WaxSettingRow(
                title: l10n.settingsKeepPlayingTitle,
                control: WaxSwitch(
                  value: ref.watch(keepPlayingSimilarProvider),
                  label: l10n.settingsKeepPlayingTitle,
                  semanticsId: SemanticsIds.setting('keep-playing-similar'),
                  onChanged: ref.read(keepPlayingSimilarProvider.notifier).set,
                ),
              ),
            ),
            SettingAnchor(
              id: 'car-button',
              child: WaxSettingRow(
                title: l10n.settingsCarButtonTitle,
                control: WaxSwitch(
                  value: ref.watch(carModeButtonProvider),
                  label: l10n.settingsCarButtonTitle,
                  semanticsId: SemanticsIds.setting('car-button'),
                  onChanged: ref.read(carModeButtonProvider.notifier).set,
                ),
              ),
            ),
            // Desktop alone: this is a machine left playing in a room,
            // which a phone or a tab is not. Absent rather than
            // disabled, since a switch with nothing behind it lies.
            if (ref.watch(desktopProvider))
              SettingAnchor(
                id: 'visualizer-idle',
                child: WaxSettingRow(
                  title: l10n.settingsVisualizerIdleTitle,
                  control: WaxSwitch(
                    value: ref.watch(visualizerWhenIdleProvider),
                    label: l10n.settingsVisualizerIdleTitle,
                    semanticsId: SemanticsIds.setting('visualizer-idle'),
                    onChanged: ref
                        .read(visualizerWhenIdleProvider.notifier)
                        .set,
                  ),
                ),
              ),
            // A screen left on the player; a phone locks its own instead.
            if (kIsWeb || ref.watch(desktopProvider))
              SettingAnchor(
                id: 'artwork-cycle',
                child: WaxSettingRow(
                  title: l10n.settingsArtworkCycleTitle,
                  control: WaxSwitch(
                    value: ref.watch(playerArtworkCycleProvider),
                    label: l10n.settingsArtworkCycleTitle,
                    semanticsId: SemanticsIds.setting('artwork-cycle'),
                    onChanged: ref
                        .read(playerArtworkCycleProvider.notifier)
                        .set,
                  ),
                ),
              ),
          ],
        ),
        _Group(
          // Named for what it applies to rather than for what it is.
          // Nothing local reads either value yet on the platforms that
          // play item by item, and a "Crossfade" heading over a control
          // that does nothing on this device is the kind of promise a
          // settings screen must not make. A browser playing gaplessly
          // rides the same server render a cast queue does, so there
          // both values apply here too - which is why the help lines
          // say what they apply to rather than where.
          title: l10n.settingsGroupCasting,
          note: noteFor(casting.values),
          children: <Widget>[
            SettingAnchor(
              id: 'crossfade',
              child: WaxSettingRow(
                title: l10n.settingsCrossfadeTitle,
                help: crossfade.help,
                control: WaxChoice<double>(
                  value: prefs?.crossfadeSeconds ?? 0,
                  options: const <double>[0, 2, 4, 6, 8, 12],
                  labelFor: (seconds) => seconds == 0
                      ? l10n.settingsOptionOff
                      : wax.spellDuration(Duration(seconds: seconds.round())),
                  label: l10n.settingsCrossfadeTitle,
                  semanticsId: SemanticsIds.setting('crossfade'),
                  // Rounded: the options are doubles, and a spec names 6.
                  optionSemanticsIdFor: (seconds) =>
                      SemanticsIds.settingOption('crossfade', seconds.round()),
                  onChanged: prefs == null || !crossfade.offered
                      ? null
                      : (seconds) => saveSetting(
                          context,
                          prefsController.setCrossfadeSeconds(seconds),
                        ),
                ),
              ),
            ),
            SettingAnchor(
              id: 'replay-gain',
              child: WaxSettingRow(
                title: l10n.settingsReplayGainTitle,
                help: replayGain.help,
                control: WaxSwitch(
                  value: prefs?.replayGain ?? false,
                  label: l10n.settingsReplayGainTitle,
                  semanticsId: SemanticsIds.setting('replay-gain'),
                  onChanged: prefs == null || !replayGain.offered
                      ? null
                      : (on) => saveSetting(
                          context,
                          prefsController.setReplayGain(on),
                        ),
                ),
              ),
            ),
            // Browsers only, and here rather than under the player
            // because it is the same rendering the two settings above
            // shape: a queue the server cuts into one stream. Every
            // other platform crosses a boundary without a gap already,
            // so elsewhere this would be a switch between two identical
            // outcomes.
            if (webGapless case final gapless?)
              SettingAnchor(
                id: 'web-gapless',
                child: WaxSettingRow(
                  title: l10n.settingsWebGaplessTitle,
                  help: webGaplessHelp(
                    l10n,
                    streaming,
                    ref.watch(webGaplessStatusProvider),
                  ),
                  // Disabled on a server that renders nothing.
                  control: WaxSwitch(
                    value: ref.watch(webGaplessProvider),
                    label: l10n.settingsWebGaplessTitle,
                    semanticsId: SemanticsIds.setting('web-gapless'),
                    onChanged: gapless.offered
                        ? ref.read(webGaplessProvider.notifier).set
                        : null,
                  ),
                ),
              ),
          ],
        ),
        _Group(
          title: l10n.settingsGroupStartingOnItsOwn,
          children: <Widget>[
            SettingAnchor(
              id: 'autoplay',
              child: WaxSettingRow(
                title: l10n.settingsAutoplayTitle,
                help: l10n.settingsAutoplayHelp,
                control: WaxSwitch(
                  value: prefs?.autoplay ?? true,
                  label: l10n.settingsAutoplayTitle,
                  semanticsId: SemanticsIds.setting('autoplay'),
                  onChanged: prefs == null
                      ? null
                      : (on) => saveSetting(
                          context,
                          prefsController.setAutoplay(on),
                        ),
                ),
              ),
            ),
          ],
        ),
        _Group(
          title: l10n.settingsGroupStreaming,
          // Its rows need an engine and never a feature of one, so only a
          // missing or an away engine is ever its line.
          note: noteFor(const []),
          children: <Widget>[
            // One choice where the platform cannot tell a metered
            // connection apart (desktop, web); the mobile platforms
            // split the decision by connection.
            if (mobile) ...<Widget>[
              _streamQualityRow(
                id: 'stream-quality-wifi',
                title: l10n.settingsStreamQualityWifiTitle,
                help: l10n.settingsStreamQualityHelp,
                provider: streamQualityWifiProvider,
              ),
              _streamQualityRow(
                id: 'stream-quality-metered',
                title: l10n.settingsStreamQualityMeteredTitle,
                help: l10n.settingsStreamQualityHelp,
                provider: streamQualityMeteredProvider,
              ),
            ] else
              _streamQualityRow(
                id: 'stream-quality-wifi',
                title: l10n.settingsStreamQualityTitle,
                help: l10n.settingsStreamQualityHelp,
                provider: streamQualityWifiProvider,
              ),
          ],
        ),
        if (!kIsWeb)
          _Group(
            title: l10n.settingsGroupData,
            children: <Widget>[
              SettingAnchor(
                id: 'preload-wifi',
                child: WaxSettingRow(
                  title: l10n.settingsPreloadWifiTitle,
                  control: WaxSwitch(
                    value: ref.watch(preloadOnWifiOnlyProvider),
                    label: l10n.settingsPreloadWifiTitle,
                    semanticsId: SemanticsIds.setting('preload-wifi'),
                    onChanged: ref.read(preloadOnWifiOnlyProvider.notifier).set,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
    assert(
      _drawsEvery(body.children, needs.keys),
      'an engine row is declared above and drawn in no group',
    );
    return body;
  }

  /// A stream quality is a bitrate the engine's transcode keeps to: a
  /// server without one serves originals whatever is chosen.
  Widget _streamQualityRow({
    required String id,
    required String title,
    required String help,
    required NotifierProvider<EnumSetting<StreamQuality>, StreamQuality>
    provider,
  }) => Consumer(
    builder: (context, ref, _) {
      final l10n = context.l10n;
      final row = engineRow(
        ref.watch(serverStreamingProvider),
        offers: (_) => true,
        help: help,
        lacking: help,
      );
      return SettingAnchor(
        id: id,
        child: WaxSettingRow(
          title: title,
          help: row.help,
          control: WaxChoice<StreamQuality>(
            value: ref.watch(provider),
            options: StreamQuality.values,
            labelFor: (quality) => switch (quality) {
              StreamQuality.auto => l10n.settingsStreamQualityAuto,
              StreamQuality.high => l10n.settingsStreamQualityHigh,
              StreamQuality.normal => l10n.settingsStreamQualityNormal,
              StreamQuality.low => l10n.settingsStreamQualityLow,
            },
            label: title,
            semanticsId: SemanticsIds.setting(id),
            optionSemanticsIdFor: (quality) =>
                SemanticsIds.settingOption(id, quality.name),
            onChanged: row.offered ? ref.read(provider.notifier).set : null,
          ),
        ),
      );
    },
  );
}

// --- Library and metadata ----------------------------------------------------

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final prefs = ref.watch(prefsControllerProvider).value;
    final prefsController = ref.read(prefsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: l10n.settingsGroupBrowsing,
          children: <Widget>[
            SettingAnchor(
              id: 'technical-details',
              child: WaxSettingRow(
                title: l10n.settingsTechnicalDetailsTitle,
                control: WaxSwitch(
                  value: ref.watch(technicalDetailsProvider),
                  label: l10n.settingsTechnicalDetailsTitle,
                  semanticsId: SemanticsIds.setting('technical-details'),
                  onChanged: ref.read(technicalDetailsProvider.notifier).set,
                ),
              ),
            ),
            SettingAnchor(
              id: 'browse-unknown',
              child: WaxSettingRow(
                title: l10n.settingsBrowseUnknownTitle,
                control: WaxSwitch(
                  value: prefs?.browseShowUnknown ?? true,
                  label: l10n.settingsBrowseUnknownTitle,
                  semanticsId: SemanticsIds.setting('browse-unknown'),
                  onChanged: prefs == null
                      ? null
                      : (on) => saveSetting(
                          context,
                          prefsController.setBrowseShowUnknown(on),
                        ),
                ),
              ),
            ),
          ],
        ),
        _Group(
          title: l10n.settingsBrowseOrderTitle,
          children: <Widget>[
            for (final dimension in MusicDimension.values)
              SettingAnchor(
                id: 'browse-sort-${dimension.segment}',
                child: WaxSettingRow(
                  title: dimension.titleOf(l10n),
                  control: WaxChoice<FacetSort>(
                    value:
                        prefs?.browseSortFor(dimension.wireName) ??
                        defaultBrowseSort(dimension),
                    options: FacetSort.values,
                    labelFor: (sort) => browseSortLabel(l10n, sort),
                    // Five controls in one group need telling apart.
                    label: l10n.settingsBrowseOrderChoiceLabel(
                      dimension.titleOf(l10n),
                    ),
                    semanticsId: SemanticsIds.setting(
                      'browse-sort-${dimension.segment}',
                    ),
                    onChanged: prefs == null
                        ? null
                        : (value) => saveSetting(
                            context,
                            prefsController.setBrowseSort(
                              dimension.wireName,
                              value,
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
        _Group(
          title: l10n.settingsGroupAdding,
          children: <Widget>[
            SettingAnchor(
              id: 'identify-uploads',
              child: WaxSettingRow(
                title: l10n.settingsIdentifyUploadsTitle,
                // Printed, not a tip: the title names no third party.
                help: l10n.settingsIdentifyUploadsHelp,
                control: WaxSwitch(
                  value: !(prefs?.identifyOptOut ?? false),
                  label: l10n.settingsIdentifyUploadsTitle,
                  semanticsId: SemanticsIds.setting('identify-uploads'),
                  onChanged: prefs == null
                      ? null
                      : (on) => saveSetting(
                          context,
                          prefsController.setIdentifyOptOut(!on),
                        ),
                ),
              ),
            ),
          ],
        ),
        const _LibraryAccessGroup(),
      ],
    );
  }
}

/// What this account can see, read-only, so a household member can
/// answer "why can I not find that album" without asking. The grant is
/// the administrator's, so a control here would be a refusal waiting.
/// The answer is the row's value, all or a count; the row holds its
/// place while the grant is first read, keeps its last answer through a
/// re-read that is in flight or fails, and a read that fails with no
/// answer yet says so under it.
class _LibraryAccessGroup extends ConsumerWidget {
  const _LibraryAccessGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final account = ref.watch(myAccountProvider);
    final access = account.value?.libraryAccess;
    final label = switch (access) {
      null => null,
      LibraryAccess(mode: 'all') => l10n.settingsLibraryAccessEverything,
      _ => l10n.settingsLibraryAccessSome(access.libraryPids.length),
    };
    final help = label == null && account.hasError
        ? l10n.settingsLibraryAccessError
        : null;
    return _Group(
      title: l10n.settingsGroupAccess,
      children: <Widget>[
        SettingAnchor(
          id: 'library-access',
          child: Semantics(
            identifier: SemanticsIds.setting('library-access'),
            child: WaxSettingRow(
              title: l10n.settingsLibraryAccessTitle,
              help: help,
              glyph: WaxIcons.albums,
              control: label == null
                  ? const SizedBox.shrink()
                  : Text(
                      label,
                      style: WaxType.body.copyWith(
                        color: WaxColors.of(context).textSecondary,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Downloads and storage ---------------------------------------------------

class _DownloadsBody extends ConsumerWidget {
  const _DownloadsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!kIsWeb) ...<Widget>[
          _Group(
            title: l10n.settingsGroupDownloads,
            children: <Widget>[
              SettingAnchor(
                id: 'downloads-wifi',
                child: WaxSettingRow(
                  title: l10n.settingsDownloadsWifiTitle,
                  control: WaxSwitch(
                    value: ref.watch(downloadsOnWifiOnlyProvider),
                    label: l10n.settingsDownloadsWifiTitle,
                    semanticsId: SemanticsIds.setting('downloads-wifi'),
                    onChanged: ref
                        .read(downloadsOnWifiOnlyProvider.notifier)
                        .set,
                  ),
                ),
              ),
              SettingAnchor(
                id: 'auto-remove-finished',
                child: WaxSettingRow(
                  title: l10n.settingsAutoRemoveFinishedTitle,
                  help: l10n.settingsAutoRemoveFinishedHelp,
                  control: WaxSwitch(
                    value: ref.watch(autoRemoveFinishedProvider),
                    label: l10n.settingsAutoRemoveFinishedTitle,
                    semanticsId: SemanticsIds.setting('auto-remove-finished'),
                    onChanged: ref
                        .read(autoRemoveFinishedProvider.notifier)
                        .set,
                  ),
                ),
              ),
              // Only where it decides something.
              if (ref.watch(autoRemoveFinishedProvider))
                WaxSettingRow(
                  title: l10n.settingsAutoRemoveAfterTitle,
                  control: WaxChoice<int>(
                    value: ref.watch(autoRemoveFinishedAfterHoursProvider),
                    options: AutoRemoveFinishedAfterHours.options,
                    labelFor: (hours) => l10n.spellHours(hours),
                    label: l10n.settingsAutoRemoveAfterTitle,
                    semanticsId: SemanticsIds.setting('auto-remove-after'),
                    onChanged: ref
                        .read(autoRemoveFinishedAfterHoursProvider.notifier)
                        .set,
                  ),
                ),
              SettingAnchor(
                id: 'downloads-manager',
                child: WaxOptionRow(
                  title: l10n.settingsDownloadsManagerTitle,
                  glyph: WaxIcons.downloads,
                  semanticsId: SemanticsIds.setting('downloads-manager'),
                  trailing: const WaxIcon(WaxIcons.forward, size: 16),
                  onTap: () => context.go(WaxRoute.downloads),
                ),
              ),
            ],
          ),
        ],
        _Group(
          title: l10n.settingsGroupStorage,
          children: const <Widget>[_ArtworkCacheRow()],
        ),
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
    final messenger = ref.read(shellMessengerProvider.notifier);
    final cleared = context.l10n.settingsArtworkCacheCleared;
    setState(() => _clearing = true);
    try {
      await ref.read(artworkStoreProvider).forgetEverything();
      ref.read(paletteCacheProvider).clear();
      messenger.show(cleared);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingAnchor(
      id: 'artwork-cache',
      child: WaxSettingRow(
        title: l10n.settingsArtworkCacheTitle,
        glyph: WaxIcons.albums,
        control: WaxButton(
          label: l10n.settingsArtworkCacheClear,
          kind: WaxButtonKind.tonal,
          onPressed: _clearing ? null : () => _clear(),
          semanticsId: SemanticsIds.setting('artwork-cache'),
        ),
      ),
    );
  }
}

// --- Devices and casting -----------------------------------------------------

class _DevicesBody extends ConsumerWidget {
  const _DevicesBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: l10n.settingsGroupWhereSoundComesOut,
          children: <Widget>[
            SettingAnchor(
              id: 'endpoints',
              child: WaxOptionRow(
                title: l10n.settingsEndpointsTitle,
                glyph: WaxIcons.cast,
                semanticsId: SemanticsIds.setting('endpoints'),
                trailing: const WaxIcon(WaxIcons.forward, size: 16),
                // The same picker the deck bar opens, from the same
                // source: nothing local is being sent, so this lists and
                // controls rather than hands anything over.
                onTap: () => showDevicePicker(context, from: CastSource.here),
              ),
            ),
            SettingAnchor(
              id: 'cast-check',
              child: WaxOptionRow(
                title: l10n.settingsCastCheckTitle,
                glyph: WaxIcons.warning,
                semanticsId: SemanticsIds.setting('cast-check'),
                trailing: const WaxIcon(WaxIcons.forward, size: 16),
                onTap: () => showCastPreflight(context),
              ),
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
    final l10n = context.l10n;
    final prefs = ref.watch(prefsControllerProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The registry names the group; the controls inside it keep the
        // per-service handles the e2e suite already steers by.
        SettingAnchor(
          id: 'scrobbling',
          child: Semantics(
            identifier: SemanticsIds.setting('scrobbling'),
            child: const ScrobblingSection(),
          ),
        ),
        _Group(
          title: l10n.settingsGroupWhatGetsScrobbled,
          children: <Widget>[
            SettingAnchor(
              id: 'radio-scrobbling',
              child: WaxSettingRow(
                title: l10n.settingsRadioScrobblingTitle,
                control: WaxSwitch(
                  value: !(prefs?.radioScrobbleOptOut ?? false),
                  label: l10n.settingsRadioScrobblingTitle,
                  semanticsId: SemanticsIds.radioScrobbleSwitch,
                  onChanged: prefs == null
                      ? null
                      : (on) => saveSetting(
                          context,
                          ref
                              .read(prefsControllerProvider.notifier)
                              .setRadioScrobbleOptOut(!on),
                        ),
                ),
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
        SettingAnchor(
          id: 'notifications',
          child: Semantics(
            identifier: SemanticsIds.setting('notifications'),
            child: const PersonalNotificationTargetsSection(),
          ),
        ),
      ],
    );
  }
}

// --- Appearance --------------------------------------------------------------

/// The tag that stands for "no stored choice" in the language picker.
///
/// A sentinel rather than a null option: the picker rides `showMenu`,
/// which answers null when it is dismissed, so a null value would make
/// choosing Match the system indistinguishable from closing the menu.
/// Not a parseable BCP 47 tag, so it can never collide with a real one.
const _systemLocaleTag = 'system';

/// Which option a stored preference stands for.
///
/// The same reading the app itself does, so the row cannot disagree with
/// what is on screen: `es-MX` is a Spanish this build has and reads as
/// Spanish, and a tag it cannot draw reads as the system - which is what
/// the app is then following, because [localeOverrideProvider] answers
/// null for exactly the same tags.
String _languageValue(String? stored) =>
    (stored == null ? null : supportedLocaleFor(stored))?.toLanguageTag() ??
    _systemLocaleTag;

class _AppearanceBody extends ConsumerWidget {
  const _AppearanceBody();

  static String _themeLabel(AppLocalizations l10n, ThemePref theme) =>
      switch (theme) {
        ThemePref.system => l10n.settingsMatchTheSystem,
        ThemePref.dark => l10n.settingsThemeDark,
        ThemePref.light => l10n.settingsThemeLight,
        ThemePref.oled => l10n.settingsThemeOled,
      };

  static String _densityLabel(AppLocalizations l10n, WaxDensity density) =>
      switch (density) {
        WaxDensity.comfortable => l10n.settingsDensityComfortable,
        WaxDensity.compact => l10n.settingsDensityCompact,
      };

  static String _gridLabel(AppLocalizations l10n, WaxGridSize size) =>
      switch (size) {
        WaxGridSize.small => l10n.settingsGridSmall,
        WaxGridSize.medium => l10n.settingsGridMedium,
        WaxGridSize.large => l10n.settingsGridLarge,
      };

  static String _captionLabel(AppLocalizations l10n, WaxCaptionMode mode) =>
      switch (mode) {
        WaxCaptionMode.always => l10n.settingsCaptionsAlways,
        WaxCaptionMode.onHover => l10n.settingsCaptionsOnHover,
      };

  static String _languageLabel(AppLocalizations l10n, String tag) =>
      tag == _systemLocaleTag
      ? l10n.settingsMatchTheSystem
      : languageEndonyms[tag] ?? tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final prefs = ref.watch(prefsControllerProvider).value;
    final prefsController = ref.read(prefsControllerProvider.notifier);
    // The hardware question, not the this-second one: a touchscreen
    // laptop is in touch highlight mode for as long as the last input
    // was a finger, and greying the row there would be the app telling
    // a machine with a mouse on it that it has no pointer.
    final hasPointer = ref.watch(mouseConnectedProvider);
    // Derived from the locales the app resolves, so the picker cannot
    // offer one it has no strings for: a third ARB pair is the only edit
    // adding a language takes, beside its endonym.
    final languageTags = <String>[
      _systemLocaleTag,
      for (final locale in appSupportedLocales) locale.toLanguageTag(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Untitled: a heading over one row says that row's title twice.
        // Its scope tip says the language follows the account, unlike
        // everything under This device.
        _Group(
          children: <Widget>[
            SettingAnchor(
              id: 'language',
              child: WaxSettingRow(
                title: l10n.settingsLanguageTitle,
                info: l10n.settingsScopeAccountHelp,
                control: WaxChoice<String>(
                  value: _languageValue(prefs?.locale),
                  options: languageTags,
                  labelFor: (tag) => _languageLabel(l10n, tag),
                  label: l10n.settingsLanguageTitle,
                  semanticsId: SemanticsIds.setting('language'),
                  optionSemanticsIdFor: (tag) =>
                      SemanticsIds.settingOption('language', tag),
                  onChanged: prefs == null
                      ? null
                      : (tag) => saveSetting(
                          context,
                          tag == _systemLocaleTag
                              ? prefsController.clearLocale()
                              : prefsController.setLocale(tag),
                        ),
                ),
              ),
            ),
          ],
        ),
        _Group(
          title: l10n.settingsGroupThisDevice,
          children: <Widget>[
            // This device's, not the account's: the screen being looked at
            // is what a theme is about.
            SettingAnchor(
              id: 'theme',
              child: WaxSettingRow(
                title: l10n.settingsThemeTitle,
                control: WaxChoice<ThemePref>(
                  value: ref.watch(themeSettingProvider),
                  options: ThemePref.values,
                  labelFor: (theme) => _themeLabel(l10n, theme),
                  label: l10n.settingsThemeTitle,
                  semanticsId: SemanticsIds.themeSelect,
                  optionSemanticsIdFor: (theme) =>
                      SemanticsIds.settingOption('theme', theme.name),
                  onChanged: (theme) =>
                      ref.read(themeSettingProvider.notifier).set(theme),
                ),
              ),
            ),
            SettingAnchor(
              id: 'density',
              child: WaxSettingRow(
                title: l10n.settingsDensityTitle,
                control: WaxChoice<WaxDensity>(
                  value: ref.watch(densityProvider),
                  options: WaxDensity.values,
                  labelFor: (density) => _densityLabel(l10n, density),
                  label: l10n.settingsDensityTitle,
                  semanticsId: SemanticsIds.setting('density'),
                  onChanged: ref.read(densityProvider.notifier).set,
                ),
              ),
            ),
            SettingAnchor(
              id: 'grid-size',
              child: WaxSettingRow(
                title: l10n.settingsGridSizeTitle,
                control: WaxChoice<WaxGridSize>(
                  value: ref.watch(gridSizeProvider),
                  options: WaxGridSize.values,
                  labelFor: (size) => _gridLabel(l10n, size),
                  label: l10n.settingsGridSizeTitle,
                  semanticsId: SemanticsIds.setting('grid-size'),
                  onChanged: ref.read(gridSizeProvider.notifier).set,
                ),
              ),
            ),
            SettingAnchor(
              id: 'artwork-glow',
              child: WaxSettingRow(
                title: l10n.settingsArtworkGlowTitle,
                control: WaxSwitch(
                  value: ref.watch(artworkGlowProvider),
                  label: l10n.settingsArtworkGlowTitle,
                  semanticsId: SemanticsIds.setting('artwork-glow'),
                  onChanged: ref.read(artworkGlowProvider.notifier).set,
                ),
              ),
            ),
            SettingAnchor(
              id: 'card-captions',
              child: WaxSettingRow(
                title: l10n.settingsCardCaptionsTitle,
                // Hover is the only way back to a hidden caption, so with
                // no pointer the choice is refused rather than taken and
                // quietly ignored, and the help line says why.
                help: hasPointer
                    ? null
                    : l10n.settingsCardCaptionsNoPointerHelp,
                control: WaxChoice<WaxCaptionMode>(
                  value: ref.watch(cardCaptionsProvider),
                  options: WaxCaptionMode.values,
                  labelFor: (mode) => _captionLabel(l10n, mode),
                  label: l10n.settingsCardCaptionsTitle,
                  semanticsId: SemanticsIds.setting('card-captions'),
                  onChanged: hasPointer
                      ? ref.read(cardCaptionsProvider.notifier).set
                      : null,
                ),
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
    final l10n = context.l10n;
    final platformReduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: l10n.settingsGroupMotion,
          children: <Widget>[
            SettingAnchor(
              id: 'reduce-motion',
              child: WaxSettingRow(
                title: l10n.settingsReduceMotionTitle,
                // Says what it is doing when the platform already asked for
                // this, rather than sitting on with no effect and looking
                // broken. The switch stays live: turning it off here does
                // not put motion back, and the line is what explains that.
                help: platformReduced && !ref.watch(reduceMotionProvider)
                    ? l10n.settingsReduceMotionPlatformHelp
                    : null,
                control: WaxSwitch(
                  value: ref.watch(reduceMotionProvider),
                  label: l10n.settingsReduceMotionTitle,
                  semanticsId: SemanticsIds.setting('reduce-motion'),
                  onChanged: ref.read(reduceMotionProvider.notifier).set,
                ),
              ),
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
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Group(
          title: l10n.settingsServerSummaryTitle,
          children: <Widget>[
            const SettingAnchor(
              id: 'server-summary',
              child: AboutRow(semanticsId: SemanticsIds.serverSummary),
            ),
            // A door rather than a control panel: the switches that used
            // to sit here are decisions about the server, and belong
            // beside the other ones.
            SettingAnchor(
              id: 'admin-console',
              child: WaxOptionRow(
                title: l10n.settingsAdminConsoleOpenTitle,
                glyph: WaxIcons.admin,
                trailing: const WaxIcon(WaxIcons.forward, size: 16),
                semanticsId: SemanticsIds.setting('admin-console'),
                onTap: () => context.go(WaxRoute.admin),
              ),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),
        const SimilarityStatusSection(),
      ],
    );
  }
}
