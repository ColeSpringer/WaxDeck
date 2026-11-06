import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/async_box_face.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'prefs_controller.dart';
import 'save_setting.dart';
import 'setting_anchor.dart';

/// Listening preferences: shared-stats participation, the stats
/// timezone, and the door into the share-links list.
class ListeningSection extends ConsumerWidget {
  const ListeningSection({super.key});

  Future<void> _editTimezone(BuildContext context, String? current) =>
      showDialog<void>(
        context: context,
        builder: (_) => _TimezoneDialog(initial: current),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final prefs = ref.watch(prefsControllerProvider).value;
    final optedOut = prefs?.sharedStatsOptOut ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.settingsGroupListening),
        SettingAnchor(
          id: 'shared-stats',
          child: WaxSettingRow(
            key: const Key(SemanticsIds.sharedStatsSwitch),
            title: l10n.settingsSharedStatsSwitchTitle,
            help: l10n.settingsSharedStatsHelp,
            glyph: WaxIcons.stats,
            control: WaxSwitch(
              value: !optedOut,
              label: l10n.settingsSharedStatsSwitchTitle,
              semanticsId: SemanticsIds.sharedStatsSwitch,
              onChanged: prefs == null
                  ? null
                  : (include) => saveSetting(
                      context,
                      ref
                          .read(prefsControllerProvider.notifier)
                          .setSharedStatsOptOut(!include),
                    ),
            ),
          ),
        ),
        SettingAnchor(
          id: 'timezone',
          child: WaxOptionRow(
            key: const Key(SemanticsIds.timezoneEdit),
            title: l10n.settingsTimezoneTitle,
            subtitle: prefs?.timezone ?? l10n.settingsTimezoneServerDefault,
            glyph: WaxIcons.clock,
            semanticsId: SemanticsIds.timezoneEdit,
            trailing: const WaxIcon(WaxIcons.edit, size: 16),
            onTap: prefs == null
                ? null
                : () => _editTimezone(context, prefs.timezone),
          ),
        ),
        WaxOptionRow(
          key: const Key(SemanticsIds.openShareLinks),
          title: l10n.settingsShareLinksTitle,
          glyph: WaxIcons.share,
          semanticsId: SemanticsIds.openShareLinks,
          trailing: const WaxIcon(WaxIcons.forward, size: 16),
          // Gone to, not pushed: the location is declared beneath
          // settings now, so `go` builds this row's own screen under
          // it and the address bar follows the hop.
          onTap: () => context.go(WaxRoute.shares),
        ),
      ],
    );
  }
}

/// Timezone editor: a plain text field for the IANA name, saved to the
/// server, whose validation error comes back into the dialog. The
/// simplest honest thing while the app carries no timezone database of
/// its own.
class _TimezoneDialog extends ConsumerStatefulWidget {
  const _TimezoneDialog({required this.initial});

  final String? initial;

  @override
  ConsumerState<_TimezoneDialog> createState() => _TimezoneDialogState();
}

class _TimezoneDialogState extends ConsumerState<_TimezoneDialog> {
  late final _controller = TextEditingController(text: widget.initial ?? '');
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final timezone = _controller.text.trim();
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    try {
      // An emptied field returns to the server default; without an
      // explicit clear path a saved timezone could never be unset.
      if (timezone.isEmpty) {
        await ref.read(prefsControllerProvider.notifier).clearTimezone();
      } else {
        await ref.read(prefsControllerProvider.notifier).setTimezone(timezone);
      }
      navigator.pop();
    } on WaxDeckApiException catch (e) {
      // A refusal keeps the server's sentence (what a timezone name may
      // be is its rule); anything else, a dropped connection included,
      // reads from the table in the app's language.
      setState(() => _error = explainRefusal(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.settingsTimezoneTitle),
      content: WaxTextField(
        key: const Key('timezone-field'),
        controller: _controller,
        label: l10n.settingsTimezoneFieldLabel,
        hint: l10n.settingsTimezoneFieldHint,
        helperText: l10n.settingsTimezoneFieldHelp,
        errorText: _error,
        autofocus: true,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          semanticsId: SemanticsIds.timezoneSave,
          label: l10n.commonSave,
          busy: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Coverage of the sonic-similarity surface, for administrators
/// deciding whether sonic affordances have data behind them.
final similarityStatusProvider = FutureProvider<SimilarityStatus>(
  (ref) => ref.watch(repositoryProvider).getSimilarityStatus(),
);

/// Admin-only status row for the sonic-similarity worker.
class SimilarityStatusSection extends ConsumerWidget {
  const SimilarityStatusSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final status = ref.watch(similarityStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.settingsGroupSonicSimilarity),
        switch (status) {
          AsyncData(:final value) => WaxOptionRow(
            key: const Key('similarity-status'),
            glyph: value.enabled ? WaxIcons.waveform : WaxIcons.power,
            title: value.enabled
                ? l10n.settingsSimilarityCoverage(value.coveragePct.round())
                : l10n.settingsSimilarityNoWorker,
            subtitle: value.enabled
                ? l10n.settingsSimilarityAnalyzed(
                    value.totalTracks,
                    value.embeddedTracks,
                    value.queueDepth,
                  )
                : l10n.settingsSimilarityFallback,
          ),
          AsyncValue(hasError: true) => AsyncFailureCard.from(
            status,
            title: l10n.settingsSimilarityError,
            onRetry: () => ref.invalidate(similarityStatusProvider),
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list, count: 1),
        },
      ],
    );
  }
}
