import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import 'prefs_controller.dart';
import 'sessions_controller.dart';

/// Account surface: the signed-in user, the synced theme preference, the
/// device list with revocation, and sign out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static String _themeLabel(ThemePref theme) => switch (theme) {
    ThemePref.system => 'System',
    ThemePref.dark => 'Dark',
    ThemePref.light => 'Light',
    ThemePref.oled => 'OLED black',
  };

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    await ref.read(authControllerProvider.notifier).logout();
    // This screen sits above the root gate; unwind so the gate's login
    // screen is what remains.
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    DeviceSession session,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          session.current ? 'Sign out this device?' : 'Sign out device?',
        ),
        content: Text(
          session.current
              ? 'This is the device you are using now. Revoking its '
                    'session signs you out.'
              : '"${session.label}" will be signed out immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('device-revoke-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final wasCurrent = await ref
          .read(sessionsControllerProvider.notifier)
          .revoke(session.id);
      if (wasCurrent) {
        await ref.read(authControllerProvider.notifier).signOutLocally();
        navigator.popUntil((route) => route.isFirst);
      }
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).value?.user;
    final prefs = ref.watch(prefsControllerProvider).value;
    final sessions = ref.watch(sessionsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Account', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(user?.label ?? 'Signed in'),
            subtitle: user == null ? null : Text(user.username),
          ),
          const SizedBox(height: 16),
          Text('Appearance', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            trailing: Semantics(
              identifier: 'theme-select',
              child: DropdownButton<ThemePref>(
                key: const Key('theme-select'),
                value: prefs?.theme ?? ThemePref.dark,
                onChanged: (theme) {
                  if (theme == null) return;
                  ref.read(prefsControllerProvider.notifier).setTheme(theme);
                },
                items: [
                  for (final theme in ThemePref.values)
                    DropdownMenuItem(
                      value: theme,
                      child: Text(_themeLabel(theme)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Devices', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          switch (sessions) {
            AsyncData(:final value) => Column(
              children: [
                for (final session in value)
                  _DeviceRow(
                    session: session,
                    onRevoke: () => _revoke(context, ref, session),
                  ),
              ],
            ),
            AsyncError() => Text(
              'Could not load devices',
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            ),
            _ => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          },
          const SizedBox(height: 24),
          Semantics(
            identifier: 'logout-button',
            child: FilledButton.tonalIcon(
              key: const Key('logout-button'),
              onPressed: () => _signOut(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.session, required this.onRevoke});

  final DeviceSession session;
  final VoidCallback onRevoke;

  static String _date(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = StringBuffer('Signed in ${_date(session.createdAt)}');
    final client = session.client;
    if (session.deviceName != null && client != null) {
      subtitle.write(' with $client');
    }
    return Semantics(
      identifier: 'device-row-${session.id}',
      child: ListTile(
        key: Key('device-row-${session.id}'),
        leading: Icon(
          session.kind == SessionKind.web
              ? Icons.language
              : Icons.devices_other,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(session.label, overflow: TextOverflow.ellipsis),
            ),
            if (session.current) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('This device'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
        subtitle: Text(subtitle.toString()),
        trailing: Semantics(
          identifier: 'device-revoke-${session.id}',
          child: IconButton(
            key: Key('device-revoke-${session.id}'),
            tooltip: 'Sign out device',
            icon: const Icon(Icons.logout),
            onPressed: onRevoke,
          ),
        ),
      ),
    );
  }
}
