import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../sync/sync_providers.dart';

/// Downloads one item's original for offline playback, and pins its cover
/// beside it.
///
/// Hidden on platforms with no download manager (web), which is what
/// makes it safe to place unconditionally: a screen adds it and the
/// control decides whether this build has anything to offer.
///
/// The two calls are the point. Downloading an item is a promise that it
/// plays with the server unreachable, and an offline library of grey
/// monograms does not keep it - so the cover comes down with the audio.
/// Removal is the same pair from the other side, which is
/// the downloads manager's job.
class DownloadAction extends ConsumerStatefulWidget {
  const DownloadAction({
    required this.pid,
    required this.semanticsId,
    this.artUrl,
    this.label = 'Download',
    super.key,
  });

  final String pid;

  /// The cover to pin beside the audio, when the item has one.
  final String? artUrl;

  final String semanticsId;

  /// What the control is called before anything is on disk. "Download"
  /// on a track; a book says what it is downloading.
  final String label;

  @override
  ConsumerState<DownloadAction> createState() => _DownloadActionState();
}

class _DownloadActionState extends ConsumerState<DownloadAction> {
  bool? _complete;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void didUpdateWidget(DownloadAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pid != widget.pid) {
      _complete = null;
      _probe();
    }
  }

  Future<void> _probe() async {
    final port = ref.read(downloadManagerProvider);
    if (port == null) return;
    final complete = await port.isComplete(widget.pid);
    if (mounted) setState(() => _complete = complete);
  }

  Future<void> _download() async {
    final port = ref.read(downloadManagerProvider);
    if (port == null) return;
    setState(() => _inFlight = true);
    try {
      // Listen before enqueuing so a fast completion cannot slip past,
      // and stop on failure too; waiting on the complete event alone
      // would spin forever when a file fails.
      final done = Completer<void>();
      final sub = port.progress.listen((p) {
        if (p.pid == widget.pid &&
            (p.complete || p.failed) &&
            !done.isCompleted) {
          done.complete();
        }
      });
      try {
        await port.download(widget.pid);
        // Everything may already be on disk (an early tap before the
        // probe landed, or a server-side retag): nothing was enqueued,
        // so no event will ever come.
        if (!await port.isComplete(widget.pid)) {
          await done.future;
        }
      } finally {
        await sub.cancel();
      }
      // Only once the audio is actually on disk: the wait above ends on
      // a failed transfer too, and a pinned cover for an item that
      // cannot play is a promise about nothing.
      if (await port.isComplete(widget.pid)) {
        await ref
            .read(artworkStoreProvider)
            .pinForOffline(widget.pid, widget.artUrl);
      }
    } finally {
      if (mounted) setState(() => _inFlight = false);
      await _probe();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(downloadManagerProvider) == null) {
      return const SizedBox.shrink();
    }
    final complete = _complete ?? false;
    return WaxIconButton(
      // One glyph in three states, told apart by fill and tint rather
      // than by a second icon: the filled tick is on disk, the outline
      // arrow is not yet, and a transfer in flight is the arrow with the
      // control refusing a second tap.
      glyph: complete ? WaxIcons.success : WaxIcons.downloads,
      label: switch ((complete, _inFlight)) {
        (true, _) => context.l10n.downloadsDownloaded,
        (false, true) => context.l10n.downloadsDownloading,
        (false, false) => widget.label,
      },
      active: complete,
      semanticsId: widget.semanticsId,
      onPressed: complete || _inFlight ? null : _download,
    );
  }
}
