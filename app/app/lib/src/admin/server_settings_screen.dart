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
              const SizedBox(height: WaxSpace.s24),
              const _TranscodingGroup(),
              const SizedBox(height: WaxSpace.s24),
              _RetentionGroup(settings: value),
            ],
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ),
    );
  }
}

class _Switches extends ConsumerWidget {
  const _Switches({required this.settings});

  final AdminSettings settings;

  Future<void> _save(WidgetRef ref, AdminSettings next) async {
    try {
      await ref.read(adminSettingsProvider.notifier).save(next);
    } on WaxDeckApiException catch (error) {
      ref.read(shellMessengerProvider.notifier).show(error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        const SizedBox(height: WaxSpace.s16),
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
        const SizedBox(height: WaxSpace.s16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: <Widget>[
              WaxTextField(
                label: 'Transcodes at once, server-wide',
                controller: _maxConcurrent,
                semanticsId: SemanticsIds.transcodingMaxConcurrent,
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTextField(
                label: 'Transcodes at once, per listener',
                controller: _maxPerUser,
                semanticsId: SemanticsIds.transcodingMaxPerUser,
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTextField(
                label: 'Default bitrate ceiling (kbps)',
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

/// How long the server keeps what it has stopped needing.
class _RetentionGroup extends ConsumerStatefulWidget {
  const _RetentionGroup({required this.settings});

  final AdminSettings settings;

  @override
  ConsumerState<_RetentionGroup> createState() => _RetentionGroupState();
}

class _RetentionGroupState extends ConsumerState<_RetentionGroup> {
  final TextEditingController _days = TextEditingController();
  bool _seeded = false;
  bool _busy = false;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final messenger = ref.read(shellMessengerProvider.notifier);
    // Refused outright rather than silently falling back to the stored
    // value and still reporting success.
    final parsed = int.tryParse(_days.text.trim());
    if (parsed == null || parsed < 0) {
      messenger.show(
        'Enter a whole number of days (0 keeps them until '
        'you empty the trash)',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(adminSettingsProvider.notifier)
          .save(widget.settings.copyWith(trashRetentionDays: parsed));
      // Reflect what was stored, so a padded "007" reads back as 7.
      _days.text = '$parsed';
      messenger.show('Trash retention saved');
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
              WaxTextField(
                label: 'Purge trashed files after (days)',
                hint: '0 keeps them until the trash is emptied by hand',
                controller: _days,
                semanticsId: SemanticsIds.trashRetentionDays,
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
