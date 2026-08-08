import 'dart:async';

import 'package:waxdeck_ui/waxdeck_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'auth_controller.dart';

/// Configured single-sign-on providers, for rendering login buttons. An
/// unreachable server hides the buttons rather than erroring the form.
final oidcProvidersProvider = FutureProvider<List<OidcProvider>>(
  (ref) => ref.watch(repositoryProvider).oidcProviders(),
);

/// Username and password form, plus one button per configured SSO
/// provider. On success the auth controller flips to authenticated and
/// the root gate swaps this screen for the library.
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

  Future<void> _oidcSubmit(OidcProvider provider) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).loginWithOidc(provider);
      // Web: the browser is navigating away, keep the spinner. Native: on
      // success the root gate unmounts this screen.
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Sign-in timed out; try again';
      });
    }
  }

  Future<void> _openSignup() async {
    final username = await context.push<String>(WaxRoute.signup);
    if (username == null || !mounted) return;
    // The account is active already; prefill so signing in is one step.
    setState(() => _username.text = username);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final oidcProviders =
        ref.watch(oidcProvidersProvider).value ?? const <OidcProvider>[];
    final signupEnabled = ref.watch(signupEnabledProvider).value ?? false;
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
                  Text(
                    'WaxDeck',
                    style: WaxType.titleScreen.copyWith(
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: WaxSpace.s8),
                  Text(
                    'Music, podcasts, and audiobooks',
                    style: WaxType.body.copyWith(color: colors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: WaxSpace.s32),
                  Semantics(
                    identifier: SemanticsIds.loginUsername,
                    child: TextFormField(
                      key: const Key(SemanticsIds.loginUsername),
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
                  const SizedBox(height: WaxSpace.s16),
                  Semantics(
                    identifier: SemanticsIds.loginPassword,
                    child: TextFormField(
                      key: const Key(SemanticsIds.loginPassword),
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
                  const SizedBox(height: WaxSpace.s24),
                  if (_error != null) ...[
                    Semantics(
                      identifier: SemanticsIds.loginError,
                      child: Text(
                        _error!,
                        key: const Key(SemanticsIds.loginError),
                        style: WaxType.body.copyWith(color: colors.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: WaxSpace.s16),
                  ],
                  Semantics(
                    identifier: SemanticsIds.loginSubmit,
                    child: FilledButton(
                      key: const Key(SemanticsIds.loginSubmit),
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
                  const SizedBox(height: WaxSpace.s12),
                  // Open signup gets the louder wording; without it the
                  // link still serves people holding an invite token.
                  Semantics(
                    identifier: SemanticsIds.signupOpen,
                    child: TextButton(
                      key: const Key(SemanticsIds.signupOpen),
                      onPressed: _submitting ? null : _openSignup,
                      child: Text(
                        signupEnabled
                            ? 'Request an account'
                            : 'Have an invite?',
                      ),
                    ),
                  ),
                  if (oidcProviders.isNotEmpty) ...[
                    const SizedBox(height: WaxSpace.s24),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: WaxSpace.s12,
                          ),
                          child: Text(
                            'or',
                            style: WaxType.bodySmall.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    for (final provider in oidcProviders) ...[
                      const SizedBox(height: WaxSpace.s16),
                      Semantics(
                        identifier: SemanticsIds.oidcLogin(provider.id),
                        child: OutlinedButton.icon(
                          key: Key(SemanticsIds.oidcLogin(provider.id)),
                          onPressed: _submitting
                              ? null
                              : () => _oidcSubmit(provider),
                          icon: const WaxIcon(WaxIcons.signIn),
                          label: Text('Continue with ${provider.displayName}'),
                        ),
                      ),
                    ],
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
