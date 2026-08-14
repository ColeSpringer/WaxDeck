import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// Requests an account: open signup queues the request for an
/// administrator, an invite token activates it immediately. Pops the
/// username when the account is active so the login form can prefill.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _inviteToken = TextEditingController();
  var _submitting = false;
  var _pending = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    _inviteToken.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final router = GoRouter.of(context);
    final displayName = _displayName.text.trim();
    final inviteToken = _inviteToken.text.trim();
    try {
      final result = await ref
          .read(repositoryProvider)
          .signup(
            username: _username.text.trim(),
            password: _password.text,
            displayName: displayName.isEmpty ? null : displayName,
            inviteToken: inviteToken.isEmpty ? null : inviteToken,
          );
      if (!mounted) return;
      if (result.pending) {
        setState(() {
          _submitting = false;
          _pending = true;
        });
      } else {
        // Active right away: back to the login form, prefilled.
        router.leave(fallback: WaxRoute.login, result: _username.text.trim());
      }
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
      appBar: AppBar(title: Text(l10n.authRequestAccount)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(WaxSpace.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _pending
                ? Semantics(
                    identifier: SemanticsIds.signupResult,
                    child: Column(
                      key: const Key(SemanticsIds.signupResult),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const WaxIcon(WaxIcons.hourglass, size: 48),
                        const SizedBox(height: WaxSpace.s16),
                        Text(
                          l10n.authRequestReceived,
                          style: WaxType.titleEntity.copyWith(
                            color: colors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: WaxSpace.s8),
                        Text(
                          l10n.authRequestPending,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: WaxSpace.s24),
                        OutlinedButton(
                          onPressed: () =>
                              context.leave(fallback: WaxRoute.login),
                          child: Text(l10n.authBackToSignIn),
                        ),
                      ],
                    ),
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          identifier: SemanticsIds.signupUsername,
                          child: TextFormField(
                            key: const Key(SemanticsIds.signupUsername),
                            controller: _username,
                            autofillHints: const [AutofillHints.newUsername],
                            decoration: InputDecoration(
                              labelText: l10n.authUsername,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? l10n.authChooseUsername
                                : null,
                          ),
                        ),
                        const SizedBox(height: WaxSpace.s16),
                        Semantics(
                          identifier: SemanticsIds.signupPassword,
                          child: TextFormField(
                            key: const Key(SemanticsIds.signupPassword),
                            controller: _password,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: l10n.authPassword,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                ? l10n.authChoosePassword
                                : null,
                          ),
                        ),
                        const SizedBox(height: WaxSpace.s16),
                        TextFormField(
                          key: const Key('signup-display-name'),
                          controller: _displayName,
                          decoration: InputDecoration(
                            labelText: l10n.authDisplayName,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: WaxSpace.s16),
                        Semantics(
                          identifier: SemanticsIds.signupInviteToken,
                          child: TextFormField(
                            key: const Key(SemanticsIds.signupInviteToken),
                            controller: _inviteToken,
                            decoration: InputDecoration(
                              labelText: l10n.authInviteToken,
                              helperText: l10n.authInviteHelp,
                              border: const OutlineInputBorder(),
                            ),
                            onFieldSubmitted: (_) => _submit(),
                          ),
                        ),
                        const SizedBox(height: WaxSpace.s24),
                        if (_error != null) ...[
                          Semantics(
                            identifier: SemanticsIds.signupError,
                            child: Text(
                              _error!,
                              key: const Key(SemanticsIds.signupError),
                              style: WaxType.body.copyWith(color: colors.error),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: WaxSpace.s16),
                        ],
                        Semantics(
                          identifier: SemanticsIds.signupSubmit,
                          child: FilledButton(
                            key: const Key(SemanticsIds.signupSubmit),
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(l10n.authRequestSubmit),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
