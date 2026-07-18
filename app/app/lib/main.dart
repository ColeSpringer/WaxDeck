import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Browser automation drives the web build through the semantics tree, so
  // semantics must be live from the first frame, not gated on a screen
  // reader announcing itself.
  SemanticsBinding.instance.ensureSemantics();
  // Points just_audio at mpv on desktop; no-op on web and mobile.
  ensureAudioEngineInitialized();
  runApp(const ProviderScope(child: WaxDeckApp()));
}
