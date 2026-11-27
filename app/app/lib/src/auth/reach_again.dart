import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show Backoff;

import '../providers.dart';
import 'auth_controller.dart';
import 'login_screen.dart' show oidcProvidersProvider;

/// Asks the server again once Riverpod has stopped: while a screen a
/// visitor signs in, sets up or picks a server on watches this, and the
/// session read or the first-run probe failed for want of the server.
///
/// The provider's own retry gives up after about forty seconds, and it
/// stays that way: [retryUnlessRefused] is shared by every read of the app,
/// most of which have screens of their own to ask again, and one that
/// never gave up made everything awaiting it wait with it. These two are
/// the ones a device out of reach is left looking at, so they are asked
/// again here, and only for as long as such a screen shows.
///
/// One request at a time, the first-run probe's (public, and no session
/// read outside the controller), after the ladder's last wait, doubling
/// to a minute. Once the server answers, the reads that failed are made
/// again and the app goes where they say. A refusal is final, as the
/// ladder's is; nothing is asked once an answer landed or someone signed
/// in, and no timer outlives the screen.
final reachAgainProvider = Provider.autoDispose<void>((ref) {
  final wait = Backoff(
    first: const Duration(milliseconds: 6400),
    last: const Duration(minutes: 1),
  );
  Timer? next;
  var asking = false;

  bool lost(AsyncValue<Object?> read) => switch (read) {
    AsyncValue(
      isLoading: false,
      error: WaxDeckApiException(unreachable: true),
    ) =>
      true,
    _ => false,
  };

  bool due() {
    final session = ref.read(authControllerProvider);
    if (lost(session)) return true;
    if (session.value?.authenticated ?? false) return false;
    return lost(ref.read(bootstrapStatusProvider));
  }

  late final void Function() look;

  Future<void> ask() async {
    next = null;
    asking = true;
    var answered = true;
    try {
      await ref.read(apiClientProvider).bootstrapStatus();
    } on WaxDeckApiException catch (error) {
      // A refusal in the server's own words is an answer too.
      answered = !error.unreachable;
    } finally {
      asking = false;
    }
    if (!ref.mounted) return;
    if (!answered) {
      look();
      return;
    }
    // The pace starts over only once the reads made again answer too
    // ([look]): a server that answers this and not them is asked at the
    // growing pace.
    if (lost(ref.read(authControllerProvider))) {
      ref.invalidate(authControllerProvider);
    }
    if (lost(ref.read(bootstrapStatusProvider))) {
      ref.invalidate(bootstrapStatusProvider);
    }
    if (lost(ref.read(oidcProvidersProvider))) {
      ref.invalidate(oidcProvidersProvider);
    }
  }

  look = () {
    if (!due()) {
      next?.cancel();
      next = null;
      // Not while a read is still being made: it can fail again.
      if (!ref.read(authControllerProvider).isLoading &&
          !ref.read(bootstrapStatusProvider).isLoading) {
        wait.reset();
      }
      return;
    }
    if (asking || next != null) return;
    next = Timer(wait.take(), () => unawaited(ask()));
  };

  ref.listen(authControllerProvider, (_, _) => look());
  ref.listen(bootstrapStatusProvider, (_, _) => look());
  ref.onDispose(() => next?.cancel());
  look();
});
