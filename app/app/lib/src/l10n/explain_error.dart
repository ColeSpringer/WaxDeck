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
  'endpoint-failed' => l.errorEndpointFailed,
  'quota-exceeded' => l.errorQuotaExceeded,
  'storage-full' => l.errorStorageFull,
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

/// The sentence for a write that carried values somebody just typed.
///
/// The table answers on the code, which is right for an operation that
/// failed and wrong for a field that was refused: `invalid-request`
/// translated says only that something was wrong, while the server's own
/// sentence names the cron field it could not parse, the root that
/// already covers that path, or the alias two genres share. Those
/// endpoints validate precisely so they can say which value refused, and
/// flattening that leaves a form with nothing to look at.
///
/// So a refusal of the input keeps the server's words, and everything
/// else - a timeout, a 500, a code carrying no detail - reads from the
/// table. The same split the timezone dialog already makes, hoisted to
/// where the other forms can reach it.
/// `feature-unavailable` joins them under one condition: that it names
/// no `feature`. That code is an umbrella, and its params are what say
/// which refusal it is - so a parameterised one still reads from the
/// table, where the sentence is translated and specific. One with no
/// params has nothing there but the umbrella's own "this server is not
/// running the feature that request needs", which is exactly wrong for
/// the refusals that are about the request: an .nsp export saying no
/// part of this rule can be written is a sentence about what the person
/// built, and the server is running the feature fine.
String explainRefusal(AppLocalizations l10n, Object error) {
  if (error is! WaxDeckApiException || error.message.trim().isEmpty) {
    return explainError(l10n, error);
  }
  if (const {'invalid-request', 'conflict'}.contains(error.code)) {
    return error.message;
  }
  if (error.code == 'feature-unavailable' && error.params?['feature'] == null) {
    return error.message;
  }
  return explainError(l10n, error);
}

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
