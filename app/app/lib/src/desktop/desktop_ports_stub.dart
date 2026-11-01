/// The web build's desktop shell: none of it, but the tab's title.
///
/// A browser tab has no window to shrink and no tray to sit in, and both
/// plugins reach for `dart:io`, so keeping them out of this compilation
/// unit is what keeps them out of the wasm build.
library;

import 'package:web/web.dart' as web;

import 'desktop_ports.dart';

void ensureDesktopWindowInitialized() {}

MiniWindowPort createMiniWindowPort() => const NoMiniWindow();

TrayPort createTrayPort() => const NoTray();

/// Not `SystemChrome.setApplicationSwitcherDescription`: on the web that
/// rewrites the theme-color meta as well, which the app's bars own.
WindowTitlePort createWindowTitlePort({required bool desktop}) =>
    const BrowserWindowTitle();

class BrowserWindowTitle implements WindowTitlePort {
  const BrowserWindowTitle();

  @override
  void show(String title) => web.document.title = title;
}
