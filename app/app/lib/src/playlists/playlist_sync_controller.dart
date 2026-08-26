import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// One playlist's source binding, keyed by pid. Null is the unbound
/// state - the endpoint's 404 - not a failure; only the owner's
/// surfaces watch this, since the endpoint is owner-only.
class PlaylistSyncController extends AsyncNotifier<PlaylistSource?> {
  PlaylistSyncController(this.pid);

  final String pid;

  @override
  Future<PlaylistSource?> build() async {
    try {
      return await ref.watch(repositoryProvider).getPlaylistSource(pid);
    } on WaxDeckApiException catch (e) {
      if (e.code == 'not-found') return null;
      rethrow;
    }
  }

  /// Stores a binding, replacing any previous one whole.
  Future<PlaylistSource> bind({
    required String mode,
    String? url,
    String? source,
    String? payload,
    int? intervalHours,
  }) async {
    final stored = await ref
        .read(repositoryProvider)
        .setPlaylistSource(
          pid,
          mode: mode,
          url: url,
          source: source,
          payload: payload,
          intervalHours: intervalHours,
        );
    if (ref.mounted) state = AsyncData(stored);
    return stored;
  }

  /// Removes the binding; the playlist and its members stay.
  Future<void> unbind() async {
    await ref.read(repositoryProvider).unbindPlaylistSource(pid);
    if (ref.mounted) state = const AsyncData(null);
  }

  /// Queues a sync run now; the health surface catches up through the
  /// next read.
  Future<ToolTask> syncNow() async {
    final task = await ref.read(repositoryProvider).syncPlaylistSource(pid);
    if (ref.mounted) ref.invalidateSelf();
    return task;
  }

  /// Dry-runs the reconciler: with arguments, over those prospective
  /// settings; without, over the stored binding.
  Future<PlaylistSyncPreview> preview({
    String? mode,
    String? url,
    String? source,
    String? payload,
    int? intervalHours,
  }) => ref
      .read(repositoryProvider)
      .previewPlaylistSync(
        pid,
        mode: mode,
        url: url,
        source: source,
        payload: payload,
        intervalHours: intervalHours,
      );
}

/// Failure-final: an unbound playlist answers as data (null), so a real
/// error here is a broken read that retrying would only stretch into
/// thirteen seconds of skeleton.
final playlistSyncProvider =
    AsyncNotifierProvider.family<
      PlaylistSyncController,
      PlaylistSource?,
      String
    >(PlaylistSyncController.new, retry: (_, _) => null);
