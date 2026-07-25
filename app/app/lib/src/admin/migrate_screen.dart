import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../tools/tasks_screen.dart';

/// The importable sources. Podcast feeds move by OPML, which has no
/// affordance in the podcasts UI yet, so it is not offered here.
enum _MigrationSource {
  navidrome('navidrome', 'Navidrome'),
  subsonic('subsonic', 'Subsonic server'),
  audiobookshelf('audiobookshelf', 'Audiobookshelf');

  const _MigrationSource(this.wireName, this.label);

  final String wireName;
  final String label;

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
    final messenger = ScaffoldMessenger.of(context);
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
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Import started'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Tasks',
              onPressed: () => router.push<void>(WaxRoute.tasks),
            ),
          ),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _serverUrl.text.trim();
    return Semantics(
      identifier: SemanticsIds.adminMigrate,
      container: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('Import from another server')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              identifier: SemanticsIds.migrateSource,
              child: DropdownButton<_MigrationSource>(
                key: const Key(SemanticsIds.migrateSource),
                value: _source,
                isExpanded: true,
                onChanged: (selected) {
                  if (selected != null) setState(() => _source = selected);
                },
                items: [
                  for (final source in _MigrationSource.values)
                    DropdownMenuItem(value: source, child: Text(source.label)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              identifier: SemanticsIds.migrateServerUrl,
              child: TextField(
                key: const Key(SemanticsIds.migrateServerUrl),
                controller: _serverUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://music.example',
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_source.usesToken)
              Semantics(
                identifier: SemanticsIds.migrateToken,
                child: TextField(
                  key: const Key(SemanticsIds.migrateToken),
                  controller: _token,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API token'),
                ),
              )
            else ...[
              Semantics(
                identifier: SemanticsIds.migrateUsername,
                child: TextField(
                  key: const Key(SemanticsIds.migrateUsername),
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                identifier: SemanticsIds.migratePassword,
                child: TextField(
                  key: const Key(SemanticsIds.migratePassword),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('migrate-stars'),
              title: const Text('Stars'),
              value: _stars,
              onChanged: (value) => setState(() => _stars = value),
            ),
            SwitchListTile(
              key: const Key('migrate-ratings'),
              title: const Text('Ratings'),
              value: _ratings,
              onChanged: (value) => setState(() => _ratings = value),
            ),
            SwitchListTile(
              key: const Key('migrate-history'),
              title: const Text('Listen history'),
              value: _history,
              onChanged: (value) => setState(() => _history = value),
            ),
            SwitchListTile(
              key: const Key('migrate-progress'),
              title: const Text('Playback progress'),
              value: _progress,
              onChanged: (value) => setState(() => _progress = value),
            ),
            CheckboxListTile(
              key: const Key('migrate-dry-run'),
              title: const Text('Dry run'),
              subtitle: const Text('Report what would match; change nothing'),
              value: _dryRun,
              onChanged: (value) => setState(() => _dryRun = value ?? false),
            ),
            const SizedBox(height: 16),
            Semantics(
              identifier: SemanticsIds.migrateSubmit,
              child: FilledButton(
                key: const Key(SemanticsIds.migrateSubmit),
                onPressed: _busy || url.isEmpty ? null : _submit,
                child: const Text('Start import'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
