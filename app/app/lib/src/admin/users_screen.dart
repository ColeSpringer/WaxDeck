import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// The roles of an account or an invite, as words.
///
/// A role WaxDeck knows reads in the reader's language; one a newer
/// server adds shows as its own token, which is the only honest thing
/// to draw for a word this build has never heard of.
String _roleLabels(AppLocalizations l10n, List<String> roles) => roles
    .map(
      (role) => switch (role) {
        'admin' => l10n.adminRoleAdmin,
        'user' => l10n.adminRoleUser,
        _ => role,
      },
    )
    .join(', ');

/// Accumulated pages of accounts.
class UsersState {
  const UsersState({
    required this.users,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<UserAccount> users;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  UsersState copyWith({bool? loadingMore}) => UsersState(
    users: users,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages the account list with keyset cursors.
class UsersController extends AsyncNotifier<UsersState> {
  static const pageSize = 50;

  var _generation = 0;

  @override
  Future<UsersState> build() async {
    _generation++;
    final page = await ref.watch(repositoryProvider).listUsers(limit: pageSize);
    return UsersState(users: page.users, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listUsers(cursor: current.nextCursor, limit: pageSize);
      if (generation != _generation) return;
      state = AsyncData(
        UsersState(
          users: [...current.users, ...page.users],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure,
      // a bad cast. Release the paging guard first - loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently - then let the error
      // reach the app's error handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

final adminUsersProvider = AsyncNotifierProvider<UsersController, UsersState>(
  UsersController.new,
);

/// Account administration: the user list with per-account editing,
/// pending signup requests, and invites.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: WaxScaffold(
        title: context.l10n.adminUsersTitle,
        largeTitle: false,
        semanticsId: SemanticsIds.adminUsers,
        onBack: adminBack(context),
        // Slivers rather than a body: a TabBarView needs bounded height
        // and each tab pages a list of its own, so the remaining space
        // is exactly what it should get.
        slivers: const <Widget>[
          SliverToBoxAdapter(child: _Tabs()),
          SliverFillRemaining(
            child: TabBarView(
              children: <Widget>[_UsersTab(), _RequestsTab(), _InvitesTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Material(
      color: colors.canvas,
      child: TabBar(
        labelColor: colors.accent,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.accent,
        tabs: <Widget>[
          Tab(key: const Key('users-tab'), text: l10n.adminUsersTabUsers),
          Tab(key: const Key('requests-tab'), text: l10n.adminUsersTabRequests),
          Tab(key: const Key('invites-tab'), text: l10n.adminUsersTabInvites),
        ],
      ),
    );
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    UserAccount user,
  ) async {
    final changed = await context.push<bool>(
      WaxRoute.userEdit,
      extra: UserEditArgs(user: user),
    );
    if (changed ?? false) ref.invalidate(adminUsersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersProvider);
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return switch (users) {
      AsyncData(:final value) => NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 400) {
            ref.read(adminUsersProvider.notifier).loadMore();
          }
          return false;
        },
        child: ListView(
          padding: WaxSizeClass.of(
            context,
          ).gutter.add(const EdgeInsets.symmetric(vertical: WaxSpace.s16)),
          children: <Widget>[
            WaxTable<UserAccount>(
              rows: value.users,
              rowId: (user) => user.id,
              rowSemanticsId: SemanticsIds.userRow,
              rowDetailSemanticsId: SemanticsIds.userDetail,
              onRowTap: (user) => _open(context, ref, user),
              empty: EmptyState(
                glyph: WaxIcons.artists,
                title: l10n.adminUsersEmptyTitle,
                message: l10n.adminUsersEmptyMessage,
              ),
              columns: <WaxColumn<UserAccount>>[
                WaxColumn<UserAccount>(
                  label: l10n.adminUsersColumnAccount,
                  priority: WaxColumnPriority.primary,
                  text: (user) => user.username,
                  cell: (context, user) => Text(
                    user.displayName == null || user.displayName!.isEmpty
                        ? user.username
                        : l10n.adminUsersNamedAccount(
                            user.displayName!,
                            user.username,
                          ),
                    style: WaxType.titleItem.copyWith(
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                WaxColumn<UserAccount>(
                  label: l10n.adminUsersColumnRoles,
                  width: 140,
                  text: (user) => _roles(l10n, user),
                  cell: (context, user) => Text(
                    _roles(l10n, user),
                    style: WaxType.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                WaxColumn<UserAccount>(
                  label: l10n.adminUsersColumnState,
                  width: 116,
                  text: (user) => _state(l10n, user),
                  cell: (context, user) => Text(
                    _state(l10n, user),
                    style: WaxType.bodySmall.copyWith(
                      color: user.disabled
                          ? colors.error
                          : colors.textSecondary,
                    ),
                  ),
                ),
                WaxColumn<UserAccount>(
                  label: l10n.adminUsersColumnUploads,
                  width: 128,
                  priority: WaxColumnPriority.detail,
                  text: (user) => _uploads(l10n, user),
                  cell: (context, user) => Text(
                    _uploads(l10n, user),
                    style: WaxType.monoData.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (value.loadingMore)
              const Padding(
                padding: EdgeInsets.all(WaxSpace.s16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
      AsyncError(:final error) => _ErrorRetry(
        error: error,
        onRetry: () => ref.invalidate(adminUsersProvider),
      ),
      _ => const SkeletonShapes(shape: SkeletonShape.list),
    };
  }

  /// An account with no role at all is an ordinary account, which is
  /// what the server means by an empty list and what the row said
  /// before these words were translated.
  static String _roles(AppLocalizations l10n, UserAccount user) =>
      _roleLabels(l10n, user.roles.isEmpty ? const ['user'] : user.roles);

  static String _state(AppLocalizations l10n, UserAccount user) {
    if (user.disabled) return l10n.adminUsersStateDisabled;
    if (user.pending) return l10n.adminUsersStatePending;
    return l10n.adminUsersStateActive;
  }

  /// The account's pending-upload allowance, as the console reads it:
  /// what may wait in staging, not what has been contributed.
  /// Megabytes, not the byte formatter's own choice of unit: the field
  /// that sets this is labelled in megabytes, and a column answering a
  /// 2048 with "2.0 GB" is the two halves of one setting disagreeing.
  static String _uploads(AppLocalizations l10n, UserAccount user) {
    if (!user.uploadEnabled) return l10n.adminUsersUploadsNone;
    final quota = user.uploadQuotaBytes;
    if (quota == null || quota == 0) return l10n.adminUsersUploadsUnlimited;
    return l10n.adminUsersUploadsMb(quota ~/ (1024 * 1024));
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    UserAccount user,
  ) async {
    final changed = await context.push<bool>(
      WaxRoute.userEdit,
      extra: UserEditArgs(user: user, approve: true),
    );
    if (changed ?? false) {
      ref.invalidate(signupRequestsProvider);
      ref.invalidate(adminUsersProvider);
    }
  }

  Future<void> _reject(
    BuildContext context,
    WidgetRef ref,
    UserAccount user,
  ) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminUsersRejectTitle(user.username)),
        content: Text(l10n.adminUsersRejectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('request-reject-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminUsersRejectAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).rejectSignupRequest(user.id);
      ref.invalidate(signupRequestsProvider);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainRefusal(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(signupRequestsProvider);
    final l10n = context.l10n;
    return Semantics(
      identifier: SemanticsIds.signupRequests,
      container: true,
      child: switch (requests) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Text(l10n.adminUsersNoRequests),
        ),
        AsyncData(:final value) => ListView(
          padding: WaxSizeClass.of(
            context,
          ).gutter.add(const EdgeInsets.symmetric(vertical: WaxSpace.s16)),
          children: [
            for (final user in value)
              WaxOptionRow(
                key: ValueKey(SemanticsIds.requestRow(user.id)),
                semanticsId: SemanticsIds.requestRow(user.id),
                glyph: WaxIcons.addPerson,
                title: user.username,
                subtitle: user.displayName == null
                    ? l10n.adminUsersRequestedOn(
                        l10n.formatDate(user.createdAt),
                      )
                    : l10n.adminUsersRequestedByOn(
                        user.displayName!,
                        l10n.formatDate(user.createdAt),
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      identifier: SemanticsIds.requestApprove(user.id),
                      child: TextButton(
                        key: Key(SemanticsIds.requestApprove(user.id)),
                        onPressed: () => _approve(context, ref, user),
                        child: Text(l10n.adminUserApproveAction),
                      ),
                    ),
                    Semantics(
                      identifier: SemanticsIds.requestReject(user.id),
                      child: TextButton(
                        key: Key(SemanticsIds.requestReject(user.id)),
                        onPressed: () => _reject(context, ref, user),
                        child: Text(l10n.adminUsersRejectAction),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        AsyncError(:final error) => _ErrorRetry(
          error: error,
          onRetry: () => ref.invalidate(signupRequestsProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _InvitesTab extends ConsumerWidget {
  const _InvitesTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final request = await showDialog<_InviteRequest>(
      context: context,
      builder: (_) => const _CreateInviteDialog(),
    );
    if (request == null || !context.mounted) return;
    try {
      final created = await ref
          .read(repositoryProvider)
          .createInvite(
            note: request.note,
            roles: request.roles,
            libraryAccess: request.libraryAccess,
            uploadEnabled: request.uploadEnabled,
            maxUses: request.maxUses,
            expiresAt: request.expiresAt,
          );
      ref.invalidate(invitesProvider);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.adminInviteCreatedTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.adminInviteCreatedBody),
              const SizedBox(height: WaxSpace.s12),
              Semantics(
                identifier: SemanticsIds.inviteToken,
                child: SelectableText(
                  created.token,
                  key: const Key(SemanticsIds.inviteToken),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonDone),
            ),
          ],
        ),
      );
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    Invite invite,
  ) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminInviteRevokeTitle),
        content: Text(l10n.adminInviteRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('invite-revoke-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminInviteRevokeAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).revokeInvite(invite.id);
      ref.invalidate(invitesProvider);
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(invitesProvider);
    final l10n = context.l10n;
    return Scaffold(
      floatingActionButton: Semantics(
        identifier: SemanticsIds.inviteCreate,
        label: l10n.adminInviteCreate,
        button: true,
        child: FloatingActionButton(
          key: const Key(SemanticsIds.inviteCreate),
          tooltip: l10n.adminInviteCreate,
          onPressed: () => _create(context, ref),
          child: const WaxIcon(WaxIcons.addPerson),
        ),
      ),
      body: switch (invites) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Text(l10n.adminInvitesEmpty),
        ),
        AsyncData(:final value) => ListView(
          padding: WaxSizeClass.of(
            context,
          ).gutter.add(const EdgeInsets.symmetric(vertical: WaxSpace.s16)),
          children: [
            for (final invite in value)
              _InviteRow(
                invite: invite,
                onRevoke: () => _revoke(context, ref, invite),
              ),
          ],
        ),
        AsyncError(:final error) => _ErrorRetry(
          error: error,
          onRetry: () => ref.invalidate(invitesProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.invite, required this.onRevoke});

  final Invite invite;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spent = invite.revoked || invite.expired;
    return WaxOptionRow(
      key: ValueKey(SemanticsIds.inviteRow(invite.id)),
      semanticsId: SemanticsIds.inviteRow(invite.id),
      glyph: WaxIcons.ticket,
      // Not `enabled: false`, though a spent invite is spent: that flag
      // greys the title and the subtitle to the disabled tone, which is
      // held to a visibility floor rather than to reading contrast -
      // and "revoked" is the one word an administrator scans this list
      // for. It leads the line at full contrast instead, and the absent
      // revoke button is what says the invite is done with.
      title: invite.note ?? invite.id,
      subtitle: <String>[
        if (invite.revoked)
          l10n.adminInviteRevoked
        else if (invite.expired)
          l10n.adminInviteExpired,
        _roleLabels(l10n, invite.roles),
        l10n.adminInviteUses(invite.usedCount, invite.maxUses),
      ].join(', '),
      trailing: spent
          ? null
          : WaxIconButton(
              key: Key(SemanticsIds.inviteRevoke(invite.id)),
              glyph: WaxIcons.delete,
              label: l10n.adminInviteRevokeButton,
              semanticsId: SemanticsIds.inviteRevoke(invite.id),
              onPressed: onRevoke,
            ),
    );
  }
}

class _InviteRequest {
  const _InviteRequest({
    this.note,
    required this.roles,
    this.libraryAccess,
    required this.uploadEnabled,
    required this.maxUses,
    this.expiresAt,
  });

  final String? note;
  final List<String> roles;
  final LibraryAccess? libraryAccess;
  final bool uploadEnabled;
  final int maxUses;
  final DateTime? expiresAt;
}

class _CreateInviteDialog extends ConsumerStatefulWidget {
  const _CreateInviteDialog();

  @override
  ConsumerState<_CreateInviteDialog> createState() =>
      _CreateInviteDialogState();
}

class _CreateInviteDialogState extends ConsumerState<_CreateInviteDialog> {
  final _note = TextEditingController();
  final _maxUses = TextEditingController(text: '1');
  final _expiresDays = TextEditingController();
  var _admin = false;
  var _accessAll = true;
  final _grantedPids = <String>{};
  var _uploadEnabled = false;

  @override
  void dispose() {
    _note.dispose();
    _maxUses.dispose();
    _expiresDays.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _note.text.trim();
    final days = int.tryParse(_expiresDays.text.trim());
    Navigator.of(context).pop(
      _InviteRequest(
        note: note.isEmpty ? null : note,
        roles: [if (_admin) 'admin' else 'user'],
        libraryAccess: _accessAll
            ? null
            : LibraryAccess(
                mode: 'granted',
                libraryPids: _grantedPids.toList(),
              ),
        uploadEnabled: _uploadEnabled,
        maxUses: int.tryParse(_maxUses.text.trim()) ?? 1,
        expiresAt: days == null
            ? null
            : DateTime.now().toUtc().add(Duration(days: days)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraries = ref.watch(librariesProvider).value ?? const [];
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.adminInviteCreate),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('invite-note'),
              controller: _note,
              decoration: InputDecoration(
                labelText: l10n.adminInviteNoteLabel,
                helperText: l10n.adminInviteNoteHelp,
              ),
            ),
            WaxSettingRow(
              key: const Key('invite-admin-role'),
              title: l10n.adminUserAdminTitle,
              help: l10n.adminInviteAdminHelp,
              control: WaxSwitch(
                value: _admin,
                label: l10n.adminUserAdminTitle,
                onChanged: (value) => setState(() => _admin = value),
              ),
            ),
            WaxSettingRow(
              key: const Key('invite-access-all'),
              title: l10n.adminUserAccessAllTitle,
              help: l10n.adminInviteAccessAllHelp,
              control: WaxSwitch(
                value: _accessAll,
                label: l10n.adminUserAccessAllTitle,
                onChanged: (value) => setState(() => _accessAll = value),
              ),
            ),
            if (!_accessAll)
              for (final library in libraries)
                WaxSettingRow(
                  key: Key('invite-library-${library.pid}'),
                  title: library.name,
                  help: l10n.adminInviteIncludeLibrary,
                  control: WaxSwitch(
                    value: _grantedPids.contains(library.pid),
                    label: library.name,
                    onChanged: (checked) => setState(() {
                      checked
                          ? _grantedPids.add(library.pid)
                          : _grantedPids.remove(library.pid);
                    }),
                  ),
                ),
            WaxSettingRow(
              key: const Key('invite-upload-enabled'),
              title: l10n.adminUserMayUploadTitle,
              help: l10n.adminInviteUploadHelp,
              control: WaxSwitch(
                value: _uploadEnabled,
                label: l10n.adminUserMayUploadTitle,
                onChanged: (value) => setState(() => _uploadEnabled = value),
              ),
            ),
            TextField(
              key: const Key('invite-max-uses'),
              controller: _maxUses,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.adminInviteMaxUsesLabel,
              ),
            ),
            TextField(
              key: const Key('invite-expires-days'),
              controller: _expiresDays,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.adminInviteExpiresLabel,
                helperText: l10n.adminInviteExpiresHelp,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('invite-create-confirm'),
          onPressed: _submit,
          child: Text(l10n.adminInviteCreateAction),
        ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.explain(error), textAlign: TextAlign.center),
          const SizedBox(height: WaxSpace.s12),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(context.l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}
