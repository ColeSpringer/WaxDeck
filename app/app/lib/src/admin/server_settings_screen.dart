import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// What this instance does: who may sign up, whether it accepts writes,
/// what it analyzes, what it transcodes, and how long it keeps things.
///
/// The listener's settings screen keeps a Server section, but it is a
/// door rather than a control panel now: these are decisions about the
/// server, they belong beside the other server decisions, and mixing
/// them into a list of personal preferences made "read-only mode" a
/// sibling of "reduce motion".
class ServerSettingsScreen extends ConsumerWidget {
  const ServerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final settings = ref.watch(adminSettingsProvider);
    return WaxScaffold(
      title: 'Server settings',
      largeTitle: false,
      semanticsId: SemanticsIds.adminSettingsSection,
      onBack: adminBack(context),
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: ReadingColumn(
          // The same cap the listener-facing settings take, for the same
          // reason: these are `WaxSettingRow`s, and past the reading
          // width the help sentence and the switch it belongs to drift
          // so far apart that the pair stops reading as one row.
          child: switch (settings) {
            AsyncError(:final error) => ErrorState(
              title: 'Could not load the server settings',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'Something went wrong reading them.',
              onRetry: () => ref.invalidate(adminSettingsProvider),
            ),
            AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Switches(settings: value),
                SizedBox(height: WaxLayout.of(context).sectionGap),
                const _TranscodingGroup(),
                SizedBox(height: WaxLayout.of(context).sectionGap),
                _RetentionGroup(settings: value),
              ],
            ),
            _ => const SkeletonShapes(shape: SkeletonShape.list),
          },
        ),
      ),
    );
  }
}

class _Switches extends ConsumerWidget {
  const _Switches({required this.settings});

  final AdminSettings settings;

  Future<void> _save(WidgetRef ref, AdminSettings next) async {
    // Taken before the write: a refusal has to be sayable even when the
    // section has been left, and `ref` past its widget throws.
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(adminSettingsProvider.notifier).save(next);
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionGap = WaxLayout.of(context).sectionGap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Access'),
        WaxSettingRow(
          title: 'Open signup',
          help: 'Anyone may request an account; requests wait for approval',
          control: WaxSwitch(
            label: 'Open signup',
            value: settings.signupEnabled,
            semanticsId: SemanticsIds.settingSignupEnabled,
            onChanged: (value) =>
                _save(ref, settings.copyWith(signupEnabled: value)),
          ),
        ),
        WaxSettingRow(
          title: 'Read-only mode',
          help:
              'Refuse every change to library content, server-wide. '
              'Playback, stars, and progress keep working',
          control: WaxSwitch(
            label: 'Read-only mode',
            value: settings.readOnly,
            semanticsId: SemanticsIds.settingReadOnly,
            onChanged: (value) =>
                _save(ref, settings.copyWith(readOnly: value)),
          ),
        ),
        SizedBox(height: sectionGap),
        const SectionHeader(title: 'Analysis'),
        WaxSettingRow(
          title: 'Sonic analysis',
          help:
              'Analyze the library in the background for instant mixes, '
              'similar tracks, and sonic paths',
          control: WaxSwitch(
            label: 'Sonic analysis',
            value: settings.sonicAnalysis,
            semanticsId: SemanticsIds.settingSonicAnalysis,
            onChanged: (value) =>
                _save(ref, settings.copyWith(sonicAnalysis: value)),
          ),
        ),
        SizedBox(height: sectionGap),
        const SectionHeader(title: 'Radio'),
        WaxSettingRow(
          title: 'Look up cover art online',
          help:
              'When a station announces a track this library does not '
              'hold, ask MusicBrainz and the Cover Art Archive for its '
              'cover. This sends the artist and title the station '
              'announced off this server. Off by default; with it off '
              'the player draws the station mark.',
          control: WaxSwitch(
            label: 'Look up cover art online',
            value: settings.radioExternalArt,
            semanticsId: SemanticsIds.settingRadioExternalArt,
            onChanged: (value) =>
                _save(ref, settings.copyWith(radioExternalArt: value)),
          ),
        ),
      ],
    );
  }
}

/// The three transcoding ceilings, each with what it actually bounds.
class _TranscodingGroup extends ConsumerStatefulWidget {
  const _TranscodingGroup();

  @override
  ConsumerState<_TranscodingGroup> createState() => _TranscodingGroupState();
}

class _TranscodingGroupState extends ConsumerState<_TranscodingGroup> {
  final TextEditingController _maxConcurrent = TextEditingController();
  final TextEditingController _maxPerUser = TextEditingController();
  final TextEditingController _defaultKbps = TextEditingController();
  bool _seeded = false;
  bool _busy = false;

  @override
  void dispose() {
    _maxConcurrent.dispose();
    _maxPerUser.dispose();
    _defaultKbps.dispose();
    super.dispose();
  }

  void _seed(TranscodingLimits limits) {
    if (_seeded) return;
    _seeded = true;
    _maxConcurrent.text = '${limits.maxConcurrent}';
    _maxPerUser.text = '${limits.maxConcurrentPerUser}';
    _defaultKbps.text = '${limits.defaultMaxBitrateKbps}';
  }

  Future<void> _save(TranscodingLimits current) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref
          .read(transcodingLimitsProvider.notifier)
          .save(
            TranscodingLimits(
              maxConcurrent:
                  int.tryParse(_maxConcurrent.text.trim()) ??
                  current.maxConcurrent,
              maxConcurrentPerUser:
                  int.tryParse(_maxPerUser.text.trim()) ??
                  current.maxConcurrentPerUser,
              defaultMaxBitrateKbps:
                  int.tryParse(_defaultKbps.text.trim()) ??
                  current.defaultMaxBitrateKbps,
            ),
          );
      messenger.show('Transcoding limits saved');
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final limits = ref.watch(transcodingLimitsProvider).value;
    if (limits == null) return const SizedBox.shrink();
    _seed(limits);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Transcoding'),
        Text(
          'A transcode is what happens when a client cannot play a file as '
          'stored. These bound how many run at once, so a busy evening does '
          'not become a slow one.',
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s12),
        const _TranscodingActivityLine(),
        const SizedBox(height: WaxSpace.s16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: <Widget>[
              // Labelled rather than hinted: all three are seeded from
              // the server, so a hint would never be on screen, and
              // three identical boxes reading "0" is a good way to
              // throttle everybody by putting the per-listener number
              // in the server-wide field.
              WaxTextField(
                label: 'Transcodes at once, server-wide',
                showLabel: true,
                controller: _maxConcurrent,
                semanticsId: SemanticsIds.transcodingMaxConcurrent,
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTextField(
                label: 'Transcodes at once, per listener',
                showLabel: true,
                controller: _maxPerUser,
                semanticsId: SemanticsIds.transcodingMaxPerUser,
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTextField(
                label: 'Default bitrate ceiling (kbps)',
                showLabel: true,
                hint: '0 means no ceiling',
                controller: _defaultKbps,
                semanticsId: SemanticsIds.transcodingDefaultKbps,
              ),
              const SizedBox(height: WaxSpace.s16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: WaxButton(
                  label: 'Save transcoding limits',
                  kind: WaxButtonKind.tonal,
                  semanticsId: SemanticsIds.transcodingSave,
                  onPressed: _busy ? null : () => _save(limits),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the caps are bounding right now, above the caps themselves.
///
/// The copy is careful because the number is: it both under- and
/// over-counts what a person means by "transcoding". A client that pins
/// the source's own format is routed through the engine and charged a
/// session though nothing is re-encoded, and HLS timeline segments are
/// admitted by the streaming engine's own control and never counted
/// here. Saying so is cheaper than an operator drawing the wrong
/// conclusion from a number that looks exact.
class _TranscodingActivityLine extends ConsumerWidget {
  const _TranscodingActivityLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final activity = ref.watch(transcodingActivityProvider);
    final count = activity.value?.activeSessions;
    final headline = switch (activity) {
      AsyncError() => 'The server did not say what is running.',
      _ when count == null => 'Reading what is running...',
      _ when count == 1 => '1 engine-backed stream right now.',
      _ => '$count engine-backed streams right now.',
    };
    const caveat =
        'Counts streams the engine is transcoding or remuxing, '
        'including a client that forced the source\'s own format; HLS '
        'timelines are admitted separately and are not counted here.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The identifier and an explicit label ride the text region
        // alone, MediaListRow's own placement rule: the label is built
        // with excludeSemantics, and wrapping the refresh button too
        // would take it out of reach of a screen reader and the suite
        // both.
        Expanded(
          child: Semantics(
            identifier: SemanticsIds.transcodingActivity,
            container: true,
            label: count != null ? '$headline $caveat' : headline,
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(headline, style: WaxType.titleItem),
                if (count != null)
                  Text(
                    caveat,
                    style: WaxType.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        WaxIconButton(
          glyph: WaxIcons.refresh,
          label: 'Refresh what is running',
          semanticsId: SemanticsIds.transcodingActivityRefresh,
          onPressed: () => ref.invalidate(transcodingActivityProvider),
        ),
      ],
    );
  }
}

/// How long the server keeps what it has stopped needing.
class _RetentionGroup extends ConsumerStatefulWidget {
  const _RetentionGroup({required this.settings});

  final AdminSettings settings;

  @override
  ConsumerState<_RetentionGroup> createState() => _RetentionGroupState();
}

class _RetentionGroupState extends ConsumerState<_RetentionGroup> {
  final TextEditingController _days = TextEditingController();
  final TextEditingController _taskDays = TextEditingController();
  bool _seeded = false;
  bool _busy = false;

  @override
  void dispose() {
    _days.dispose();
    _taskDays.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final messenger = ref.read(shellMessengerProvider.notifier);
    // Refused outright rather than falling back to the stored value and
    // still reporting success. One save writes both windows, so each
    // message names its own field.
    final parsed = int.tryParse(_days.text.trim());
    if (parsed == null || parsed < 0) {
      messenger.show(
        'Purge trashed files after: enter a whole number of days '
        '(0 keeps them until you empty the trash)',
      );
      return;
    }
    final parsedTasks = int.tryParse(_taskDays.text.trim());
    if (parsedTasks == null || parsedTasks < 0) {
      messenger.show(
        'Clear finished tasks after: enter a whole number of days '
        '(0 keeps every finished task)',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(adminSettingsProvider.notifier)
          .save(
            widget.settings.copyWith(
              trashRetentionDays: parsed,
              taskRetentionDays: parsedTasks,
            ),
          );
      // Reflect what was stored, so a padded "007" reads back as 7.
      _days.text = '$parsed';
      _taskDays.text = '$parsedTasks';
      messenger.show('Retention saved');
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_seeded) {
      _seeded = true;
      _days.text = '${widget.settings.trashRetentionDays}';
      _taskDays.text = '${widget.settings.taskRetentionDays}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Retention'),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Seeded from the settings on the first frame, like the
              // transcoding three above, so the same rule applies: a
              // hint on a field that is never empty is never drawn, and
              // two boxes reading 30 and 7 under one header is how the
              // task window gets typed into the trash purge.
              WaxTextField(
                label: 'Purge trashed files after (days)',
                showLabel: true,
                hint: '0 keeps them until the trash is emptied by hand',
                controller: _days,
                semanticsId: SemanticsIds.trashRetentionDays,
              ),
              const SizedBox(height: WaxSpace.s16),
              // Beside the trash rather than on the tasks screen: both
              // are the operator's policy on how long a record outlives
              // its use.
              WaxTextField(
                label: 'Clear finished tasks after (days)',
                showLabel: true,
                hint: '0 keeps every finished task',
                controller: _taskDays,
                semanticsId: SemanticsIds.taskRetentionDays,
              ),
              const SizedBox(height: WaxSpace.s16),
              WaxButton(
                label: 'Save retention',
                kind: WaxButtonKind.tonal,
                semanticsId: SemanticsIds.trashRetentionSave,
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
