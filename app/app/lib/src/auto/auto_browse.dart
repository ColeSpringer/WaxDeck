import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// The Android Auto browse tree, fed purely from the local mirror so it
/// works identically offline: Continue for in-progress listening,
/// per-medium folders, and Downloads for what is guaranteed playable
/// with no connectivity.
///
/// The folder names are English until this port learns a locale. It is
/// built from a database rather than from an element, so there is no
/// `BuildContext` to read one through, and it is deferred with the
/// media-session strings it belongs beside.
class MirrorBrowseSource implements BrowseSourcePort {
  MirrorBrowseSource(this.db);

  final MirrorDatabase db;

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
        return const [
          BrowseEntry(id: _continueId, title: 'Continue'),
          BrowseEntry(id: _musicId, title: 'Music'),
          BrowseEntry(id: _podcastsId, title: 'Podcasts'),
          BrowseEntry(id: _booksId, title: 'Audiobooks'),
          BrowseEntry(id: _downloadsId, title: 'Downloads'),
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
