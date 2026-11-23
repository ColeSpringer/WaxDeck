import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../artwork/artwork_providers.dart';
import '../providers.dart';
import '../queue/queue_persistence.dart';
import '../sync/sync_providers.dart';
import 'downloads_controller.dart';

/// Has the artwork store pin the cover of every complete download the
/// device holds, at each size it lacks, for a server just come into
/// reach. A sign-out drops every pin and keeps the audio, and a
/// download's own start is the only other thing that pins its cover.
///
/// Every held item is named, whoever downloaded it, as the sync engine
/// names every one to the server: the art endpoint answers what the
/// signed-in account may see, and no cover for an item it may not.
Future<void> pinHeldCovers(ProviderContainer container) async {
  final port = container.read(downloadManagerProvider);
  if (port == null) return;
  final store = container.read(artworkStoreProvider);
  final artUrlFor = container.read(repositoryProvider).artUrlFor;
  final List<DownloadedItem> held;
  try {
    held = await port.stored();
  } on Object {
    // The next reach asks again.
    return;
  }
  store.pinHeld({
    for (final item in held)
      if (item.complete) item.pid: artUrlFor(item.pid),
  }, landed: (pid) => _coverPinned(container, pid));
}

/// What drew [pid] with no cover because none was pinned reads it again.
void _coverPinned(ProviderContainer container, String pid) {
  container.read(_heldRedrawProvider).landed();
  if (container.exists(queueRestoreProvider)) {
    unawaited(container.read(queueRestoreProvider.notifier).coverPinned(pid));
  }
}

final _heldRedrawProvider = Provider<_HeldRedraw>((ref) {
  final redraw = _HeldRedraw(() => ref.invalidate(downloadsProvider));
  ref.onDispose(redraw.dispose);
  return redraw;
});

/// Rebuilds the Downloads list for covers pinned in a run. A rebuild
/// reads every row, so one per cover is a read of them all per cover:
/// the first cover rebuilds it at once, and while more keep landing it
/// is rebuilt after a gap that doubles up to [most], so each row draws
/// its cover while the run goes on and hundreds cost a handful of
/// rebuilds.
class _HeldRedraw {
  _HeldRedraw(this._redraw);

  static const Duration least = Duration(seconds: 1);
  static const Duration most = Duration(seconds: 16);

  final void Function() _redraw;
  Duration _gap = least;
  Timer? _resting;

  /// A cover landed during the rest.
  bool _more = false;

  void landed() {
    if (_resting != null) {
      _more = true;
      return;
    }
    _redraw();
    _resting = Timer(_gap, () {
      _resting = null;
      if (!_more) {
        // The run paused: the next cover is the first of another.
        _gap = least;
        return;
      }
      _more = false;
      _gap = _gap * 2 < most ? _gap * 2 : most;
      landed();
    });
  }

  void dispose() => _resting?.cancel();
}
