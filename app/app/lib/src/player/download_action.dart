import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../downloads/download_state.dart';
import '../l10n/l10n.dart';

/// [state] as an entity bar's download pill, or null where this build has
/// no download manager (web), so the caller leaves it out of the bar.
///
/// [label] is the caller's own word for the ready pill; a book says what
/// it is downloading.
WaxAction? downloadWaxAction(
  AppLocalizations l10n,
  DownloadState state, {
  required String label,
  required String semanticsId,
  required VoidCallback onStart,
}) => switch (state) {
  DownloadUnavailable() => null,
  // The device has not answered yet: the pill's place, with no press and
  // no state to take back.
  DownloadChecking() => WaxAction(
    label: label,
    semanticsId: semanticsId,
    glyph: WaxIcons.downloads,
    state: const WaxActionState.status(),
  ),
  DownloadIdle() => WaxAction(
    label: label,
    semanticsId: semanticsId,
    glyph: WaxIcons.downloads,
    onPressed: onStart,
  ),
  // Held, not stalled: nothing moves until the device is on wifi.
  DownloadTransferring(held: true) => WaxAction(
    label: l10n.downloadsActionHeld,
    semanticsId: semanticsId,
    glyph: WaxIcons.downloads,
    state: const WaxActionState.status(),
    detail: l10n.downloadsHeldForWifi,
  ),
  // The pill speaks its share as its value, so the name stays put.
  DownloadTransferring(:final fraction) => WaxAction(
    label: l10n.downloadsActionDownloading(_percent(fraction)),
    spokenLabel: l10n.downloadsDownloading,
    semanticsId: semanticsId,
    glyph: WaxIcons.downloads,
    state: WaxActionState.progress(fraction),
    onPressed: onStart,
  ),
  DownloadDone() => WaxAction(
    label: l10n.downloadsDownloaded,
    semanticsId: semanticsId,
    glyph: WaxIcons.downloads,
    state: const WaxActionState.done(),
  ),
  DownloadFailed() => WaxAction(
    label: l10n.downloadsActionRetry,
    semanticsId: semanticsId,
    glyph: WaxIcons.downloads,
    state: const WaxActionState.failed(),
    detail: _why(l10n, state),
    onPressed: onStart,
  ),
};

/// Why [failed] gave up, in one sentence: what the request threw, else
/// the manager's reason.
String _why(AppLocalizations l10n, DownloadFailed failed) =>
    switch (failed.cause) {
      final cause? => explainError(l10n, cause),
      null => switch (failed.reason) {
        DownloadFailure.gone => l10n.downloadsFailedGone,
        DownloadFailure.refused => l10n.downloadsFailedRefused,
        DownloadFailure.interrupted => l10n.downloadsFailedInterrupted,
      },
    };

int _percent(double fraction) =>
    fraction.isFinite ? (fraction.clamp(0.0, 1.0) * 100).round() : 0;

/// One item's download as an icon, for a header of icons such as the
/// player's. Draws nothing where this build has no download manager
/// (web), which is what makes it safe to place unconditionally.
class DownloadAction extends ConsumerWidget {
  const DownloadAction({
    required this.pid,
    required this.semanticsId,
    required this.label,
    this.artUrl,
    super.key,
  });

  final String pid;

  /// The cover to pin beside the audio, when the item has one.
  final String? artUrl;

  final String semanticsId;

  /// What the control is called before anything is on disk. Required,
  /// because a defaulted sentence is one language every caller who
  /// forgets it draws in all of them.
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    void start() => unawaited(
      ref.read(downloadStateProvider(pid).notifier).start(artUrl: artUrl),
    );
    return switch (ref.watch(downloadStateProvider(pid))) {
      DownloadUnavailable() => const SizedBox.shrink(),
      DownloadChecking() => WaxIconButton(
        glyph: WaxIcons.downloads,
        label: label,
        semanticsId: semanticsId,
        status: true,
        onPressed: null,
      ),
      DownloadIdle() => WaxIconButton(
        glyph: WaxIcons.downloads,
        label: label,
        semanticsId: semanticsId,
        onPressed: start,
      ),
      DownloadTransferring(held: true) => WaxIconButton(
        glyph: WaxIcons.downloads,
        label: l10n.downloadsActionHeld,
        detail: l10n.downloadsHeldForWifi,
        semanticsId: semanticsId,
        status: true,
        onPressed: null,
      ),
      // Busy rather than a null callback: working, not unavailable.
      DownloadTransferring() => WaxIconButton(
        glyph: WaxIcons.downloads,
        label: l10n.downloadsDownloading,
        semanticsId: semanticsId,
        busy: true,
        onPressed: start,
      ),
      DownloadDone() => WaxIconButton(
        glyph: WaxIcons.success,
        label: l10n.downloadsDownloaded,
        semanticsId: semanticsId,
        active: true,
        status: true,
        onPressed: null,
      ),
      final DownloadFailed failed => WaxIconButton(
        glyph: WaxIcons.warning,
        label: l10n.downloadsActionRetry,
        detail: _why(l10n, failed),
        semanticsId: semanticsId,
        onPressed: start,
      ),
    };
  }
}
