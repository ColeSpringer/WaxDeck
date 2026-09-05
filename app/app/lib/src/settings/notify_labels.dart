import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';

/// What a notification event is called, and what it is about.
///
/// The token is the boundary, the way the code is for errors and the rule
/// name is for health. The catalogue the server sends carries a
/// description in English and no title at all, which is why the rows drew
/// the raw wire token - `signup-requested` - as their heading. An event
/// this client knows gets a title of its own; one it does not falls back
/// to the server's own words.
String notifyEventTitle(AppLocalizations l10n, NotifyEvent event) =>
    _title(l10n, event.name) ?? event.name;

String notifyEventHelp(AppLocalizations l10n, NotifyEvent event) =>
    _help(l10n, event.name) ?? event.description;

/// The same table by wire token, for a surface holding an event name
/// without the catalogue row it came from: an inbox row carries the
/// token and the server's own wording, and nothing else.
String notifyTokenTitle(AppLocalizations l10n, String token, String fallback) =>
    _title(l10n, token) ?? fallback;

String notifyTokenHelp(AppLocalizations l10n, String token, String fallback) =>
    _help(l10n, token) ?? fallback;

String? _title(AppLocalizations l, String token) => switch (token) {
  'backup-completed' => l.notifBackupCompletedTitle,
  'backup-failed' => l.notifBackupFailedTitle,
  'episode-downloaded' => l.notifEpisodeDownloadedTitle,
  'feed-disabled' => l.notifFeedDisabledTitle,
  'import-completed' => l.notifImportCompletedTitle,
  'playlist-synced' => l.notifPlaylistSyncedTitle,
  'review-ready' => l.notifReviewReadyTitle,
  'signup-requested' => l.notifSignupRequestedTitle,
  _ => null,
};

String? _help(AppLocalizations l, String token) => switch (token) {
  'backup-completed' => l.notifBackupCompletedHelp,
  'backup-failed' => l.notifBackupFailedHelp,
  'episode-downloaded' => l.notifEpisodeDownloadedHelp,
  'feed-disabled' => l.notifFeedDisabledHelp,
  'import-completed' => l.notifImportCompletedHelp,
  'playlist-synced' => l.notifPlaylistSyncedHelp,
  'review-ready' => l.notifReviewReadyHelp,
  'signup-requested' => l.notifSignupRequestedHelp,
  _ => null,
};
