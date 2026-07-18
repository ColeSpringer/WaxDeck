import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'src/app.dart';
import 'src/auto/media_session_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Browser automation drives the web build through the semantics tree, so
  // semantics must be live from the first frame, not gated on a screen
  // reader announcing itself.
  SemanticsBinding.instance.ensureSemantics();
  // Points just_audio at mpv on desktop; no-op on web and mobile.
  ensureAudioEngineInitialized();
  // The media session and the app share one provider world, so the
  // Android Auto browse tree reads the same mirror the UI does.
  final container = ProviderContainer();
  await initMediaSession(container);
  runApp(
    UncontrolledProviderScope(container: container, child: const WaxDeckApp()),
  );
}
