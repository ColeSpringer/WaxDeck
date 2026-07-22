import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';
import 'integrations_controller.dart';

/// Scrobbling connections: Last.fm through the browser authorization
/// flow, ListenBrainz through a token dialog.
class ScrobblingSection extends ConsumerWidget {
  const ScrobblingSection({super.key});

  String _label(String service) => switch (service) {
    'lastfm' => 'Last.fm',
    'listenbrainz' => 'ListenBrainz',
    _ => service,
  };

  Future<void> _connect(
    BuildContext context,
    WidgetRef ref,
    Scrobbler slot,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (slot.service == 'lastfm') {
      try {
        final authUrl = await ref
            .read(scrobblersProvider.notifier)
            .startLastfmConnect();
        await ref.read(urlOpenerProvider).open(authUrl);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Approve WaxDeck in the browser tab, then come back here',
            ),
          ),
        );
      } on WaxDeckApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => const _ListenBrainzDialog(),
    );
  }

  Future<void> _disconnect(
    BuildContext context,
    WidgetRef ref,
    Scrobbler slot,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(scrobblersProvider.notifier).disconnect(slot.service);
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openLastfmSetup(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const _LastfmCredentialsDialog(),
  );

  /// The row's trailing action. Administrators additionally get the
  /// server-credential setup on the Last.fm row: it replaces the dead
  /// disabled Connect while credentials are missing, and sits beside
  /// Connect/Disconnect once they exist.
  Widget _trailing(
    BuildContext context,
    WidgetRef ref,
    Scrobbler slot, {
    required bool isAdmin,
  }) {
    final adminSetup = isAdmin && slot.service == 'lastfm';
    if (adminSetup && !slot.connected && !slot.available) {
      return Semantics(
        identifier: 'scrobbler-setup-lastfm',
        button: true,
        child: TextButton(
          key: const ValueKey('scrobbler-setup-lastfm'),
          onPressed: () => _openLastfmSetup(context),
          child: const Text('Set up…'),
        ),
      );
    }
    final action = slot.connected
        ? Semantics(
            identifier: 'scrobbler-disconnect-${slot.service}',
            button: true,
            child: TextButton(
              key: ValueKey('scrobbler-disconnect-${slot.service}'),
              onPressed: () => _disconnect(context, ref, slot),
              child: const Text('Disconnect'),
            ),
          )
        : Semantics(
            identifier: 'scrobbler-connect-${slot.service}',
            button: true,
            child: TextButton(
              key: ValueKey('scrobbler-connect-${slot.service}'),
              onPressed: slot.available
                  ? () => _connect(context, ref, slot)
                  : null,
              child: const Text('Connect'),
            ),
          );
    if (!adminSetup) return action;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action,
        Semantics(
          identifier: 'scrobbler-setup-lastfm',
          button: true,
          child: IconButton(
            key: const ValueKey('scrobbler-setup-lastfm'),
            tooltip: 'Server API credentials',
            icon: const Icon(Icons.settings_outlined),
            visualDensity: VisualDensity.compact,
            onPressed: () => _openLastfmSetup(context),
          ),
        ),
      ],
    );
  }

  /// The row's one-line status: connection state first, then delivery
  /// health. A standing error outranks the connected pleasantry; the
  /// user opening this screen wants to know why scrobbles stopped.
  String _slotStatus(Scrobbler slot) {
    if (!slot.connected) {
      return slot.available ? 'Not connected' : 'Needs server API credentials';
    }
    if (slot.lastError != null) {
      return 'Delivery failing: ${slot.lastError}';
    }
    final who = slot.username == null ? '' : ' as ${slot.username}';
    if (slot.lastSuccessAt != null) {
      return 'Connected$who, delivering';
    }
    return 'Connected$who';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrobblers = ref.watch(scrobblersProvider);
    final user = ref.watch(authControllerProvider).value?.user;
    final isAdmin = user?.roles.contains('admin') ?? false;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scrobbling', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        switch (scrobblers) {
          AsyncData(:final value) => Column(
            children: [
              for (final slot in value)
                Semantics(
                  identifier: 'scrobbler-${slot.service}',
                  child: ListTile(
                    key: ValueKey('scrobbler-${slot.service}'),
                    leading: const Icon(Icons.multitrack_audio),
                    title: Text(_label(slot.service)),
                    subtitle: Text(
                      _slotStatus(slot),
                      style: slot.lastError == null
                          ? null
                          : TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                    ),
                    trailing: _trailing(context, ref, slot, isAdmin: isAdmin),
                  ),
                ),
            ],
          ),
          AsyncError() => const Text('Could not load scrobbling connections'),
          _ => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
        },
      ],
    );
  }
}

class _ListenBrainzDialog extends ConsumerStatefulWidget {
  const _ListenBrainzDialog();

  @override
  ConsumerState<_ListenBrainzDialog> createState() =>
      _ListenBrainzDialogState();
}

class _ListenBrainzDialogState extends ConsumerState<_ListenBrainzDialog> {
  final _tokenController = TextEditingController();
  final _apiUrlController = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty || _busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final apiUrl = _apiUrlController.text.trim();
    try {
      await ref
          .read(scrobblersProvider.notifier)
          .connectListenBrainz(token, apiUrl: apiUrl.isEmpty ? null : apiUrl);
      navigator.pop();
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
    return AlertDialog(
      title: const Text('Connect ListenBrainz'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No Semantics identifier wrapper: on the web it would mint a
          // second, disabled text-field node beside the real input.
          TextField(
            key: const Key('listenbrainz-token-field'),
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'User token',
              helperText: 'From your ListenBrainz profile page',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('listenbrainz-api-field'),
            controller: _apiUrlController,
            decoration: const InputDecoration(
              labelText: 'API server (optional)',
              helperText: 'For a compatible server; empty for listenbrainz.org',
            ),
            keyboardType: TextInputType.url,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: 'listenbrainz-connect-confirm',
          label: 'Connect',
          button: true,
          child: FilledButton(
            key: const Key('listenbrainz-connect-confirm'),
            onPressed: _busy ? null : _connect,
            child: const Text('Connect'),
          ),
        ),
      ],
    );
  }
}

/// The server-level Last.fm API credentials (administrators). The API
/// key reads back for display; the secret is write-only, stored sealed.
/// Clearing falls back to the server environment's credentials when it
/// has them.
class _LastfmCredentialsDialog extends ConsumerStatefulWidget {
  const _LastfmCredentialsDialog();

  @override
  ConsumerState<_LastfmCredentialsDialog> createState() =>
      _LastfmCredentialsDialogState();
}

class _LastfmCredentialsDialogState
    extends ConsumerState<_LastfmCredentialsDialog> {
  final _apiKeyController = TextEditingController();
  final _secretController = TextEditingController();
  var _seeded = false;
  var _busy = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  void _seed(ScrobblingAdminConfig config) {
    if (_seeded) return;
    _seeded = true;
    _apiKeyController.text = config.lastfmApiKey ?? '';
  }

  Future<void> _save({required bool clear}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(scrobblingAdminConfigProvider.notifier)
          .save(
            apiKey: clear ? '' : _apiKeyController.text.trim(),
            secret: clear ? '' : _secretController.text.trim(),
          );
      navigator.pop();
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
    final config = ref.watch(scrobblingAdminConfigProvider);
    return AlertDialog(
      title: const Text('Last.fm API credentials'),
      content: switch (config) {
        AsyncData(:final value) => Builder(
          builder: (context) {
            _seed(value);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // No Semantics identifier wrappers, for the same web
                // duplicate-node reason as the ListenBrainz dialog.
                TextField(
                  key: const Key('lastfm-api-key-field'),
                  controller: _apiKeyController,
                  decoration: const InputDecoration(
                    labelText: 'API key',
                    helperText: 'Register at last.fm/api/account/create',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('lastfm-secret-field'),
                  controller: _secretController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Shared secret',
                    helperText: value.lastfmSecretSet
                        ? 'Stored sealed; never shown again'
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
        AsyncError() => const Text('Could not load the credential state'),
        _ => const Padding(
          padding: EdgeInsets.all(8),
          child: LinearProgressIndicator(),
        ),
      },
      actions: [
        // Only stored credentials can be cleared; the environment pair
        // is the fallback, not something this surface removes.
        if (config.value?.lastfmSource == 'settings')
          Semantics(
            identifier: 'lastfm-credentials-clear',
            button: true,
            child: TextButton(
              key: const Key('lastfm-credentials-clear'),
              onPressed: _busy ? null : () => _save(clear: true),
              child: const Text('Clear'),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: 'lastfm-credentials-save',
          label: 'Save',
          button: true,
          child: FilledButton(
            key: const Key('lastfm-credentials-save'),
            onPressed: _busy || config is! AsyncData
                ? null
                : () => _save(clear: false),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

/// App passwords for the compatibility APIs (Subsonic clients, gpodder
/// sync). The secret shows exactly once at creation.
class AppPasswordsSection extends ConsumerWidget {
  const AppPasswordsSection({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New app password'),
        content: TextField(
          key: const Key('app-password-label-field'),
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Label',
            helperText: 'Which app is this for?',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('app-password-create-confirm'),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty || !context.mounted) return;
    try {
      final created = await ref
          .read(appPasswordsProvider.notifier)
          .create(label);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('App password created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copy it now; the server stores it sealed and never '
                'shows it again.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                created.secret,
                key: const Key('app-password-secret'),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: created.secret));
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              key: const Key('app-password-secret-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passwords = ref.watch(appPasswordsProvider);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('App passwords', style: textTheme.titleMedium),
            ),
            Semantics(
              identifier: 'app-password-add',
              label: 'New app password',
              button: true,
              child: IconButton(
                key: const Key('app-password-add'),
                tooltip: 'New app password',
                icon: const Icon(Icons.add),
                onPressed: () => _create(context, ref),
              ),
            ),
          ],
        ),
        Text(
          'For Subsonic apps and podcast sync clients. Your login '
          'password never works there.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        switch (passwords) {
          AsyncData(:final value) =>
            value.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No app passwords yet'),
                  )
                : Column(
                    children: [
                      for (final ap in value)
                        ListTile(
                          key: ValueKey('app-password-${ap.id}'),
                          leading: const Icon(Icons.key),
                          title: Text(
                            ap.label.isEmpty ? 'Unlabeled' : ap.label,
                          ),
                          trailing: Semantics(
                            identifier: 'app-password-revoke-${ap.id}',
                            button: true,
                            child: IconButton(
                              key: ValueKey('app-password-revoke-${ap.id}'),
                              tooltip: 'Revoke',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => ref
                                  .read(appPasswordsProvider.notifier)
                                  .revoke(ap.id),
                            ),
                          ),
                        ),
                    ],
                  ),
          AsyncError() => const Text('Could not load app passwords'),
          _ => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
        },
      ],
    );
  }
}

/// Push registrations from UnifiedPush distributors, listed with
/// revocation. Registration itself happens on the Android client.
class PushRegistrationsSection extends ConsumerWidget {
  const PushRegistrationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registrations = ref.watch(pushRegistrationsProvider);
    final rows = registrations.value ?? const <PushRegistration>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Push notifications', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final reg in rows)
          ListTile(
            key: ValueKey('push-${reg.pid}'),
            leading: const Icon(Icons.notifications_outlined),
            title: Text(reg.label ?? 'Unnamed device'),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  ref.read(pushRegistrationsProvider.notifier).remove(reg.pid),
            ),
          ),
      ],
    );
  }
}

/// The Apprise relay configuration; administrators only.
class NotificationsSection extends ConsumerStatefulWidget {
  const NotificationsSection({super.key});

  @override
  ConsumerState<NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<NotificationsSection> {
  final _urlController = TextEditingController();
  final _targetsController = TextEditingController();
  Set<String>? _enabled;
  var _seeded = false;
  var _busy = false;

  @override
  void dispose() {
    _urlController.dispose();
    _targetsController.dispose();
    super.dispose();
  }

  void _seed(NotificationConfig config) {
    if (_seeded) return;
    _seeded = true;
    _urlController.text = config.appriseUrl;
    _targetsController.text = config.targets ?? '';
    _enabled = config.enabledEvents.toSet();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final targets = _targetsController.text.trim();
      await ref
          .read(notificationConfigProvider.notifier)
          .save(
            appriseUrl: _urlController.text.trim(),
            targets: targets.isEmpty ? null : targets,
            enabledEvents: (_enabled ?? const {}).toList()..sort(),
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Notification settings saved')),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationConfigProvider.notifier).sendTest();
      messenger.showSnackBar(
        const SnackBar(content: Text('Test notification queued')),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(notificationConfigProvider);
    final textTheme = Theme.of(context).textTheme;
    return switch (config) {
      AsyncData(:final value) => Builder(
        builder: (context) {
          _seed(value);
          final enabled = _enabled ?? const <String>{};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notifications', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                key: const Key('apprise-url-field'),
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Apprise server URL',
                  helperText: 'Empty disables delivery through Apprise',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('apprise-targets-field'),
                controller: _targetsController,
                decoration: const InputDecoration(
                  labelText: 'Targets (optional)',
                  helperText:
                      'Apprise URLs; empty uses the server\'s own configuration',
                ),
              ),
              const SizedBox(height: 8),
              for (final event in value.knownEvents)
                if (event != 'test')
                  CheckboxListTile(
                    key: ValueKey('notify-event-$event'),
                    title: Text(event),
                    value: enabled.contains(event),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (checked) => setState(() {
                      final next = {...enabled};
                      if (checked ?? false) {
                        next.add(event);
                      } else {
                        next.remove(event);
                      }
                      _enabled = next;
                    }),
                  ),
              Row(
                children: [
                  Semantics(
                    identifier: 'notifications-save',
                    button: true,
                    child: FilledButton.tonal(
                      key: const Key('notifications-save'),
                      onPressed: _busy ? null : _save,
                      child: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: 'notifications-test',
                    button: true,
                    child: OutlinedButton(
                      key: const Key('notifications-test'),
                      onPressed: _busy ? null : _test,
                      child: const Text('Send test'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      // Non-admins get a typed forbidden error; the section simply
      // stays absent for them.
      AsyncError() => const SizedBox.shrink(),
      _ => const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      ),
    };
  }
}
