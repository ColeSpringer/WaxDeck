import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../tools/tasks_screen.dart';
import 'admin_console.dart';

/// The importable sources. Podcast feeds move by OPML, which has no
/// affordance in the podcasts UI yet, so it is not offered here.
enum _MigrationSource {
  navidrome('navidrome'),
  subsonic('subsonic'),
  audiobookshelf('audiobookshelf');

  const _MigrationSource(this.wireName);

  final String wireName;

  /// Two of these are bare product names, which read the same in every
  /// language; the third carries a word that does not.
  String labelOf(AppLocalizations l10n) => switch (this) {
    navidrome => 'Navidrome',
    subsonic => l10n.adminMigrateSubsonicServer,
    audiobookshelf => 'Audiobookshelf',
  };

  /// Audiobookshelf authenticates with an API token; the subsonic
  /// family with username and password.
  bool get usesToken => this == audiobookshelf;
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
  var _dryRun = false;
  var _stars = true;
  var _ratings = true;
  var _history = true;
  var _progress = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _serverUrl.addListener(() => setState(() {}));
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
            serverUrl: _serverUrl.text.trim(),
            username: _source.usesToken ? null : _username.text.trim(),
            password: _source.usesToken ? null : _password.text,
            token: _source.usesToken ? _token.text.trim() : null,
            options: MigrationOptions(
              stars: _stars,
              ratings: _ratings,
              history: _history,
              progress: _progress,
            ),
            dryRun: _dryRun,
          );
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

  @override
  Widget build(BuildContext context) {
    final url = _serverUrl.text.trim();
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
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
                          setState(() => _source = selected);
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
                  Semantics(
                    identifier: SemanticsIds.migrateServerUrl,
                    child: TextField(
                      key: const Key(SemanticsIds.migrateServerUrl),
                      controller: _serverUrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: l10n.adminMigrateServerUrlLabel,
                        hintText: l10n.adminMigrateServerUrlHint,
                      ),
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s8),
                  if (_source.usesToken)
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
                    )
                  else ...[
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
                      onPressed: _busy || url.isEmpty ? null : _submit,
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
