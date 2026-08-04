import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxSettingRow, WaxSwitch;

import '../auth/auth_controller.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'client_prefs.dart';
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
        identifier: SemanticsIds.scrobblerSetupLastfm,
        button: true,
        child: TextButton(
          key: const ValueKey(SemanticsIds.scrobblerSetupLastfm),
          onPressed: () => _openLastfmSetup(context),
          child: const Text('Set up…'),
        ),
      );
    }
    final action = slot.connected
        ? Semantics(
            identifier: SemanticsIds.scrobblerDisconnect(slot.service),
            button: true,
            child: TextButton(
              key: ValueKey(SemanticsIds.scrobblerDisconnect(slot.service)),
              onPressed: () => _disconnect(context, ref, slot),
              child: const Text('Disconnect'),
            ),
          )
        : Semantics(
            identifier: SemanticsIds.scrobblerConnect(slot.service),
            button: true,
            child: TextButton(
              key: ValueKey(SemanticsIds.scrobblerConnect(slot.service)),
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
          identifier: SemanticsIds.scrobblerSetupLastfm,
          button: true,
          child: IconButton(
            key: const ValueKey(SemanticsIds.scrobblerSetupLastfm),
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
                  identifier: SemanticsIds.scrobbler(slot.service),
                  child: ListTile(
                    key: ValueKey(SemanticsIds.scrobbler(slot.service)),
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
          identifier: SemanticsIds.listenbrainzConnectConfirm,
          label: 'Connect',
          button: true,
          child: FilledButton(
            key: const Key(SemanticsIds.listenbrainzConnectConfirm),
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
            identifier: SemanticsIds.lastfmCredentialsClear,
            button: true,
            child: TextButton(
              key: const Key(SemanticsIds.lastfmCredentialsClear),
              onPressed: _busy ? null : () => _save(clear: true),
              child: const Text('Clear'),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: SemanticsIds.lastfmCredentialsSave,
          label: 'Save',
          button: true,
          child: FilledButton(
            key: const Key(SemanticsIds.lastfmCredentialsSave),
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

/// Discord rich presence: whether this desktop tells a Discord client
/// running beside it what is playing.
///
/// A switch and, folded under it, an override nobody has to touch:
/// presence is published as a Discord *application*, WaxDeck has one
/// registered, and the field is for somebody who would rather use their
/// own. It is second and optional because that is what it is.
class DiscordPresenceSection extends ConsumerStatefulWidget {
  const DiscordPresenceSection({super.key});

  @override
  ConsumerState<DiscordPresenceSection> createState() =>
      _DiscordPresenceSectionState();
}

class _DiscordPresenceSectionState
    extends ConsumerState<DiscordPresenceSection> {
  /// Seeded here rather than in a `late final` initializer: a section
  /// built and torn down without ever being laid out would run that
  /// initializer from `dispose`, where reading `ref` is unsafe.
  late final TextEditingController _id;

  @override
  void initState() {
    super.initState();
    _id = TextEditingController(text: ref.read(discordApplicationIdProvider));
  }

  /// Stores what was typed, once. Per keystroke, each write would
  /// reconnect the binder against a prefix of the real id - nineteen
  /// dials, nineteen socket sweeps, and a race over which one survives.
  void _commit() {
    final typed = _id.text.trim();
    if (typed == ref.read(discordApplicationIdProvider)) return;
    ref.read(discordApplicationIdProvider.notifier).set(typed);
  }

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(discordPresenceEnabledProvider);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Discord', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        WaxSettingRow(
          title: 'Show what I am listening to',
          help:
              'Sets your Discord status while WaxDeck plays, through the '
              'Discord app on this machine',
          control: WaxSwitch(
            value: on,
            label: 'Show what I am listening to on Discord',
            semanticsId: SemanticsIds.setting('discord-presence'),
            onChanged: ref.read(discordPresenceEnabledProvider.notifier).set,
          ),
        ),
        if (on)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // No Semantics identifier wrapper: on the web it would
                // mint a second, disabled text-field node beside the
                // real input. The switch above carries the handle.
                Focus(
                  // The ordinary use is paste, then click away.
                  onFocusChange: (has) {
                    if (!has) _commit();
                  },
                  child: TextField(
                    key: const Key('discord-application-id-field'),
                    controller: _id,
                    decoration: const InputDecoration(
                      labelText: 'Publish as another application (optional)',
                      helperText:
                          'Empty publishes as WaxDeck. An application ID from '
                          'discord.com/developers changes the name Discord '
                          'shows and where its cover art comes from',
                    ),
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _commit(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'The cover is one image for every track, uploaded to '
                    'that application rather than taken from your library: '
                    'Discord fetches art through its own servers, which '
                    'cannot reach a private one.',
                    style: textTheme.bodySmall,
                  ),
                ),
              ],
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
              identifier: SemanticsIds.appPasswordAdd,
              label: 'New app password',
              button: true,
              child: IconButton(
                key: const Key(SemanticsIds.appPasswordAdd),
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
                            identifier: SemanticsIds.appPasswordRevoke(ap.id),
                            button: true,
                            child: IconButton(
                              key: ValueKey(
                                SemanticsIds.appPasswordRevoke(ap.id),
                              ),
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

/// One kind's config field descriptor for the target editor.
class _ConfigField {
  const _ConfigField(
    this.key,
    this.label, {
    this.optional = false,
    this.integer = false,
    this.secret = false,
    this.helper,
  });

  final String key;
  final String label;
  final bool optional;
  final bool integer;
  final bool secret;
  final String? helper;
}

/// The per-kind config surface. Mirrors the server's provider
/// validation; the server's message is the authority when they drift.
const _kindFields = <String, List<_ConfigField>>{
  'pushover': [
    _ConfigField('token', 'Application token', secret: true),
    _ConfigField('userKey', 'User or group key', secret: true),
    _ConfigField(
      'priority',
      'Priority',
      optional: true,
      integer: true,
      helper: '-2 (quietest) to 2 (emergency)',
    ),
  ],
  'ntfy': [
    _ConfigField('topic', 'Topic'),
    _ConfigField(
      'serverUrl',
      'Server URL',
      optional: true,
      helper: 'Empty uses ntfy.sh',
    ),
    _ConfigField('accessToken', 'Access token', optional: true, secret: true),
  ],
  'gotify': [
    _ConfigField('serverUrl', 'Server URL'),
    _ConfigField('token', 'Application token', secret: true),
    _ConfigField(
      'priority',
      'Priority',
      optional: true,
      integer: true,
      helper: '0 to 10',
    ),
  ],
  'discord': [
    _ConfigField(
      'webhookUrl',
      'Webhook URL',
      secret: true,
      helper: 'A discord.com webhook URL',
    ),
  ],
  'webhook': [
    _ConfigField(
      'url',
      'URL',
      helper: 'Receives {event, title, body, timestamp} as JSON',
    ),
  ],
  'apprise': [
    _ConfigField('serverUrl', 'Apprise server URL'),
    _ConfigField(
      'targets',
      'Targets',
      optional: true,
      helper: 'Apprise URLs; empty uses the server\'s own configuration',
    ),
  ],
  'unifiedpush': [
    _ConfigField(
      'endpoint',
      'Endpoint URL',
      helper: 'Usually registered by the app through its distributor',
    ),
  ],
};

String _kindLabel(String kind) => switch (kind) {
  'pushover' => 'Pushover',
  'ntfy' => 'ntfy',
  'gotify' => 'Gotify',
  'discord' => 'Discord',
  'webhook' => 'Webhook',
  'apprise' => 'Apprise',
  'unifiedpush' => 'UnifiedPush',
  _ => kind,
};

IconData _kindIcon(String kind) => switch (kind) {
  'unifiedpush' => Icons.smartphone_outlined,
  'discord' => Icons.forum_outlined,
  'webhook' => Icons.webhook_outlined,
  _ => Icons.notifications_outlined,
};

/// The per-target event checklist, driven by the server's catalog and
/// filtered to what this target's scope may select.
class _EventChecklist extends ConsumerWidget {
  const _EventChecklist({
    required this.serverScope,
    required this.ownerIsAdmin,
    required this.selected,
    required this.onChanged,
  });

  /// Whether the target being edited is server-scope.
  final bool serverScope;
  final bool ownerIsAdmin;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(notifyEventCatalogProvider);
    final textTheme = Theme.of(context).textTheme;
    return switch (catalog) {
      AsyncData(:final value) => Builder(
        builder: (context) {
          final events = value
              .where(
                (e) => serverScope
                    ? e.scope == 'server'
                    : e.scope == 'user' ||
                          (e.scope == 'server' && ownerIsAdmin),
              )
              .toList(growable: false);
          // A personal editor that offers both scopes (admins) gets
          // scope group headers; everyone else sees a flat list.
          final grouped = !serverScope && ownerIsAdmin;
          final children = <Widget>[];
          String? group;
          for (final event in events) {
            if (grouped && group != event.scope) {
              group = event.scope;
              children.add(
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    event.scope == 'server' ? 'Server events' : 'My events',
                    style: textTheme.labelMedium,
                  ),
                ),
              );
            }
            children.add(
              CheckboxListTile(
                key: ValueKey('notify-event-${event.name}'),
                title: Text(event.name),
                subtitle: Text(event.description),
                value: selected.contains(event.name),
                contentPadding: EdgeInsets.zero,
                onChanged: (checked) {
                  final next = {...selected};
                  if (checked ?? false) {
                    next.add(event.name);
                  } else {
                    next.remove(event.name);
                  }
                  onChanged(next);
                },
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
        },
      ),
      AsyncError() => const Text('Could not load the event catalog'),
      _ => const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      ),
    };
  }
}

/// The create-or-edit dialog for one notification target. The save
/// callback performs the write; server rejections surface inline.
class _TargetEditorDialog extends ConsumerStatefulWidget {
  const _TargetEditorDialog({
    required this.serverScope,
    required this.ownerIsAdmin,
    required this.onSave,
    this.existing,
  });

  final bool serverScope;
  final bool ownerIsAdmin;
  final NotificationTarget? existing;
  final Future<void> Function({
    String? pid,
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  })
  onSave;

  @override
  ConsumerState<_TargetEditorDialog> createState() =>
      _TargetEditorDialogState();
}

class _TargetEditorDialogState extends ConsumerState<_TargetEditorDialog> {
  late String _kind = widget.existing?.kind ?? 'pushover';
  late final _labelController = TextEditingController(
    text: widget.existing?.label ?? '',
  );
  final _fieldControllers = <String, TextEditingController>{};
  late Set<String> _events = widget.existing?.enabledEvents.toSet() ?? {};
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _seedFields();
  }

  @override
  void dispose() {
    _labelController.dispose();
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _seedFields() {
    final config = widget.existing?.config ?? const <String, Object?>{};
    for (final field in _kindFields[_kind] ?? const <_ConfigField>[]) {
      _fieldControllers.putIfAbsent(
        '$_kind.${field.key}',
        () => TextEditingController(text: '${config[field.key] ?? ''}'),
      );
    }
  }

  TextEditingController _controllerFor(_ConfigField field) =>
      _fieldControllers['$_kind.${field.key}']!;

  Map<String, Object?>? _buildConfig() {
    final config = <String, Object?>{};
    for (final field in _kindFields[_kind] ?? const <_ConfigField>[]) {
      final text = _controllerFor(field).text.trim();
      if (text.isEmpty) {
        if (!field.optional) {
          setState(() => _error = '${field.label} is required');
          return null;
        }
        continue;
      }
      if (field.integer) {
        final parsed = int.tryParse(text);
        if (parsed == null) {
          setState(() => _error = '${field.label} must be a whole number');
          return null;
        }
        config[field.key] = parsed;
      } else {
        config[field.key] = text;
      }
    }
    return config;
  }

  Future<void> _save() async {
    if (_busy) return;
    final config = _buildConfig();
    if (config == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final label = _labelController.text.trim();
      await widget.onSave(
        pid: widget.existing?.pid,
        kind: _kind,
        label: label.isEmpty ? null : label,
        config: config,
        enabledEvents: _events.toList()..sort(),
      );
      if (mounted) Navigator.of(context).pop();
    } on WaxDeckApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.existing == null;
    return AlertDialog(
      title: Text(
        creating
            ? 'New notification target'
            : 'Edit ${_kindLabel(_kind)} target',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (creating)
                DropdownButtonFormField<String>(
                  key: const Key('notify-target-kind'),
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Deliver via'),
                  items: [
                    for (final kind in _kindFields.keys)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(_kindLabel(kind)),
                      ),
                  ],
                  onChanged: (kind) => setState(() {
                    _kind = kind ?? _kind;
                    _error = null;
                    _seedFields();
                  }),
                ),
              TextField(
                key: const Key('notify-target-label'),
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                ),
              ),
              for (final field in _kindFields[_kind] ?? const <_ConfigField>[])
                TextField(
                  key: ValueKey('notify-config-${field.key}'),
                  controller: _controllerFor(field),
                  obscureText: field.secret,
                  decoration: InputDecoration(
                    labelText: field.optional
                        ? '${field.label} (optional)'
                        : field.label,
                    helperText: field.helper,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Notify me about',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              _EventChecklist(
                serverScope: widget.serverScope,
                ownerIsAdmin: widget.ownerIsAdmin,
                selected: _events,
                onChanged: (next) => setState(() => _events = next),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('notify-target-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('notify-target-save'),
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// One scope's target list with add, edit, test, and remove.
class _TargetList extends ConsumerWidget {
  const _TargetList({
    required this.title,
    required this.subtitle,
    required this.serverScope,
    required this.ownerIsAdmin,
    required this.targets,
    required this.controller,
    required this.addKey,
  });

  final String title;
  final String subtitle;
  final bool serverScope;
  final bool ownerIsAdmin;
  final AsyncValue<List<NotificationTarget>> targets;
  final NotificationTargetActions controller;
  final String addKey;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    NotificationTarget? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _TargetEditorDialog(
        serverScope: serverScope,
        ownerIsAdmin: ownerIsAdmin,
        existing: existing,
        onSave: controller.save,
      ),
    );
  }

  Future<void> _test(BuildContext context, NotificationTarget target) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.sendTest(target.pid);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Test queued; the outcome shows on the target shortly'),
        ),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _healthLine(NotificationTarget t) {
    if (t.lastError != null) return 'Last delivery failed: ${t.lastError}';
    if (t.lastSuccessAt != null) return 'Last delivered ${t.lastSuccessAt}';
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: textTheme.titleMedium)),
            Semantics(
              identifier: addKey,
              label: 'Add notification target',
              button: true,
              child: IconButton(
                key: Key(addKey),
                tooltip: 'Add notification target',
                icon: const Icon(Icons.add),
                onPressed: () => _edit(context, ref),
              ),
            ),
          ],
        ),
        Text(subtitle, style: textTheme.bodySmall),
        const SizedBox(height: 8),
        switch (targets) {
          AsyncData(:final value) =>
            value.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No notification targets yet'),
                  )
                : Column(
                    children: [
                      for (final target in value)
                        ListTile(
                          key: ValueKey('notify-target-${target.pid}'),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(_kindIcon(target.kind)),
                          title: Text(
                            target.label?.isNotEmpty ?? false
                                ? target.label!
                                : _kindLabel(target.kind),
                          ),
                          subtitle: Text(
                            [
                              _kindLabel(target.kind),
                              if (_healthLine(target).isNotEmpty)
                                _healthLine(target),
                            ].join('\n'),
                            style: target.lastError != null
                                ? TextStyle(color: colorScheme.error)
                                : null,
                          ),
                          onTap: () => _edit(context, ref, existing: target),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                identifier: SemanticsIds.notifyTargetTest(
                                  target.pid,
                                ),
                                button: true,
                                child: IconButton(
                                  key: ValueKey(
                                    SemanticsIds.notifyTargetTest(target.pid),
                                  ),
                                  tooltip: 'Send test',
                                  icon: const Icon(
                                    Icons.notification_add_outlined,
                                  ),
                                  onPressed: () => _test(context, target),
                                ),
                              ),
                              IconButton(
                                key: ValueKey(
                                  'notify-target-remove-${target.pid}',
                                ),
                                tooltip: 'Remove',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => controller.remove(target.pid),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          AsyncError() => const Text('Could not load notification targets'),
          _ => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
        },
      ],
    );
  }
}

/// The caller's personal notification targets, UnifiedPush devices
/// included.
class PersonalNotificationTargetsSection extends ConsumerWidget {
  const PersonalNotificationTargetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value?.user;
    return _TargetList(
      title: 'My notifications',
      subtitle:
          'Where your events (new episodes, review queue) get '
          'delivered: Pushover, ntfy, Gotify, Discord, webhooks, or '
          'this device\'s push registration.',
      serverScope: false,
      ownerIsAdmin: user?.roles.contains('admin') ?? false,
      targets: ref.watch(myNotificationTargetsProvider),
      controller: ref.read(myNotificationTargetsProvider.notifier),
      addKey: SemanticsIds.notifyTargetAdd,
    );
  }
}

/// The server-scope notification targets; administrators only.
class ServerNotificationTargetsSection extends ConsumerWidget {
  const ServerNotificationTargetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TargetList(
      title: 'Server notifications',
      subtitle:
          'Operations events (account requests, backup outcomes) '
          'delivered to server-wide destinations.',
      serverScope: true,
      // The section renders behind the admin gate; the flag only
      // shapes the personal checklist, which server scope never shows.
      ownerIsAdmin: true,
      targets: ref.watch(serverNotificationTargetsProvider),
      controller: ref.read(serverNotificationTargetsProvider.notifier),
      addKey: SemanticsIds.notifyServerTargetAdd,
    );
  }
}
