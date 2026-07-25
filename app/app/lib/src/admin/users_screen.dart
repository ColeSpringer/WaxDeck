import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../review/review_controller.dart';
import 'admin_providers.dart';
import 'user_edit_screen.dart';

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
      // a bad cast. Release the paging guard first — loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently — then let the error
      // reach the zone's handler instead of vanishing here.
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
    return Semantics(
      identifier: 'admin-users',
      container: true,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Users'),
            bottom: const TabBar(
              tabs: [
                Tab(key: Key('users-tab'), text: 'Users'),
                Tab(key: Key('requests-tab'), text: 'Requests'),
                Tab(key: Key('invites-tab'), text: 'Invites'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [_UsersTab(), _RequestsTab(), _InvitesTab()],
          ),
        ),
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
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => UserEditScreen(user: user)));
    if (changed ?? false) ref.invalidate(adminUsersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersProvider);
    return switch (users) {
      AsyncData(:final value) => NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 400) {
            ref.read(adminUsersProvider.notifier).loadMore();
          }
          return false;
        },
        child: ListView.builder(
          itemCount: value.users.length + (value.loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= value.users.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final user = value.users[index];
            return _UserRow(user: user, onTap: () => _open(context, ref, user));
          },
        ),
      ),
      AsyncError(:final error) => _ErrorRetry(
        error: error,
        onRetry: () => ref.invalidate(adminUsersProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.onTap});

  final UserAccount user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget badge(String label, {bool error = false}) {
      final colorScheme = Theme.of(context).colorScheme;
      return Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: error ? colorScheme.errorContainer : null,
        labelStyle: error
            ? TextStyle(color: colorScheme.onErrorContainer)
            : null,
      );
    }

    return Semantics(
      identifier: 'user-row-${user.id}',
      button: true,
      child: ListTile(
        key: ValueKey('user-row-${user.id}'),
        leading: const Icon(Icons.account_circle_outlined),
        title: Row(
          children: [
            Flexible(
              child: Text(user.username, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            for (final role in user.roles) ...[
              badge(role),
              const SizedBox(width: 4),
            ],
            if (user.disabled) badge('disabled', error: true),
            if (user.pending) badge('pending'),
          ],
        ),
        subtitle: user.displayName == null ? null : Text(user.displayName!),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    UserAccount user,
  ) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => UserEditScreen(user: user, approve: true),
      ),
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
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reject ${user.username}?'),
        content: const Text('The request is removed; nothing is created.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('request-reject-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).rejectSignupRequest(user.id);
      ref.invalidate(signupRequestsProvider);
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(signupRequestsProvider);
    return Semantics(
      identifier: 'signup-requests',
      container: true,
      child: switch (requests) {
        AsyncData(:final value) when value.isEmpty => const Center(
          child: Text('No pending requests'),
        ),
        AsyncData(:final value) => ListView(
          children: [
            for (final user in value)
              Semantics(
                identifier: 'request-row-${user.id}',
                child: ListTile(
                  key: ValueKey('request-row-${user.id}'),
                  leading: const Icon(Icons.person_add_alt),
                  title: Text(user.username),
                  subtitle: Text(
                    user.displayName == null
                        ? 'Requested ${_date(user.createdAt)}'
                        : '${user.displayName}, requested '
                              '${_date(user.createdAt)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        identifier: 'request-approve-${user.id}',
                        child: TextButton(
                          key: Key('request-approve-${user.id}'),
                          onPressed: () => _approve(context, ref, user),
                          child: const Text('Approve'),
                        ),
                      ),
                      Semantics(
                        identifier: 'request-reject-${user.id}',
                        child: TextButton(
                          key: Key('request-reject-${user.id}'),
                          onPressed: () => _reject(context, ref, user),
                          child: const Text('Reject'),
                        ),
                      ),
                    ],
                  ),
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

  static String _date(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

class _InvitesTab extends ConsumerWidget {
  const _InvitesTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
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
          title: const Text('Invite created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Share this token; it is shown exactly once.'),
              const SizedBox(height: 12),
              Semantics(
                identifier: 'invite-token',
                child: SelectableText(
                  created.token,
                  key: const Key('invite-token'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    Invite invite,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke invite?'),
        content: const Text('The token stops working immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('invite-revoke-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).revokeInvite(invite.id);
      ref.invalidate(invitesProvider);
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(invitesProvider);
    return Scaffold(
      floatingActionButton: Semantics(
        identifier: 'invite-create',
        label: 'Create invite',
        button: true,
        child: FloatingActionButton(
          key: const Key('invite-create'),
          tooltip: 'Create invite',
          onPressed: () => _create(context, ref),
          child: const Icon(Icons.person_add),
        ),
      ),
      body: switch (invites) {
        AsyncData(:final value) when value.isEmpty => const Center(
          child: Text('No invites yet'),
        ),
        AsyncData(:final value) => ListView(
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
    final colorScheme = Theme.of(context).colorScheme;
    final spent = invite.revoked || invite.expired;
    return Semantics(
      identifier: 'invite-row-${invite.id}',
      child: ListTile(
        key: ValueKey('invite-row-${invite.id}'),
        leading: const Icon(Icons.local_activity_outlined),
        title: Row(
          children: [
            Flexible(
              child: Text(
                invite.note ?? invite.id,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (invite.revoked) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('revoked'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: colorScheme.errorContainer,
                labelStyle: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ] else if (invite.expired) ...[
              const SizedBox(width: 8),
              const Chip(
                label: Text('expired'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${invite.roles.join(', ')}, uses ${invite.usedCount}/'
          '${invite.maxUses}',
        ),
        trailing: spent
            ? null
            : Semantics(
                identifier: 'invite-revoke-${invite.id}',
                child: IconButton(
                  key: Key('invite-revoke-${invite.id}'),
                  tooltip: 'Revoke invite',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRevoke,
                ),
              ),
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
    return AlertDialog(
      title: const Text('Create invite'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('invite-note'),
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note',
                helperText: 'Who this invite is for',
              ),
            ),
            SwitchListTile(
              key: const Key('invite-admin-role'),
              title: const Text('Administrator'),
              value: _admin,
              onChanged: (value) => setState(() => _admin = value),
            ),
            SwitchListTile(
              key: const Key('invite-access-all'),
              title: const Text('All libraries'),
              value: _accessAll,
              onChanged: (value) => setState(() => _accessAll = value),
            ),
            if (!_accessAll)
              for (final library in libraries)
                CheckboxListTile(
                  key: Key('invite-library-${library.pid}'),
                  title: Text(library.name),
                  value: _grantedPids.contains(library.pid),
                  onChanged: (checked) => setState(() {
                    checked ?? false
                        ? _grantedPids.add(library.pid)
                        : _grantedPids.remove(library.pid);
                  }),
                ),
            SwitchListTile(
              key: const Key('invite-upload-enabled'),
              title: const Text('May upload'),
              value: _uploadEnabled,
              onChanged: (value) => setState(() => _uploadEnabled = value),
            ),
            TextField(
              key: const Key('invite-max-uses'),
              controller: _maxUses,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Max uses'),
            ),
            TextField(
              key: const Key('invite-expires-days'),
              controller: _expiresDays,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Expires in (days)',
                helperText: 'Empty never expires',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('invite-create-confirm'),
          onPressed: _submit,
          child: const Text('Create'),
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
    final message = error is WaxDeckApiException
        ? (error as WaxDeckApiException).message
        : 'Could not load';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
