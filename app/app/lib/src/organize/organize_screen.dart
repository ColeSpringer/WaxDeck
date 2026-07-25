import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../shell/semantics_ids.dart';

/// The configured file organization profiles.
final organizeProfilesProvider = FutureProvider<List<OrganizeProfile>>(
  (ref) => ref.watch(repositoryProvider).listOrganizeProfiles(),
);

/// File organization: pick a profile, preview the planned moves, then
/// apply behind a typed confirmation (moves rewrite the library's
/// on-disk layout, so a misclick must not be enough).
class OrganizeScreen extends ConsumerStatefulWidget {
  const OrganizeScreen({super.key});

  @override
  ConsumerState<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends ConsumerState<OrganizeScreen> {
  String? _profile;
  OrganizePlan? _plan;
  OrganizeReport? _report;
  var _busy = false;

  Future<void> _preview(String profile) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _report = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final plan = await ref
          .read(repositoryProvider)
          .previewOrganize(profile: profile);
      if (mounted) setState(() => _plan = plan);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(String profile) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _TypedConfirmDialog(profile: profile),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = await ref
          .read(repositoryProvider)
          .applyOrganize(profile: profile);
      if (mounted) {
        setState(() {
          _report = report;
          _plan = null;
        });
      }
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(organizeProfilesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Organize files')),
      body: switch (profiles) {
        AsyncData(:final value) => _body(context, value),
        AsyncError(:final error) => _errorView(context, error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _errorView(BuildContext context, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load organize profiles';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(organizeProfilesProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, List<OrganizeProfile> profiles) {
    final textTheme = Theme.of(context).textTheme;
    if (profiles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No organize profiles are configured. Profiles are part of the '
            'server configuration; add one there and it appears here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final profile = _profile ?? profiles.first.name;
    final plan = _plan;
    final report = _report;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                identifier: SemanticsIds.organizeProfile,
                child: DropdownButton<String>(
                  key: const Key(SemanticsIds.organizeProfile),
                  value: profile,
                  onChanged: (value) => setState(() {
                    _profile = value;
                    _plan = null;
                    _report = null;
                  }),
                  items: [
                    for (final p in profiles)
                      DropdownMenuItem(value: p.name, child: Text(p.name)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Semantics(
                identifier: SemanticsIds.organizePreview,
                label: 'Preview moves',
                button: true,
                child: OutlinedButton(
                  key: const Key(SemanticsIds.organizePreview),
                  onPressed: _busy ? null : () => _preview(profile),
                  child: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                identifier: SemanticsIds.organizeApply,
                label: 'Apply moves',
                button: true,
                child: FilledButton(
                  key: const Key(SemanticsIds.organizeApply),
                  onPressed: _busy || plan == null
                      ? null
                      : () => _apply(profile),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (plan != null) Expanded(child: _planView(context, plan)),
          if (report != null) _reportView(context, report),
          if (plan == null && report == null)
            Text(
              'Preview shows where the selected profile would move files '
              'before anything happens.',
              style: textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _planView(BuildContext context, OrganizePlan plan) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: SemanticsIds.organizePlan,
      child: Column(
        key: const Key(SemanticsIds.organizePlan),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${plan.totalActions} planned moves'
            '${plan.actions.length < plan.totalActions ? ' (showing the first ${plan.actions.length})' : ''}'
            '${plan.tagWrite ? '; tags are rewritten too' : ''}',
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: plan.actions.isEmpty
                ? const Text('Everything is already in place')
                : ListView.builder(
                    itemCount: plan.actions.length,
                    itemBuilder: (context, index) {
                      final action = plan.actions[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(action.from, style: textTheme.bodySmall),
                            Row(
                              children: [
                                Icon(
                                  Icons.subdirectory_arrow_right,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    action.to,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _reportView(BuildContext context, OrganizeReport report) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: SemanticsIds.organizeReport,
      child: Column(
        key: const Key(SemanticsIds.organizeReport),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Moved ${report.moved}, skipped ${report.skipped}, '
            'failed ${report.failed}',
            style: textTheme.titleSmall,
          ),
          for (final failure in report.failures)
            Text(
              '${failure.path}: ${failure.reason}',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
        ],
      ),
    );
  }
}

/// Applying moves files on disk; the user retypes the profile name so
/// the confirmation cannot be clicked through blindly.
class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({required this.profile});

  final String profile;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Apply organize profile?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Files move to their new locations on the server. Type '
            '"${widget.profile}" to confirm.',
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('organize-confirm-field'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Profile name',
              hintText: widget.profile,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: SemanticsIds.organizeConfirm,
          label: 'Confirm apply',
          button: true,
          child: FilledButton(
            key: const Key(SemanticsIds.organizeConfirm),
            onPressed: _controller.text.trim() == widget.profile
                ? () => Navigator.of(context).pop(true)
                : null,
            child: const Text('Apply'),
          ),
        ),
      ],
    );
  }
}
