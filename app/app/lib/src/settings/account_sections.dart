import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'about_screen.dart';
import 'integrations_sections.dart';
import 'listening_sections.dart';
import 'sessions_controller.dart';

/// The signed-in account's own record.
///
/// `GET /users/{id}` answers a caller's own account without administrator
/// rights, which is what makes the read-only access line in Library and
/// metadata possible for a household member. Kept here rather than in
/// the auth controller because it is a detail read, not the session: the
/// session says who you are, and this says what your account holds.
final myAccountProvider = FutureProvider<UserAccount>((ref) async {
  final session = await ref.watch(authControllerProvider.future);
  final user = session.user;
  if (user == null) {
    throw const WaxDeckApiException(
      code: 'unauthenticated',
      message: 'Not signed in',
    );
  }
  return ref.watch(repositoryProvider).getUser(user.id);
});

/// The Account section: who you are, how you sign in, and what is signed
/// in as you.
class AccountSectionBody extends ConsumerWidget {
  const AccountSectionBody({super.key});

  // Nothing to unwind by hand: dropping the session moves the auth
  // redirect, which replaces the whole signed-in stack with login.
  Future<void> _signOut(WidgetRef ref) =>
      ref.read(authControllerProvider.notifier).logout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value?.user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: WaxSpace.s16),
        WaxOptionRow(
          title: user?.label ?? 'Signed in',
          subtitle: user?.username,
          glyph: WaxIcons.settings,
          semanticsId: SemanticsIds.setting('display-name'),
        ),
        WaxSettingRow(
          title: 'Change password',
          help: 'Signs out your other devices; app passwords are unaffected',
          control: WaxButton(
            label: 'Change',
            kind: WaxButtonKind.tonal,
            semanticsId: SemanticsIds.setting('password'),
            onPressed: user == null
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => _PasswordDialog(userId: user.id),
                  ),
          ),
        ),
        const SizedBox(height: WaxSpace.s16),
        const ListeningSection(),
        const SizedBox(height: WaxSpace.s16),
        // Wrapped so the group carries the handle the registry names for
        // it. These two are lists rather than single controls, and a
        // registry entry has to point at something that is there whether
        // the list is empty or full.
        Semantics(
          identifier: SemanticsIds.setting('devices'),
          child: const _DeviceSessions(),
        ),
        const SizedBox(height: WaxSpace.s16),
        Semantics(
          identifier: SemanticsIds.setting('app-passwords'),
          child: const AppPasswordsSection(),
        ),
        const SizedBox(height: WaxSpace.s24),
        SectionHeader(title: 'About'),
        const AboutRow(semanticsId: 'about'),
        const SizedBox(height: WaxSpace.s24),
        WaxButton(
          label: 'Sign out',
          kind: WaxButtonKind.destructive,
          icon: WaxIcons.offline,
          semanticsId: SemanticsIds.logoutButton,
          onPressed: () => _signOut(ref),
        ),
      ],
    );
  }
}

/// Changing your own password, which the contract requires the current
/// one for.
///
/// A refusal lands against the field it is about rather than in a
/// snackbar, and which field that is comes from the code. `forbidden`
/// means exactly one thing here - the current password was wrong - and
/// everything else the endpoint answers is about the new one, because
/// the policy check runs before the current password is even verified.
/// Attributing both to the current-password field would tell somebody to
/// re-type a value that was already right.
class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog({required this.userId});

  final String userId;

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  String? _currentError;
  String? _nextError;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _currentError = null;
      _nextError = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .setUserPassword(
            widget.userId,
            _next.text,
            currentPassword: _current.text,
          );
      // Guarded, because a pop past a dismissed dialog pops the screen
      // underneath it: the request can be in flight while somebody taps
      // the scrim. The password still changed, so the confirmation is
      // shown either way.
      if (mounted) navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Password changed')));
    } on WaxDeckApiException catch (e) {
      // Guarded because the dialog can be dismissed while the request is
      // out, and setState past that throws.
      if (!mounted) return;
      setState(() {
        if (e.code == 'forbidden') {
          _currentError = e.message;
        } else {
          // `invalid-request` is the password policy, which the server
          // owns; showing its sentence beats guessing the rule here and
          // drifting from it.
          _nextError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WaxTextField(
          label: 'Current password',
          controller: _current,
          obscureText: true,
          autofocus: true,
          errorText: _currentError,
        ),
        const SizedBox(height: WaxSpace.s12),
        WaxTextField(
          label: 'New password',
          controller: _next,
          obscureText: true,
          errorText: _nextError,
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: <Widget>[
      WaxButton(
        label: 'Cancel',
        kind: WaxButtonKind.text,
        onPressed: () => Navigator.of(context).pop(),
      ),
      WaxButton(
        label: 'Change password',
        onPressed: _busy ? null : _save,
        semanticsId: SemanticsIds.setting('password-save'),
      ),
    ],
  );
}

/// What is signed in as this account, and how to sign one out.
class _DeviceSessions extends ConsumerWidget {
  const _DeviceSessions();

  Future<void> _rename(BuildContext context, DeviceSession session) =>
      showDialog<void>(
        context: context,
        builder: (_) => _DeviceRenameDialog(session: session),
      );

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    DeviceSession session,
  ) async {
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
        actions: <Widget>[
          WaxButton(
            label: 'Cancel',
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WaxButton(
            label: 'Sign out',
            kind: WaxButtonKind.destructive,
            key: const Key('device-revoke-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
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
      }
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static String _date(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: 'Signed-in devices'),
        switch (sessions) {
          AsyncData(:final value) => Column(
            children: <Widget>[
              for (final session in value)
                WaxOptionRow(
                  title: session.current
                      ? '${session.label} (this device)'
                      : session.label,
                  // The client is named only where the title is not
                  // already it: a web session with no device name is
                  // titled by its browser, and "Firefox / signed in
                  // with Firefox" says one thing twice.
                  subtitle: <String>[
                    'Signed in ${_date(session.createdAt)}',
                    if (session.deviceName != null) ?session.client,
                  ].join(' with '),
                  glyph: session.kind == SessionKind.web
                      ? WaxIcons.devices
                      : WaxIcons.headphones,
                  semanticsId: SemanticsIds.deviceRow(session.id),
                  // One trailing slot, two affordances, so they share a
                  // Row sized to itself rather than to the option row.
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      WaxIconButton(
                        glyph: WaxIcons.edit,
                        label: 'Rename device',
                        semanticsId: SemanticsIds.deviceRename(session.id),
                        onPressed: () => _rename(context, session),
                      ),
                      WaxIconButton(
                        glyph: WaxIcons.offline,
                        label: 'Sign out device',
                        semanticsId: SemanticsIds.deviceRevoke(session.id),
                        onPressed: () => _revoke(context, ref, session),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          AsyncError() => const ErrorState(
            title: 'Could not load devices',
            message: 'The server did not answer.',
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ],
    );
  }
}

/// Device rename: a plain text field whose value the server trims and
/// validates, so a refusal comes back into the dialog rather than into a
/// snackbar somewhere behind it.
///
/// Save is disabled while the trimmed value is empty, which is the same
/// rule the server enforces: refusing locally is a better answer than a
/// round trip that can only end in 400.
class _DeviceRenameDialog extends ConsumerStatefulWidget {
  const _DeviceRenameDialog({required this.session});

  final DeviceSession session;

  @override
  ConsumerState<_DeviceRenameDialog> createState() =>
      _DeviceRenameDialogState();
}

class _DeviceRenameDialogState extends ConsumerState<_DeviceRenameDialog> {
  late final _controller = TextEditingController(
    text: widget.session.deviceName ?? '',
  );
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (_busy || name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(sessionsControllerProvider.notifier)
          .rename(widget.session.id, name);
      navigator.pop();
    } on WaxDeckApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = _controller.text.trim().isEmpty;
    return AlertDialog(
      title: const Text('Rename device'),
      content: WaxTextField(
        label: 'Device name',
        hint: 'Kitchen radio',
        controller: _controller,
        autofocus: true,
        errorText: _error,
        // Clears the refusal as well as re-running the save gate: the
        // message is about the name that was submitted, and leaving it
        // under a name that has since changed would show "invalid" beside
        // an enabled Save.
        // Clears the refusal as well as re-running the save gate: the
        // message is about the name that was submitted, and leaving it
        // under a name that has since changed would show "invalid" beside
        // an enabled Save.
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _save(),
      ),
      actions: <Widget>[
        WaxButton(
          label: 'Cancel',
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          key: const Key('device-rename-confirm'),
          label: 'Save',
          onPressed: _busy || empty ? null : _save,
        ),
      ],
    );
  }
}
