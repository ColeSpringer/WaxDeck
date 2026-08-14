import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
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
/// present them. One enumeration, because a field drawn on the header
/// and missing from the editor is a value nobody can correct.
enum AlbumIdentityField {
  barcode('barcode'),
  label('label'),
  catalogNumber('catalog_number'),
  media('media'),
  country('country');

  const AlbumIdentityField(this.wire);

  /// The field name the entity-edit endpoint takes.
  final String wire;

  String labelOf(AppLocalizations l10n) => switch (this) {
    AlbumIdentityField.barcode => l10n.musicFieldBarcode,
    AlbumIdentityField.label => l10n.musicFieldLabel,
    AlbumIdentityField.catalogNumber => l10n.musicFieldCatalogNumber,
    AlbumIdentityField.media => l10n.musicFieldMedia,
    AlbumIdentityField.country => l10n.musicFieldCountry,
  };

  String helpOf(AppLocalizations l10n) => switch (this) {
    AlbumIdentityField.barcode => l10n.musicFieldBarcodeHelp,
    AlbumIdentityField.label => l10n.musicFieldLabelHelp,
    AlbumIdentityField.catalogNumber => l10n.musicFieldCatalogNumberHelp,
    AlbumIdentityField.media => l10n.musicFieldMediaHelp,
    AlbumIdentityField.country => l10n.musicFieldCountryHelp,
  };
}

/// This album's stored value for one identity field.
///
/// Displayed verbatim, never re-validated here: a scan stores the tag as
/// written and an edit normalizes, so the two disagree by policy and the
/// screen showing "US & Europe" is showing the truth.
String albumIdentityValue(AlbumDetail album, AlbumIdentityField field) =>
    switch (field) {
      AlbumIdentityField.barcode => album.barcode ?? '',
      AlbumIdentityField.label => album.label ?? '',
      AlbumIdentityField.catalogNumber => album.catalogNumber ?? '',
      AlbumIdentityField.media => album.media ?? '',
      AlbumIdentityField.country => album.country ?? '',
    };
