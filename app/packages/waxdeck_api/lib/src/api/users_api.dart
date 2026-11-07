import '../models.dart';

/// Accounts, invites, app passwords and per-user preferences.
abstract interface class UsersApi {
  /// `GET /users/me/app-passwords`: the caller's app passwords.
  Future<List<AppPassword>> listAppPasswords();

  /// `POST /users/me/app-passwords`: creates an app password; the
  /// returned secret is visible exactly once.
  Future<AppPasswordCreated> createAppPassword(String label);

  /// `DELETE /users/me/app-passwords/{id}`: revokes an app password.
  Future<void> revokeAppPassword(String id);

  /// `GET /users/me/prefs`: the caller's synced preferences.
  Future<Prefs> getPrefs();

  /// `PUT /users/me/prefs`: replaces the caller's synced preferences and
  /// returns the stored document. Replace semantics: start from [getPrefs].
  Future<Prefs> putPrefs(Prefs prefs);

  /// `GET /users`: keyset-paginated accounts (administrators).
  Future<UserPage> listUsers({String? cursor, int? limit});

  /// `POST /users`: creates an account (administrators).
  Future<UserAccount> createUser({
    required String username,
    required String password,
    String? displayName,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  });

  /// `PATCH /users/{userId}`: partial account update (administrators).
  /// Absent fields keep their stored values.
  Future<UserAccount> updateUser(
    String userId, {
    String? displayName,
    List<String>? roles,
    bool? disabled,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  });

  /// `GET /users/{userId}`: one account (administrators).
  Future<UserAccount> getUser(String userId);

  /// `DELETE /users/{userId}`: deletes an account (administrators). Its
  /// shared playlists go to the caller with their entries and its private
  /// ones are deleted (`transfer`, the default); [playlists] `delete`
  /// deletes them all.
  Future<void> deleteUser(String userId, {String playlists = 'transfer'});

  /// `PUT /users/{userId}/password`: sets an account's password.
  ///
  /// [currentPassword] is required when changing your own (administrators
  /// included) and omitted when an administrator resets somebody else's.
  /// A wrong value answers `forbidden`, which is the distinction the
  /// settings form shows against the field rather than as a failure.
  Future<void> setUserPassword(
    String userId,
    String newPassword, {
    String? currentPassword,
  });

  /// `DELETE /users/{userId}/sessions`: revokes every live session of
  /// one account (administrators).
  Future<void> revokeUserSessions(String userId);

  /// `GET /users/requests`: pending signup requests, oldest first
  /// (administrators).
  Future<UserPage> listSignupRequests({String? cursor, int? limit});

  /// `POST /users/requests/{userId}/approve`: activates a pending
  /// signup, optionally overriding roles, access, and permissions
  /// (administrators).
  Future<UserAccount> approveSignupRequest(
    String userId, {
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
  });

  /// `POST /users/requests/{userId}/reject`: rejects and removes a
  /// pending signup (administrators).
  Future<void> rejectSignupRequest(String userId);

  /// `GET /invites`: every invite, revoked and expired included
  /// (administrators).
  Future<List<Invite>> listInvites();

  /// `POST /invites`: mints an invite; the returned token is visible
  /// exactly once (administrators).
  Future<InviteCreated> createInvite({
    String? note,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? maxUses,
    DateTime? expiresAt,
  });

  /// `DELETE /invites/{inviteId}`: revokes an invite (administrators).
  Future<void> revokeInvite(String inviteId);
}
