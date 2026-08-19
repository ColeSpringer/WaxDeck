import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
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
  /// releases the room it held.
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
    final l10n = context.l10n;
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
      messenger.show(explainRefusal(l10n, e));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminUserSetPassword),
        content: TextField(
          key: const Key('user-new-password'),
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.adminUserNewPasswordLabel,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('user-set-password-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.adminUserSetPassword),
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
      messenger.show(l10n.adminUserPasswordSet);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainRefusal(l10n, e));
    }
  }

  Future<void> _revokeSessions() async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await _confirm(
      title: l10n.adminUserRevokeTitle,
      body: l10n.adminUserRevokeBody(widget.user.username),
      action: l10n.adminUserRevokeAction,
    );
    if (!confirmed) return;
    try {
      await ref.read(repositoryProvider).revokeUserSessions(widget.user.id);
      messenger.show(l10n.adminUserSessionsRevoked);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _deleteUser() async {
    final l10n = context.l10n;
    final router = GoRouter.of(context);
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await _confirm(
      title: l10n.adminUserDeleteTitle,
      body: l10n.adminUserDeleteBody(widget.user.username),
      action: l10n.adminUserDeleteAction,
    );
    if (!confirmed) return;
    try {
      await ref.read(repositoryProvider).deleteUser(widget.user.id);
      router.leave(fallback: WaxRoute.users, result: true);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
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
    final l10n = context.l10n;
    final sizeClass = WaxSizeClass.of(context);
    final colors = WaxColors.of(context);
    final libraries = ref.watch(librariesProvider).value ?? const [];
    return WaxScaffold(
      title: widget.approve
          ? l10n.adminUserApproveTitle(widget.user.username)
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
                label: l10n.adminUserChildPreset,
                icon: WaxIcons.check,
                kind: WaxButtonKind.tonal,
                semanticsId: SemanticsIds.userChildPreset,
                onPressed: _applyChildPreset,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s4),
              child: Text(
                l10n.adminUserChildPresetHelp,
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: WaxSpace.s16),

            SectionHeader(title: l10n.adminUserRoleGroup),
            WaxSettingRow(
              title: l10n.adminUserAdminTitle,
              help: l10n.adminUserAdminHelp,
              control: WaxSwitch(
                label: l10n.adminUserAdminTitle,
                value: _admin,
                semanticsId: SemanticsIds.userAdminRole,
                onChanged: (value) => setState(() => _admin = value),
              ),
            ),
            if (!widget.approve)
              WaxSettingRow(
                title: l10n.adminUserDisabledTitle,
                help: l10n.adminUserDisabledHelp,
                control: WaxSwitch(
                  label: l10n.adminUserDisabledTitle,
                  value: _disabled,
                  semanticsId: SemanticsIds.userDisabled,
                  onChanged: (value) => setState(() => _disabled = value),
                ),
              ),

            const SizedBox(height: WaxSpace.s16),
            SectionHeader(title: l10n.adminUserAccessGroup),
            WaxSettingRow(
              title: l10n.adminUserAccessAllTitle,
              help: l10n.adminUserAccessAllHelp,
              control: WaxSwitch(
                label: l10n.adminUserAccessAllTitle,
                value: _accessAll,
                semanticsId: SemanticsIds.userAccessAll,
                onChanged: (value) => setState(() => _accessAll = value),
              ),
            ),
            if (!_accessAll)
              for (final library in libraries)
                WaxSettingRow(
                  title: library.name,
                  help: library.path ?? l10n.adminUserCatalogLibrary,
                  control: WaxSwitch(
                    label: l10n.adminUserLibraryAccessLabel(library.name),
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
            SectionHeader(title: l10n.adminUserUploadsGroup),
            WaxSettingRow(
              title: l10n.adminUserMayUploadTitle,
              help: l10n.adminUserMayUploadHelp,
              control: WaxSwitch(
                label: l10n.adminUserMayUploadTitle,
                value: _uploadEnabled,
                semanticsId: SemanticsIds.userUploadEnabled,
                onChanged: (value) => setState(() => _uploadEnabled = value),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: WaxTextField(
                label: l10n.adminUserQuotaLabel,
                hint: l10n.adminUserQuotaHint,
                helperText: l10n.adminUserQuotaHelp,
                keyboardType: TextInputType.number,
                controller: _quotaMb,
                semanticsId: SemanticsIds.userQuota,
              ),
            ),

            const SizedBox(height: WaxSpace.s16),
            SectionHeader(title: l10n.adminUserPermissionsGroup),
            WaxSettingRow(
              title: l10n.adminUserPermDownloadTitle,
              help: l10n.adminUserPermDownloadHelp,
              control: WaxSwitch(
                label: l10n.adminUserPermDownloadTitle,
                value: _download,
                semanticsId: SemanticsIds.permDownload,
                onChanged: (value) => setState(() => _download = value),
              ),
            ),
            WaxSettingRow(
              title: l10n.adminUserPermDeleteTitle,
              help: l10n.adminUserPermDeleteHelp,
              control: WaxSwitch(
                label: l10n.adminUserPermDeleteTitle,
                value: _delete,
                semanticsId: SemanticsIds.permDelete,
                onChanged: (value) => setState(() => _delete = value),
              ),
            ),
            WaxSettingRow(
              title: l10n.adminUserPermExplicitTitle,
              help: l10n.adminUserPermExplicitHelp,
              control: WaxSwitch(
                label: l10n.adminUserPermExplicitTitle,
                value: _explicitContent,
                semanticsId: SemanticsIds.permExplicit,
                onChanged: (value) => setState(() => _explicitContent = value),
              ),
            ),
            WaxSettingRow(
              title: l10n.adminUserPermSharedOutputsTitle,
              help: l10n.adminUserPermSharedOutputsHelp,
              control: WaxSwitch(
                label: l10n.adminUserPermSharedOutputsTitle,
                value: _sharedOutputs,
                semanticsId: SemanticsIds.permSharedOutputs,
                onChanged: (value) => setState(() => _sharedOutputs = value),
              ),
            ),
            WaxSettingRow(
              title: l10n.adminUserPermManagePodcastsTitle,
              help: l10n.adminUserPermManagePodcastsHelp,
              control: WaxSwitch(
                label: l10n.adminUserPermManagePodcastsTitle,
                value: _managePodcasts,
                semanticsId: SemanticsIds.permManagePodcasts,
                onChanged: (value) => setState(() => _managePodcasts = value),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: WaxTextField(
                label: l10n.adminUserMaxKbpsLabel,
                hint: l10n.adminUserMaxKbpsHint,
                keyboardType: TextInputType.number,
                controller: _maxKbps,
                semanticsId: SemanticsIds.permMaxKbps,
              ),
            ),

            const SizedBox(height: WaxSpace.s24),
            _TagRuleEditor(
              label: l10n.adminUserTagAllowLabel,
              help: l10n.adminUserTagAllowHelp,
              keyPrefix: 'tag-allow',
              rules: _tagAllow,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: WaxSpace.s16),
            _TagRuleEditor(
              label: l10n.adminUserTagDenyLabel,
              help: l10n.adminUserTagDenyHelp,
              keyPrefix: 'tag-deny',
              rules: _tagDeny,
              onChanged: () => setState(() {}),
            ),

            const SizedBox(height: WaxSpace.s24),
            WaxButton(
              label: widget.approve
                  ? l10n.adminUserApproveAction
                  : l10n.commonSave,
              semanticsId: SemanticsIds.userSave,
              onPressed: _busy ? null : _save,
            ),
            if (!widget.approve) ...<Widget>[
              const SizedBox(height: WaxSpace.s24),
              SectionHeader(title: l10n.adminUserActionsGroup),
              Wrap(
                spacing: WaxSpace.s8,
                runSpacing: WaxSpace.s8,
                children: <Widget>[
                  WaxButton(
                    label: l10n.adminUserSetPassword,
                    kind: WaxButtonKind.tonal,
                    semanticsId: SemanticsIds.userSetPassword,
                    onPressed: _setPassword,
                  ),
                  WaxButton(
                    label: l10n.adminUserRevokeAll,
                    kind: WaxButtonKind.tonal,
                    semanticsId: SemanticsIds.userRevokeSessions,
                    onPressed: _revokeSessions,
                  ),
                  WaxButton(
                    label: l10n.adminUserDeleteAccount,
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
    final l10n = context.l10n;
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
            // Bottom-aligned so the add control lines up with the two
            // boxes rather than with the labels now over them.
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: WaxTextField(
                  label: l10n.adminUserTagKeyLabel,
                  controller: _key,
                  semanticsId: SemanticsIds.tagRuleKey(widget.keyPrefix),
                ),
              ),
              const SizedBox(width: WaxSpace.s8),
              Expanded(
                child: WaxTextField(
                  label: l10n.adminUserTagValueLabel,
                  controller: _value,
                  semanticsId: SemanticsIds.tagRuleValue(widget.keyPrefix),
                ),
              ),
              const SizedBox(width: WaxSpace.s8),
              WaxIconButton(
                glyph: WaxIcons.add,
                label: l10n.adminUserTagAddRule,
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
