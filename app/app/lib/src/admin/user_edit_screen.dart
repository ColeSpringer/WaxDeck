import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../review/review_controller.dart';

/// Editor for one account's roles, access, and permissions. Serves two
/// flows with one shape: editing an existing account, and approving a
/// pending signup (where the same choices ride along with the
/// approval). Pops `true` after any change so the caller can refresh.
class UserEditScreen extends ConsumerStatefulWidget {
  const UserEditScreen({super.key, required this.user, this.approve = false});

  final UserAccount user;

  /// True when this editor approves a pending signup instead of
  /// updating a stored account.
  final bool approve;

  @override
  ConsumerState<UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends ConsumerState<UserEditScreen> {
  late bool _admin = widget.user.roles.contains('admin');
  late bool _disabled = widget.user.disabled;
  late bool _accessAll = widget.user.libraryAccess.mode == 'all';
  late final Set<String> _grantedPids = widget.user.libraryAccess.libraryPids
      .toSet();
  late bool _uploadEnabled = widget.user.uploadEnabled;
  late final TextEditingController _quotaMb = TextEditingController(
    text: widget.user.uploadQuotaBytes == null
        ? ''
        : '${widget.user.uploadQuotaBytes! ~/ (1024 * 1024)}',
  );
  late bool _download = widget.user.permissions.download;
  late bool _delete = widget.user.permissions.delete;
  late bool _explicitContent = widget.user.permissions.explicitContent;
  late bool _sharedOutputs = widget.user.permissions.sharedOutputs;
  late bool _managePodcasts = widget.user.permissions.managePodcasts;
  late final TextEditingController _maxKbps = TextEditingController(
    text: widget.user.permissions.maxTranscodeKbps?.toString() ?? '',
  );
  late final List<TagRule> _tagAllow = List.of(
    widget.user.permissions.tagAllow,
  );
  late final List<TagRule> _tagDeny = List.of(widget.user.permissions.tagDeny);
  var _busy = false;

  @override
  void dispose() {
    _quotaMb.dispose();
    _maxKbps.dispose();
    super.dispose();
  }

  Permissions get _permissions => Permissions(
    download: _download,
    delete: _delete,
    explicitContent: _explicitContent,
    sharedOutputs: _sharedOutputs,
    managePodcasts: _managePodcasts,
    maxTranscodeKbps: int.tryParse(_maxKbps.text.trim()),
    tagAllow: _tagAllow,
    tagDeny: _tagDeny,
  );

  LibraryAccess get _libraryAccess => _accessAll
      ? const LibraryAccess(mode: 'all')
      : LibraryAccess(mode: 'granted', libraryPids: _grantedPids.toList());

  int? get _quotaBytes {
    final mb = int.tryParse(_quotaMb.text.trim());
    return mb == null ? null : mb * 1024 * 1024;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(repositoryProvider);
    final roles = [if (_admin) 'admin' else 'user'];
    try {
      if (widget.approve) {
        await repo.approveSignupRequest(
          widget.user.id,
          roles: roles,
          libraryAccess: _libraryAccess,
          permissions: _permissions,
          uploadEnabled: _uploadEnabled,
          uploadQuotaBytes: _quotaBytes,
        );
      } else {
        await repo.updateUser(
          widget.user.id,
          roles: roles,
          disabled: _disabled,
          libraryAccess: _libraryAccess,
          permissions: _permissions,
          uploadEnabled: _uploadEnabled,
          uploadQuotaBytes: _quotaBytes,
        );
      }
      navigator.pop(true);
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set password'),
        content: TextField(
          key: const Key('user-new-password'),
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('user-set-password-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Set password'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null || password.isEmpty) return;
    try {
      await ref
          .read(repositoryProvider)
          .setUserPassword(widget.user.id, password);
      messenger.showSnackBar(const SnackBar(content: Text('Password set')));
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _revokeSessions() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirm(
      title: 'Sign out everywhere?',
      body:
          'Every session of ${widget.user.username} is revoked '
          'immediately.',
      action: 'Sign out',
    );
    if (!confirmed) return;
    try {
      await ref.read(repositoryProvider).revokeUserSessions(widget.user.id);
      messenger.showSnackBar(const SnackBar(content: Text('Sessions revoked')));
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteUser() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirm(
      title: 'Delete account?',
      body:
          '${widget.user.username} is removed for good, along with its '
          'sessions and preferences. Library files are untouched.',
      action: 'Delete',
    );
    if (!confirmed) return;
    try {
      await ref.read(repositoryProvider).deleteUser(widget.user.id);
      navigator.pop(true);
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('user-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final libraries = ref.watch(librariesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.approve
              ? 'Approve ${widget.user.username}'
              : widget.user.username,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            key: const Key('user-admin-role'),
            title: const Text('Administrator'),
            value: _admin,
            onChanged: (value) => setState(() => _admin = value),
          ),
          if (!widget.approve)
            SwitchListTile(
              key: const Key('user-disabled'),
              title: const Text('Disabled'),
              subtitle: const Text('A disabled account cannot sign in'),
              value: _disabled,
              onChanged: (value) => setState(() => _disabled = value),
            ),
          const SizedBox(height: 8),
          Text('Library access', style: textTheme.titleMedium),
          SwitchListTile(
            key: const Key('user-access-all'),
            title: const Text('All libraries'),
            value: _accessAll,
            onChanged: (value) => setState(() => _accessAll = value),
          ),
          if (!_accessAll)
            for (final library in libraries)
              CheckboxListTile(
                key: Key('user-library-${library.pid}'),
                title: Text(library.name),
                value: _grantedPids.contains(library.pid),
                onChanged: (checked) => setState(() {
                  checked ?? false
                      ? _grantedPids.add(library.pid)
                      : _grantedPids.remove(library.pid);
                }),
              ),
          const SizedBox(height: 8),
          Text('Uploads', style: textTheme.titleMedium),
          SwitchListTile(
            key: const Key('user-upload-enabled'),
            title: const Text('May upload'),
            value: _uploadEnabled,
            onChanged: (value) => setState(() => _uploadEnabled = value),
          ),
          TextField(
            key: const Key('user-upload-quota'),
            controller: _quotaMb,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Upload quota (MB)',
              helperText: 'Empty keeps the server default',
            ),
          ),
          const SizedBox(height: 16),
          Text('Permissions', style: textTheme.titleMedium),
          SwitchListTile(
            key: const Key('perm-download'),
            title: const Text('Download originals'),
            value: _download,
            onChanged: (value) => setState(() => _download = value),
          ),
          SwitchListTile(
            key: const Key('perm-delete'),
            title: const Text('Delete library files'),
            value: _delete,
            onChanged: (value) => setState(() => _delete = value),
          ),
          SwitchListTile(
            key: const Key('perm-explicit'),
            title: const Text('Explicit content'),
            value: _explicitContent,
            onChanged: (value) => setState(() => _explicitContent = value),
          ),
          SwitchListTile(
            key: const Key('perm-shared-outputs'),
            title: const Text('Shared outputs'),
            subtitle: const Text('May play to endpoints others also use'),
            value: _sharedOutputs,
            onChanged: (value) => setState(() => _sharedOutputs = value),
          ),
          SwitchListTile(
            key: const Key('perm-manage-podcasts'),
            title: const Text('Manage podcasts'),
            value: _managePodcasts,
            onChanged: (value) => setState(() => _managePodcasts = value),
          ),
          TextField(
            key: const Key('perm-max-kbps'),
            controller: _maxKbps,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Max transcode kbps',
              helperText: 'Empty keeps the server default',
            ),
          ),
          const SizedBox(height: 16),
          _TagRuleEditor(
            label: 'Content allow rules',
            keyPrefix: 'tag-allow',
            rules: _tagAllow,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          _TagRuleEditor(
            label: 'Content deny rules',
            keyPrefix: 'tag-deny',
            rules: _tagDeny,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('user-save'),
            onPressed: _busy ? null : _save,
            child: Text(widget.approve ? 'Approve' : 'Save'),
          ),
          if (!widget.approve) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('user-set-password'),
              onPressed: _setPassword,
              child: const Text('Set password'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('user-revoke-sessions'),
              onPressed: _revokeSessions,
              child: const Text('Sign out everywhere'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('user-delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _deleteUser,
              child: const Text('Delete account'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Key/value rows for one tag rule list, with add and remove.
class _TagRuleEditor extends StatefulWidget {
  const _TagRuleEditor({
    required this.label,
    required this.keyPrefix,
    required this.rules,
    required this.onChanged,
  });

  final String label;
  final String keyPrefix;

  /// Mutated in place; [onChanged] tells the owner to rebuild.
  final List<TagRule> rules;
  final VoidCallback onChanged;

  @override
  State<_TagRuleEditor> createState() => _TagRuleEditorState();
}

class _TagRuleEditorState extends State<_TagRuleEditor> {
  final _key = TextEditingController();
  final _value = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  void _add() {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    final value = _value.text.trim();
    widget.rules.add(TagRule(key: key, value: value.isEmpty ? null : value));
    _key.clear();
    _value.clear();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final (index, rule) in widget.rules.indexed)
              InputChip(
                key: Key('${widget.keyPrefix}-rule-$index'),
                label: Text(
                  rule.value == null ? rule.key : '${rule.key}=${rule.value}',
                ),
                onDeleted: () {
                  widget.rules.removeAt(index);
                  widget.onChanged();
                },
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: Key('${widget.keyPrefix}-key'),
                controller: _key,
                decoration: const InputDecoration(labelText: 'Tag key'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: Key('${widget.keyPrefix}-value'),
                controller: _value,
                decoration: const InputDecoration(
                  labelText: 'Value (optional)',
                ),
              ),
            ),
            IconButton(
              key: Key('${widget.keyPrefix}-add'),
              tooltip: 'Add rule',
              icon: const Icon(Icons.add),
              onPressed: _add,
            ),
          ],
        ),
      ],
    );
  }
}
