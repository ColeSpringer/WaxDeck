import '../oidc_flow.dart';

/// Web build: no localhost listener exists; web logins use cookie mode.
const Future<LoopbackReceiverPort> Function()? bindLoopbackReceiver = null;
