import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../player/now_playing_controller.dart';
import '../providers.dart';

/// The summary behind one queued pid.
///
/// Playback already holds a summary for everything it has been handed or
/// has played, which is most of a queue and all of one built from a list
/// on screen; this asks the server only for the rest (a queue handed
/// over by another device, one restored at launch). Family-scoped and
/// auto-disposing, so a queue of five hundred resolves the rows a
/// visitor actually looks at rather than all of them.
final queueItemProvider = FutureProvider.autoDispose
    .family<ItemSummary, String>((ref, pid) async {
      final known = ref.read(nowPlayingProvider.notifier).summaryFor(pid);
      if (known != null) return known;
      return ref.watch(repositoryProvider).getItem(pid);
    });
