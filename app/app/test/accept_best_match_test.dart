import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/add_to_library.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// The accept-the-best-match switch under Identify, from the sheets that
/// ask it to the review entry that says why it is still waiting.

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

PickedAudioFile _file(String name) {
  final bytes = Uint8List.fromList(List<int>.filled(8, 7));
  return PickedAudioFile(
    name: name,
    size: bytes.length,
    openRead: ([int? start, int? end]) => Stream.value(
      Uint8List.sublistView(bytes, start ?? 0, end ?? bytes.length),
    ),
  );
}

Finder _switchWithId(String id) => find.ancestor(
  of: find.bySemanticsIdentifier(id),
  matching: find.byType(WaxSwitch),
);

WaxSwitch _switch(WidgetTester tester, String id) =>
    tester.widget<WaxSwitch>(_switchWithId(id));

Future<void> _mount(
  WidgetTester tester,
  FakeRepository repo,
  Future<void> Function(BuildContext, WidgetRef) open,
) => mountApp(
  tester,
  Consumer(
    builder: (context, ref, _) => Scaffold(
      body: Center(
        child: WaxButton(label: 'Open', onPressed: () => open(context, ref)),
      ),
    ),
  ),
  container: appContainer(repo: repo),
);

FakeRepository _repo({bool? optOut, bool? acceptBest}) => FakeRepository()
  ..sessionState = const SessionState(authenticated: true, user: _user)
  ..prefs = Prefs(identifyOptOut: optOut, acceptBestMatch: acceptBest);

Future<void> _openUpload(
  WidgetTester tester,
  FakeRepository repo, {
  int files = 1,
  MediaType? fixed,
}) async {
  await _mount(
    tester,
    repo,
    (context, ref) => uploadPickedFiles(context, ref, <PickedAudioFile>[
      for (var i = 0; i < files; i++) _file('t$i.flac'),
    ], fixed: fixed),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _openAcquire(
  WidgetTester tester,
  FakeRepository repo, {
  MediaType initial = MediaType.music,
}) async {
  await _mount(
    tester,
    repo,
    (context, ref) => acquireFromUrl(context, ref, initial: initial),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _submitAcquire(WidgetTester tester) async {
  await tester.enterText(
    find.bySemanticsIdentifier(SemanticsIds.acquireUrl),
    'https://tube.example/watch?v=one',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
  await tester.pumpAndSettle();
}

Future<void> _confirmUpload(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm));
  await tester.pumpAndSettle();
}

WaxDeckApiException _unreadable() => const WaxDeckApiException(
  code: 'unavailable',
  statusCode: 503,
  message: 'down',
);

void main() {
  group('the upload sheet', () {
    testWidgets('draws the switch for music, off unless the account says so', (
      tester,
    ) async {
      await _openUpload(tester, _repo());
      expect(_switchWithId(SemanticsIds.uploadAcceptBest), findsOne);
      expect(find.text('Accept the best match'), findsOne);
      expect(_switch(tester, SemanticsIds.uploadAcceptBest).value, isFalse);
    });

    testWidgets('opens on the account preference', (tester) async {
      await _openUpload(tester, _repo(acceptBest: true));
      expect(_switch(tester, SemanticsIds.uploadAcceptBest).value, isTrue);
    });

    testWidgets('is not drawn for an audiobook', (tester) async {
      await _openUpload(
        tester,
        _repo(acceptBest: true),
        fixed: MediaType.audiobook,
      );
      expect(_switchWithId(SemanticsIds.uploadIdentify), findsOne);
      expect(_switchWithId(SemanticsIds.uploadAcceptBest), findsNothing);
    });

    testWidgets('is disabled while Identify is off, and comes back with it', (
      tester,
    ) async {
      await _openUpload(tester, _repo(optOut: true, acceptBest: true));
      expect(_switch(tester, SemanticsIds.uploadAcceptBest).onChanged, isNull);

      await tester.tap(_switchWithId(SemanticsIds.uploadIdentify));
      await tester.pumpAndSettle();
      expect(
        _switch(tester, SemanticsIds.uploadAcceptBest).onChanged,
        isNotNull,
      );
    });

    testWidgets('sends its value on the create when Identify is on', (
      tester,
    ) async {
      final repo = _repo();
      await _openUpload(tester, repo);
      await tester.tap(_switchWithId(SemanticsIds.uploadAcceptBest));
      await tester.pumpAndSettle();
      await _confirmUpload(tester);
      expect(repo.uploadIdentifyCalls, <bool?>[true]);
      expect(repo.uploadAcceptBestCalls, <bool?>[true]);
    });

    testWidgets('sends the preference it opened on', (tester) async {
      final repo = _repo(acceptBest: true);
      await _openUpload(tester, repo);
      await _confirmUpload(tester);
      expect(repo.uploadAcceptBestCalls, <bool?>[true]);
    });

    testWidgets('a batch and its members carry it', (tester) async {
      final repo = _repo();
      await _openUpload(tester, repo, files: 2);
      await tester.tap(_switchWithId(SemanticsIds.uploadAcceptBest));
      await tester.pumpAndSettle();
      await _confirmUpload(tester);
      expect(repo.batchAcceptBestCalls, <bool?>[true]);
      expect(repo.uploadAcceptBestCalls, <bool?>[true, true]);
    });

    testWidgets('is left out with Identify off', (tester) async {
      final repo = _repo(optOut: true, acceptBest: true);
      await _openUpload(tester, repo, files: 2);
      await _confirmUpload(tester);
      expect(repo.uploadIdentifyCalls, <bool?>[false, false]);
      expect(repo.batchAcceptBestCalls, <bool?>[null]);
      expect(repo.uploadAcceptBestCalls, <bool?>[null, null]);
    });

    testWidgets('is left out when Identify is turned off after it was on', (
      tester,
    ) async {
      final repo = _repo();
      await _openUpload(tester, repo);
      await tester.tap(_switchWithId(SemanticsIds.uploadAcceptBest));
      await tester.pumpAndSettle();
      await tester.tap(_switchWithId(SemanticsIds.uploadIdentify));
      await tester.pumpAndSettle();
      await _confirmUpload(tester);
      expect(repo.uploadIdentifyCalls, <bool?>[false]);
      expect(repo.uploadAcceptBestCalls, <bool?>[null]);
    });

    testWidgets('is left out for an audiobook', (tester) async {
      final repo = _repo(acceptBest: true);
      await _openUpload(tester, repo, fixed: MediaType.audiobook);
      await _confirmUpload(tester);
      expect(repo.uploadAcceptBestCalls, <bool?>[null]);
    });
  });

  group('with the account preferences unreadable', () {
    for (final timeout in [false, true]) {
      final how = timeout ? 'timing out' : 'failing';
      FakeRepository unreadable() {
        final repo = _repo(acceptBest: true);
        if (timeout) {
          repo.prefsReadGate = Completer<void>();
        } else {
          repo.prefsReadError = _unreadable();
        }
        return repo;
      }

      Future<void> open(WidgetTester tester, FakeRepository repo, int files) =>
          _mount(
            tester,
            repo,
            (context, ref) => uploadPickedFiles(context, ref, <PickedAudioFile>[
              for (var i = 0; i < files; i++) _file('t$i.flac'),
            ]),
          ).then((_) async {
            await tester.tap(find.text('Open'));
            await tester.pump(const Duration(seconds: 6));
            await tester.pumpAndSettle();
          });

      testWidgets('the upload sheet opens off and sends false, $how', (
        tester,
      ) async {
        final repo = unreadable();
        await open(tester, repo, 1);
        expect(_switch(tester, SemanticsIds.uploadAcceptBest).value, isFalse);
        await _confirmUpload(tester);
        expect(repo.uploadAcceptBestCalls, <bool?>[false]);
      });

      testWidgets('a batch carries false, $how', (tester) async {
        final repo = unreadable();
        await open(tester, repo, 2);
        await _confirmUpload(tester);
        expect(repo.batchAcceptBestCalls, <bool?>[false]);
        expect(repo.uploadAcceptBestCalls, <bool?>[false, false]);
      });

      testWidgets('the Add-from-URL sheet sends false, $how', (tester) async {
        final repo = unreadable();
        await _mount(
          tester,
          repo,
          (context, ref) =>
              acquireFromUrl(context, ref, initial: MediaType.music),
        );
        await tester.tap(find.text('Open'));
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(_switch(tester, SemanticsIds.acquireAcceptBest).value, isFalse);
        await _submitAcquire(tester);
        expect(repo.acquisitionCalls.single.acceptBestMatch, isFalse);
      });

      testWidgets('an audiobook sends nothing, $how', (tester) async {
        final repo = unreadable();
        await _mount(
          tester,
          repo,
          (context, ref) => uploadPickedFiles(context, ref, <PickedAudioFile>[
            _file('a.flac'),
          ], fixed: MediaType.audiobook),
        );
        await tester.tap(find.text('Open'));
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        await _confirmUpload(tester);
        expect(repo.uploadAcceptBestCalls, <bool?>[null]);
      });

      testWidgets('Identify off sends nothing, $how', (tester) async {
        final repo = unreadable();
        await open(tester, repo, 1);
        await tester.tap(_switchWithId(SemanticsIds.uploadIdentify));
        await tester.pumpAndSettle();
        await _confirmUpload(tester);
        expect(repo.uploadAcceptBestCalls, <bool?>[null]);
      });
    }
  });

  group('the Add-from-URL sheet', () {
    testWidgets('draws the switch for music, seeded from the preference', (
      tester,
    ) async {
      await _openAcquire(tester, _repo(acceptBest: true));
      expect(_switch(tester, SemanticsIds.acquireAcceptBest).value, isTrue);
    });

    testWidgets('is disabled while Identify is off', (tester) async {
      await _openAcquire(tester, _repo(optOut: true));
      expect(_switch(tester, SemanticsIds.acquireAcceptBest).onChanged, isNull);
    });

    testWidgets('sends its value', (tester) async {
      final repo = _repo();
      await _openAcquire(tester, repo);
      await tester.tap(_switchWithId(SemanticsIds.acquireAcceptBest));
      await tester.pumpAndSettle();
      await _submitAcquire(tester);
      expect(repo.acquisitionCalls.single.identify, isTrue);
      expect(repo.acquisitionCalls.single.acceptBestMatch, isTrue);
    });

    testWidgets('is left out with Identify off', (tester) async {
      final repo = _repo(optOut: true, acceptBest: true);
      await _openAcquire(tester, repo);
      await _submitAcquire(tester);
      expect(repo.acquisitionCalls.single.acceptBestMatch, isNull);
    });

    testWidgets('is left out when Identify is turned off after it was on', (
      tester,
    ) async {
      final repo = _repo();
      await _openAcquire(tester, repo);
      await tester.tap(_switchWithId(SemanticsIds.acquireAcceptBest));
      await tester.pumpAndSettle();
      expect(_switch(tester, SemanticsIds.acquireAcceptBest).value, isTrue);
      await tester.tap(_switchWithId(SemanticsIds.acquireIdentify));
      await tester.pumpAndSettle();
      expect(_switch(tester, SemanticsIds.acquireAcceptBest).onChanged, isNull);
      await _submitAcquire(tester);
      expect(repo.acquisitionCalls.single.identify, isFalse);
      expect(repo.acquisitionCalls.single.acceptBestMatch, isNull);
    });

    testWidgets('follows the medium: gone and unsent for an audiobook', (
      tester,
    ) async {
      final repo = _repo(acceptBest: true);
      await _openAcquire(tester, repo);
      expect(_switchWithId(SemanticsIds.acquireAcceptBest), findsOne);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.uploadMediaType),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.uploadMediaTypeOption(MediaType.audiobook.wireName),
        ),
      );
      await tester.pumpAndSettle();
      expect(_switchWithId(SemanticsIds.acquireAcceptBest), findsNothing);

      await _submitAcquire(tester);
      expect(repo.acquisitionCalls.single.mediaType, MediaType.audiobook);
      expect(repo.acquisitionCalls.single.acceptBestMatch, isNull);
    });
  });

  group('the review entry says why it is waiting', () {
    Future<void> open(
      WidgetTester tester,
      String? withheld, {
      String status = 'pending',
    }) async {
      final repo = FakeRepository();
      repo.reviewEntryDetails['rv-1'] = ReviewEntryDetail(
        id: 'rv-1',
        kind: 'import',
        status: status,
        mediaType: MediaType.music,
        origin: 'upload',
        title: 'Quiet Wire',
        trackCount: 1,
        createdAt: DateTime.utc(2026, 8, 1),
        acceptBestWithheld: withheld,
      );
      await pumpApp(
        tester,
        const ReviewEntryScreen(entryId: 'rv-1'),
        container: appContainer(repo: repo),
        routed: false,
      );
    }

    Finder noteFinder() =>
        find.bySemanticsIdentifier(SemanticsIds.reviewAcceptBestWithheld);

    for (final (value, sentence) in [
      ('below-floor', 'The best match was not close enough to accept'),
      (
        'ambiguous',
        'Another recording could be the right one, or the others could not be ruled out',
      ),
      ('no-candidates', 'No match was found to accept'),
    ]) {
      testWidgets('$value draws its sentence', (tester) async {
        await open(tester, value);
        expect(noteFinder(), findsOne);
        expect(find.text(sentence), findsOne);
      });
    }

    // Deliberate: a value this client does not know draws nothing rather
    // than a guess.
    testWidgets('an unknown value draws nothing', (tester) async {
      await open(tester, 'something-new');
      expect(noteFinder(), findsNothing);
    });

    testWidgets('a decided entry draws no reason', (tester) async {
      await open(tester, 'below-floor', status: 'applied');
      expect(noteFinder(), findsNothing);
      expect(
        find.text('The best match was not close enough to accept'),
        findsNothing,
      );
    });

    testWidgets('nothing is drawn when the field is absent', (tester) async {
      await open(tester, null);
      expect(noteFinder(), findsNothing);
      expect(find.textContaining('accept'), findsNothing);
    });
  });
}
