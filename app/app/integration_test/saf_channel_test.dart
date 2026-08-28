// The Android folder pick against the real waxdeck/saf channel: the
// system tree picker opens, a driver outside this process (adb input
// taps, scripted beside the test invocation) walks it to the probe
// folder pushed to /sdcard/Music/WaxProbe and confirms, and the test
// asserts the walk - pulled in batches small enough that the probe
// crosses several, so the resumable half of the protocol runs - the
// filter accounting, and the windowed reads that come back. Host unit
// tests mock the channel; only this proves the Kotlin half - grant,
// traversal, resume, readChunk - on a device.
//
// The taps have to come from outside because `flutter test` holds the
// device's one instrumentation slot. e2e/tools/run-saf-probe.sh is the
// recipe, and it is what the android-conformance workflow runs:
//   cd fixtures && go run ./cmd/fixturegen -out /tmp/wax-saf -preset saf-probe
//   e2e/tools/run-saf-probe.sh /tmp/wax-saf/WaxProbe emulator-5554
// Tapping through by hand still works - push the probe, run the test
// below, and answer the picker yourself.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/saf_folder_picker.dart';

/// How long the picker interaction gets before the run counts as
/// undriven. Generous: a human tapping through also passes.
const _budget = Duration(minutes: 2);

/// A page small enough that the probe folder crosses several of them.
/// The resumable half of the protocol - Kotlin's stack, its visited
/// set, and the directory it is part way through - only runs at all
/// when a walk needs more than one batch, and a probe big enough to
/// force that at the production page size is too big to push onto an
/// emulator.
const _batch = 2;

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
        batch: _batch,
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
