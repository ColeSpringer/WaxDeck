import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
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
    final l10n = context.l10n;
    return WaxScaffold(
      title: l10n.adminServerTitle,
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
              title: l10n.adminServerLoadError,
              message: context.explain(error),
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

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    AdminSettings next,
  ) async {
    // Taken before the write: a refusal has to be sayable even when the
    // section has been left, and `ref` past its widget throws.
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    try {
      await ref.read(adminSettingsProvider.notifier).save(next);
    } on WaxDeckApiException catch (error) {
      messenger.show(explainError(l10n, error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionGap = WaxLayout.of(context).sectionGap;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminServerAccessGroup),
        WaxSettingRow(
          title: l10n.adminServerSignupTitle,
          help: l10n.adminServerSignupHelp,
          control: WaxSwitch(
            label: l10n.adminServerSignupTitle,
            value: settings.signupEnabled,
            semanticsId: SemanticsIds.settingSignupEnabled,
            onChanged: (value) =>
                _save(context, ref, settings.copyWith(signupEnabled: value)),
          ),
        ),
        WaxSettingRow(
          title: l10n.adminServerReadOnlyTitle,
          help: l10n.adminServerReadOnlyHelp,
          control: WaxSwitch(
            label: l10n.adminServerReadOnlyTitle,
            value: settings.readOnly,
            semanticsId: SemanticsIds.settingReadOnly,
            onChanged: (value) =>
                _save(context, ref, settings.copyWith(readOnly: value)),
          ),
        ),
        SizedBox(height: sectionGap),
        SectionHeader(title: l10n.adminServerAnalysisGroup),
        WaxSettingRow(
          title: l10n.adminServerSonicTitle,
          help: l10n.adminServerSonicHelp,
          control: WaxSwitch(
            label: l10n.adminServerSonicTitle,
            value: settings.sonicAnalysis,
            semanticsId: SemanticsIds.settingSonicAnalysis,
            onChanged: (value) =>
                _save(context, ref, settings.copyWith(sonicAnalysis: value)),
          ),
        ),
        SizedBox(height: sectionGap),
        SectionHeader(title: l10n.adminServerRadioGroup),
        WaxSettingRow(
          title: l10n.adminServerRadioArtTitle,
          help: l10n.adminServerRadioArtHelp,
          control: WaxSwitch(
            label: l10n.adminServerRadioArtTitle,
            value: settings.radioExternalArt,
            semanticsId: SemanticsIds.settingRadioExternalArt,
            onChanged: (value) =>
                _save(context, ref, settings.copyWith(radioExternalArt: value)),
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
    final l10n = context.l10n;
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
      messenger.show(l10n.adminServerTranscodingSaved);
    } on WaxDeckApiException catch (error) {
      messenger.show(explainRefusal(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final limits = ref.watch(transcodingLimitsProvider).value;
    if (limits == null) return const SizedBox.shrink();
    _seed(limits);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminServerTranscodingGroup),
        Text(
          l10n.adminServerTranscodingBlurb,
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s12),
        const _TranscodingActivityLine(),
        const SizedBox(height: WaxSpace.s16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: <Widget>[
              // These three are what made the label the default: all
              // are seeded from the server, so a hint is never on
              // screen, and three identical boxes reading "0" is a good
              // way to throttle everybody by putting the per-listener
              // number in the server-wide field. What the third one has
              // to say about zero is a helper line for the same reason:
              // a placeholder on a field that always arrives filled is
              // a sentence nobody ever reads.
              WaxTextField(
                label: l10n.adminServerTranscodesMaxLabel,
                keyboardType: TextInputType.number,
                controller: _maxConcurrent,
                semanticsId: SemanticsIds.transcodingMaxConcurrent,
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTextField(
                label: l10n.adminServerTranscodesPerUserLabel,
                keyboardType: TextInputType.number,
                controller: _maxPerUser,
                semanticsId: SemanticsIds.transcodingMaxPerUser,
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTextField(
                label: l10n.adminServerDefaultKbpsLabel,
                helperText: l10n.adminServerDefaultKbpsHint,
                keyboardType: TextInputType.number,
                controller: _defaultKbps,
                semanticsId: SemanticsIds.transcodingDefaultKbps,
              ),
              const SizedBox(height: WaxSpace.s16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: WaxButton(
                  label: l10n.adminServerSaveTranscoding,
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
    final l10n = context.l10n;
    final activity = ref.watch(transcodingActivityProvider);
    final count = activity.value?.activeSessions;
    final headline = switch (activity) {
      AsyncError() => l10n.adminServerActivityUnknown,
      _ when count == null => l10n.adminServerActivityReading,
      _ => l10n.adminServerActivityCount(count),
    };
    final caveat = l10n.adminServerActivityCaveat;
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
            label: count != null
                ? l10n.adminServerActivitySpoken(headline, caveat)
                : headline,
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
          label: l10n.adminServerActivityRefresh,
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
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    // Refused outright rather than falling back to the stored value and
    // still reporting success. One save writes both windows, so each
    // message names its own field.
    final parsed = int.tryParse(_days.text.trim());
    if (parsed == null || parsed < 0) {
      messenger.show(l10n.adminServerTrashDaysInvalid);
      return;
    }
    final parsedTasks = int.tryParse(_taskDays.text.trim());
    if (parsedTasks == null || parsedTasks < 0) {
      messenger.show(l10n.adminServerTaskDaysInvalid);
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
      messenger.show(l10n.adminServerRetentionSaved);
    } on WaxDeckApiException catch (error) {
      messenger.show(explainRefusal(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!_seeded) {
      _seeded = true;
      _days.text = '${widget.settings.trashRetentionDays}';
      _taskDays.text = '${widget.settings.taskRetentionDays}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminServerRetention),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Seeded from the settings on the first frame, like the
              // transcoding three above, so both say what zero means
              // under the box rather than inside it - two boxes reading
              // 30 and 7 under one header is how the task window gets
              // typed into the trash purge.
              WaxTextField(
                label: l10n.adminServerTrashDaysLabel,
                helperText: l10n.adminServerTrashDaysHint,
                keyboardType: TextInputType.number,
                controller: _days,
                semanticsId: SemanticsIds.trashRetentionDays,
              ),
              const SizedBox(height: WaxSpace.s16),
              // Beside the trash rather than on the tasks screen: both
              // are the operator's policy on how long a record outlives
              // its use.
              WaxTextField(
                label: l10n.adminServerTaskDaysLabel,
                helperText: l10n.adminServerTaskDaysHint,
                keyboardType: TextInputType.number,
                controller: _taskDays,
                semanticsId: SemanticsIds.taskRetentionDays,
              ),
              const SizedBox(height: WaxSpace.s16),
              WaxButton(
                label: l10n.adminServerSaveRetention,
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
