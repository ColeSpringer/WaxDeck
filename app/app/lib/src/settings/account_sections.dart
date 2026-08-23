import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'about_screen.dart';
import 'integrations_sections.dart';
import 'listening_sections.dart';
import 'sessions_controller.dart';
import 'setting_anchor.dart';

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
    // The one English string left in this file, and a diagnostic
    // rather than copy: the one surface that reads this provider draws
    // its own sentence for the failure, and anything that renders an
    // exception instead goes through `explainError`, which answers on
    // the code. `error_table_test.dart` records why the code is the
    // contract's own here.
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
    final l10n = context.l10n;
    final user = ref.watch(authControllerProvider).value?.user;
    // The same gap the sibling sections get from `_Group`. Account is
    // the one body built out of whole widgets rather than that helper,
    // which is how it came to space its sections closer than the section
    // beside it in the same list.
    final sectionGap = WaxLayout.of(context).sectionGap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The leading gap too: `_Group` opens its sibling bodies at the
        // section gap, so a hand-written 16 here is the same body-to-body
        // jump under one app bar that the rest of this fixed.
        SizedBox(height: sectionGap),
        SettingAnchor(
          id: 'display-name',
          child: WaxOptionRow(
            title: user?.label ?? l10n.settingsAccountSignedIn,
            subtitle: user?.username,
            glyph: WaxIcons.settings,
            semanticsId: SemanticsIds.setting('display-name'),
          ),
        ),
        SettingAnchor(
          id: 'password',
          child: WaxSettingRow(
            title: l10n.settingsPasswordTitle,
            help: l10n.settingsPasswordHelp,
            control: WaxButton(
              label: l10n.settingsPasswordChangeAction,
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
        ),
        SizedBox(height: sectionGap),
        const ListeningSection(),
        SizedBox(height: sectionGap),
        // Wrapped so the group carries the handle the registry names for
        // it. These two are lists rather than single controls, and a
        // registry entry has to point at something that is there whether
        // the list is empty or full.
        SettingAnchor(
          id: 'devices',
          child: Semantics(
            identifier: SemanticsIds.setting('devices'),
            child: const _DeviceSessions(),
          ),
        ),
        SizedBox(height: sectionGap),
        SettingAnchor(
          id: 'app-passwords',
          child: Semantics(
            identifier: SemanticsIds.setting('app-passwords'),
            child: const AppPasswordsSection(),
          ),
        ),
        SizedBox(height: sectionGap),
        SectionHeader(title: l10n.settingsGroupAbout),
        const SettingAnchor(
          id: 'about',
          child: AboutRow(semanticsId: SemanticsIds.aboutRow),
        ),
        SizedBox(height: sectionGap),
        WaxButton(
          label: l10n.settingsSignOut,
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
    final changed = context.l10n.settingsPasswordChanged;
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
      messenger.showSnackBar(SnackBar(content: Text(changed)));
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.settingsPasswordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WaxTextField(
            label: l10n.settingsPasswordCurrentLabel,
            controller: _current,
            obscureText: true,
            autofocus: true,
            errorText: _currentError,
          ),
          const SizedBox(height: WaxSpace.s12),
          WaxTextField(
            label: l10n.settingsPasswordNewLabel,
            controller: _next,
            obscureText: true,
            errorText: _nextError,
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: <Widget>[
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: l10n.settingsPasswordTitle,
          onPressed: _busy ? null : _save,
          semanticsId: SemanticsIds.setting('password-save'),
        ),
      ],
    );
  }
}

/// The app to name beside a session, or null where the row's title is
/// already it.
String? _namedClient(DeviceSession session) =>
    session.deviceName == null ? null : session.client;

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
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          session.current
              ? l10n.settingsDeviceSignOutCurrentTitle
              : l10n.settingsDeviceSignOutTitle,
        ),
        content: Text(
          session.current
              ? l10n.settingsDeviceSignOutCurrentMessage
              : l10n.settingsDeviceSignOutMessage(session.label),
        ),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WaxButton(
            label: l10n.settingsSignOut,
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
      messenger.showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsControllerProvider);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.settingsDevicesTitle),
        switch (sessions) {
          AsyncData(:final value) => Column(
            children: <Widget>[
              for (final session in value)
                WaxOptionRow(
                  title: session.current
                      ? l10n.settingsDeviceThisDevice(session.label)
                      : session.label,
                  // The client is named only where the title is not
                  // already it: a web session with no device name is
                  // titled by its browser, and "Firefox / signed in
                  // with Firefox" says one thing twice. Two sentences
                  // rather than one joined here, so a translation can
                  // put the app before the date.
                  subtitle: switch (_namedClient(session)) {
                    final client? => l10n.settingsDeviceSignedInWith(
                      l10n.formatDate(session.createdAt),
                      client,
                    ),
                    null => l10n.settingsDeviceSignedIn(
                      l10n.formatDate(session.createdAt),
                    ),
                  },
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
                        label: l10n.settingsDeviceRename,
                        semanticsId: SemanticsIds.deviceRename(session.id),
                        onPressed: () => _rename(context, session),
                      ),
                      WaxIconButton(
                        glyph: WaxIcons.offline,
                        label: l10n.settingsDeviceSignOutAction,
                        semanticsId: SemanticsIds.deviceRevoke(session.id),
                        onPressed: () => _revoke(context, ref, session),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          AsyncError() => ErrorState(
            title: l10n.settingsDevicesErrorTitle,
            message: l10n.settingsDevicesErrorMessage,
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
      // The server's own sentence: what a device name may be is its
      // rule, and this lands under the field that broke it.
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final empty = _controller.text.trim().isEmpty;
    return AlertDialog(
      title: Text(l10n.settingsDeviceRename),
      content: WaxTextField(
        label: l10n.settingsDeviceNameLabel,
        hint: l10n.settingsDeviceNameHint,
        controller: _controller,
        autofocus: true,
        errorText: _error,
        // Clears the refusal as well as re-running the save gate: the
        // message is about the name that was submitted, and leaving it
        // under a name that has since changed would show "invalid" beside
        // an enabled Save.
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _save(),
      ),
      actions: <Widget>[
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          key: const Key('device-rename-confirm'),
          label: l10n.commonSave,
          onPressed: _busy || empty ? null : _save,
        ),
      ],
    );
  }
}
