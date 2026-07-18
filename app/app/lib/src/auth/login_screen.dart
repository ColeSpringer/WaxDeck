import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'auth_controller.dart';

/// Username and password form. On success the auth controller flips to
/// authenticated and the root gate swaps this screen for the library.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(username: _username.text, password: _password.text);
      // On success the root gate unmounts this screen; nothing else to do.
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'WaxDeck',
                    style: textTheme.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Music, podcasts, and audiobooks',
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Semantics(
                    identifier: 'login-username',
                    child: TextFormField(
                      key: const Key('login-username'),
                      controller: _username,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Enter a username'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    identifier: 'login-password',
                    child: TextFormField(
                      key: const Key('login-password'),
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Enter a password'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      key: const Key('login-error'),
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Semantics(
                    identifier: 'login-submit',
                    child: FilledButton(
                      key: const Key('login-submit'),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Log in'),
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
