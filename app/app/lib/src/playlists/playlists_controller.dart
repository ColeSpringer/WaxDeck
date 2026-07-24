import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// The playlists visible to the caller: their own plus every shared
/// one. The listing is small (a household's playlists), so one generous
/// page covers it; refresh re-fetches from the top.
class PlaylistsController extends AsyncNotifier<List<Playlist>> {
  static const pageSize = 200;

  @override
  Future<List<Playlist>> build() async {
    final page = await ref
        .watch(repositoryProvider)
        .listPlaylists(limit: pageSize);
    return page.playlists;
  }

  /// Creates a playlist and reloads the list. Errors propagate so the
  /// dialog can surface the server's message (rule validation text
  /// names the offending condition).
  Future<Playlist> create({
    required String name,
    required String kind,
    String? visibility,
    SmartRule? rule,
    List<String> itemPids = const [],
  }) async {
    final created = await ref
        .read(repositoryProvider)
        .createPlaylist(
          name: name,
          kind: kind,
          visibility: visibility,
          rule: rule,
          itemPids: itemPids,
        );
    // Invalidation alone drives the refresh. Awaiting the rebuilt
    // future here can starve on a busy server: every play-state event
    // invalidates this provider, and each invalidation replaces the
    // future the caller would be waiting on.
    ref.invalidateSelf();
    return created;
  }

  /// Imports a pasted M3U document as a static playlist.
  Future<M3uImportResult> importM3u({
    required String name,
    required String content,
    String? visibility,
  }) async {
    final result = await ref
        .read(repositoryProvider)
        .importPlaylistM3u(
          name: name,
          content: content,
          visibility: visibility,
        );
    ref.invalidateSelf();
    return result;
  }

  /// Imports a pasted playlist export (Spotify, Apple Music, YouTube
  /// Music, generic CSV, or a plain text list) as a static playlist.
  Future<PlaylistImportResult> importExport({
    required String source,
    String? name,
    String? payload,
    List<PortableRef>? refs,
  }) async {
    final result = await ref
        .read(repositoryProvider)
        .importPlaylist(
          source: source,
          name: name,
          payload: payload,
          refs: refs,
        );
    ref.invalidateSelf();
    return result;
  }
}

final playlistsProvider =
    AsyncNotifierProvider<PlaylistsController, List<Playlist>>(
      PlaylistsController.new,
    );

/// One playlist's header plus its full member list. Playlist pages are
/// fetched to completion: a playlist is a bounded, user-curated list,
/// and the screens want exact counts and durations.
class PlaylistView {
  const PlaylistView({required this.playlist, required this.entries});

  final Playlist playlist;
  final List<PlaylistEntry> entries;
}

class PlaylistDetailController extends AsyncNotifier<PlaylistView> {
  PlaylistDetailController(this.pid);

  final String pid;

  @override
  Future<PlaylistView> build() async {
    final repository = ref.watch(repositoryProvider);
    final playlist = await repository.getPlaylist(pid);
    final entries = <PlaylistEntry>[];
    String? cursor;
    do {
      final page = await repository.listPlaylistItems(
        pid,
        cursor: cursor,
        limit: 500,
      );
      entries.addAll(page.entries);
      cursor = page.nextCursor;
    } while (cursor != null);
    return PlaylistView(playlist: playlist, entries: entries);
  }

  /// Renames or re-shares the playlist in place. Named [edit] because
  /// AsyncNotifier already claims `update`.
  Future<void> edit({String? name, String? visibility}) async {
    await ref
        .read(repositoryProvider)
        .updatePlaylist(pid, name: name, visibility: visibility);
    ref.invalidateSelf();
    ref.invalidate(playlistsProvider);
  }

  /// Replaces a smart playlist's rule in place; the pid is stable, so
  /// the caller keeps this detail view. Returns the updated playlist.
  Future<Playlist> replaceRule(SmartRule rule) async {
    final next = await ref
        .read(repositoryProvider)
        .updatePlaylist(pid, rule: rule);
    ref.invalidateSelf();
    ref.invalidate(playlistsProvider);
    return next;
  }

  Future<void> delete() async {
    await ref.read(repositoryProvider).deletePlaylist(pid);
    ref.invalidate(playlistsProvider);
  }

  /// Replaces the full member order; this is the reorder primitive. The
  /// stored `updatedAt` rides along as the lost-update guard.
  Future<void> reorder(List<String> itemPids) async {
    final base = state.value?.playlist.updatedAt;
    await ref
        .read(repositoryProvider)
        .replacePlaylistItems(pid, itemPids, baseUpdatedAt: base);
    ref.invalidateSelf();
  }

  Future<void> removeAt(int position) async {
    await ref.read(repositoryProvider).removePlaylistItemAt(pid, position);
    ref.invalidateSelf();
    ref.invalidate(playlistsProvider);
  }

  /// Uploads a cover, which stands in for the one the server generates
  /// from the members until it is reset.
  Future<void> setCover(Uint8List bytes) async {
    await ref
        .read(repositoryProvider)
        .setEntityArtwork('playlist', pid, bytes: bytes);
    ref.invalidateSelf();
    ref.invalidate(playlistsProvider);
  }

  /// Drops an uploaded cover, which hands the slot back to the
  /// generated one rather than leaving the playlist bare.
  Future<void> resetCover() async {
    await ref.read(repositoryProvider).clearEntityArtwork('playlist', pid);
    ref.invalidateSelf();
    ref.invalidate(playlistsProvider);
  }
}

final playlistDetailProvider =
    AsyncNotifierProvider.family<
      PlaylistDetailController,
      PlaylistView,
      String
    >(PlaylistDetailController.new);

/// The rule vocabulary, fetched once per session and on invalidation.
final ruleFieldsProvider = FutureProvider<RuleFields>((ref) {
  return ref.watch(repositoryProvider).getRuleFields();
});
