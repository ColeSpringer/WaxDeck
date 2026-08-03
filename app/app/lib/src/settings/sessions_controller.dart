import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// The caller's live sessions (the device list) with renaming and
/// revocation.
class SessionsController extends AsyncNotifier<List<DeviceSession>> {
  @override
  Future<List<DeviceSession>> build() =>
      ref.watch(repositoryProvider).listSessions();

  /// Relabels one session. The server trims and validates the name, so
  /// the list is reloaded from what it stored rather than from what was
  /// sent.
  Future<void> rename(String sessionId, String deviceName) async {
    await ref.read(repositoryProvider).renameSession(sessionId, deviceName);
    ref.invalidateSelf();
  }

  /// Revokes one session. Returns true when the revoked session was the
  /// current one, in which case the caller must sign out locally; the
  /// server side is already gone.
  Future<bool> revoke(String sessionId) async {
    final wasCurrent =
        state.value?.any((s) => s.id == sessionId && s.current) ?? false;
    await ref.read(repositoryProvider).revokeSession(sessionId);
    if (!wasCurrent) ref.invalidateSelf();
    return wasCurrent;
  }
}

final sessionsControllerProvider =
    AsyncNotifierProvider<SessionsController, List<DeviceSession>>(
      SessionsController.new,
    );
