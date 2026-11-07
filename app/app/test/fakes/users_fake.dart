import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [UsersApi] for `FakeRepository`.
mixin FakeUsers on FakeRepositoryState implements UsersApi {
  @override
  Future<List<AppPassword>> listAppPasswords() async => List.of(appPasswords);

  /// App passwords created through the fake, served by the listing.
  final List<AppPassword> appPasswords = [];

  @override
  Future<AppPasswordCreated> createAppPassword(String label) async {
    final created = AppPasswordCreated(
      id: 'ap-FAKE${appPasswords.length}',
      label: label,
      createdAt: DateTime.now().toUtc(),
      secret: 'FAKESECRETFAKESECRETFAKESE',
    );
    appPasswords.add(created);
    return created;
  }

  @override
  Future<void> revokeAppPassword(String id) async {
    appPasswords.removeWhere((ap) => ap.id == id);
  }

  @override
  Future<Prefs> getPrefs() async => prefs;

  /// Thrown by [putPrefs] when set, to exercise validation feedback
  /// (a rejected timezone, for instance).
  WaxDeckApiException? putPrefsError;

  /// Every document written, in order. Its emptiness is the assertion a
  /// per-device setting wants: nothing about it reached the account.
  final List<Prefs> putPrefsCalls = [];

  @override
  Future<Prefs> putPrefs(Prefs next) async {
    final error = putPrefsError;
    if (error != null) throw error;
    putPrefsCalls.add(next);
    return prefs = next;
  }

  @override
  Future<UserPage> listUsers({String? cursor, int? limit}) async {
    final error = listError;
    if (error != null) throw error;
    return UserPage(users: usersById.values.toList());
  }

  @override
  Future<UserAccount> createUser({
    required String username,
    required String password,
    String? displayName,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  }) async {
    final account = UserAccount(
      id: 'us-FAKE${userSeq++}',
      username: username,
      displayName: displayName,
      roles: roles ?? const ['user'],
      createdAt: DateTime.utc(2026, 7, 1),
      libraryAccess: libraryAccess ?? const LibraryAccess(mode: 'all'),
      uploadEnabled: uploadEnabled ?? false,
      uploadQuotaBytes: uploadQuotaBytes,
      permissions: permissions ?? const Permissions(),
    );
    usersById[account.id] = account;
    return account;
  }

  @override
  Future<UserAccount> updateUser(
    String userId, {
    String? displayName,
    List<String>? roles,
    bool? disabled,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  }) async {
    final current = usersById[userId];
    if (current == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such user',
        statusCode: 404,
      );
    }
    final updated = UserAccount(
      id: current.id,
      username: current.username,
      displayName: displayName ?? current.displayName,
      roles: roles ?? current.roles,
      createdAt: current.createdAt,
      identities: current.identities,
      libraryAccess: libraryAccess ?? current.libraryAccess,
      uploadEnabled: uploadEnabled ?? current.uploadEnabled,
      uploadQuotaBytes: uploadQuotaBytes ?? current.uploadQuotaBytes,
      disabled: disabled ?? current.disabled,
      hasPassword: current.hasPassword,
      pending: current.pending,
      permissions: permissions ?? current.permissions,
    );
    usersById[userId] = updated;
    return updated;
  }

  /// Holds every account read until completed, when set.
  Completer<void>? getUserGate;

  @override
  Future<UserAccount> getUser(String userId) async {
    await getUserGate?.future;
    final account = usersById[userId];
    if (account == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such user',
        statusCode: 404,
      );
    }
    return account;
  }

  /// Ids removed by [deleteUser], in order.
  final List<String> deletedUserIds = [];

  /// What each [deleteUser] asked to become of the playlists, in order.
  final List<String> deletedUserPlaylists = [];

  @override
  Future<void> deleteUser(
    String userId, {
    String playlists = 'transfer',
  }) async {
    deletedUserIds.add(userId);
    deletedUserPlaylists.add(playlists);
    usersById.remove(userId);
  }

  /// Administrator password resets, in order.
  final List<({String userId, String newPassword})> setUserPasswordCalls = [];

  @override
  Future<void> setUserPassword(
    String userId,
    String newPassword, {
    String? currentPassword,
  }) async {
    // The server's own order, which is what makes the two refusals
    // reachable together: the new password's policy is checked before
    // the current one is verified, so a correct current password and a
    // short new one answers `invalid-request` and not `forbidden`.
    if (newPassword.length < 8) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'password must be at least 8 characters',
      );
    }
    // The self-service form always sends one and the administrator reset
    // never does, so a wrong value here is the refusal the form's error
    // line exists for.
    if (currentPassword != null && currentPassword != 'password123') {
      throw const WaxDeckApiException(
        code: 'forbidden',
        message: 'That is not your current password',
      );
    }
    setUserPasswordCalls.add((userId: userId, newPassword: newPassword));
  }

  /// Ids whose sessions were revoked wholesale, in order.
  final List<String> revokeUserSessionsCalls = [];

  @override
  Future<void> revokeUserSessions(String userId) async {
    revokeUserSessionsCalls.add(userId);
  }

  @override
  Future<UserPage> listSignupRequests({String? cursor, int? limit}) async {
    final error = listError;
    if (error != null) throw error;
    final pending = usersById.values.where((u) => u.pending).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return UserPage(users: pending);
  }

  final List<
    ({
      String userId,
      List<String>? roles,
      LibraryAccess? libraryAccess,
      Permissions? permissions,
      bool? uploadEnabled,
    })
  >
  approveSignupCalls = [];

  @override
  Future<UserAccount> approveSignupRequest(
    String userId, {
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
  }) async {
    approveSignupCalls.add((
      userId: userId,
      roles: roles,
      libraryAccess: libraryAccess,
      permissions: permissions,
      uploadEnabled: uploadEnabled,
    ));
    final current = usersById[userId];
    if (current == null || !current.pending) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no such signup request',
        statusCode: 404,
      );
    }
    final approved = UserAccount(
      id: current.id,
      username: current.username,
      displayName: current.displayName,
      roles: roles ?? current.roles,
      createdAt: current.createdAt,
      libraryAccess: libraryAccess ?? current.libraryAccess,
      uploadEnabled: uploadEnabled ?? current.uploadEnabled,
      uploadQuotaBytes: uploadQuotaBytes ?? current.uploadQuotaBytes,
      permissions: permissions ?? current.permissions,
    );
    usersById[userId] = approved;
    return approved;
  }

  /// Ids rejected, in order.
  final List<String> rejectSignupCalls = [];

  @override
  Future<void> rejectSignupRequest(String userId) async {
    rejectSignupCalls.add(userId);
    usersById.remove(userId);
  }

  /// Invites by id.
  final Map<String, Invite> invitesById = {};
  int _inviteSeq = 0;

  @override
  Future<List<Invite>> listInvites() async {
    final error = listError;
    if (error != null) throw error;
    return invitesById.values.toList();
  }

  @override
  Future<InviteCreated> createInvite({
    String? note,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? maxUses,
    DateTime? expiresAt,
  }) async {
    final seq = _inviteSeq++;
    final created = InviteCreated(
      id: 'iv-FAKE$seq',
      note: note,
      roles: roles ?? const ['user'],
      libraryAccess: libraryAccess,
      permissions: permissions,
      uploadEnabled: uploadEnabled ?? false,
      maxUses: maxUses ?? 1,
      createdAt: DateTime.utc(2026, 7, 15),
      token: 'invite-token-$seq',
    );
    invitesById[created.id] = created;
    return created;
  }

  /// Ids revoked, in order.
  final List<String> revokeInviteCalls = [];

  @override
  Future<void> revokeInvite(String inviteId) async {
    revokeInviteCalls.add(inviteId);
    final current = invitesById[inviteId];
    if (current == null) return;
    invitesById[inviteId] = Invite(
      id: current.id,
      note: current.note,
      roles: current.roles,
      libraryAccess: current.libraryAccess,
      permissions: current.permissions,
      uploadEnabled: current.uploadEnabled,
      maxUses: current.maxUses,
      usedCount: current.usedCount,
      revoked: true,
      expiresAt: current.expiresAt,
      createdAt: current.createdAt,
      createdBy: current.createdBy,
    );
  }
}
