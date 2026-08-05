import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'admin_providers.dart';

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

  /// The pending-upload limit, in megabytes. What may sit in staging
  /// awaiting review, not what the account has contributed: an import
  /// releases the room it held (ADR-0046).
  late final TextEditingController _quotaMb = TextEditingController(
    text: _megabytes(widget.user.uploadQuotaBytes),
  );

  /// Bytes as megabytes, without the integer division that rendered
  /// anything under a megabyte as "0" - which the save path then sent as
  /// 0, and 0 is the contract's "remove the cap". A fractional value
  /// round-trips exactly: 524288 bytes shows as 0.5 and parses back to
  /// 524288.
  static String _megabytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    return mb == mb.roundToDouble()
        ? mb.round().toString()
        : mb.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

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

  /// What to send for the limit, or null to say nothing about it.
  ///
  /// An emptied field means "no limit", and the two paths spell that
  /// differently: an update takes 0 (the contract's remove-the-cap),
  /// while an approval's field has a minimum of 1 and has to omit it
  /// instead. Sending 0 on an approval is a 400 naming a field the
  /// administrator never touched.
  int? quotaBytesFor({required bool approving}) {
    final raw = _quotaMb.text.trim();
    if (raw.isEmpty) return approving ? null : 0;
    final mb = double.tryParse(raw);
    if (mb == null || mb <= 0) return approving ? null : 0;
    return (mb * 1024 * 1024).round();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final router = GoRouter.of(context);
    final messenger = ref.read(shellMessengerProvider.notifier);
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
          uploadQuotaBytes: quotaBytesFor(approving: true),
        );
      } else {
        await repo.updateUser(
          widget.user.id,
          roles: roles,
          disabled: _disabled,
          libraryAccess: _libraryAccess,
          permissions: _permissions,
          uploadEnabled: _uploadEnabled,
          uploadQuotaBytes: quotaBytesFor(approving: false),
        );
      }
      router.leave(fallback: WaxRoute.users, result: true);
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    final messenger = ref.read(shellMessengerProvider.notifier);
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
      messenger.show('Password set');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  Future<void> _revokeSessions() async {
    final messenger = ref.read(shellMessengerProvider.notifier);
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
      messenger.show('Sessions revoked');
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    }
  }

  Future<void> _deleteUser() async {
    final router = GoRouter.of(context);
    final messenger = ref.read(shellMessengerProvider.notifier);
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
      router.leave(fallback: WaxRoute.users, result: true);
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
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

  /// The child-account preset: the settings a household actually means
  /// by "an account for my kid", applied in one press and editable
  /// afterwards like anything else.
  ///
  /// Kids mode is admin-configured in v1 by decision - there is no
  /// kid-facing UI - so this is the whole of it: no explicit content, no
  /// delete, no download, no upload, and a tag deny rule for the
  /// advisory tag files actually carry. Library grants are left as they
  /// are, because which libraries a child may see is the one part of
  /// this nobody else can guess.
  void _applyChildPreset() {
    setState(() {
      _admin = false;
      _explicitContent = false;
      _download = false;
      _delete = false;
      _uploadEnabled = false;
      _managePodcasts = false;
      _sharedOutputs = false;
      const advisory = TagRule(key: 'ITUNESADVISORY', value: '1');
      if (!_tagDeny.any(
        (rule) => rule.key == advisory.key && rule.value == advisory.value,
      )) {
        _tagDeny.add(advisory);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final colors = WaxColors.of(context);
    final libraries = ref.watch(librariesProvider).value ?? const [];
    return WaxScaffold(
      title: widget.approve
          ? 'Approve ${widget.user.username}'
          : widget.user.username,
      largeTitle: false,
      onBack: () => context.leave(fallback: WaxRoute.users),
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: WaxButton(
                label: 'Child account preset',
                icon: WaxIcons.check,
                kind: WaxButtonKind.tonal,
                semanticsId: SemanticsIds.userChildPreset,
                onPressed: _applyChildPreset,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s4),
              child: Text(
                'Sets no explicit content, no deleting, downloading, or '
                'uploading, and a deny rule for advisory-tagged tracks. '
                'Everything below stays editable.',
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: WaxSpace.s16),

            const SectionHeader(title: 'Role'),
            WaxSettingRow(
              title: 'Administrator',
              help: 'Sees the whole library and the admin console',
              control: WaxSwitch(
                label: 'Administrator',
                value: _admin,
                semanticsId: SemanticsIds.userAdminRole,
                onChanged: (value) => setState(() => _admin = value),
              ),
            ),
            if (!widget.approve)
              WaxSettingRow(
                title: 'Disabled',
                help:
                    'A disabled account cannot sign in, and its live '
                    'sessions are revoked',
                control: WaxSwitch(
                  label: 'Disabled',
                  value: _disabled,
                  semanticsId: SemanticsIds.userDisabled,
                  onChanged: (value) => setState(() => _disabled = value),
                ),
              ),

            const SizedBox(height: WaxSpace.s16),
            const SectionHeader(title: 'Library access'),
            WaxSettingRow(
              title: 'All libraries',
              help: 'Off grants specific libraries instead',
              control: WaxSwitch(
                label: 'All libraries',
                value: _accessAll,
                semanticsId: SemanticsIds.userAccessAll,
                onChanged: (value) => setState(() => _accessAll = value),
              ),
            ),
            if (!_accessAll)
              for (final library in libraries)
                WaxSettingRow(
                  title: library.name,
                  help: library.path ?? 'A catalog library',
                  control: WaxSwitch(
                    label: 'Access to ${library.name}',
                    value: _grantedPids.contains(library.pid),
                    semanticsId: SemanticsIds.userLibrary(library.pid),
                    onChanged: (checked) => setState(() {
                      checked
                          ? _grantedPids.add(library.pid)
                          : _grantedPids.remove(library.pid);
                    }),
                  ),
                ),

            const SizedBox(height: WaxSpace.s16),
            const SectionHeader(title: 'Uploads'),
            WaxSettingRow(
              title: 'May upload',
              help: 'Add files to the library, through review',
              control: WaxSwitch(
                label: 'May upload',
                value: _uploadEnabled,
                semanticsId: SemanticsIds.userUploadEnabled,
                onChanged: (value) => setState(() => _uploadEnabled = value),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: WaxTextField(
                label: 'Pending upload limit (MB)',
                hint: 'Empty means no limit',
                controller: _quotaMb,
                semanticsId: SemanticsIds.userQuota,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s4),
              child: Text(
                'How much may sit in staging waiting for a decision. '
                'Importing an upload into the library frees the space '
                'again, so this bounds the queue rather than what the '
                'account contributes.',
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ),

            const SizedBox(height: WaxSpace.s16),
            const SectionHeader(title: 'Permissions'),
            WaxSettingRow(
              title: 'Download originals',
              help: 'Keep the stored file, not just a stream',
              control: WaxSwitch(
                label: 'Download originals',
                value: _download,
                semanticsId: SemanticsIds.permDownload,
                onChanged: (value) => setState(() => _download = value),
              ),
            ),
            WaxSettingRow(
              title: 'Delete library files',
              help: 'Move catalog files to the trash',
              control: WaxSwitch(
                label: 'Delete library files',
                value: _delete,
                semanticsId: SemanticsIds.permDelete,
                onChanged: (value) => setState(() => _delete = value),
              ),
            ),
            WaxSettingRow(
              title: 'Explicit content',
              help: 'Off hides what the deny rules match',
              control: WaxSwitch(
                label: 'Explicit content',
                value: _explicitContent,
                semanticsId: SemanticsIds.permExplicit,
                onChanged: (value) => setState(() => _explicitContent = value),
              ),
            ),
            WaxSettingRow(
              title: 'Shared outputs',
              help: 'May play to endpoints other people also use',
              control: WaxSwitch(
                label: 'Shared outputs',
                value: _sharedOutputs,
                semanticsId: SemanticsIds.permSharedOutputs,
                onChanged: (value) => setState(() => _sharedOutputs = value),
              ),
            ),
            WaxSettingRow(
              title: 'Manage podcasts',
              help: 'Subscribe, unsubscribe, and change feed settings',
              control: WaxSwitch(
                label: 'Manage podcasts',
                value: _managePodcasts,
                semanticsId: SemanticsIds.permManagePodcasts,
                onChanged: (value) => setState(() => _managePodcasts = value),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: WaxTextField(
                label: 'Transcode ceiling (kbps)',
                hint: 'Empty keeps the server default',
                controller: _maxKbps,
                semanticsId: SemanticsIds.permMaxKbps,
              ),
            ),

            const SizedBox(height: WaxSpace.s24),
            _TagRuleEditor(
              label: 'Content allow rules',
              help: 'With any rule here, only matching content is visible',
              keyPrefix: 'tag-allow',
              rules: _tagAllow,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: WaxSpace.s16),
            _TagRuleEditor(
              label: 'Content deny rules',
              help: 'Matching content is hidden from this account',
              keyPrefix: 'tag-deny',
              rules: _tagDeny,
              onChanged: () => setState(() {}),
            ),

            const SizedBox(height: WaxSpace.s24),
            WaxButton(
              label: widget.approve ? 'Approve' : 'Save',
              semanticsId: SemanticsIds.userSave,
              onPressed: _busy ? null : _save,
            ),
            if (!widget.approve) ...<Widget>[
              const SizedBox(height: WaxSpace.s24),
              const SectionHeader(title: 'Account actions'),
              Wrap(
                spacing: WaxSpace.s8,
                runSpacing: WaxSpace.s8,
                children: <Widget>[
                  WaxButton(
                    label: 'Set password',
                    kind: WaxButtonKind.tonal,
                    semanticsId: SemanticsIds.userSetPassword,
                    onPressed: _setPassword,
                  ),
                  WaxButton(
                    label: 'Sign out everywhere',
                    kind: WaxButtonKind.tonal,
                    semanticsId: SemanticsIds.userRevokeSessions,
                    onPressed: _revokeSessions,
                  ),
                  WaxButton(
                    label: 'Delete account',
                    kind: WaxButtonKind.destructive,
                    semanticsId: SemanticsIds.userDelete,
                    onPressed: _deleteUser,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One tag rule list, as chips with an add row.
///
/// The kids-mode mechanism: a rule names a tag key, optionally with a
/// value, and content carrying it is admitted or hidden. There is no
/// first-class explicit flag anywhere in music metadata, so what files
/// actually carry (ITUNESADVISORY and friends) rides the custom-tag
/// surface and these rules are what act on it.
class _TagRuleEditor extends StatefulWidget {
  const _TagRuleEditor({
    required this.label,
    required this.help,
    required this.keyPrefix,
    required this.rules,
    required this.onChanged,
  });

  final String label;
  final String help;
  final String keyPrefix;

  /// Mutated in place; [onChanged] tells the owner to rebuild.
  final List<TagRule> rules;
  final VoidCallback onChanged;

  @override
  State<_TagRuleEditor> createState() => _TagRuleEditorState();
}

class _TagRuleEditorState extends State<_TagRuleEditor> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _value = TextEditingController();

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
    final colors = WaxColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: widget.label),
        Text(
          widget.help,
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s8),
        if (widget.rules.isNotEmpty)
          Wrap(
            spacing: WaxSpace.s8,
            runSpacing: WaxSpace.s8,
            children: <Widget>[
              for (final (index, rule) in widget.rules.indexed)
                WaxPill(
                  label: rule.value == null
                      ? rule.key
                      : '${rule.key}=${rule.value}',
                  selected: true,
                  semanticsId: SemanticsIds.tagRule(widget.keyPrefix, index),
                  onPressed: () {
                    widget.rules.removeAt(index);
                    widget.onChanged();
                  },
                ),
            ],
          ),
        const SizedBox(height: WaxSpace.s8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: WaxTextField(
                  label: 'Tag key',
                  controller: _key,
                  semanticsId: SemanticsIds.tagRuleKey(widget.keyPrefix),
                ),
              ),
              const SizedBox(width: WaxSpace.s8),
              Expanded(
                child: WaxTextField(
                  label: 'Value (optional)',
                  controller: _value,
                  semanticsId: SemanticsIds.tagRuleValue(widget.keyPrefix),
                ),
              ),
              const SizedBox(width: WaxSpace.s8),
              WaxIconButton(
                glyph: WaxIcons.add,
                label: 'Add rule',
                semanticsId: SemanticsIds.tagRuleAdd(widget.keyPrefix),
                onPressed: _add,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
