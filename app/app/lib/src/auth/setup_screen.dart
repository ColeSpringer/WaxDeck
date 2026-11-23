import 'package:flutter/foundation.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/asked_from.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'auth_controller.dart';
import 'reach_again.dart';

/// First-run setup: creates the server's first administrator. Shown by the
/// root gate instead of the login form while the server has no accounts;
/// on success the auth controller flips to authenticated and the gate
/// swaps in the library.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _displayName = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final from = AskedFrom.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final displayName = _displayName.text.trim();
      final shown = await ref
          .read(authControllerProvider.notifier)
          .bootstrap(
            username: _username.text.trim(),
            password: _password.text,
            displayName: displayName.isEmpty ? null : displayName,
          );
      // On success the root gate unmounts this screen. Overtaken before it
      // showed, the form is as it was before the press: whatever came
      // instead may have left nobody signed in.
      if (!shown && mounted) setState(() => _submitting = false);
    } on WaxDeckApiException catch (e) {
      // A refusal of what was just typed keeps the server's words: under
      // the form while this page is still there, else through the shell.
      from.refused(
        explainRefusal(l10n, e),
        inline: (refusal) => setState(() {
          _submitting = false;
          _error = refusal;
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reachAgainProvider);
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return ShellMessageArea(
      child: Scaffold(
        body: WaxPlainTextStyle(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(WaxSpace.s24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const WaxBrandBlock(),
                      const SizedBox(height: WaxSpace.s16),
                      Text(
                        l10n.authFirstAdmin,
                        style: WaxType.body.copyWith(color: colors.textPrimary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: WaxSpace.s32),
                      WaxTextField(
                        semanticsId: SemanticsIds.setupUsername,
                        controller: _username,
                        label: l10n.authUsername,
                        autofillHints: const [AutofillHints.username],
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? l10n.authEnterUsername
                            : null,
                      ),
                      const SizedBox(height: WaxSpace.s16),
                      WaxTextField(
                        semanticsId: SemanticsIds.setupPassword,
                        controller: _password,
                        label: l10n.authPassword,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        validator: (value) =>
                            (value == null || value.length < 8)
                            ? l10n.authPasswordTooShort
                            : null,
                      ),
                      const SizedBox(height: WaxSpace.s16),
                      WaxTextField(
                        semanticsId: SemanticsIds.setupConfirm,
                        controller: _confirm,
                        label: l10n.authConfirmPassword,
                        obscureText: true,
                        validator: (value) => (value != _password.text)
                            ? l10n.authPasswordsDiffer
                            : null,
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: WaxSpace.s16),
                      WaxTextField(
                        semanticsId: SemanticsIds.setupDisplayName,
                        controller: _displayName,
                        label: l10n.authDisplayName,
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: WaxSpace.s24),
                      if (_error != null) ...[
                        Semantics(
                          identifier: SemanticsIds.setupError,
                          child: Text(
                            _error!,
                            key: const Key(SemanticsIds.setupError),
                            style: WaxType.body.copyWith(color: colors.error),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: WaxSpace.s16),
                      ],
                      WaxButton(
                        semanticsId: SemanticsIds.setupSubmit,
                        label: l10n.authCreateAccount,
                        expand: true,
                        busy: _submitting,
                        onPressed: _submitting ? null : _submit,
                      ),
                      // Which server this form would administer, native
                      // only, with the way back out. A typo'd address that
                      // reaches somebody's fresh install lands here, and
                      // without this the only exits are creating an admin
                      // account on the wrong server or clearing app data.
                      if (!kIsWeb) ...[
                        const SizedBox(height: WaxSpace.s24),
                        Text(
                          ref.watch(serverAddressProvider) ?? '',
                          style: WaxType.bodySmall.copyWith(
                            color: colors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        WaxButton(
                          semanticsId: SemanticsIds.connectServerOpen,
                          label: l10n.authChangeServer,
                          kind: WaxButtonKind.text,
                          expand: true,
                          onPressed: _submitting
                              ? null
                              : () => context.pushOnce(WaxRoute.serverConnect),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
