import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../sync/sync_providers.dart';
import 'page_reload/page_reload.dart';
import 'semantics_ids.dart';

/// Whether the live event channel is up, as the web build sees it.
///
/// Native has an engine with a status stream of its own; the web build's
/// listener has no state to read, so it reports here as it connects and
/// drops. Null until the first answer, which is what keeps the banner
/// off a client that has not tried to connect yet.
class LiveLink extends Notifier<bool?> {
  @override
  bool? build() => null;

  void report({required bool connected}) => state = connected;

  /// Back to "no answer yet", for a session ending: a client with no
  /// session is not a client with a broken connection.
  void forget() => state = null;
}

final liveLinkProvider = NotifierProvider<LiveLink, bool?>(LiveLink.new);

/// Whether this client is reaching the server's live channel, or null
/// where this build has no live channel to speak of (a widget test, a
/// session that has not started one).
///
/// The two platforms answer from different places for the same reason:
/// native runs a sync engine whose status is already a stream, and web
/// runs an invalidation listener that reports as it goes.
final liveConnectionProvider = Provider.autoDispose<bool?>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (engine != null) {
    if (!engine.started) return null;
    final status = ref.watch(syncStatusProvider).value ?? engine.current;
    return status.online;
  }
  return ref.watch(liveLinkProvider);
});

/// Whether the server was replaced under this client.
///
/// A restart is exactly when the socket comes back, so every reconnect
/// re-probes the unauthenticated health endpoint, which already carries
/// the build and the API version. The first answer is the baseline; a
/// later one that disagrees means the binary this client was talking to
/// is gone, and the bundle in this tab was built against it.
class ServerBuildWatcher extends Notifier<bool> {
  String? _baseline;

  @override
  bool build() {
    ref.listen(liveConnectionProvider, (previous, next) {
      if (next == true && previous != true) unawaited(_probe());
    }, fireImmediately: true);
    return false;
  }

  Future<void> _probe() async {
    try {
      final health = await ref.read(repositoryProvider).health();
      if (!ref.mounted) return;
      // The API version counts as much as the build: a bundle from
      // before a contract change is the case the banner exists for.
      final seen = '${health.version}/${health.apiVersion}';
      final baseline = _baseline;
      if (baseline == null) {
        _baseline = seen;
        return;
      }
      if (baseline != seen) state = true;
    } on Object catch (error) {
      // Best effort by design: a probe that cannot be made says nothing
      // about the build, and a banner on a failed probe would be a
      // guess. The console keeps the reason.
      //
      // Everything, not just the structured API error. This runs
      // unawaited, so anything escaping it is an unhandled zone error,
      // and the client maps only Dio's failures into that type: a
      // response the generated deserializer cannot build throws
      // something else entirely - which is precisely the shape of the
      // one event this probe exists to notice, a server replaced by a
      // build that answers differently.
      debugPrint('server build probe failed: $error');
    }
  }
}

final serverUpdatedProvider = NotifierProvider<ServerBuildWatcher, bool>(
  ServerBuildWatcher.new,
);

/// The shell's standing messages about the app's own state.
///
/// Self-hosters restart and upgrade servers constantly and the web
/// client is embedded in the binary, so both events are visible here
/// rather than mysterious: a dropped socket says it is reconnecting
/// instead of leaving actions to fail one at a time, and a server that
/// came back as a different build says so before a stale bundle meets a
/// changed API.
List<Widget> lifecycleBanners(WidgetRef ref) {
  final connected = ref.watch(liveConnectionProvider);
  final updated = ref.watch(serverUpdatedProvider);
  return <Widget>[
    if (connected == false)
      const WaxBanner(
        message:
            'Reconnecting to the server. Anything already playing '
            'keeps playing.',
        glyph: WaxIcons.offline,
        semanticsId: SemanticsIds.bannerReconnecting,
      ),
    if (updated)
      WaxBanner(
        tone: WaxBannerTone.notice,
        message: canReloadPage
            ? 'WaxDeck was updated. Reload to get the new version.'
            : 'The server was updated. Restart WaxDeck to catch up.',
        actionLabel: canReloadPage ? 'Reload' : null,
        onAction: canReloadPage ? reloadPage : null,
        semanticsId: SemanticsIds.bannerUpdated,
        actionSemanticsId: SemanticsIds.bannerUpdatedReload,
      ),
  ];
}
