import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/server_event_bus.dart';
import 'auth_controller.dart';

/// Keeps the session view current while somebody is signed in.
///
/// An administrator can grant a role, lift the upload gate or widen a
/// library grant while the account it belongs to has the app open. The
/// server says so with a pid-less `account` marker; this re-reads
/// `/auth/session`, which is what every rights gate in the app watches,
/// so Server settings appear and an upload button lights up without a
/// relaunch.
final accountBinderProvider = Provider.autoDispose<void>((ref) {
  final subscription = ref.watch(serverEventBusProvider).events.listen((event) {
    if (event.kind != 'account') return;
    // Read, not watch: this fires from a stream, and watching the
    // controller here would rebuild the binder on the very refresh it
    // just asked for. Nothing waits on the read - the gates watch the
    // session, so they follow when it settles.
    unawaited(ref.read(authControllerProvider.notifier).refreshSession());
  });
  ref.onDispose(subscription.cancel);
});
