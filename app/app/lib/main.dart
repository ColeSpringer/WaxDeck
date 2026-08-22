import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'src/app.dart';
import 'src/artwork/artwork_providers.dart';
import 'src/auto/media_session_init.dart';
import 'src/diagnostics/defect_log.dart';
import 'src/desktop/desktop_ports_io.dart'
    if (dart.library.js_interop) 'src/desktop/desktop_ports_stub.dart';
import 'src/shell/url_strategy/url_strategy.dart';
import 'src/sync/refresh_pacing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before the router reads the launch location: the web build's
  // locations live in the path, so this has to be set before anything
  // parses one. No-op off the web.
  useWaxUrlStrategy();
  // Before anything can decode a cover: this app draws grids of them,
  // and the framework's defaults are sized for apps that draw a few.
  applyArtworkImageCacheBounds();
  // Browser automation drives the web build through the semantics tree, so
  // semantics must be live from the first frame, not gated on a screen
  // reader announcing itself.
  SemanticsBinding.instance.ensureSemantics();
  // Points just_audio at mpv on desktop; no-op on web and mobile.
  ensureAudioEngineInitialized();
  // Tells the window plugin the window exists, before anything asks it
  // to shrink; no-op off the desktops.
  ensureDesktopWindowInitialized();
  // The media session and the app share one provider world, so the
  // Android Auto browse tree reads the same mirror the UI does. The
  // observer is the live fan-out's ledger of in-flight first builds; it
  // only works registered here, from the first element.
  final container = ProviderContainer(observers: [FirstBuildObserver()]);
  // Before anything else can raise: the paged controllers rethrow the
  // defects they cannot handle on purpose, and until this is installed
  // there is nothing on the other end of that.
  installDefectHandlers(container);
  await initMediaSession(container);
  runApp(
    UncontrolledProviderScope(container: container, child: const WaxDeckApp()),
  );
}
