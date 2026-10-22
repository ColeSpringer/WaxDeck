import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _opml = '<opml version="2.0"><body><outline xmlUrl="x"/></body></opml>';

/// A picker that answers one OPML file read through its byte stream, the
/// way the web build hands one over.
class _OpmlPicker implements FilePickerPort {
  @override
  bool get canPickFolders => false;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles({
    String audioLabel = '',
    String anyLabel = '',
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const [];

  @override
  Future<FolderPick> pickAudioFolder({
    UploadFormatSets formats = const UploadFormatSets(),
  }) async => const FolderPick();

  @override
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    String anyLabel = '',
  }) async {
    final bytes = utf8.encode(_opml);
    return PickedAudioFile(
      name: 'subscriptions.opml',
      size: bytes.length,
      openRead: ([start, end]) => Stream.value(bytes),
    );
  }
}

/// Imports through the hub's overflow and answers what the shell said.
/// [reloadError] fails the subscription list's reload that follows the
/// import, until the shell has spoken.
Future<String?> _import(
  WidgetTester tester,
  List<OpmlImportOutcome> outcomes, {
  WaxDeckApiException? reloadError,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeRepository()..opmlOutcomes = outcomes;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        filePickerProvider.overrideWithValue(_OpmlPicker()),
      ],
      child: routedHost(const PodcastsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  repo.listError = reloadError;
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastOverflow));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.podcastOpmlImport));
  await tester.pump();
  await tester.pump();
  expect(repo.importedOpml, [_opml]);
  final said = shellMessageText(raisedMessage(tester));
  // Lets the reload's retries land, so nothing is left pending.
  repo.listError = null;
  await tester.pump(const Duration(minutes: 1));
  await tester.pumpAndSettle();
  return said;
}

const _landed = OpmlImportOutcome(
  feedUrl: 'https://feeds.example/one.xml',
  title: 'One',
  pid: 'pc-01JZX5N8QW3F4V9T2B7KD3M9R6',
);

void main() {
  testWidgets('an import that took every feed says so', (tester) async {
    expect(await _import(tester, const [_landed]), 'Subscriptions imported');
  });

  testWidgets('a file that names no feed says so', (tester) async {
    expect(
      await _import(tester, const []),
      'No feeds were found in that file.',
    );
  });

  testWidgets('a reload that fails after the import never replaces its '
      'report', (tester) async {
    final said = await _import(
      tester,
      const [
        _landed,
        OpmlImportOutcome(
          feedUrl: 'https://members.example/feed.xml',
          error: "The feed's host refused the request; it may need a login.",
          reason: 'host-refused',
        ),
      ],
      reloadError: const WaxDeckApiException(
        code: 'internal',
        message: 'the list could not be read',
        statusCode: 500,
      ),
    );
    expect(
      said,
      '1 feed could not be added. The host refused the request. It may '
      'need a login.',
    );
  });

  testWidgets('feeds that failed alike are counted with their reason', (
    tester,
  ) async {
    final said = await _import(tester, const [
      _landed,
      OpmlImportOutcome(
        feedUrl: 'https://members.example/feed.xml',
        error: "The feed's host refused the request; it may need a login.",
        reason: 'host-refused',
      ),
      OpmlImportOutcome(
        feedUrl: 'https://paid.example/feed.xml',
        error: "The feed's host refused the request; it may need a login.",
        reason: 'host-refused',
      ),
    ]);
    expect(
      said,
      '2 feeds could not be added. The host refused the request. It may '
      'need a login.',
    );
  });

  testWidgets('feeds that failed for different reasons are not given one '
      'reason, and the details name each', (tester) async {
    final said = await _import(tester, const [
      OpmlImportOutcome(
        feedUrl: 'https://members.example/feed.xml',
        error: "The feed's host refused the request; it may need a login.",
        reason: 'host-refused',
      ),
      OpmlImportOutcome(
        feedUrl: 'https://gone.example/feed.xml',
        error: 'No feed was found at that address.',
        reason: 'host-missing',
      ),
    ]);
    expect(said, '2 feeds could not be added, for different reasons.');
    await pressRaisedAction(tester);
    await tester.pumpAndSettle();
    final details = find.byKey(const Key('opml-not-added'));
    expect(details, findsOneWidget);
    final text = tester.widget<WaxProse>(details).data!;
    expect(text, contains('https://members.example/feed.xml'));
    expect(
      text,
      contains('The host refused the request. It may need a login.'),
    );
    expect(text, contains('https://gone.example/feed.xml'));
    expect(text, contains('The host has nothing at that address.'));
  });

  testWidgets('a reason is worded by this client, and a failure with none '
      'in the server words', (tester) async {
    for (final (outcome, sentence) in const [
      (
        OpmlImportOutcome(
          feedUrl: 'https://example.com/',
          error: 'That address did not return a podcast feed.',
          reason: 'not-a-feed',
        ),
        'That address answered, but not with anything a podcast app can read.',
      ),
      (
        OpmlImportOutcome(
          feedUrl: 'http://10.0.0.5/feed.xml',
          error:
              'This server does not fetch feeds from private or local network addresses.',
          reason: 'blocked-address',
        ),
        'This server does not fetch from private or local network addresses.',
      ),
      (
        OpmlImportOutcome(
          feedUrl: 'https://adult.example/feed.xml',
          error: 'This account cannot subscribe to explicit shows.',
        ),
        'This account cannot subscribe to explicit shows.',
      ),
    ]) {
      expect(
        await _import(tester, [outcome]),
        '1 feed could not be added. $sentence',
      );
    }
  });
}
