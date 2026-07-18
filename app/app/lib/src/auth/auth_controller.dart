import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// Session state for the whole app.
///
/// Builds by probing the server session, so a live cookie (web) skips the
/// login screen entirely. [login] flips the state on success and rethrows
/// the structured API error on failure so the form can show it.
class AuthController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() {
    return ref.watch(repositoryProvider).getSession();
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final result = await ref
        .read(repositoryProvider)
        .login(username: username, password: password);
    state = AsyncData(SessionState(authenticated: true, user: result.user));
  }

  Future<void> logout() async {
    try {
      await ref.read(repositoryProvider).logout();
    } on WaxDeckApiException {
      // Losing the server-side revoke is acceptable; drop the local session.
    }
    state = const AsyncData(SessionState(authenticated: false));
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, SessionState>(AuthController.new);
