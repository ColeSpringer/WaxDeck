import 'package:waxdeck_api/waxdeck_api.dart';

import 'gen/app_localizations.dart';

/// One sentence for an error surface.
///
/// The boundary between the two halves of WaxDeck is the machine `code`,
/// not the `message`: a known code renders this client's own translation,
/// an unknown one falls back to the server's sentence (the contract says
/// unknown codes stay opaque, and an English sentence beats no sentence),
/// and anything that is not an API failure at all gets the generic line -
/// a stack trace belongs to the defect log, never to a snackbar.
///
/// The server never localizes; it words its messages for a human reading
/// a log, and this is where they become copy.
String explainError(AppLocalizations l10n, Object error) {
  if (error is WaxDeckApiException) {
    return _byCode(l10n, error) ?? error.message;
  }
  return l10n.errorUnexpected;
}

/// The sentence for a code this client knows, or null for one it does not.
String? _byCode(AppLocalizations l, WaxDeckApiException e) => switch (e.code) {
  // Every code the spec's `Error` currently defines. A code added there
  // and not here fails `error_table_test.dart`, which reads the list out
  // of the committed bundle rather than out of a second copy of it.
  'invalid-request' => l.errorInvalidRequest,
  'unauthenticated' => l.errorUnauthenticated,
  'forbidden' => l.errorForbidden,
  'not-found' => l.errorNotFound,
  'conflict' => l.errorConflict,
  'internal' => l.errorInternal,
  'rate-limited' => l.errorRateLimited,
  'stream-stale' => l.errorStreamStale,
  'catalog-maintenance' => l.errorCatalogMaintenance,
  'catalog-busy' => l.errorCatalogBusy,
  'sync-reset' => l.errorSyncReset,
  'feed-unreachable' => l.errorFeedUnreachable,
  'source-unavailable' => l.errorSourceUnavailable,
  'directory-unavailable' => l.errorDirectoryUnavailable,
  'service-unreachable' => l.errorServiceUnreachable,
  'feature-unavailable' => _featureUnavailable(l, e),
  'endpoint-offline' => l.errorEndpointOffline,
  'quota-exceeded' => l.errorQuotaExceeded,
  'field-locked' => l.errorFieldLocked,
  'unsupported-format' => l.errorUnsupportedFormat,
  'read-only' => l.errorReadOnly,
  'transcode-limited' => l.errorTranscodeLimited,
  'timeout' => l.errorTimeout,
  // The codes the client mints for itself, which never appear in the
  // spec's list. Keying on the code is what neutralizes the English the
  // HTTP layer would otherwise put on screen. `waxdeck_api` owns the
  // transport three; the `local-` ones name a failure of this device,
  // and they exist because borrowing a spec code for one would tell a
  // listener the server said something it never said.
  'transport' => l.errorNetwork,
  'transport-timeout' => l.errorTransportTimeout,
  'transport-empty' => l.errorTransportEmpty,
  'local-channel-offline' => l.errorLocalChannelOffline,
  'local-command-timeout' => l.errorLocalCommandTimeout,
  'local-unregistered' => l.errorLocalUnregistered,
  // `local-protocol` deliberately has no arm: a malformed frame is a
  // defect, and its own diagnostic says more than a sentence could.
  _ => null,
};

/// `feature-unavailable` is an umbrella, and its `params` are what say
/// which refusal it is.
///
/// Params are best-effort by contract - a refusal that has them fills
/// them, one that does not is an ordinary error of that code - so an
/// unrecognised feature, or none at all, falls back to the general
/// sentence rather than guessing.
String _featureUnavailable(AppLocalizations l, WaxDeckApiException e) =>
    switch (e.params?['feature']) {
      'multi-part-audiobook' => l.errorMultiPartAudiobook,
      'windowed-track' => l.errorWindowedTrack,
      _ => l.errorFeatureUnavailable,
    };
