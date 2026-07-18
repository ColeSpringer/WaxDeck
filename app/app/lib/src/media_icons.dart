import 'package:flutter/material.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Icon shown wherever an item has no artwork.
IconData mediaFallbackIcon(MediaType type) => switch (type) {
  MediaType.music => Icons.music_note,
  MediaType.podcast => Icons.podcasts,
  MediaType.audiobook => Icons.menu_book,
};
