import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';

/// What a health rule is called, in this client's words.
///
/// The server sends a label of its own beside the token, and it is always
/// English. So the token is the boundary here, exactly as the code is for
/// errors: a rule this client knows renders its own translation, a rule
/// it does not falls back to the server's label, and the raw token is the
/// last resort - a server ahead of this app still draws a readable table
/// rather than a blank column.
String healthRuleLabel(AppLocalizations l10n, HealthRuleCount rule) =>
    healthRuleName(l10n, rule.rule) ?? rule.label ?? rule.rule;

/// What sort of entity a duplicate finding is about.
///
/// An open string in the contract, like every other vocabulary the
/// client draws, so one this build has not heard of shows as the
/// server wrote it.
String healthEntityKind(AppLocalizations l10n, String token) => switch (token) {
  'artist' => l10n.healthEntityArtist,
  'album' => l10n.healthEntityAlbum,
  'release-group' => l10n.healthEntityReleaseGroup,
  'genre' => l10n.healthEntityGenre,
  _ => token,
};

/// The same, for a surface holding the token alone.
///
/// The drill-in screen is reached by route, so a rule arrives as the
/// path segment it was named by and there is no server label beside it.
/// Null for a rule this client does not know, which is the token itself
/// and is what the caller draws.
String? healthRuleName(AppLocalizations l10n, String token) =>
    _byToken(l10n, token);

String? _byToken(AppLocalizations l, String token) => switch (token) {
  'corrupt-audio' => l.healthCorruptAudio,
  'duration-mismatch' => l.healthDurationMismatch,
  'genre-whitelist' => l.healthGenreWhitelist,
  'legacy-tags' => l.healthLegacyTags,
  'missing-art' => l.healthMissingArt,
  'missing-asin' => l.healthMissingAsin,
  'missing-genre' => l.healthMissingGenre,
  'missing-lyrics' => l.healthMissingLyrics,
  'missing-mbid' => l.healthMissingMbid,
  'missing-narrator' => l.healthMissingNarrator,
  'missing-year' => l.healthMissingYear,
  'path-mismatch' => l.healthPathMismatch,
  'small-art' => l.healthSmallArt,
  'write-unsynced' => l.healthWriteUnsynced,
  _ => null,
};

/// What an install lacks to fix a rule, from the summary's code. A code
/// this build does not know still says the fix cannot run.
String healthFixBlockedReason(AppLocalizations l10n, String code) =>
    switch (code) {
      'needs-contact' => l10n.healthFixBlockedContact,
      'needs-lyrics-source' => l10n.healthFixBlockedLyricsSource,
      'needs-art-source' => l10n.healthFixBlockedArtSource,
      'needs-genre-source' => l10n.healthFixBlockedGenreSource,
      'needs-book-source' => l10n.healthFixBlockedBookSource,
      'no-managed-library' => l10n.healthFixBlockedNoManaged,
      'read-only' => l10n.healthFixBlockedReadOnly,
      _ => l10n.healthFixBlockedOther,
    };
