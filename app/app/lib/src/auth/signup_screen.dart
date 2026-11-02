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
    // Built here, once a build, and handed to the layout builder below,
    // which runs on every scroll frame: a widget it is handed whole is
    // not built again.
    final body = Padding(
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
                    Text(l10n.authRequestPending, textAlign: TextAlign.center),
                    const SizedBox(height: WaxSpace.s24),
                    WaxButton(
                      label: l10n.authBackToSignIn,
                      kind: WaxButtonKind.tonal,
                      onPressed: () => context.leave(fallback: WaxRoute.login),
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
                    WaxTextField(
                      semanticsId: SemanticsIds.signupUsername,
                      controller: _username,
                      label: l10n.authUsername,
                      autofillHints: const [AutofillHints.newUsername],
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? l10n.authChooseUsername
                          : null,
                    ),
                    const SizedBox(height: WaxSpace.s16),
                    WaxTextField(
                      semanticsId: SemanticsIds.signupPassword,
                      controller: _password,
                      label: l10n.authPassword,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: (value) => (value == null || value.isEmpty)
                          ? l10n.authChoosePassword
                          : null,
                    ),
                    const SizedBox(height: WaxSpace.s16),
                    WaxTextField(
                      key: const Key('signup-display-name'),
                      controller: _displayName,
                      label: l10n.authDisplayName,
                    ),
                    const SizedBox(height: WaxSpace.s16),
                    WaxTextField(
                      semanticsId: SemanticsIds.signupInviteToken,
                      controller: _inviteToken,
                      label: l10n.authInviteToken,
                      helperText: l10n.authInviteHelp,
                      onSubmitted: (_) => _submit(),
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
                    WaxButton(
                      semanticsId: SemanticsIds.signupSubmit,
                      label: l10n.authRequestSubmit,
                      expand: true,
                      busy: _submitting,
                      onPressed: _submitting ? null : _submit,
                    ),
                  ],
                ),
              ),
      ),
    );
    return WaxScaffold(
      title: l10n.authRequestAccount,
      largeTitle: false,
      onBack: () => context.leave(fallback: WaxRoute.login),
      // Centred in what the bar leaves, as the sign-in form it came from
      // is, and scrolling once a short window cannot hold it. Measured
      // off the viewport rather than SliverFillRemaining's intrinsic
      // height, which asks the form at the page's width, not its own
      // narrower one, and so comes up short where a line wraps.
      slivers: <Widget>[
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    constraints.viewportMainAxisExtent -
                    constraints.precedingScrollExtent,
              ),
              child: Center(child: body),
            ),
          ),
        ),
      ],
    );
  }
}
