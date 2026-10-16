import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'scripted_platform.dart';

/// Whether an engine plays an HLS presentation, which is what the server
/// is told when it decides between a live encode and one item's HLS
/// rendering of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedPlatform platform;
  setUp(() => JustAudioPlatform.instance = platform = ScriptedPlatform());

  test('ExoPlayer and mpv play HLS; the browser element does not', () {
    expect(scriptedEngine().playsHls, isTrue);
    expect(scriptedEngine(isWeb: true).playsHls, isFalse);
  });

  test('a presentation the server hands over loads as HLS', () async {
    final native = scriptedEngine();
    await native.load('http://host:4420/media/hls/master.m3u8?it=k&mt=t');
    await native.load('http://host:4420/media/stream?pid=tr-1&mt=t');
    // A replacing load may start on a fresh platform player.
    final sources = platform.players.expand((p) => p.loadedSources);
    expect(sources.map((s) => s.runtimeType), [
      HlsAudioSourceMessage,
      ProgressiveAudioSourceMessage,
    ]);
  });
}
