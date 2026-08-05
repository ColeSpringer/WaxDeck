import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

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
                    'Welcome to WaxDeck',
                    style: textTheme.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create the first administrator account',
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Semantics(
                    identifier: SemanticsIds.setupUsername,
                    child: TextFormField(
                      key: const Key(SemanticsIds.setupUsername),
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
                    identifier: SemanticsIds.setupPassword,
                    child: TextFormField(
                      key: const Key(SemanticsIds.setupPassword),
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value == null || value.length < 8)
                          ? 'Use at least 8 characters'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    identifier: SemanticsIds.setupConfirm,
                    child: TextFormField(
                      key: const Key(SemanticsIds.setupConfirm),
                      controller: _confirm,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value != _password.text)
                          ? 'Passwords do not match'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    identifier: SemanticsIds.setupDisplayName,
                    child: TextFormField(
                      key: const Key(SemanticsIds.setupDisplayName),
                      controller: _displayName,
                      decoration: const InputDecoration(
                        labelText: 'Display name (optional)',
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Semantics(
                      identifier: SemanticsIds.setupError,
                      child: Text(
                        _error!,
                        key: const Key(SemanticsIds.setupError),
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                          : const Text('Create account'),
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
