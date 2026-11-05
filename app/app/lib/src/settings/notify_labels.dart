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

/// The line under an event's switch: the events whose title leaves
/// something out draw one ([_help] marks them), a known event the title
/// says plainly draws none, and one this client does not know falls back
/// to the server's own words.
String? notifyEventHelp(AppLocalizations l10n, NotifyEvent event) =>
    _help(l10n, event.name)?.checklistLine ??
    (_title(l10n, event.name) == null ? event.description : null);

/// The same table by wire token, for a surface holding an event name
/// without the catalogue row it came from: an inbox row carries the
/// token and the server's own wording, and nothing else.
String notifyTokenTitle(AppLocalizations l10n, String token, String fallback) =>
    _title(l10n, token) ?? fallback;

String notifyTokenHelp(AppLocalizations l10n, String token, String fallback) =>
    _help(l10n, token)?.text ?? fallback;

String? _title(AppLocalizations l, String token) => switch (token) {
  'backup-completed' => l.notifBackupCompletedTitle,
  'backup-failed' => l.notifBackupFailedTitle,
  'catalog-reset' => l.notifCatalogResetTitle,
  'episode-arrived' => l.notifEpisodeArrivedTitle,
  'episode-downloaded' => l.notifEpisodeDownloadedTitle,
  'feed-disabled' => l.notifFeedDisabledTitle,
  'gpodder-device-removed' => l.notifGpodderDeviceRemovedTitle,
  'health-fix-finished' => l.notifHealthFixFinishedTitle,
  'import-completed' => l.notifImportCompletedTitle,
  'job-failed' => l.notifJobFailedTitle,
  'job-finished' => l.notifJobFinishedTitle,
  'playlist-synced' => l.notifPlaylistSyncedTitle,
  'review-ready' => l.notifReviewReadyTitle,
  'signup-requested' => l.notifSignupRequestedTitle,
  'subscription-failed' => l.notifSubscriptionFailedTitle,
  'tool-task-failed' => l.notifToolTaskFailedTitle,
  _ => null,
};

_Help? _help(AppLocalizations l, String token) => switch (token) {
  'backup-completed' => _Help(l.notifBackupCompletedHelp, drawn: false),
  'backup-failed' => _Help(l.notifBackupFailedHelp, drawn: false),
  'catalog-reset' => _Help(l.notifCatalogResetHelp, drawn: true),
  'episode-arrived' => _Help(l.notifEpisodeArrivedHelp, drawn: false),
  'episode-downloaded' => _Help(l.notifEpisodeDownloadedHelp, drawn: false),
  'feed-disabled' => _Help(l.notifFeedDisabledHelp, drawn: false),
  'gpodder-device-removed' => _Help(
    l.notifGpodderDeviceRemovedHelp,
    drawn: true,
  ),
  'health-fix-finished' => _Help(l.notifHealthFixFinishedHelp, drawn: false),
  'import-completed' => _Help(l.notifImportCompletedHelp, drawn: true),
  'job-failed' => _Help(l.notifJobFailedHelp, drawn: false),
  'job-finished' => _Help(l.notifJobFinishedHelp, drawn: true),
  'playlist-synced' => _Help(l.notifPlaylistSyncedHelp, drawn: true),
  'review-ready' => _Help(l.notifReviewReadyHelp, drawn: false),
  'signup-requested' => _Help(l.notifSignupRequestedHelp, drawn: false),
  'subscription-failed' => _Help(l.notifSubscriptionFailedHelp, drawn: true),
  'tool-task-failed' => _Help(l.notifToolTaskFailedHelp, drawn: true),
  _ => null,
};

/// An event's sentence, and whether the checklist draws it under the
/// switch. The inbox uses the sentence either way, as the body of a row
/// the server sent none for.
class _Help {
  const _Help(this.text, {required this.drawn});

  final String text;
  final bool drawn;

  String? get checklistLine => drawn ? text : null;
}
