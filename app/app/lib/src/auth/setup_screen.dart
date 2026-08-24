import 'package:flutter/foundation.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'auth_controller.dart';

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
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final displayName = _displayName.text.trim();
      await ref
          .read(authControllerProvider.notifier)
          .bootstrap(
            username: _username.text.trim(),
            password: _password.text,
            displayName: displayName.isEmpty ? null : displayName,
          );
      // On success the root gate unmounts this screen; nothing else to do.
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // A refusal of what was just typed keeps the server's words.
        _error = explainRefusal(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Scaffold(
      body: Center(
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
                  Semantics(
                    identifier: SemanticsIds.setupUsername,
                    child: TextFormField(
                      key: const Key(SemanticsIds.setupUsername),
                      controller: _username,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: l10n.authUsername,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? l10n.authEnterUsername
                          : null,
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s16),
                  Semantics(
                    identifier: SemanticsIds.setupPassword,
                    child: TextFormField(
                      key: const Key(SemanticsIds.setupPassword),
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: l10n.authPassword,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => (value == null || value.length < 8)
                          ? l10n.authPasswordTooShort
                          : null,
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s16),
                  Semantics(
                    identifier: SemanticsIds.setupConfirm,
                    child: TextFormField(
                      key: const Key(SemanticsIds.setupConfirm),
                      controller: _confirm,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.authConfirmPassword,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => (value != _password.text)
                          ? l10n.authPasswordsDiffer
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s16),
                  Semantics(
                    identifier: SemanticsIds.setupDisplayName,
                    child: TextFormField(
                      key: const Key(SemanticsIds.setupDisplayName),
                      controller: _displayName,
                      decoration: InputDecoration(
                        labelText: l10n.authDisplayName,
                        border: const OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (_) => _submit(),
                    ),
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
                  Semantics(
                    identifier: SemanticsIds.setupSubmit,
                    child: FilledButton(
                      key: const Key(SemanticsIds.setupSubmit),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.authCreateAccount),
                    ),
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
                    Semantics(
                      identifier: SemanticsIds.connectServerOpen,
                      child: TextButton(
                        key: const Key(SemanticsIds.connectServerOpen),
                        onPressed: _submitting
                            ? null
                            : () => context.go(WaxRoute.serverConnect),
                        child: Text(l10n.authChangeServer),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
