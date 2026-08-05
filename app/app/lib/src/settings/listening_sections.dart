import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'prefs_controller.dart';

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
    final textTheme = Theme.of(context).textTheme;
    final prefs = ref.watch(prefsControllerProvider).value;
    final optedOut = prefs?.sharedStatsOptOut ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Listening', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        Semantics(
          identifier: SemanticsIds.sharedStatsSwitch,
          child: SwitchListTile(
            key: const Key(SemanticsIds.sharedStatsSwitch),
            secondary: const Icon(Icons.groups_outlined),
            title: const Text('Include me in server-wide stats'),
            subtitle: const Text(
              'Counts your listening into the shared year in review',
            ),
            value: !optedOut,
            onChanged: prefs == null
                ? null
                : (include) => ref
                      .read(prefsControllerProvider.notifier)
                      .setSharedStatsOptOut(!include),
          ),
        ),
        Semantics(
          identifier: SemanticsIds.timezoneEdit,
          label: 'Timezone',
          button: true,
          child: ListTile(
            key: const Key(SemanticsIds.timezoneEdit),
            leading: const Icon(Icons.schedule),
            title: const Text('Timezone'),
            subtitle: Text(prefs?.timezone ?? 'Server default'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: prefs == null
                ? null
                : () => _editTimezone(context, prefs.timezone),
          ),
        ),
        Semantics(
          identifier: SemanticsIds.openShareLinks,
          label: 'Share links',
          button: true,
          child: ListTile(
            key: const Key(SemanticsIds.openShareLinks),
            leading: const Icon(Icons.link),
            title: const Text('Share links'),
            subtitle: const Text('Public links you have handed out'),
            trailing: const Icon(Icons.chevron_right),
            // Gone to, not pushed: the location is declared beneath
            // settings now, so `go` builds this row's own screen under
            // it and the address bar follows the hop (8.3).
            onTap: () => context.go(WaxRoute.shares),
          ),
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
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Timezone'),
      content: TextField(
        key: const Key('timezone-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'IANA timezone',
          hintText: 'Europe/Amsterdam',
          helperText:
              'Calendar stats bucket days in this timezone; '
              'empty uses the server default (UTC)',
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: SemanticsIds.timezoneSave,
          label: 'Save',
          button: true,
          child: FilledButton(
            key: const Key(SemanticsIds.timezoneSave),
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
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
    final textTheme = Theme.of(context).textTheme;
    final status = ref.watch(similarityStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sonic similarity', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        switch (status) {
          AsyncData(:final value) => ListTile(
            key: const Key('similarity-status'),
            leading: Icon(
              value.enabled ? Icons.graphic_eq : Icons.power_off_outlined,
            ),
            title: Text(
              value.enabled
                  ? 'Coverage ${value.coveragePct.toStringAsFixed(0)}%'
                  : 'No analysis worker configured',
            ),
            subtitle: Text(
              value.enabled
                  ? '${value.embeddedTracks} of ${value.totalTracks} tracks '
                        'analyzed, ${value.queueDepth} queued'
                  : 'Similar tracks and mixes fall back to metadata',
            ),
          ),
          AsyncError() => ListTile(
            key: const Key('similarity-status'),
            leading: const Icon(Icons.error_outline),
            title: const Text('Could not load similarity status'),
          ),
          _ => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
        },
      ],
    );
  }
}
