import 'package:flutter/material.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Drops a playlist cover from the in-memory image cache. The cover
/// lives at one stable URL whatever it holds, and the cache keys on that
/// URL, so a client that just changed the cover would keep painting the
/// old bytes until a restart. Call it after a cover write, with the URL
/// the cover had before: that is the one already in the cache.
Future<void> evictPlaylistCover(String? artUrl) async {
  if (artUrl == null) return;
  await NetworkImage(artUrl).evict();
}

/// A playlist's cover: the owner's upload, or the mosaic the server
/// builds from the members. Both arrive as one URL, so this draws the
/// same thing either way and falls back to the kind icon when a
/// playlist has neither (no member carries art yet).
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.playlist, required this.size});

  final Playlist playlist;

  /// Edge length in logical pixels. The cover is always square.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final artUrl = playlist.artUrl;
    final placeholder = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          playlist.isSmart ? Icons.auto_awesome : Icons.queue_music,
          size: size * 0.5,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size < 64 ? 4 : 12),
        child: artUrl == null
            ? placeholder
            : Image.network(
                artUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}
