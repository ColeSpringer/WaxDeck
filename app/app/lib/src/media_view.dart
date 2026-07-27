/// Turning API models into the design system's plain view data.
///
/// `waxdeck_ui` never imports the API package (ADR-0016), so every
/// screen maps at the call site. These are the mappings more than one
/// screen would otherwise write differently: which domain a media type
/// belongs to, what shape its artwork takes, and how a URL becomes an
/// image. Everything else stays at its call site, where the screen knows
/// what its own rows mean.
library;

import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'artwork/artwork_store.dart';

WaxDomain waxDomainOf(MediaType type) => switch (type) {
  MediaType.music => WaxDomain.music,
  MediaType.podcast => WaxDomain.podcasts,
  MediaType.audiobook => WaxDomain.audiobooks,
};

/// Shape is a domain signal that reads at 40 px and survives greyscale.
/// Book covers vary between square (audio sources) and portrait (book
/// sources), so they are fitted on a matte rather than cropped to match
/// music and podcast art, which are square by nature.
ArtworkShape waxShapeOf(MediaType type) => switch (type) {
  MediaType.music || MediaType.podcast => ArtworkShape.square,
  MediaType.audiobook => ArtworkShape.portrait,
};

/// The artwork behind a URL the API already resolved, or null where
/// there is none: the placeholder monogram is a real state, not a
/// loading one.
///
/// The store decides what a URL costs — which size rung to ask the
/// server for, whether the bytes come off the network at all, what the
/// decode is bounded to. Screens only decide where the cover goes.
WaxArtwork? waxArtwork(ArtworkStore store, String? url) => store.source(url);
