import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/share_intake.dart';
import 'package:waxdeck/src/uploads/share_intake_gate.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// Hands out one queued payload, like MainActivity's share queue.
class FakeShareIntake implements ShareIntakePort {
  FakeShareIntake({this.intake});

  SharedIntake? intake;
  var consumeCalls = 0;

  @override
  Future<SharedIntake?> consumeShared() async {
    consumeCalls++;
    final queued = intake;
    intake = null;
    return queued;
  }
}

Widget _host(FakeRepository repo, FakeShareIntake port) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    shareIntakeProvider.overrideWithValue(port),
    // The gate is a signed-in surface and the acquire sheet reads the
    // account's own identification default, so the session has to
    // resolve against something rather than the platform keychain.
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(
    const ShareIntakeGate(child: Scaffold(body: Text('library'))),
  ),
);

void main() {
  testWidgets('a shared URL opens the acquire dialog prefilled', (
    tester,
  ) async {
    final repo = FakeRepository();
    final port = FakeShareIntake(
      intake: const SharedUrlIntake('https://tube.example/watch?v=pony'),
    );
    await tester.pumpWidget(_host(repo, port));
    await tester.pumpAndSettle();

    expect(port.consumeCalls, 1);
    final url = find.bySemanticsIdentifier(SemanticsIds.acquireUrl);
    expect(url, findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(of: url, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'https://tube.example/watch?v=pony');

    // Submitting rides the normal acquisition path.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
    await tester.pumpAndSettle();
    expect(
      repo.acquisitionCalls.single.url,
      'https://tube.example/watch?v=pony',
    );
  });

  testWidgets('shared audio files stream from disk to the library', (
    tester,
  ) async {
    // Real staged files, as MainActivity leaves them: the upload path
    // reads windows from disk and never holds a file whole. Setup and
    // teardown use the synchronous io calls (async io never completes
    // outside runAsync under the test binding - it hangs the test);
    // the upload flow itself runs under runAsync, where the real
    // event loop turns, with completion polled rather than
    // pump-settled.
    final dir = Directory.systemTemp.createTempSync('share-intake-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pony = File('${dir.path}/share-1-pony.flac')
      ..writeAsBytesSync([1, 2, 3]);
    final bree = File('${dir.path}/share-2-bree.flac')
      ..writeAsBytesSync([4, 5]);

    final repo = FakeRepository();
    final port = FakeShareIntake(
      intake: SharedFilesIntake([
        SharedFile(path: pony.path, name: 'pony.flac'),
        SharedFile(path: bree.path, name: 'bree.flac'),
      ]),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(_host(repo, port));
      for (var waited = 0; waited < 5000; waited += 10) {
        if (repo.uploadsById.length == 2 &&
            repo.uploadsById.values.every((u) => u.state == 'staged')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    final names = repo.uploadsById.values.map((u) => u.fileName).toList();
    expect(names, containsAll(['pony.flac', 'bree.flac']));
    // Each upload ran to completion: bytes in, session sealed.
    for (final upload in repo.uploadsById.values) {
      expect(upload.state, 'staged');
      expect(upload.receivedBytes, upload.sizeBytes);
    }
  });
}
