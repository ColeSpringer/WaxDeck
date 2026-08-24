import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'server_address.dart';

/// The pre-login server-address screen, native only: the web build is
/// served by the server it talks to and never sees it. Its own screen
/// rather than a login field, because the login screen fires pre-auth
/// probes the moment it mounts, which would race the typing here.
class ConnectServerScreen extends ConsumerStatefulWidget {
  const ConnectServerScreen({super.key});

  @override
  ConsumerState<ConnectServerScreen> createState() =>
      _ConnectServerScreenState();
}

class _ConnectServerScreenState extends ConsumerState<ConnectServerScreen> {
  final _address = TextEditingController();
  bool _probing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _address.text = ref.read(serverAddressProvider) ?? '';
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    // The button disables itself, but the text field's submit does not:
    // a second ladder racing the first would adopt whichever candidate
    // answered last.
    if (_probing) return;
    final l10n = context.l10n;
    final candidates = serverAddressCandidates(_address.text);
    if (candidates.isEmpty) {
      setState(() => _error = l10n.authServerInvalid);
      return;
    }
    setState(() {
      _probing = true;
      _error = null;
    });
    final probe = ref.read(serverProbeProvider);
    try {
      for (final candidate in candidates) {
        try {
          await probe(candidate);
        } on Exception {
          // Any failure reads as "not this candidate": the transport
          // wraps what it recognizes into WaxDeckApiException, and
          // whatever escapes the wrapping is the same answer. Narrower
          // than this and an odd throw leaves the screen spinning with
          // the whole app pinned behind it.
          continue;
        }
        if (!mounted) return;
        await ref.read(serverAddressProvider.notifier).adopt(candidate);
        if (!mounted) return;
        // Adopting clears any stored token, so sign-in is what comes next.
        context.go(WaxRoute.login);
        return;
      }
      if (!mounted) return;
      setState(() => _error = l10n.authServerUnreachable);
    } finally {
      // On every path, success included: a failed adopt or an escape
      // from above must not leave the one affordance on this screen
      // disabled forever.
      if (mounted) setState(() => _probing = false);
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WaxBrandBlock(tagline: l10n.authServerConnectTagline),
                const SizedBox(height: WaxSpace.s32),
                Semantics(
                  identifier: SemanticsIds.connectServerAddress,
                  child: TextField(
                    key: const Key(SemanticsIds.connectServerAddress),
                    controller: _address,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l10n.authServerAddressLabel,
                      hintText: l10n.authServerAddressHint,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                ),
                const SizedBox(height: WaxSpace.s24),
                if (_error != null) ...[
                  Semantics(
                    identifier: SemanticsIds.connectServerError,
                    child: Text(
                      _error!,
                      key: const Key(SemanticsIds.connectServerError),
                      style: WaxType.body.copyWith(color: colors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s16),
                ],
                Semantics(
                  identifier: SemanticsIds.connectServerSubmit,
                  child: FilledButton(
                    key: const Key(SemanticsIds.connectServerSubmit),
                    onPressed: _probing ? null : _connect,
                    child: _probing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.authServerConnect),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
