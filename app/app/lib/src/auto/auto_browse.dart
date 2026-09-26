import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import '../l10n/l10n.dart';

/// The Android Auto browse tree, fed purely from the local mirror so it
/// works identically offline: Continue for in-progress listening,
/// per-medium folders, and Downloads for what is guaranteed playable
/// with no connectivity.
class MirrorBrowseSource implements BrowseSourcePort {
  MirrorBrowseSource(this.db, {required this.l10n});

  final MirrorDatabase db;

  /// The app's copy now, read at each browse so the folders follow a
  /// change of language the next time the car asks.
  final AppLocalizations Function() l10n;

  static const _continueId = 'continue';
  static const _musicId = 'music';
  static const _podcastsId = 'podcasts';
  static const _booksId = 'books';
  static const _downloadsId = 'downloads';

  /// Head units render lists, not infinite scrolls; cap every folder.
  static const _folderCap = 300;

  @override
  Future<List<BrowseEntry>> children(String parentId) async {
    switch (parentId) {
      case browseRootId:
        final copy = l10n();
        return [
          BrowseEntry(id: _continueId, title: copy.autoFolderContinue),
          BrowseEntry(id: _musicId, title: copy.autoFolderMusic),
          BrowseEntry(id: _podcastsId, title: copy.autoFolderPodcasts),
          BrowseEntry(id: _booksId, title: copy.autoFolderAudiobooks),
          BrowseEntry(id: _downloadsId, title: copy.autoFolderDownloads),
        ];
      case _continueId:
        final pids = await mirrorInProgressPids(db);
        return _hydrate(pids);
      case _downloadsId:
        final pids = await mirrorDownloadedPids(db);
        return _hydrate(pids);
      case _musicId:
        return _mediumFolder(MediaType.music);
      case _podcastsId:
        return _mediumFolder(MediaType.podcast);
      case _booksId:
        return _mediumFolder(MediaType.audiobook);
      default:
        return const [];
    }
  }

  Future<List<BrowseEntry>> _mediumFolder(MediaType medium) async {
    final page = await mirrorItemsPage(
      db,
      mediaType: medium,
      limit: _folderCap,
    );
    return [
      for (final item in page.items)
        BrowseEntry(
          id: item.pid,
          title: item.title,
          subtitle: item.artist,
          playable: true,
        ),
    ];
  }

  Future<List<BrowseEntry>> _hydrate(List<String> pids) async {
    final out = <BrowseEntry>[];
    for (final pid in pids) {
      final item = await mirrorItemByPid(db, pid);
      if (item == null) continue;
      out.add(
        BrowseEntry(
          id: item.pid,
          title: item.title,
          subtitle: item.artist,
          playable: true,
        ),
      );
    }
    return out;
  }
}
