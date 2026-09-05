import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';

/// The caller's scrobbling connection slots.
class ScrobblersController extends AsyncNotifier<List<Scrobbler>> {
  @override
  Future<List<Scrobbler>> build() {
    // Keyed on the account, not only on the server. A scrobble
    // connection is per user and the repository moves only when the
    // base URL does, so without this a same-server re-login reads the
    // departed account's connection back - which the radio menus gate
    // on, and would offer to mute a station for a scrobbler this
    // listener does not have.
    ref.watch(signedInAccountProvider);
    return ref.watch(repositoryProvider).listScrobblers();
  }

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

/// The notification event catalog, for the per-target checklist.
final notifyEventCatalogProvider = FutureProvider<List<NotifyEvent>>(
  (ref) => ref.watch(repositoryProvider).listNotificationEvents(),
);

/// The mutation surface a notification target list drives, shared by
/// the server- and personal-scope controllers so the widgets keep
/// static checking instead of duck-typing a dynamic controller.
abstract interface class NotificationTargetActions {
  Future<void> save({
    String? pid,
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted,
    int minIntervalSeconds,
  });
  Future<void> remove(String pid);
  Future<void> sendTest(String pid);
}

/// The server-scope notification targets (administrators). Save
/// errors propagate so the editor dialog surfaces the server's
/// message (bad config, private host, cap reached).
class ServerNotificationTargetsController
    extends AsyncNotifier<List<NotificationTarget>>
    implements NotificationTargetActions {
  @override
  Future<List<NotificationTarget>> build() =>
      ref.watch(repositoryProvider).listServerNotificationTargets();

  @override
  Future<void> save({
    String? pid,
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  }) async {
    final repository = ref.read(repositoryProvider);
    if (pid == null) {
      await repository.createServerNotificationTarget(
        kind: kind,
        label: label,
        config: config,
        enabledEvents: enabledEvents,
        muted: muted,
        minIntervalSeconds: minIntervalSeconds,
      );
    } else {
      await repository.updateServerNotificationTarget(
        pid: pid,
        label: label,
        config: config,
        enabledEvents: enabledEvents,
        muted: muted,
        minIntervalSeconds: minIntervalSeconds,
      );
    }
    ref.invalidateSelf();
    await future;
  }

  @override
  Future<void> remove(String pid) async {
    await ref.read(repositoryProvider).deleteServerNotificationTarget(pid);
    ref.invalidateSelf();
    await future;
  }

  /// Queues one test delivery; the outcome lands on the target's
  /// health fields, so the list refreshes to show it.
  @override
  Future<void> sendTest(String pid) async {
    await ref.read(repositoryProvider).testServerNotificationTarget(pid);
    ref.invalidateSelf();
  }
}

final serverNotificationTargetsProvider =
    AsyncNotifierProvider<
      ServerNotificationTargetsController,
      List<NotificationTarget>
    >(ServerNotificationTargetsController.new);

/// The caller's personal notification targets, UnifiedPush
/// registrations included (they are unifiedpush rows of the same
/// list).
class MyNotificationTargetsController
    extends AsyncNotifier<List<NotificationTarget>>
    implements NotificationTargetActions {
  @override
  Future<List<NotificationTarget>> build() =>
      ref.watch(repositoryProvider).listMyNotificationTargets();

  @override
  Future<void> save({
    String? pid,
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
    bool muted = false,
    int minIntervalSeconds = 0,
  }) async {
    final repository = ref.read(repositoryProvider);
    if (pid == null) {
      await repository.createMyNotificationTarget(
        kind: kind,
        label: label,
        config: config,
        enabledEvents: enabledEvents,
        muted: muted,
        minIntervalSeconds: minIntervalSeconds,
      );
    } else {
      await repository.updateMyNotificationTarget(
        pid: pid,
        label: label,
        config: config,
        enabledEvents: enabledEvents,
        muted: muted,
        minIntervalSeconds: minIntervalSeconds,
      );
    }
    ref.invalidateSelf();
    await future;
  }

  @override
  Future<void> remove(String pid) async {
    await ref.read(repositoryProvider).deleteMyNotificationTarget(pid);
    ref.invalidateSelf();
    await future;
  }

  @override
  Future<void> sendTest(String pid) async {
    await ref.read(repositoryProvider).testMyNotificationTarget(pid);
    ref.invalidateSelf();
  }
}

final myNotificationTargetsProvider =
    AsyncNotifierProvider<
      MyNotificationTargetsController,
      List<NotificationTarget>
    >(MyNotificationTargetsController.new);
