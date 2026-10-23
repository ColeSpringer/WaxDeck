import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// What the server says of itself (`GET /health`): its version, its
/// streaming engine, and whether it keeps podcasts.
///
/// One read for every surface that asks, and read again when the server
/// says it moved (the pid-less `server` sync marker): an engine going
/// away or coming back changes what the settings, the console and the
/// shell offer while somebody is looking at them.
final serverHealthProvider = FutureProvider<ServerHealth>(
  (ref) => ref.watch(repositoryProvider).health(),
);

/// The streaming engine as the server last said, null until it has said
/// (or on a server too old to).
final serverStreamingProvider = Provider<ServerStreaming?>(
  (ref) => ref.watch(serverHealthProvider).value?.streaming,
);

/// Whether the server keeps podcasts. True until it says otherwise, so a
/// slow or older server never hides the podcast doors for nothing.
final podcastsOnProvider = Provider<bool>(
  (ref) => ref.watch(serverHealthProvider).value?.podcasts ?? true,
);
