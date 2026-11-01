import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck/src/uploads/share_intake.dart';
import 'package:waxdeck/src/uploads/share_intake_gate.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

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

Widget _host(
  FakeRepository repo,
  FakeShareIntake port, {
  List<Override> extra = const [],
}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    shareIntakeProvider.overrideWithValue(port),
    // The gate is a signed-in surface and the acquire sheet reads the
    // account's own identification default, so the session has to
    // resolve against something rather than the platform keychain.
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ...extra,
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

  /// Shares files named [names] (two bytes each, staged on disk as the
  /// platform side leaves them) and waits for every one to stage.
  Future<void> shareFiles(
    WidgetTester tester,
    FakeRepository repo,
    List<String> names, {
    List<Override> overrides = const [],
  }) async {
    final dir = Directory.systemTemp.createTempSync('share-intake-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final files = [
      for (final (i, name) in names.indexed)
        SharedFile(
          path: (File(
            '${dir.path}/share-$i-$name',
          )..writeAsBytesSync([i + 1, 2])).path,
          name: name,
        ),
    ];
    final port = FakeShareIntake(intake: SharedFilesIntake(files));
    await tester.runAsync(() async {
      await tester.pumpWidget(_host(repo, port, extra: overrides));
      for (var waited = 0; waited < 5000; waited += 10) {
        if (repo.uploadsById.length == names.length &&
            repo.uploadsById.values.every((u) => u.state == 'staged')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  testWidgets('shared .m4b files upload as an audiobook batch', (tester) async {
    final repo = FakeRepository();
    await shareFiles(tester, repo, ['book-1.m4b', 'book-2.m4b']);

    expect(repo.batchesById.values.single.mediaType, MediaType.audiobook);
    expect(
      repo.uploadsById.values.map((u) => u.mediaType),
      everyElement(MediaType.audiobook),
    );
  });

  testWidgets('one .m4b among other audio makes the share an audiobook, '
      'grouped by auto-detection', (tester) async {
    final repo = FakeRepository();
    await shareFiles(tester, repo, ['book.m4b', 'bonus.flac']);

    final batch = repo.batchesById.values.single;
    expect(batch.mediaType, MediaType.audiobook);
    expect(batch.grouping, UploadGrouping.auto);
  });

  group('the remembered library follows the shared kind', () {
    const music = UploadTarget(
      pid: 'lb-music',
      name: 'Music',
      mediaTypes: [MediaType.music],
      managed: true,
    );
    const bootlegs = UploadTarget(
      pid: 'lb-bootlegs',
      name: 'Bootlegs',
      mediaTypes: [MediaType.music],
      managed: false,
    );
    const books = UploadTarget(
      pid: 'lb-books',
      name: 'Books',
      mediaTypes: [MediaType.audiobook],
      managed: true,
    );

    Future<FakeRepository> shareWithMemory(
      WidgetTester tester,
      List<String> names,
    ) async {
      final repo = FakeRepository()
        ..uploadTargets.addAll([music, bootlegs, books]);
      final settings = MemoryClientSettingsStore();
      await settings.write(ClientSettingKeys.uploadTarget, bootlegs.pid);
      await shareFiles(
        tester,
        repo,
        names,
        overrides: [clientSettingsStoreProvider.overrideWithValue(settings)],
      );
      return repo;
    }

    testWidgets('a music share is filed where music last went', (tester) async {
      final repo = await shareWithMemory(tester, ['a.flac', 'b.flac']);

      expect(repo.batchesById.values.single.libraryPid, bootlegs.pid);
    });

    testWidgets('an audiobook share does not inherit a music library', (
      tester,
    ) async {
      final repo = await shareWithMemory(tester, ['a.m4b', 'b.m4b']);

      expect(repo.batchesById.values.single.libraryPid, isNull);
    });
  });

  testWidgets('a shared file over the whole allowance is worded as a '
      'picked one is', (tester) async {
    // Staged on disk for the reason the test above gives; the share
    // and the picker are two ways in, and one refusal reads one way.
    final dir = Directory.systemTemp.createTempSync('share-intake-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final book = File('${dir.path}/share-1-book.flac')
      ..writeAsBytesSync(List<int>.filled(2048, 1));
    final repo = FakeRepository()
      ..uploadPageQuota = const UploadQuota(bytesInUse: 0, quotaBytes: 1024)
      ..createUploadRefusal = const WaxDeckApiException(
        code: 'quota-exceeded',
        message:
            'uploads waiting for review may total 1024 bytes, 0 in use; '
            'this one needs 2048 more',
        statusCode: 413,
      );
    final port = FakeShareIntake(
      intake: SharedFilesIntake([
        SharedFile(path: book.path, name: 'book.flac'),
      ]),
    );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        shareIntakeProvider.overrideWithValue(port),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
    );
    addTearDown(container.dispose);
    // The allowance as the session list last read it.
    await tester.runAsync(() => container.read(uploadsProvider.future));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(
            const ShareIntakeGate(child: Scaffold(body: Text('library'))),
          ),
        ),
      );
      for (var waited = 0; waited < 5000; waited += 10) {
        if (container.read(shellMessengerProvider) != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(
      shellMessageText(container.read(shellMessengerProvider)),
      'book.flac: Larger than your whole upload limit of 1 KB, so clearing '
      'Past uploads cannot make room. An administrator can raise the limit.',
    );
  });
}
