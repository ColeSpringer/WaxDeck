import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../artwork/artwork_providers.dart';
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

  /// Appends items to [playlist] without opening it.
  ///
  /// Not on the detail controller: reaching for its notifier from
  /// elsewhere builds it, which is a playlist read plus every page of
  /// its members to add one track.
  Future<void> appendTo(Playlist playlist, List<String> itemPids) async {
    if (itemPids.isEmpty) return;
    await ref.read(repositoryProvider).addPlaylistItems(playlist.pid, itemPids);
    await evictPlaylistCover(ref, playlist.artUrl);
    // A no-op while nothing is watching it, which is the case here.
    ref.invalidate(playlistDetailProvider(playlist.pid));
    ref.invalidateSelf();
  }
}

/// Drops a playlist's cover from every cache holding it.
///
/// The server keys the generated cover on a hash of the ordered member
/// pids, so every membership write regenerates it at the same URL - the
/// one the caches key on. Pass the URL from before the write. Run even
/// where the cover may be an upload: the wire does not say which it is,
/// and being wrong costs one request that answers 304.
Future<void> evictPlaylistCover(Ref ref, String? artUrl) async {
  if (artUrl == null) return;
  await ref.read(artworkStoreProvider).evict(artUrl);
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

  /// How long the whole list runs; the wire carries no playlist
  /// duration, so it is summed from the members.
  Duration get duration => Duration(
    milliseconds: entries.fold(0, (total, e) => total + e.item.durationMs),
  );

  /// Whether this caller may edit the member list: a smart list's
  /// membership is its rule, and somebody else's is theirs.
  bool get isEditable => playlist.isOwner && !playlist.isSmart;
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
  ///
  /// The listing is deliberately not invalidated: a reorder changes
  /// nothing a card draws. The cover it does change, hence the evict.
  Future<void> reorder(List<String> itemPids) async {
    final base = state.value?.playlist.updatedAt;
    final cover = state.value?.playlist.artUrl;
    await ref
        .read(repositoryProvider)
        .replacePlaylistItems(pid, itemPids, baseUpdatedAt: base);
    await evictPlaylistCover(ref, cover);
    ref.invalidateSelf();
  }

  /// Drops the member at [position] in the stored order.
  ///
  /// Optimistic: a `Dismissible` still in the tree after its own
  /// dismissal throws. A refusal puts the list back from the server.
  Future<void> removeAt(int position) async {
    final current = state.value;
    final cover = current?.playlist.artUrl;
    if (current != null) {
      state = AsyncData<PlaylistView>(
        PlaylistView(
          playlist: current.playlist,
          entries: <PlaylistEntry>[
            for (final entry in current.entries)
              if (entry.position != position)
                // Everything after the hole moves down one, as it does
                // server-side, so a second removal names a live position.
                if (entry.position != null && entry.position! > position)
                  PlaylistEntry(position: entry.position! - 1, item: entry.item)
                else
                  entry,
          ],
        ),
      );
    }
    try {
      await ref.read(repositoryProvider).removePlaylistItemAt(pid, position);
      await evictPlaylistCover(ref, cover);
    } finally {
      ref.invalidateSelf();
      ref.invalidate(playlistsProvider);
    }
  }

  /// Appends to the end. The append endpoint rather than a replace:
  /// adding one track should not stake a claim on the order every other
  /// device is holding.
  Future<void> append(List<String> itemPids) async {
    if (itemPids.isEmpty) return;
    final cover = state.value?.playlist.artUrl;
    await ref.read(repositoryProvider).addPlaylistItems(pid, itemPids);
    await evictPlaylistCover(ref, cover);
    ref.invalidateSelf();
    ref.invalidate(playlistsProvider);
  }

  /// Uploads a cover, which stands in for the one the server generates
  /// from the members until it is reset.
  Future<void> setCover(Uint8List bytes) async {
    final cover = state.value?.playlist.artUrl;
    await ref
        .read(repositoryProvider)
        .setEntityArtwork('playlist', pid, bytes: bytes);
    await evictPlaylistCover(ref, cover);
    ref.invalidateSelf();
    ref.invalidate(playlistsProvider);
  }

  /// Drops an uploaded cover, which hands the slot back to the
  /// generated one rather than leaving the playlist bare.
  Future<void> resetCover() async {
    final cover = state.value?.playlist.artUrl;
    await ref.read(repositoryProvider).clearEntityArtwork('playlist', pid);
    await evictPlaylistCover(ref, cover);
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
