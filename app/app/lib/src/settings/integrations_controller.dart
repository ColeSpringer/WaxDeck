import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// The caller's scrobbling connection slots.
class ScrobblersController extends AsyncNotifier<List<Scrobbler>> {
  @override
  Future<List<Scrobbler>> build() =>
      ref.watch(repositoryProvider).listScrobblers();

  /// Connects ListenBrainz; errors propagate so the dialog surfaces the
  /// server's message (invalid token, unreachable service).
  Future<void> connectListenBrainz(String token, {String? apiUrl}) async {
    await ref
        .read(repositoryProvider)
        .connectListenBrainz(token, apiUrl: apiUrl);
    ref.invalidateSelf();
    await future;
  }

  Future<void> disconnect(String service) async {
    final repository = ref.read(repositoryProvider);
    if (service == 'lastfm') {
      await repository.disconnectLastfm();
    } else {
      await repository.disconnectListenBrainz();
    }
    ref.invalidateSelf();
    await future;
  }

  /// Mints the Last.fm authorization URL; the caller opens it in a
  /// browser and the server completes the link on the callback.
  Future<String> startLastfmConnect() =>
      ref.read(repositoryProvider).startLastfmConnect();
}

final scrobblersProvider =
    AsyncNotifierProvider<ScrobblersController, List<Scrobbler>>(
      ScrobblersController.new,
    );

/// The server-level Last.fm API credential state (administrators).
class ScrobblingAdminConfigController
    extends AsyncNotifier<ScrobblingAdminConfig> {
  @override
  Future<ScrobblingAdminConfig> build() =>
      ref.watch(repositoryProvider).getScrobblingConfig();

  /// Stores a credential pair, or clears the stored pair when both
  /// values are empty. Errors propagate so the dialog surfaces the
  /// server's message (half-set pair, unusable credentials).
  Future<void> save({required String apiKey, required String secret}) async {
    final saved = await ref
        .read(repositoryProvider)
        .putScrobblingConfig(apiKey: apiKey, secret: secret);
    state = AsyncData(saved);
    // Availability may have flipped; reload the connection slots so
    // the section updates without a revisit.
    ref.invalidate(scrobblersProvider);
  }
}

final scrobblingAdminConfigProvider =
    AsyncNotifierProvider<
      ScrobblingAdminConfigController,
      ScrobblingAdminConfig
    >(ScrobblingAdminConfigController.new);

/// The caller's app passwords for the compatibility APIs.
class AppPasswordsController extends AsyncNotifier<List<AppPassword>> {
  @override
  Future<List<AppPassword>> build() =>
      ref.watch(repositoryProvider).listAppPasswords();

  /// Creates one and returns the secret, shown exactly once.
  Future<AppPasswordCreated> create(String label) async {
    final created = await ref.read(repositoryProvider).createAppPassword(label);
    ref.invalidateSelf();
    await future;
    return created;
  }

  Future<void> revoke(String id) async {
    await ref.read(repositoryProvider).revokeAppPassword(id);
    ref.invalidateSelf();
    await future;
  }
}

final appPasswordsProvider =
    AsyncNotifierProvider<AppPasswordsController, List<AppPassword>>(
      AppPasswordsController.new,
    );

/// The server's notification relay configuration (administrators).
class NotificationConfigController extends AsyncNotifier<NotificationConfig> {
  @override
  Future<NotificationConfig> build() =>
      ref.watch(repositoryProvider).getNotificationConfig();

  Future<void> save({
    required String appriseUrl,
    String? targets,
    required List<String> enabledEvents,
  }) async {
    final saved = await ref
        .read(repositoryProvider)
        .putNotificationConfig(
          appriseUrl: appriseUrl,
          targets: targets,
          enabledEvents: enabledEvents,
        );
    state = AsyncData(saved);
  }

  Future<void> sendTest() => ref.read(repositoryProvider).testNotifications();
}

final notificationConfigProvider =
    AsyncNotifierProvider<NotificationConfigController, NotificationConfig>(
      NotificationConfigController.new,
    );

/// The caller's UnifiedPush registrations. Registering happens on the
/// Android client through its distributor; this surface lists and
/// revokes.
class PushRegistrationsController
    extends AsyncNotifier<List<PushRegistration>> {
  @override
  Future<List<PushRegistration>> build() =>
      ref.watch(repositoryProvider).listPushRegistrations();

  Future<void> remove(String pid) async {
    await ref.read(repositoryProvider).deletePushRegistration(pid);
    ref.invalidateSelf();
    await future;
  }
}

final pushRegistrationsProvider =
    AsyncNotifierProvider<PushRegistrationsController, List<PushRegistration>>(
      PushRegistrationsController.new,
    );
