/// The web build's desktop shell: none of it.
///
/// A browser tab has no window to shrink and no tray to sit in, and both
/// plugins reach for `dart:io`, so keeping them out of this compilation
/// unit is what keeps them out of the wasm build.
library;

import 'desktop_ports.dart';

void ensureDesktopWindowInitialized() {}

MiniWindowPort createMiniWindowPort() => const NoMiniWindow();

TrayPort createTrayPort() => const NoTray();
