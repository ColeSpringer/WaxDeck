import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// The Android Auto browse tree, fed purely from the local mirror so it
/// works identically offline. Initial shape: a Library folder of the
/// mirrored items in title order (per-medium folders and richer
/// drill-down land with the matured Auto slice).
class MirrorBrowseSource implements BrowseSourcePort {
  MirrorBrowseSource(this.db);

  final MirrorDatabase db;

  static const _libraryId = 'library';

  /// Head units render lists, not infinite scrolls; cap the flat
  /// listing until the tree grows folders.
  static const _libraryCap = 500;

  @override
  Future<List<BrowseEntry>> children(String parentId) async {
    switch (parentId) {
      case browseRootId:
        return const [BrowseEntry(id: _libraryId, title: 'Library')];
      case _libraryId:
        final page = await mirrorItemsPage(db, limit: _libraryCap);
        return [
          for (final item in page.items)
            BrowseEntry(
              id: item.pid,
              title: item.title,
              subtitle: item.artist,
              playable: true,
            ),
        ];
      default:
        return const [];
    }
  }
}
