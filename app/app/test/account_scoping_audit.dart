import 'package:flutter_test/flutter_test.dart';

import 'account_scoping_scan.dart';
import 'analysis_host.dart';

/// A kept-alive provider that fetches per-account rows must be keyed on the
/// account.
///
/// The repository moves only with the server, so a second account signing
/// in on the same server leaves every kept-alive provider holding the
/// first one's rows unless its build watches `signedInAccountProvider`.
/// Nothing in the compiler says so, and `account_reads_test.dart` only
/// covers the providers somebody remembered. This scan reads every
/// top-level provider in `lib`, and fails one that is kept alive, reaches
/// `repositoryProvider` from its build and does not watch the account,
/// unless [_sameForEveryAccount] names it with the reason its rows are the
/// same for every account. A provider that is exempt but no longer needs
/// to be fails too, so the map cannot rot.
///
/// What the scan sees, and what a green run cannot, is stated in
/// `account_scoping_scan.dart`.
void accountScopingAudit(AnalysisHost Function() host) {
  test('every kept-alive provider that reads the repository is keyed on the '
      'account or says why not', () async {
    final breaches = await breachesIn(
      host(),
      libFiles(host()),
      _sameForEveryAccount,
    );
    expect(
      breaches,
      isEmpty,
      reason:
          'A kept-alive provider that reads the repository from its build '
          'must `ref.watch(signedInAccountProvider)` there, or be named in '
          '_sameForEveryAccount with the reason its rows are the same for '
          'every account.\n\n${breaches.join('\n')}',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('every exemption has a reason', () {
    expect(
      _sameForEveryAccount.entries.where((e) => e.value.trim().isEmpty),
      isEmpty,
    );
  });
}

/// Providers that read the repository from a kept-alive build and answer
/// the same for every account, each with why.
const Map<String, String> _sameForEveryAccount = <String, String>{
  // Server-wide data: every account that can read it sees the same rows.
  'adminJobsProvider': _serverWide,
  'adminSettingsProvider': _serverWide,
  'adminUsersProvider': _serverWide,
  'auditProvider': _serverWide,
  'backupsProvider': _serverWide,
  'catalogCheckProvider': _serverWide,
  'diagnosticSummaryProvider': _serverWide,
  'diagnosticsProvider': _serverWide,
  'duplicatesProvider': _serverWide,
  'genreTreeProvider': _serverWide,
  'healthProvider': _serverWide,
  'invitesProvider': _serverWide,
  'libraryCountsProvider': _serverWide,
  'libraryMatchingProvider': _serverWide,
  'librariesProvider': _serverWide,
  'notifyEventCatalogProvider': _serverWide,
  'organizeProfilesProvider': _serverWide,
  'schedulesProvider': _serverWide,
  'scrobblingAdminConfigProvider': _serverWide,
  'serverHealthProvider': _serverWide,
  'serverNotificationTargetsProvider': _serverWide,
  'signupRequestsProvider': _serverWide,
  'similarityStatusProvider': _serverWide,
  'stagedRestoreProvider': _serverWide,
  'thumbnailCacheProvider': _serverWide,
  'transcodingActivityProvider': _serverWide,
  'transcodingLimitsProvider': _serverWide,
  'trashProvider': _serverWide,
  'upgradesProvider': _serverWide,
  // The server's own vocabulary and capabilities.
  'ruleFieldsProvider': _serverVocabulary,
  'uploadFormatSetsProvider': _serverVocabulary,
  // Stations are shared by all users, as the API spec says.
  'radioStationsProvider': _serverWide,
  // Read before any account exists, or by the sign-in screen itself.
  'bootstrapStatusProvider': _beforeSignIn,
  'oidcFlowProvider': _beforeSignIn,
  'oidcProvidersProvider': _beforeSignIn,
  // Probes the unauthenticated health endpoint for the server's build.
  'serverUpdatedProvider': _unauthenticatedProbe,
  // The account's own source, and what follows it through that.
  'authControllerProvider': _accountSource,
  'myAccountProvider': _followsAuth,
  'prefsControllerProvider': _followsAuth,
  // The public podcast and radio directories: no account's rows.
  'podcastDirectoryResultsProvider': _publicDirectory,
  'radioDirectoryResultsProvider': _radioDirectory,
  // Playback and device state that sign-out already resets.
  'artworkStoreProvider': _deviceState,
  'nowPlayingProvider': _deviceState,
  'queueRecheckProvider': _deviceState,
  // The offer is the account's last playback sessions, from the server.
  'queueRestoreProvider': _clearedLeavingAccount,
  'queueSourcePagerProvider': _deviceState,
  'radioNowPlayingArtProvider': _deviceState,
  // Plumbing that outlives an account: the repository itself, and the
  // pieces whose account is set once per session by their binder.
  'discordCoversProvider': _infrastructure,
  'downloadManagerProvider': _infrastructure,
  'repositoryProvider': _infrastructure,
  'syncEngineProvider': _infrastructure,
  // Whether the server takes the compound save: a capability of the server.
  'compoundSaveProvider': _serverVocabulary,
  // Commands, routes, the forget action and what carries a play to the
  // queue, which read only when they run.
  'commandRegistryProvider': _readsWhenRun,
  'connectBinderProvider': _readsWhenRun,
  'connectControllerProvider': _readsWhenRun,
  'forgetServerProvider': _readsWhenRun,
  'queueGatewayProvider': _readsWhenRun,
  'routerProvider': _readsWhenRun,
  // A track's waveform, held while that track plays.
  'trackWaveformProvider': _serverWide,
};

const _serverWide =
    'server-wide data: every account that can read it sees the same rows';
const _serverVocabulary =
    'the server\'s own vocabulary or capabilities, the same for every account';
const _beforeSignIn =
    'read before any account exists, or by the sign-in screen';
const _unauthenticatedProbe =
    'reads the unauthenticated health endpoint, which answers every '
    'account alike';
const _clearedLeavingAccount =
    'its rows are the account\'s own, but every road out of the account '
    '(a sign-out, a session the server ended, another account\'s session '
    'in its place, a dead stored one at launch) invalidates it through '
    'forgetQueueOnSignOut before another account\'s session is adopted';
const _accountSource = 'the source the account is derived from';
const _followsAuth =
    'follows the account through authControllerProvider, which it watches';
const _publicDirectory =
    'a public directory search: no account\'s rows are in it';
const _radioDirectory =
    'public directory rows; only their order follows the caller\'s locale '
    'region, and none of the caller\'s own data is in them';
const _deviceState =
    'playback or device state that sign-out resets, not an account\'s rows';
const _infrastructure =
    'plumbing that outlives an account; its account is set per session';
const _readsWhenRun =
    'reads the repository only when the app runs it, and holds none of '
    'its rows';
