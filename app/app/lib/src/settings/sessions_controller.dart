import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// The caller's live sessions (the device list) with revocation.
class SessionsController extends AsyncNotifier<List<DeviceSession>> {
  @override
  Future<List<DeviceSession>> build() =>
      ref.watch(repositoryProvider).listSessions();

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
