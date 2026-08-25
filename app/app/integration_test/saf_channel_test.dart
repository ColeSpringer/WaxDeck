// The Android folder pick against the real waxdeck/saf channel: the
// system tree picker opens, a driver outside this process (adb input
// taps, scripted beside the test invocation) walks it to the probe
// folder pushed to /sdcard/Music/WaxProbe and confirms, and the test
// asserts the walk, the filter accounting, and the windowed reads that
// come back. Host unit tests mock the channel; only this proves the
// Kotlin half - grant, traversal, readChunk - on a device.
//
// Run it by hand, like the suites beside it (the picker taps make it
// interactive unless a driver taps for you):
//   adb push <probe folder> /sdcard/Music/WaxProbe
//   flutter test integration_test/saf_channel_test.dart -d emulator-5554
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/saf_folder_picker.dart';

/// How long the picker interaction gets before the run counts as
/// undriven. Generous: a human tapping through also passes.
const _budget = Duration(minutes: 2);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a picked tree enumerates, filters, and reads over the channel',
    () async {
      if (defaultTargetPlatform != TargetPlatform.android) {
        markTestSkipped('the waxdeck/saf channel is Android-only');
        return;
      }

      final pick = await pickSafAudioFolder(
        const UploadFormatSets(),
      ).timeout(_budget);

      // The probe folder: lantern-one/two at the top, sodium-sky under
      // Disc1, a text file and an Audible container to be left behind.
      expect(pick.files.map((f) => f.name).toList(), [
        'lantern-one.mp3',
        'lantern-two.mp3',
        'sodium-sky.mp3',
      ]);
      expect(pick.files[0].relativeDir, 'WaxProbe');
      expect(pick.files[2].relativeDir, 'WaxProbe/Disc1');
      expect(
        pick.skippedUnsupported,
        1,
        reason: 'notes.txt fell to the filter',
      );
      expect(pick.skippedDrm, 1, reason: 'memoir.aax counts apart');

      // The windowed read serves real bytes: a bounded window is exactly
      // its size, and the whole file arrives across windows.
      final file = pick.files.first;
      expect(file.size, greaterThan(0));
      final window = <int>[
        for (final chunk in await file.openRead!(0, 16).toList()) ...chunk,
      ];
      expect(window, hasLength(16));
      var total = 0;
      await for (final chunk in file.openRead!()) {
        total += chunk.length;
      }
      expect(total, file.size);
      // The default 30s per-test timeout is shorter than [_budget], so it
      // fires first and reads as the channel failing; the real wait is
      // whoever is tapping through the picker.
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
