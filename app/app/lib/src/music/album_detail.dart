import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// Whether a failed read is worth trying again.
///
/// Riverpod retries a failed provider with backoff, which is right for a
/// dropped connection and wrong for a refusal: an album the server does
/// not have will not appear on the fourth ask, and a header that quietly
/// re-asks every few seconds for a pid that will never resolve is a
/// background loop nobody can see. Anything that is not the server saying
/// no keeps the default.
Duration? _retryUnlessRefused(int attempt, Object error) {
  if (error case WaxDeckApiException(
    statusCode: final int status,
  ) when status >= 400 && status < 500) {
    return null;
  }
  return Duration(milliseconds: 200 * (1 << attempt.clamp(0, 6)));
}

/// One album entity's identity, for the album header and the editor.
///
/// Auto-disposed and per-pid, like [itemDetailProvider] beside it: the
/// header is the only screen that reads it and holding every album a
/// listener passed through would be a cache nothing invalidates.
final albumDetailProvider = FutureProvider.autoDispose
    .family<AlbumDetail, String>(
      (ref, pid) => ref.watch(repositoryProvider).getAlbum(pid),
      retry: _retryUnlessRefused,
    );

/// The curated overrides on one album entity, keyed by field name.
///
/// Read beside the album itself rather than folded into it: curation is
/// the editor's business (which fields a user set, which are locked) and
/// the header has no use for it.
final albumCurationProvider = FutureProvider.autoDispose
    .family<Map<String, EntityCuratedField>, String>((ref, pid) async {
      final rows = await ref
          .watch(repositoryProvider)
          .getEntityCuration('album', pid);
      return <String, EntityCuratedField>{
        for (final row in rows) row.field: row,
      };
    }, retry: _retryUnlessRefused);

/// The five edition columns, in the order the editor and the header both
/// present them, with the label each carries and the wire name the entity
/// edit takes.
///
/// One list, because the read surface and the write surface have to agree
/// about what an album's identity *is*: a field drawn on the header and
/// missing from the editor is a value nobody can correct.
const albumIdentityFields = <({String name, String label, String help})>[
  (
    name: 'barcode',
    label: 'Barcode',
    help: 'UPC or EAN, normalized to digits on save',
  ),
  (name: 'label', label: 'Label', help: 'The issuing label'),
  (
    name: 'catalog_number',
    label: 'Catalog number',
    help: "The label's number for this release",
  ),
  (
    name: 'media',
    label: 'Media',
    help: 'What it was pressed on - CD, 2xVinyl, Digital Media',
  ),
  (
    name: 'country',
    label: 'Country',
    help: 'Two-letter code (GB), an alpha-3 or UK alias, or XW/XE',
  ),
];

/// This album's stored value for one identity field.
///
/// Displayed verbatim, never re-validated here: a scan stores the tag as
/// written and an edit normalizes, so the two disagree by policy and the
/// screen showing "US & Europe" is showing the truth.
String albumIdentityValue(AlbumDetail album, String field) => switch (field) {
  'barcode' => album.barcode ?? '',
  'label' => album.label ?? '',
  'catalog_number' => album.catalogNumber ?? '',
  'media' => album.media ?? '',
  'country' => album.country ?? '',
  _ => '',
};
