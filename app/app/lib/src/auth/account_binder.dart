import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/server_event_bus.dart';
import 'auth_controller.dart';

/// Keeps the session view current while somebody is signed in.
///
/// An administrator can grant a role, lift the upload gate or widen a
/// library grant while the account it belongs to has the app open, and
/// can turn the server's read-only mode on or off. The server says so with
/// a pid-less `account` marker; this re-reads `/auth/session`, which is
/// what every rights gate and the read-only banner in the app watch, so
/// Server settings appear and an upload button lights up without a
/// relaunch.
///
/// A walk of the event stream that loses its place (the change log was
/// pruned, a restore replaced it) drops markers without saying which, so
/// that re-reads the session as well.
final accountBinderProvider = Provider.autoDispose<void>((ref) {
  final bus = ref.watch(serverEventBusProvider);
  // Read, not watch: this fires from a stream, and watching the
  // controller here would rebuild the binder on the very refresh it
  // just asked for. Nothing waits on the read - the gates watch the
  // session, so they follow when it settles.
  void reread() =>
      unawaited(ref.read(authControllerProvider.notifier).refreshSession());
  final events = bus.events.listen((event) {
    if (event.kind == 'account') reread();
  });
  final resets = bus.resets.listen((_) => reread());
  ref.onDispose(events.cancel);
  ref.onDispose(resets.cancel);
});
