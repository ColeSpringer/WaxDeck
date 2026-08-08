import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_entry_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/add_to_library.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// The per-submission identification choice, from the sheet that asks it
/// to the review entry that explains itself when it was declined.

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

/// The WaxSwitch carrying one semantics identifier. The identifier is
/// published by the switch's own inner Semantics node, so the widget is
/// the ancestor of what the finder matches.
Finder _switchWithId(String id) => find.ancestor(
  of: find.bySemanticsIdentifier(id),
  matching: find.byType(WaxSwitch),
);

/// A host that opens one of the add sheets from a button, so the flow
/// under test is the real one rather than the dialog alone.
Widget _host(
  FakeRepository repo,
  Future<void> Function(BuildContext, WidgetRef) open,
) {
  return ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
    // Over the real route table: the acquire flow reaches for the router
    // to offer its "Tasks" action.
    child: routedHost(
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: WaxButton(
              label: 'Open',
              onPressed: () => open(context, ref),
            ),
          ),
        ),
      ),
    ),
  );
}

FakeRepository _repo({bool? optOut}) => FakeRepository()
  ..sessionState = const SessionState(authenticated: true, user: _user)
  ..prefs = Prefs(identifyOptOut: optOut);

void main() {
  testWidgets('the upload sheet opens on the account default and sends it', (
    tester,
  ) async {
    final repo = _repo(optOut: true);
    await tester.pumpWidget(
      _host(
        repo,
        (context, ref) =>
            uploadPickedFiles(context, ref, <PickedAudioFile>[_file('a.flac')]),
      ),
    );
    // The controller has to have read prefs before the sheet opens; the
    // provider is lazy, so the flow's own read is what seeds the switch.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final switchFinder = _switchWithId(SemanticsIds.uploadIdentify);
    expect(switchFinder, findsOne);
    expect(
      tester.widget<WaxSwitch>(switchFinder).value,
      isFalse,
      reason: 'the account opted out, so the sheet opens off',
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();
    expect(repo.uploadIdentifyCalls, <bool?>[false]);
  });

  testWidgets('flipping the upload switch overrides the preference', (
    tester,
  ) async {
    final repo = _repo(optOut: true);
    await tester.pumpWidget(
      _host(
        repo,
        (context, ref) =>
            uploadPickedFiles(context, ref, <PickedAudioFile>[_file('a.flac')]),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(_switchWithId(SemanticsIds.uploadIdentify));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.uploadIdentifyCalls, <bool?>[true]);
  });

  testWidgets('a batch carries the choice for its members', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(
      _host(
        repo,
        (context, ref) => uploadPickedFiles(context, ref, <PickedAudioFile>[
          _file('a.flac'),
          _file('b.flac'),
        ]),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Nothing stored, so the sheet opens on.
    expect(
      tester
          .widget<WaxSwitch>(_switchWithId(SemanticsIds.uploadIdentify))
          .value,
      isTrue,
    );
    await tester.tap(_switchWithId(SemanticsIds.uploadIdentify));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.uploadMediaConfirm),
    );
    await tester.pumpAndSettle();

    expect(repo.batchIdentifyCalls, <bool?>[false]);
    expect(repo.uploadIdentifyCalls, <bool?>[false, false]);
  });

  testWidgets('the Add-from-URL sheet sends the choice', (tester) async {
    final repo = _repo(optOut: true);
    await tester.pumpWidget(
      _host(repo, (context, ref) => acquireFromUrl(context, ref)),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<WaxSwitch>(_switchWithId(SemanticsIds.acquireIdentify))
          .value,
      isFalse,
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.acquireUrl),
      'https://tube.example/watch?v=one',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls, hasLength(1));
    expect(repo.acquisitionCalls.single.identify, isFalse);
  });

  // Only ever seen where the automatic import refused, which is the
  // one case a declined submission is still waiting for somebody.
  testWidgets('a stuck declined entry says nothing was searched', (
    tester,
  ) async {
    final repo = FakeRepository();
    repo.reviewEntryDetails['rv-1'] = ReviewEntryDetail(
      id: 'rv-1',
      kind: 'import',
      status: 'pending',
      mediaType: MediaType.music,
      origin: 'upload',
      title: 'Quiet Wire',
      trackCount: 1,
      createdAt: DateTime.utc(2026, 8, 1),
      identifyDeclined: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: ReviewEntryScreen(entryId: 'rv-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Identification was skipped'), findsOne);
    expect(find.text('No candidates found'), findsNothing);
  });

  testWidgets('a searched-empty entry keeps the older copy', (tester) async {
    final repo = FakeRepository();
    repo.reviewEntryDetails['rv-2'] = ReviewEntryDetail(
      id: 'rv-2',
      kind: 'import',
      status: 'pending',
      mediaType: MediaType.music,
      origin: 'upload',
      title: 'Quiet Wire',
      trackCount: 1,
      createdAt: DateTime.utc(2026, 8, 1),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: ReviewEntryScreen(entryId: 'rv-2')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No candidates found'), findsOne);
    expect(find.text('Identification was skipped'), findsNothing);
  });

  testWidgets('a podcast is asked, and the control says what it does', (
    tester,
  ) async {
    // Nothing is matched for a podcast, so the switch does not promise
    // MusicBrainz - but it does open a review entry, so whether that
    // waits for a decision is a real question and is asked.
    final repo = _repo(optOut: true);
    await tester.pumpWidget(
      _host(
        repo,
        (context, ref) =>
            acquireFromUrl(context, ref, initial: MediaType.podcast),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(_switchWithId(SemanticsIds.acquireIdentify), findsOne);
    expect(find.text('Review before adding'), findsOne);
    expect(find.text('Identify against MusicBrainz'), findsNothing);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.acquireUrl),
      'https://feeds.example/show.xml',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.acquireSubmit));
    await tester.pumpAndSettle();

    expect(repo.acquisitionCalls.single.identify, isFalse);
  });

  testWidgets('an audiobook is not promised a match either', (tester) async {
    // The lie this catches is not the podcast one: the switch has
    // always been drawn for books, and the identify worker has never
    // taken one to the engine.
    final repo = _repo();
    await tester.pumpWidget(
      _host(
        repo,
        (context, ref) => uploadPickedFiles(context, ref, <PickedAudioFile>[
          _file('a.m4b'),
        ], initial: MediaType.audiobook),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Review before adding'), findsOne);
    expect(find.text('Identify against MusicBrainz'), findsNothing);
  });
}
