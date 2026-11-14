import 'package:flutter/gestures.dart' show PointerDeviceKind;

/// Every pointer that may swipe a player surface: all but a mouse.
///
/// A mouse's drag slop is a pixel, so a swipe over controls would take
/// every click that drifted, and a mouse drag over text is a selection.
/// A trackpad's swipe arrives as pan-zoom and keeps it. Shared by the
/// deck bar and the player, so the two cannot drift apart. Not exported
/// from the barrel.
final Set<PointerDeviceKind> swipeDevices = PointerDeviceKind.values
    .where((kind) => kind != PointerDeviceKind.mouse)
    .toSet();
