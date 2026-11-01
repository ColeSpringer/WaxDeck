import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop/desktop_ports.dart';
import '../desktop/desktop_ports_io.dart'
    if (dart.library.js_interop) '../desktop/desktop_ports_stub.dart';
import '../l10n/l10n.dart';
import '../l10n/off_tree.dart';
import '../player/now_playing_slot.dart';
import '../providers.dart';

final windowTitlePortProvider = Provider<WindowTitlePort>(
  (ref) => createWindowTitlePort(desktop: ref.watch(desktopProvider)),
);

// brand, not copy
const String _appTitle = 'WaxDeck';

/// What the tab or title bar names for [slot], or null for the app's own
/// title. A paused item keeps its title: the deck still names it. An item
/// whose summary has not arrived has none yet; [windowTitleBinderProvider]
/// holds the previous one across that gap.
String? windowTitleOf({
  required NowPlayingSlot slot,
  required AppLocalizations copy,
}) => switch (slot) {
  ItemSlot(:final now) => switch (now.item) {
    final item? => _joined(item.title, item.artist, copy.shellWindowTitleItem),
    null => null,
  },
  StationSlot(:final station, :final playback) => _joined(
    station.name,
    playback.nowPlaying,
    copy.shellWindowTitleLive,
  ),
  ParkedSlot() || RemoteSlot() || OfferSlot() || EmptySlot() => null,
};

String _joined(
  String name,
  String? detail,
  String Function(String name, String detail) both,
) => detail == null || detail.isEmpty ? name : both(name, detail);

/// Keeps the window's title saying what the now-playing slot names, and
/// the app's own title when it names nothing.
///
/// Watched from the signed-in scope with the other feeds, so it runs while
/// the app is minimized and a browser tab is in the background; signing out
/// disposes it and the title goes back.
final windowTitleBinderProvider = Provider.autoDispose<void>((ref) {
  final port = ref.watch(windowTitlePortProvider);
  String? shown;
  void publish() {
    final slot = ref.read(nowPlayingSlotProvider);
    final title = windowTitleOf(
      slot: slot,
      copy: ref.read(offTreeL10nProvider),
    );
    // Between two tracks the entry is there and its summary is not yet.
    if (title == null && slot is ItemSlot && slot.now.error == null) return;
    final next = title ?? _appTitle;
    if (next == shown) return;
    shown = next;
    port.show(next);
  }

  ref.listen(nowPlayingSlotProvider, (_, _) => publish());
  ref.listen(offTreeL10nProvider, (_, _) => publish());
  publish();
  ref.onDispose(() => port.show(_appTitle));
});
