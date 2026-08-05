import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

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
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Request an account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _pending
                ? Semantics(
                    identifier: SemanticsIds.signupResult,
                    child: Column(
                      key: const Key(SemanticsIds.signupResult),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hourglass_top, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Request received',
                          style: textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'An administrator has to approve your account '
                          'before you can sign in.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: () =>
                              context.leave(fallback: WaxRoute.login),
                          child: const Text('Back to sign-in'),
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
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'Choose a username'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          identifier: SemanticsIds.signupPassword,
                          child: TextFormField(
                            key: const Key(SemanticsIds.signupPassword),
                            controller: _password,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                ? 'Choose a password'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('signup-display-name'),
                          controller: _displayName,
                          decoration: const InputDecoration(
                            labelText: 'Display name (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          identifier: SemanticsIds.signupInviteToken,
                          child: TextFormField(
                            key: const Key(SemanticsIds.signupInviteToken),
                            controller: _inviteToken,
                            decoration: const InputDecoration(
                              labelText: 'Invite token (optional)',
                              helperText:
                                  'With a valid invite the account works '
                                  'right away',
                              border: OutlineInputBorder(),
                            ),
                            onFieldSubmitted: (_) => _submit(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[
                          Semantics(
                            identifier: SemanticsIds.signupError,
                            child: Text(
                              _error!,
                              key: const Key(SemanticsIds.signupError),
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
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
                                : const Text('Request account'),
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
