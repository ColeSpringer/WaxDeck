import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/downloads_controller.dart';
import '../providers.dart';
import '../sync/sync_providers.dart';
import 'auth_controller.dart';

/// Forgets this server: the downloads and their files, the mirror, the
/// session, then the address, so nothing is left naming pids another
/// server never minted.
class ForgetServer {
  const ForgetServer(this._ref);

  final Ref _ref;

  Future<void> call() async {
    // Read afresh: removal walks the listing it holds, which a download
    // started since it was built is missing from.
    _ref.invalidate(downloadsProvider);
    await _ref.read(downloadsProvider.future);
    await _ref.read(downloadsProvider.notifier).removeAll();
    // Before the wipe: the covers are found through the pin records.
    await _ref.read(authControllerProvider.notifier).signOutLocally();
    await _ref.read(mirrorDatabaseProvider)?.wipe();
    await _ref.read(serverAddressProvider.notifier).forget();
  }
}

final forgetServerProvider = Provider<ForgetServer>(ForgetServer.new);
