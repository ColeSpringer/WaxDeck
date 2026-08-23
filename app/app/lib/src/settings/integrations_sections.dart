import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'client_prefs.dart';
import 'integrations_controller.dart';
import 'notify_labels.dart';
import 'setting_anchor.dart';

/// Scrobbling connections: Last.fm through the browser authorization
/// flow, ListenBrainz through a token dialog.
class ScrobblingSection extends ConsumerWidget {
  const ScrobblingSection({super.key});

  /// Service names, which are the same in every language.
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
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (slot.service == 'lastfm') {
      try {
        final authUrl = await ref
            .read(scrobblersProvider.notifier)
            .startLastfmConnect();
        await ref.read(urlOpenerProvider).open(authUrl);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsScrobblerApprove)),
        );
      } on WaxDeckApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
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
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(scrobblersProvider.notifier).disconnect(slot.service);
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
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
    final l10n = context.l10n;
    final adminSetup = isAdmin && slot.service == 'lastfm';
    if (adminSetup && !slot.connected && !slot.available) {
      return Semantics(
        identifier: SemanticsIds.scrobblerSetupLastfm,
        button: true,
        child: TextButton(
          key: const ValueKey(SemanticsIds.scrobblerSetupLastfm),
          onPressed: () => _openLastfmSetup(context),
          child: Text(l10n.settingsScrobblerSetUp),
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
              child: Text(l10n.settingsScrobblerDisconnect),
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
              child: Text(l10n.settingsScrobblerConnect),
            ),
          );
    if (!adminSetup) return action;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action,
        WaxIconButton(
          key: const ValueKey(SemanticsIds.scrobblerSetupLastfm),
          glyph: WaxIcons.settings,
          label: l10n.settingsScrobblerCredentialsLabel,
          semanticsId: SemanticsIds.scrobblerSetupLastfm,
          onPressed: () => _openLastfmSetup(context),
        ),
      ],
    );
  }

  /// The row's one-line status: connection state first, then delivery
  /// health. A standing error outranks the connected pleasantry; the
  /// user opening this screen wants to know why scrobbles stopped.
  String _slotStatus(AppLocalizations l10n, Scrobbler slot) {
    if (!slot.connected) {
      return slot.available
          ? l10n.settingsScrobblerNotConnected
          : l10n.settingsScrobblerNeedsCredentials;
    }
    final failure = slot.lastError;
    if (failure != null) return l10n.settingsScrobblerFailing(failure);
    // Four sentences rather than one built out of pieces: which half of
    // "connected as X, delivering" comes first is the translator's, and
    // a string joined here would take that away.
    final who = slot.username;
    if (slot.lastSuccessAt != null) {
      return who == null
          ? l10n.settingsScrobblerDelivering
          : l10n.settingsScrobblerDeliveringAs(who);
    }
    return who == null
        ? l10n.settingsScrobblerConnected
        : l10n.settingsScrobblerConnectedAs(who);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scrobblers = ref.watch(scrobblersProvider);
    final user = ref.watch(authControllerProvider).value?.user;
    final isAdmin = user?.roles.contains('admin') ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.settingsScrobblingTitle),
        switch (scrobblers) {
          AsyncData(:final value) => Column(
            children: [
              for (final slot in value)
                WaxOptionRow(
                  key: ValueKey(SemanticsIds.scrobbler(slot.service)),
                  semanticsId: SemanticsIds.scrobbler(slot.service),
                  // A standing delivery failure changes the glyph rather
                  // than reddening the line it is written on: the line
                  // already says "Delivery failing", and colour that
                  // repeats words is the half of the signal a screen
                  // reader and a colour-blind reader both lose.
                  glyph: slot.lastError == null
                      ? WaxIcons.waveform
                      : WaxIcons.warning,
                  title: _label(slot.service),
                  subtitle: _slotStatus(l10n, slot),
                  // The status can carry a whole server error; two
                  // lines would ellipse the half that says why.
                  subtitleMaxLines: 6,
                  trailing: _trailing(context, ref, slot, isAdmin: isAdmin),
                ),
            ],
          ),
          AsyncError() => Text(l10n.settingsScrobblingError),
          _ => const Padding(
            padding: EdgeInsets.all(WaxSpace.s8),
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
      // The server's own sentence rather than the code's: this is a
      // refusal of the token that was just typed, and the translation
      // for `invalid-request` would say only that something was wrong.
      // The same rule the password and timezone dialogs follow.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.settingsListenBrainzTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No Semantics identifier wrapper: on the web it would mint a
          // second, disabled text-field node beside the real input.
          TextField(
            key: const Key('listenbrainz-token-field'),
            controller: _tokenController,
            decoration: InputDecoration(
              labelText: l10n.settingsListenBrainzToken,
              helperText: l10n.settingsListenBrainzTokenHelp,
            ),
            autofocus: true,
          ),
          const SizedBox(height: WaxSpace.s8),
          TextField(
            key: const Key('listenbrainz-api-field'),
            controller: _apiUrlController,
            decoration: InputDecoration(
              labelText: l10n.settingsListenBrainzApi,
              helperText: l10n.settingsListenBrainzApiHelp,
            ),
            keyboardType: TextInputType.url,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        Semantics(
          identifier: SemanticsIds.listenbrainzConnectConfirm,
          label: l10n.settingsScrobblerConnect,
          button: true,
          child: FilledButton(
            key: const Key(SemanticsIds.listenbrainzConnectConfirm),
            onPressed: _busy ? null : _connect,
            child: Text(l10n.settingsScrobblerConnect),
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
      // The server's own sentence, for the same reason the ListenBrainz
      // dialog keeps one: this refuses the pair that was just typed, and
      // says which half is missing.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = ref.watch(scrobblingAdminConfigProvider);
    return AlertDialog(
      title: Text(l10n.settingsLastfmCredentialsTitle),
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
                  decoration: InputDecoration(
                    labelText: l10n.settingsLastfmApiKey,
                    helperText: l10n.settingsLastfmApiKeyHelp,
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: WaxSpace.s8),
                TextField(
                  key: const Key('lastfm-secret-field'),
                  controller: _secretController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.settingsLastfmSecret,
                    helperText: value.lastfmSecretSet
                        ? l10n.settingsLastfmSecretHelp
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
        AsyncError() => Text(l10n.settingsLastfmCredentialsError),
        _ => const Padding(
          padding: EdgeInsets.all(WaxSpace.s8),
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
              child: Text(l10n.settingsLastfmCredentialsClear),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        Semantics(
          identifier: SemanticsIds.lastfmCredentialsSave,
          label: l10n.commonSave,
          button: true,
          child: FilledButton(
            key: const Key(SemanticsIds.lastfmCredentialsSave),
            onPressed: _busy || config is! AsyncData
                ? null
                : () => _save(clear: false),
            child: Text(l10n.commonSave),
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
    final l10n = context.l10n;
    final on = ref.watch(discordPresenceEnabledProvider);
    final colors = WaxColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.settingsGroupDiscord),
        SettingAnchor(
          id: 'discord-presence',
          child: WaxSettingRow(
            title: l10n.settingsDiscordPresenceRowTitle,
            help: l10n.settingsDiscordPresenceHelp,
            control: WaxSwitch(
              value: on,
              label: l10n.settingsDiscordPresenceTitle,
              semanticsId: SemanticsIds.setting('discord-presence'),
              onChanged: ref.read(discordPresenceEnabledProvider.notifier).set,
            ),
          ),
        ),
        if (on)
          Padding(
            padding: const EdgeInsets.only(top: WaxSpace.s8),
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
                    decoration: InputDecoration(
                      labelText: l10n.settingsDiscordApplicationLabel,
                      helperText: l10n.settingsDiscordApplicationHelp,
                    ),
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _commit(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: WaxSpace.s8),
                  child: Text(
                    l10n.settingsDiscordCoverNote,
                    style: WaxType.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
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
    final l10n = context.l10n;
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsAppPasswordNewSpoken),
        content: TextField(
          key: const Key('app-password-label-field'),
          controller: controller,
          decoration: InputDecoration(
            labelText: l10n.settingsAppPasswordLabel,
            helperText: l10n.settingsAppPasswordLabelHelp,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('app-password-create-confirm'),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.settingsAppPasswordCreate),
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
          title: Text(l10n.settingsAppPasswordCreatedTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsAppPasswordCreatedMessage),
              const SizedBox(height: WaxSpace.s12),
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
              child: Text(l10n.settingsAppPasswordCopy),
            ),
            FilledButton(
              key: const Key('app-password-secret-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.settingsAppPasswordDone),
            ),
          ],
        ),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final passwords = ref.watch(appPasswordsProvider);
    final colors = WaxColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.settingsAppPasswordsTitle,
          actionLabel: l10n.settingsAppPasswordNewAction,
          spokenActionLabel: l10n.settingsAppPasswordNewSpoken,
          semanticsId: SemanticsIds.appPasswordAdd,
          onAction: () => _create(context, ref),
        ),
        Text(
          l10n.settingsAppPasswordsBlurb,
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s8),
        switch (passwords) {
          AsyncData(:final value) =>
            value.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
                    child: Text(l10n.settingsAppPasswordsEmpty),
                  )
                : Column(
                    children: [
                      for (final ap in value)
                        WaxOptionRow(
                          key: ValueKey('app-password-${ap.id}'),
                          glyph: WaxIcons.key,
                          title: ap.label.isEmpty
                              ? l10n.settingsAppPasswordUnlabeled
                              : ap.label,
                          trailing: WaxIconButton(
                            key: ValueKey(
                              SemanticsIds.appPasswordRevoke(ap.id),
                            ),
                            glyph: WaxIcons.delete,
                            // The same fallback the title takes: an
                            // unlabelled password would otherwise give
                            // two identical "Revoke" buttons with no
                            // subject.
                            label: l10n.settingsAppPasswordRevoke(
                              ap.label.isEmpty
                                  ? l10n.settingsAppPasswordUnlabeled
                                  : ap.label,
                            ),
                            semanticsId: SemanticsIds.appPasswordRevoke(ap.id),
                            onPressed: () => ref
                                .read(appPasswordsProvider.notifier)
                                .revoke(ap.id),
                          ),
                        ),
                    ],
                  ),
          AsyncError() => Text(l10n.settingsAppPasswordsError),
          _ => const Padding(
            padding: EdgeInsets.all(WaxSpace.s8),
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

/// The per-kind config surface, and the kinds themselves: the picker
/// offers these keys, so a service cannot be listed with no fields
/// behind it, nor carry fields nothing can reach.
///
/// Mirrors the server's provider validation; the server's message is the
/// authority when they drift. A map rather than a switch because the
/// keys are half of what it answers.
Map<String, List<_ConfigField>> _kindFields(
  AppLocalizations l10n,
) => <String, List<_ConfigField>>{
  'pushover': <_ConfigField>[
    _ConfigField('token', l10n.settingsNotifyPushoverToken, secret: true),
    _ConfigField('userKey', l10n.settingsNotifyPushoverUserKey, secret: true),
    _ConfigField(
      'priority',
      l10n.settingsNotifyPriority,
      optional: true,
      integer: true,
      helper: l10n.settingsNotifyPushoverPriorityHelp,
    ),
  ],
  'ntfy': <_ConfigField>[
    _ConfigField('topic', l10n.settingsNotifyNtfyTopic),
    _ConfigField(
      'serverUrl',
      l10n.settingsNotifyServerUrl,
      optional: true,
      helper: l10n.settingsNotifyNtfyServerHelp,
    ),
    _ConfigField(
      'accessToken',
      l10n.settingsNotifyAccessToken,
      optional: true,
      secret: true,
    ),
  ],
  'gotify': <_ConfigField>[
    _ConfigField('serverUrl', l10n.settingsNotifyServerUrl),
    _ConfigField('token', l10n.settingsNotifyPushoverToken, secret: true),
    _ConfigField(
      'priority',
      l10n.settingsNotifyPriority,
      optional: true,
      integer: true,
      helper: l10n.settingsNotifyGotifyPriorityHelp,
    ),
  ],
  'discord': <_ConfigField>[
    _ConfigField(
      'webhookUrl',
      l10n.settingsNotifyWebhookUrl,
      secret: true,
      helper: l10n.settingsNotifyDiscordWebhookHelp,
    ),
  ],
  'webhook': <_ConfigField>[
    _ConfigField(
      'url',
      l10n.settingsNotifyUrl,
      helper: l10n.settingsNotifyWebhookHelp,
    ),
  ],
  'apprise': <_ConfigField>[
    _ConfigField('serverUrl', l10n.settingsNotifyAppriseServerUrl),
    _ConfigField(
      'targets',
      l10n.settingsNotifyAppriseTargets,
      optional: true,
      helper: l10n.settingsNotifyAppriseTargetsHelp,
    ),
  ],
  'unifiedpush': <_ConfigField>[
    _ConfigField(
      'endpoint',
      l10n.settingsNotifyEndpointUrl,
      helper: l10n.settingsNotifyUnifiedPushHelp,
    ),
  ],
};

/// Service names, which are the same in every language.
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

WaxGlyph _kindIcon(String kind) => switch (kind) {
  'unifiedpush' => WaxIcons.devices,
  'discord' => WaxIcons.chat,
  'webhook' => WaxIcons.webhook,
  _ => WaxIcons.bell,
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
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
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
                  padding: const EdgeInsets.only(top: WaxSpace.s8),
                  child: Text(
                    event.scope == 'server'
                        ? l10n.settingsNotifyServerEvents
                        : l10n.settingsNotifyMyEvents,
                    style: WaxType.label.copyWith(color: colors.textSecondary),
                  ),
                ),
              );
            }
            children.add(
              WaxSettingRow(
                key: ValueKey('notify-event-${event.name}'),
                title: notifyEventTitle(l10n, event),
                help: notifyEventHelp(l10n, event),
                control: WaxSwitch(
                  value: selected.contains(event.name),
                  label: notifyEventTitle(l10n, event),
                  onChanged: (checked) {
                    final next = {...selected};
                    if (checked) {
                      next.add(event.name);
                    } else {
                      next.remove(event.name);
                    }
                    onChanged(next);
                  },
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
        },
      ),
      AsyncError() => Text(l10n.settingsNotifyCatalogError),
      _ => const Padding(
        padding: EdgeInsets.all(WaxSpace.s8),
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
  void dispose() {
    _labelController.dispose();
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The controller for one field, made the first time that field is
  /// drawn.
  ///
  /// On demand rather than seeded ahead: a field's label is copy now, so
  /// the list of them needs a locale, and `initState` has no context to
  /// read one from. Switching kinds needs no seeding either - the new
  /// kind's controllers are made as its fields are built.
  TextEditingController _controllerFor(_ConfigField field) =>
      _fieldControllers.putIfAbsent('$_kind.${field.key}', () {
        final config = widget.existing?.config ?? const <String, Object?>{};
        return TextEditingController(text: '${config[field.key] ?? ''}');
      });

  Map<String, Object?>? _buildConfig(AppLocalizations l10n) {
    final config = <String, Object?>{};
    for (final field in _kindFields(l10n)[_kind] ?? const <_ConfigField>[]) {
      final text = _controllerFor(field).text.trim();
      if (text.isEmpty) {
        if (!field.optional) {
          setState(
            () => _error = l10n.settingsNotifyFieldRequired(field.label),
          );
          return null;
        }
        continue;
      }
      if (field.integer) {
        final parsed = int.tryParse(text);
        if (parsed == null) {
          setState(
            () => _error = l10n.settingsNotifyFieldWholeNumber(field.label),
          );
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
    final config = _buildConfig(context.l10n);
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
    final l10n = context.l10n;
    final kinds = _kindFields(l10n);
    final creating = widget.existing == null;
    return AlertDialog(
      title: Text(
        creating
            ? l10n.settingsNotifyTargetNewTitle
            : l10n.settingsNotifyTargetEditTitle(_kindLabel(_kind)),
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
                  decoration: InputDecoration(
                    labelText: l10n.settingsNotifyDeliverVia,
                  ),
                  items: [
                    for (final kind in kinds.keys)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(_kindLabel(kind)),
                      ),
                  ],
                  onChanged: (kind) => setState(() {
                    _kind = kind ?? _kind;
                    _error = null;
                  }),
                ),
              TextField(
                key: const Key('notify-target-label'),
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: l10n.settingsNotifyTargetLabel,
                ),
              ),
              for (final field in kinds[_kind] ?? const <_ConfigField>[])
                TextField(
                  key: ValueKey('notify-config-${field.key}'),
                  controller: _controllerFor(field),
                  obscureText: field.secret,
                  decoration: InputDecoration(
                    labelText: field.optional
                        ? l10n.settingsNotifyFieldOptional(field.label)
                        : field.label,
                    helperText: field.helper,
                  ),
                ),
              const SizedBox(height: WaxSpace.s12),
              Text(
                l10n.settingsNotifyAbout,
                style: WaxType.label.copyWith(
                  color: WaxColors.of(context).textPrimary,
                ),
              ),
              _EventChecklist(
                serverScope: widget.serverScope,
                ownerIsAdmin: widget.ownerIsAdmin,
                selected: _events,
                onChanged: (next) => setState(() => _events = next),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: WaxSpace.s8),
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
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('notify-target-save'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.commonSave),
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
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.sendTest(target.pid);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsNotifyTestQueued)),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    }
  }

  /// The delivery line under a target, or null where it has neither
  /// failed nor delivered.
  ///
  /// Null rather than an empty string, so the row draws it with one
  /// call: an empty sentinel has to be asked for twice, and this one
  /// formats a date.
  String? _healthLine(AppLocalizations l10n, NotificationTarget t) {
    final failure = t.lastError;
    if (failure != null) return l10n.settingsNotifyLastFailed(failure);
    final delivered = t.lastSuccessAt;
    if (delivered != null) {
      return l10n.settingsNotifyLastDelivered(l10n.formatStamp(delivered));
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          actionLabel: l10n.settingsNotifyTargetAddAction,
          spokenActionLabel: l10n.settingsNotifyTargetAddSpoken,
          semanticsId: addKey,
          onAction: () => _edit(context, ref),
        ),
        Text(
          subtitle,
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s8),
        switch (targets) {
          AsyncData(:final value) =>
            value.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
                    child: Text(l10n.settingsNotifyTargetsEmpty),
                  )
                : Column(
                    children: [
                      for (final target in value)
                        WaxOptionRow(
                          key: ValueKey('notify-target-${target.pid}'),
                          // The failing target says so in its glyph as
                          // well as in its line, for the reason the
                          // scrobbler rows above record.
                          glyph: target.lastError != null
                              ? WaxIcons.warning
                              : _kindIcon(target.kind),
                          title: target.label?.isNotEmpty ?? false
                              ? target.label!
                              : _kindLabel(target.kind),
                          subtitle: [
                            _kindLabel(target.kind),
                            ?_healthLine(l10n, target),
                          ].join('\n'),
                          // Two lines are the kind and the health line;
                          // a failing delivery adds the server's own
                          // words to the second and needs the room.
                          subtitleMaxLines: 6,
                          onTap: () => _edit(context, ref, existing: target),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              WaxIconButton(
                                key: ValueKey(
                                  SemanticsIds.notifyTargetTest(target.pid),
                                ),
                                glyph: WaxIcons.bell,
                                label: l10n.settingsNotifySendTest,
                                semanticsId: SemanticsIds.notifyTargetTest(
                                  target.pid,
                                ),
                                onPressed: () => _test(context, target),
                              ),
                              WaxIconButton(
                                key: ValueKey(
                                  'notify-target-remove-${target.pid}',
                                ),
                                glyph: WaxIcons.delete,
                                label: l10n.settingsNotifyTargetRemove,
                                onPressed: () => controller.remove(target.pid),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          AsyncError() => Text(l10n.settingsNotifyTargetsError),
          _ => const Padding(
            padding: EdgeInsets.all(WaxSpace.s8),
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
    final l10n = context.l10n;
    final user = ref.watch(authControllerProvider).value?.user;
    return _TargetList(
      title: l10n.settingsNotifyMyTitle,
      subtitle: l10n.settingsNotifyMyBlurb,
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
    final l10n = context.l10n;
    return _TargetList(
      title: l10n.settingsNotifyServerTitle,
      subtitle: l10n.settingsNotifyServerBlurb,
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
