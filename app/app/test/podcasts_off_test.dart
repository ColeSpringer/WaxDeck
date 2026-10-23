import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/podcasts/podcasts_screen.dart';
import 'package:waxdeck/src/podcasts/show_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/search/search_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';

/// A platform with a file dialog, which picks nothing.
class _Picker implements FilePickerPort {
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
  }) async => null;
}

/// A server whose podcasts are turned off refuses every subscribe, so the
/// app offers none: no add, no follow, no directory to follow from.
void main() {
  Future<void> pump(
    WidgetTester tester,
    FakeRepository repo,
    Widget screen, {
    FilePickerPort? picker,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          audioEngineProvider.overrideWithValue(FakeEngine()),
          if (picker != null) filePickerProvider.overrideWithValue(picker),
        ],
        child: routedHost(screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final on in <bool>[true, false]) {
    final state = on ? 'on' : 'off';
    testWidgets('the podcasts hub offers a show to add only with podcasts '
        '$state', (tester) async {
      await pump(
        tester,
        FakeRepository()..serverPodcasts = on,
        const PodcastsScreen(),
      );
      final offered = on ? findsOneWidget : findsNothing;
      expect(find.bySemanticsIdentifier(SemanticsIds.podcastAdd), offered);
      expect(find.text(AppLocalizationsEn().podcastsEmptyAction), offered);
    });

    testWidgets('the hub offers an OPML import only with podcasts $state', (
      tester,
    ) async {
      await pump(
        tester,
        FakeRepository()..serverPodcasts = on,
        const PodcastsScreen(),
        picker: _Picker(),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.podcastOverflow),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.podcastOpmlImport),
        on ? findsOneWidget : findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.podcastOpmlExport),
        findsOneWidget,
      );
    });

    testWidgets('a show offers to follow it only with podcasts $state', (
      tester,
    ) async {
      final repo = FakeRepository()
        ..serverPodcasts = on
        ..shows[_showPid] = testShow(_showPid)
        ..episodesByShow[_showPid] = <EpisodeSummary>[];
      await pump(tester, repo, const ShowScreen(pid: _showPid));
      expect(
        find.bySemanticsIdentifier(SemanticsIds.podcastSubscribe),
        on ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('search asks no podcast directory with podcasts off', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..serverPodcasts = false
      ..podcastDirectoryEntries = <PodcastDirectoryEntry>[
        const PodcastDirectoryEntry(
          name: 'Nightjar Radio Hour',
          feedUrl: 'https://feeds.example/nightjar',
        ),
      ];
    await pump(tester, repo, const SearchScreen(initialQuery: 'night'));
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.searchFilter('podcasts')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nightjar Radio Hour'), findsNothing);
    expect(repo.podcastDirectoryQueries, isEmpty);
  });
}
