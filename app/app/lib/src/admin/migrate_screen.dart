import 'dart:async';

import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../settings/integrations_controller.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../tools/tasks_screen.dart';
import '../uploads/file_picker_port.dart';
import 'admin_console.dart';
import 'users_screen.dart';

/// The importable sources, and what each one needs to be asked for.
/// Podcast feeds move by OPML, which has no affordance in the podcasts
/// UI yet, so it is not offered here.
enum _MigrationSource {
  navidrome('navidrome'),
  subsonic('subsonic'),
  audiobookshelf('audiobookshelf'),
  jellyfin('jellyfin'),
  lastfm('lastfm'),
  listenbrainz('listenbrainz'),
  spotify('spotify');

  const _MigrationSource(this.wireName);

  final String wireName;

  /// Most of these are bare product names, which read the same in every
  /// language; two carry a word that does not.
  String labelOf(AppLocalizations l10n) => switch (this) {
    navidrome => 'Navidrome',
    subsonic => l10n.adminMigrateSubsonicServer,
    audiobookshelf => 'Audiobookshelf',
    jellyfin => l10n.adminMigrateJellyfin,
    lastfm => l10n.adminMigrateLastfm,
    listenbrainz => l10n.adminMigrateListenBrainz,
    spotify => l10n.adminMigrateSpotifyExport,
  };

  /// Whether the form asks for the source server's address, and whether
  /// it insists on one: ListenBrainz defaults to its own host, so the
  /// field is an override rather than a requirement.
  bool get usesUrl => this != lastfm && this != spotify;
  bool get needsUrl => usesUrl && this != listenbrainz;

  /// Which credential fields the form draws. Jellyfin takes either a
  /// login or an API key, so it draws all three.
  bool get usesUsername => this != spotify && this != audiobookshelf;
  bool get usesPassword =>
      this == navidrome || this == subsonic || this == jellyfin;
  bool get usesToken =>
      this == audiobookshelf || this == jellyfin || this == listenbrainz;

  /// Whether the credential is optional: a public listening history
  /// answers without one.
  bool get tokenOptional => this == listenbrainz;

  /// Whether this source reads an uploaded export rather than a server.
  bool get usesExport => this == spotify;

  /// What the source actually carries. A switch for something it does
  /// not hold reads as a choice, and turning it off would change
  /// nothing: only the Subsonic family keeps a per-song rating, and
  /// only a server that tracks position has one to import.
  bool get usesRatings => this == navidrome || this == subsonic;
  bool get usesProgress =>
      this == navidrome ||
      this == subsonic ||
      this == audiobookshelf ||
      this == jellyfin;
}

/// One-shot import of stars, ratings, history, and progress from
/// another server, running server-side as a tool task.
class MigrateScreen extends ConsumerStatefulWidget {
  const MigrateScreen({super.key});

  @override
  ConsumerState<MigrateScreen> createState() => _MigrateScreenState();
}

class _MigrateScreenState extends ConsumerState<MigrateScreen> {
  final _serverUrl = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _token = TextEditingController();
  var _source = _MigrationSource.navidrome;

  /// The account the writes land on; null is the signed-in one, which
  /// is the administrator moving their own library.
  String? _account;

  /// The uploaded export a file-reading source will import from, and
  /// the name it was uploaded under.
  MigrationExport? _export;
  String _exportName = '';
  var _uploading = false;
  var _dryRun = false;
  var _stars = true;
  var _ratings = true;
  var _history = true;
  var _progress = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    // Every field the submit gate reads: what counts as a complete form
    // is per source now, so a rebuild on the address alone would leave
    // the button disabled after the last credential was typed.
    for (final field in [_serverUrl, _username, _password, _token]) {
      field.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _serverUrl.dispose();
    _username.dispose();
    _password.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final router = GoRouter.of(context);
    try {
      await ref
          .read(repositoryProvider)
          .createMigration(
            source: _source.wireName,
            serverUrl: _source.usesUrl ? _serverUrl.text.trim() : null,
            accountId: _targetAccount(),
            username: _source.usesUsername ? _username.text.trim() : null,
            // Jellyfin takes either, and what was typed decides: an
            // empty password with a key in the token field is the key
            // path, which the server records at the order rather than
            // guessing at run time.
            password: _source.usesPassword ? _password.text : null,
            token: _source.usesToken ? _token.text.trim() : null,
            exportId: _source.usesExport ? _export?.pid : null,
            options: MigrationOptions(
              stars: _stars,
              ratings: _ratings,
              history: _history,
              progress: _progress,
            ),
            dryRun: _dryRun,
          );
      // A run that reads the whole archive deletes it, so the id it used
      // names nothing afterwards; leaving it set would refuse the next
      // submit with a sentence about an upload that is gone. A dry run
      // keeps the archive - running the real import afterwards is the
      // point of one - and so does a run told to leave part of it
      // unread, which the server will not destroy either.
      //
      // Read off the files the server recognised in this archive rather
      // than off the switches alone: a history-only export has no saved
      // tracks to decline, so a run with stars turned off still reads
      // all of it, and guessing otherwise leaves the form holding an id
      // that names nothing.
      final files = _export?.files ?? const <String>[];
      final library = files.any((f) => f.endsWith('YourLibrary.json'));
      final history = files.any((f) => !f.endsWith('YourLibrary.json'));
      final consumed =
          !_dryRun && (!library || _stars) && (!history || _history);
      if (consumed && mounted) {
        setState(() {
          _export = null;
          _exportName = '';
        });
      }
      ref.invalidate(toolTasksProvider);
      messenger.show(
        l10n.adminMigrateStarted,
        actionLabel: l10n.adminOpenTasks,
        actionSemanticsId: SemanticsIds.adminAction('migrate-tasks'),
        onAction: () => router.push<void>(WaxRoute.tasks),
      );
    } on WaxDeckApiException catch (e) {
      // The address and credentials somebody just typed.
      messenger.show(explainRefusal(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Which account the import lands on.
  ///
  /// Defaults to the signed-in administrator, which is the common case
  /// and the only one that used to exist; the rest of the household is
  /// how a move actually finishes, and nobody has their passwords.
  /// A list that has not arrived leaves the picker off rather than
  /// blocking the form: the default is the right answer either way.
  /// The accounts the import may land on besides the signed-in one, in
  /// the order they are offered.
  List<UserAccount> _otherAccounts() {
    final me = ref.read(signedInAccountProvider);
    final users = ref.read(adminUsersProvider).value?.users ?? const [];
    return [
      for (final u in users)
        if (u.id != me && !u.disabled && !u.pending) u,
    ]..sort(
      (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
    );
  }

  /// The account the writes land on, checked against the list as it
  /// stands.
  ///
  /// The list is refetched, and the account that was picked can leave it
  /// - disabled, deleted, its approval revoked. The picker falls back to
  /// the signed-in account when that happens, and sending the id anyway
  /// would either import onto an account the form had stopped showing or
  /// be refused naming one nobody can see.
  String? _targetAccount() {
    final id = _account;
    if (id == null) return null;
    return _otherAccounts().any((u) => u.id == id) ? id : null;
  }

  Widget _accountPicker(AppLocalizations l10n) {
    final me = ref.watch(signedInAccountProvider);
    ref.watch(adminUsersProvider);
    final others = _otherAccounts();
    if (others.isEmpty) return const SizedBox.shrink();
    final picked = _targetAccount();
    return WaxSettingRow(
      key: const Key('migrate-account-row'),
      title: l10n.adminMigrateAccountLabel,
      help: l10n.adminMigrateAccountHelp,
      control: WaxChoice<String?>(
        key: const Key(SemanticsIds.migrateAccount),
        value: picked,
        options: [null, for (final u in others) u.id],
        labelFor: (id) => id == null
            ? l10n.adminMigrateAccountSelf
            : others.firstWhere((u) => u.id == id).username,
        label: l10n.adminMigrateAccountLabel,
        semanticsId: SemanticsIds.migrateAccount,
        optionSemanticsIdFor: (id) =>
            SemanticsIds.migrateAccountOption(id ?? me ?? 'self'),
        onChanged: (selected) => setState(() => _account = selected),
      ),
    );
  }

  /// Whether the form holds enough to send. Per source, because what
  /// counts as enough is: an address for the servers, an account name
  /// for the public histories, an uploaded file for the exports.
  bool get _ready {
    if (_busy || _uploading) return false;
    if (_source.needsUrl && _serverUrl.text.trim().isEmpty) return false;
    if (_source.usesUsername && _username.text.trim().isEmpty) return false;
    if (_source.usesExport && _export == null) return false;
    // A credential where one is required, read only off the fields this
    // source draws. The controllers outlive a change of source, so a
    // password typed for one server would otherwise satisfy the next
    // one's token field and enable a Start the server refuses.
    final needsSecret =
        (_source.usesPassword || _source.usesToken) && !_source.tokenOptional;
    final hasSecret =
        (_source.usesPassword && _password.text.isNotEmpty) ||
        (_source.usesToken && _token.text.trim().isNotEmpty);
    if (needsSecret && !hasSecret) return false;
    return true;
  }

  /// Uploads an account data export and holds what came back.
  Future<void> _pickExport() async {
    final picker = ref.read(filePickerProvider);
    if (picker == null || _uploading) return;
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    // Read before the picker's await rather than after it: the screen
    // can be gone by the time a file comes back, and a provider read on
    // a disposed container throws where nothing is left to catch it.
    final repository = ref.read(repositoryProvider);
    final file = await picker.pickFile(
      extensions: const {'zip'},
      label: l10n.adminMigrateSpotifyExport,
      anyLabel: l10n.uploadsFileTypeAny,
    );
    final openRead = file?.openRead;
    if (file == null || openRead == null) return;
    setState(() => _uploading = true);
    try {
      // Read lazily off the picked file and its length declared, so a
      // server with no room refuses before reading any of it.
      final staged = await repository.stageMigrationExport(
        sizeBytes: file.size,
        openRead: () => openRead(),
      );
      // The one this replaces is nobody's any more: hand it back rather
      // than leaving a household's listening history on the server for
      // the sweep to notice a day later.
      final replaced = _export;
      if (replaced != null) {
        unawaited(
          repository
              .discardMigrationExport(replaced.pid)
              .catchError((Object _) {}),
        );
      }
      if (!mounted) return;
      setState(() {
        _export = staged;
        _exportName = file.name;
      });
    } on WaxDeckApiException catch (e) {
      // The archive somebody just picked, so the server's own sentence
      // about it is the useful one.
      messenger.show(explainRefusal(l10n, e));
    } on Object catch (e) {
      // A connection that dropped mid-upload is not an API refusal, and
      // without this it would leave the form silent and unchanged.
      messenger.show(explainError(l10n, e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    // Read rather than assumed: the Last.fm import runs on the server's
    // own API credentials, so an install without them cannot use it and
    // says so here instead of in a task report.
    final lastfmReady =
        ref.watch(scrobblingAdminConfigProvider).value?.lastfmConfigured ??
        true;
    return WaxScaffold(
      title: l10n.adminMigrateTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.adminMigrate,
      onBack: adminBack(context),
      slivers: <Widget>[
        SliverPadding(
          padding: sizeClass.gutter.add(
            const EdgeInsets.symmetric(vertical: WaxSpace.s16),
          ),
          sliver: SliverToBoxAdapter(
            child: ReadingColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    identifier: SemanticsIds.migrateSource,
                    child: DropdownButton<_MigrationSource>(
                      key: const Key(SemanticsIds.migrateSource),
                      value: _source,
                      isExpanded: true,
                      onChanged: (selected) {
                        if (selected != null) {
                          setState(() {
                            _source = selected;
                            // The credentials go with the source they
                            // were typed for. The controllers outlive
                            // the change, and Jellyfin draws both a
                            // password and a token field: a password
                            // left over from another server would be
                            // sent beside a fresh API key, and the
                            // server takes the password - a login
                            // against the wrong host, refused, with the
                            // key never tried.
                            _password.clear();
                            _token.clear();
                          });
                        }
                      },
                      items: [
                        for (final source in _MigrationSource.values)
                          DropdownMenuItem(
                            value: source,
                            child: Text(source.labelOf(l10n)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s8),
                  _accountPicker(l10n),
                  if (_source == _MigrationSource.lastfm && !lastfmReady)
                    Padding(
                      padding: const EdgeInsets.only(bottom: WaxSpace.s8),
                      child: WaxBanner(
                        key: const Key(SemanticsIds.migrateLastfmMissingKey),
                        semanticsId: SemanticsIds.migrateLastfmMissingKey,
                        tone: WaxBannerTone.caution,
                        message: l10n.adminMigrateLastfmKeyMissing,
                      ),
                    ),
                  const SizedBox(height: WaxSpace.s8),
                  if (_source.usesUrl) ...[
                    Semantics(
                      identifier: SemanticsIds.migrateServerUrl,
                      child: TextField(
                        key: const Key(SemanticsIds.migrateServerUrl),
                        controller: _serverUrl,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: l10n.adminMigrateServerUrlLabel,
                          hintText: l10n.adminMigrateServerUrlHint,
                          helperText: _source.needsUrl
                              ? null
                              : l10n.adminMigrateListenBrainzServerHelp,
                        ),
                      ),
                    ),
                    const SizedBox(height: WaxSpace.s8),
                  ],
                  if (_source.usesUsername) ...[
                    Semantics(
                      identifier: SemanticsIds.migrateUsername,
                      child: TextField(
                        key: const Key(SemanticsIds.migrateUsername),
                        controller: _username,
                        decoration: InputDecoration(
                          labelText: l10n.adminMigrateUsernameLabel,
                        ),
                      ),
                    ),
                    const SizedBox(height: WaxSpace.s8),
                  ],
                  if (_source.usesPassword) ...[
                    Semantics(
                      identifier: SemanticsIds.migratePassword,
                      child: TextField(
                        key: const Key(SemanticsIds.migratePassword),
                        controller: _password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.adminMigratePasswordLabel,
                        ),
                      ),
                    ),
                    const SizedBox(height: WaxSpace.s8),
                  ],
                  if (_source.usesToken) ...[
                    Semantics(
                      identifier: SemanticsIds.migrateToken,
                      child: TextField(
                        key: const Key(SemanticsIds.migrateToken),
                        controller: _token,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.adminMigrateTokenLabel,
                        ),
                      ),
                    ),
                    const SizedBox(height: WaxSpace.s8),
                  ],
                  if (_source.usesExport) ...[
                    Semantics(
                      identifier: SemanticsIds.migrateExportPick,
                      button: true,
                      child: OutlinedButton(
                        key: const Key(SemanticsIds.migrateExportPick),
                        onPressed: _uploading ? null : _pickExport,
                        child: Text(l10n.adminMigrateExportPick),
                      ),
                    ),
                    if (_export case final staged?)
                      Padding(
                        padding: const EdgeInsets.only(top: WaxSpace.s8),
                        child: Semantics(
                          identifier: SemanticsIds.migrateExportStatus,
                          child: Text(
                            key: const Key(SemanticsIds.migrateExportStatus),
                            l10n.adminMigrateExportStaged(
                              staged.files.length,
                              _exportName,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: WaxSpace.s8),
                  ],
                  const SizedBox(height: WaxSpace.s8),
                  WaxSettingRow(
                    key: const Key('migrate-stars'),
                    title: l10n.adminMigrateStarsTitle,
                    help: l10n.adminMigrateStarsHelp,
                    control: WaxSwitch(
                      value: _stars,
                      label: l10n.adminMigrateStarsTitle,
                      onChanged: (value) => setState(() => _stars = value),
                    ),
                  ),
                  if (_source.usesRatings)
                    WaxSettingRow(
                      key: const Key('migrate-ratings'),
                      title: l10n.adminMigrateRatingsTitle,
                      help: l10n.adminMigrateRatingsHelp,
                      control: WaxSwitch(
                        value: _ratings,
                        label: l10n.adminMigrateRatingsTitle,
                        onChanged: (value) => setState(() => _ratings = value),
                      ),
                    ),
                  WaxSettingRow(
                    key: const Key('migrate-history'),
                    title: l10n.adminMigrateHistoryTitle,
                    help: l10n.adminMigrateHistoryHelp,
                    control: WaxSwitch(
                      value: _history,
                      label: l10n.adminMigrateHistoryTitle,
                      onChanged: (value) => setState(() => _history = value),
                    ),
                  ),
                  if (_source.usesProgress)
                    WaxSettingRow(
                      key: const Key('migrate-progress'),
                      title: l10n.adminMigrateProgressTitle,
                      help: l10n.adminMigrateProgressHelp,
                      control: WaxSwitch(
                        value: _progress,
                        label: l10n.adminMigrateProgressTitle,
                        onChanged: (value) => setState(() => _progress = value),
                      ),
                    ),
                  WaxSettingRow(
                    key: const Key('migrate-dry-run'),
                    title: l10n.adminMigrateDryRunTitle,
                    help: l10n.adminMigrateDryRunHelp,
                    control: WaxSwitch(
                      value: _dryRun,
                      label: l10n.adminMigrateDryRunTitle,
                      onChanged: (value) => setState(() => _dryRun = value),
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s16),
                  Semantics(
                    identifier: SemanticsIds.migrateSubmit,
                    child: FilledButton(
                      key: const Key(SemanticsIds.migrateSubmit),
                      onPressed: _ready ? _submit : null,
                      child: Text(l10n.adminMigrateSubmit),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
