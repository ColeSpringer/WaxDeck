import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';

/// The display names of the services WaxDeck fetches covers from.
///
/// Proper nouns, so they are here rather than in the translation table:
/// "Cover Art Archive" is the archive's name in every language, and a
/// translator given it as a string would be asked to translate a brand.
/// An id with no entry falls through as itself, which is the honest
/// answer for a provider added upstream after this list.
const _providerNames = <String, String>{
  'coverartarchive': 'Cover Art Archive',
  'deezer': 'Deezer',
  'fanarttv': 'fanart.tv',
  'musicbrainz': 'MusicBrainz',
  'itunes': 'iTunes',
  'audnexus': 'Audnexus',
  'listenbrainz': 'ListenBrainz',
  'lrclib': 'LRCLIB',
};

/// How a picture's provenance reads under it.
///
/// One line, naming the producer - or the provider where a third party
/// supplied it, which is the case the mark exists for. An unrecognized
/// source draws nothing: the vocabulary is open, and inventing a
/// sentence for a word this build does not know would be worse than
/// saying nothing.
///
/// There is no `organize` case and there should not be: the organizer
/// moves files and never produces a picture, which is why the server's
/// own gate for an art attachment excludes it. Every other value the
/// gate accepts is here.
String? artSourceLabel(AppLocalizations l10n, ArtSource? source) {
  final from = source?.source;
  if (from == null || from.isEmpty) return null;
  switch (from) {
    case 'tag':
      return l10n.artSourceTag;
    case 'sidecar':
      return l10n.artSourceSidecar;
    case 'feed':
      return l10n.artSourceFeed;
    case 'user':
      return l10n.artSourceUser;
    case 'generated':
      return l10n.artSourceGenerated;
    case 'enrichment':
      final provider = source!.provider;
      if (provider == null || provider.isEmpty) {
        return l10n.artSourceProviderUnnamed;
      }
      return l10n.artSourceProvider(_providerNames[provider] ?? provider);
    default:
      return null;
  }
}

/// The label plus the borrowed note, for a caption that is a bare
/// string rather than a widget. A release showing one of its tracks'
/// covers is saying two things at once: where that track's picture came
/// from, and that the release did not choose it. Both, or the mark
/// reads as a choice the release never made.
String? artSourceLabelWithBorrow(AppLocalizations l10n, ArtSource? source) {
  final label = artSourceLabel(l10n, source);
  if (label == null) return null;
  if (!source!.derived) return label;
  // One key rather than two glued with a separator: both halves are
  // sentences, and a locale that wants them the other way round can
  // only say so if it owns the order.
  return l10n.artSourceBorrowedFrom(label, l10n.artSourceBorrowed);
}

/// A producer's name as it reads inside a tally ("3 from tags"), which
/// is a short noun rather than the sentence the mark under a cover
/// draws. [key] is a provider id where one supplied the value and a
/// source token otherwise, which is how the provenance rows key it.
///
/// An unrecognized key falls through as itself. The vocabulary is open,
/// and a wire token is a worse answer than a name only in the cases
/// this table has been taught - inventing a phrase for one it has not
/// would be worse than either.
String provenanceProducerName(AppLocalizations l10n, String key) {
  final named = _providerNames[key];
  if (named != null) return named;
  return switch (key) {
    'tag' => l10n.metadataSourceTag,
    'sidecar' => l10n.metadataSourceSidecar,
    'user' => l10n.metadataSourceUser,
    'organize' => l10n.metadataSourceOrganize,
    'enrichment' => l10n.metadataSourceEnrichment,
    'feed' => l10n.metadataSourceFeed,
    _ => key,
  };
}

/// The same for one artwork slot the entity holds itself, which carries
/// its own attribution rather than a resolve's.
String? artRoleSourceLabel(AppLocalizations l10n, ArtRoleInfo role) =>
    artSourceLabel(
      l10n,
      role.source == null
          ? null
          : ArtSource(source: role.source!, provider: role.provider),
    );

/// The same for a provenance row, which is always drawn behind a
/// prefix naming the artifact ("Artwork · {source}", "Lyrics ·
/// {source}"). That prefix is why two sources word themselves apart
/// from the standalone marks: `tag` reads as the bare "From the file"
/// - the standalone "Art from the file" would stutter behind "Artwork
/// ·" and call a lyric a picture behind "Lyrics ·" - and a lyric's
/// `sidecar` is an `.lrc` beside the track, which the artwork wording
/// (a folder image) describes not at all.
///
/// Callers must satisfy themselves that the item holds the artifact
/// first. A row can exist with nothing behind it - that is what locking
/// the field to stop a scan filling it looks like - and the source on
/// such a row was invented by whichever writer took the lock.
String? provenanceSourceLabel(AppLocalizations l10n, FieldProvenance row) {
  if (row.source == 'tag') return l10n.artSourceFromFile;
  if (row.field == 'lyrics' && row.source == 'sidecar') {
    return l10n.artSourceLyricsSidecar;
  }
  return artSourceLabel(
    l10n,
    ArtSource(source: row.source, provider: row.provider),
  );
}
