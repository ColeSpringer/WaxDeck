import 'dart:async';

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
    final l10n = context.l10n;
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
        _error = _signInError(l10n, e, l10n.authSignInRejected);
      });
    }
  }

  /// `explainRefusal`, except for `unauthenticated`: the table tells a
  /// reader to sign in again, which is what just failed, and the server
  /// answers a log line. [rejected] is what this half of the form says.
  static String _signInError(
    AppLocalizations l10n,
    Object error,
    String rejected,
  ) {
    if (error is WaxDeckApiException && error.code == 'unauthenticated') {
      return rejected;
    }
    return explainRefusal(l10n, error);
  }

  Future<void> _oidcSubmit(OidcProvider provider) async {
    final l10n = context.l10n;
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
        _error = _signInError(l10n, e, l10n.authSsoFailed);
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = l10n.authTimedOut;
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
    final l10n = context.l10n;
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
                  // The mark, not the name set as a heading: this is the
                  // first screen an account ever sees, and the one place
                  // the identity is the whole content.
                  WaxBrandBlock(tagline: l10n.authTagline),
                  const SizedBox(height: WaxSpace.s32),
                  Semantics(
                    identifier: SemanticsIds.loginUsername,
                    child: TextFormField(
                      key: const Key(SemanticsIds.loginUsername),
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
                    identifier: SemanticsIds.loginPassword,
                    child: TextFormField(
                      key: const Key(SemanticsIds.loginPassword),
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: l10n.authPassword,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? l10n.authEnterPassword
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
                          : Text(l10n.authLogIn),
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
                            ? l10n.authRequestAccount
                            : l10n.authHaveInvite,
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
                            l10n.authOr,
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
                          label: Text(
                            l10n.authContinueWith(provider.displayName),
                          ),
                        ),
                      ),
                    ],
                  ],
                  // Which server this form signs into, native only: the
                  // web build is served by its own server and has no
                  // other one to name.
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
