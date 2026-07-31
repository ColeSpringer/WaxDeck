import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'src/app.dart';
import 'src/artwork/artwork_providers.dart';
import 'src/auto/media_session_init.dart';
import 'src/sync/refresh_pacing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything can decode a cover: this app draws grids of them,
  // and the framework's defaults are sized for apps that draw a few.
  applyArtworkImageCacheBounds();
  // Browser automation drives the web build through the semantics tree, so
  // semantics must be live from the first frame, not gated on a screen
  // reader announcing itself.
  SemanticsBinding.instance.ensureSemantics();
  // Points just_audio at mpv on desktop; no-op on web and mobile.
  ensureAudioEngineInitialized();
  // The media session and the app share one provider world, so the
  // Android Auto browse tree reads the same mirror the UI does. The
  // observer is the live fan-out's ledger of in-flight first builds
  // (ADR-0036); it only works registered here, from the first element.
  final container = ProviderContainer(observers: [FirstBuildObserver()]);
  await initMediaSession(container);
  runApp(
    UncontrolledProviderScope(container: container, child: const WaxDeckApp()),
  );
}
