import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../radio/radio_controller.dart';
import '../radio/radio_screen.dart';
import '../search/search_controller.dart';
import '../search/search_open.dart';
import '../settings/settings_registry.dart';
import 'adaptive_shell.dart';
import 'commands.dart';
import 'routes.dart';
import 'semantics_ids.dart';

/// The palette reaches one known thing; the search screen shows the rest,
/// and the group's last row says so.
const int kPaletteHitLimit = 8;

/// Per kind, on the wire and on screen. The endpoint caps per group, and
/// taking rows a kind at a time is what stops nine matching artists
/// hiding every album behind them.
const int kPaletteHitsPerKind = 3;

const int kPaletteStationLimit = 4;
const int kPaletteSettingLimit = 4;

/// What has been typed, and what has settled: local matches move on the
/// keystroke, the library waits. One state, so a frame cannot draw one
/// query's rows beside another's hits.
class PaletteQuery {
  const PaletteQuery({this.typed = '', this.settled = ''});

  final String typed;
  final String settled;
}

class PaletteQueryController extends Notifier<PaletteQuery> {
  static const debounce = Duration(milliseconds: 200);

  /// One character over a large catalog matches most of it.
  static const minimum = 2;

  Timer? _timer;

  @override
  PaletteQuery build() {
    ref.onDispose(() => _timer?.cancel());
    return const PaletteQuery();
  }

  void type(String value) {
    _timer?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < minimum) {
      state = PaletteQuery(typed: trimmed);
      return;
    }
    state = PaletteQuery(typed: trimmed, settled: state.settled);
    _timer = Timer(debounce, () {
      state = PaletteQuery(typed: trimmed, settled: trimmed);
    });
  }
}

/// Auto-disposed: the next Ctrl+K starts empty.
final paletteQueryProvider =
    NotifierProvider.autoDispose<PaletteQueryController, PaletteQuery>(
      PaletteQueryController.new,
    );

/// Library matches for the settled query; null when there is nothing to
/// ask about.
final paletteHitsProvider = FutureProvider.autoDispose<SearchResults?>((
  ref,
) async {
  final query = ref.watch(paletteQueryProvider.select((q) => q.settled));
  if (query.isEmpty) return null;
  return ref
      .watch(repositoryProvider)
      .search(query, limit: kPaletteHitsPerKind);
});

/// Opens the palette. The host context is the root navigator's, because
/// a command runs after this closes and the surface that opened it may
/// be gone by then.
Future<void> showCommandPalette(BuildContext context) {
  final host = Navigator.of(context, rootNavigator: true).context;
  return showDialog<void>(
    context: context,
    builder: (_) => _CommandPaletteDialog(host: host),
  );
}

class _CommandPaletteDialog extends ConsumerWidget {
  const _CommandPaletteDialog({required this.host});

  final BuildContext host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(paletteQueryProvider);
    final hits = ref.watch(paletteHitsProvider);
    final entries = <String, void Function()>{};
    final groups = _groups(ref, query, hits.value, entries);

    return Align(
      // High rather than centred, so results grow into empty space.
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.all(WaxSpace.s16),
        child: WaxCommandPalette(
          groups: groups,
          busy: hits.isLoading,
          semanticsId: SemanticsIds.commandPalette,
          fieldSemanticsId: SemanticsIds.commandPaletteField,
          emptyTitle: query.typed.isEmpty
              ? 'Nothing to run'
              : 'Nothing matches "${query.typed}"',
          onQueryChanged: ref.read(paletteQueryProvider.notifier).type,
          onClose: () => Navigator.of(context).pop(),
          onRun: (id) {
            final run = entries[id];
            if (run == null) return;
            // Closed first: a command may open a sheet or a route, and
            // the pop only begins this route's exit, so the ref below is
            // still live.
            Navigator.of(context).pop();
            run();
          },
        ),
      ),
    );
  }

  /// Actions, then places, then settings, then the admin areas.
  /// [runners] is filled as rows are built, so a row can be reported by
  /// id rather than carrying a closure through the design system.
  List<WaxPaletteGroup> _groups(
    WidgetRef ref,
    PaletteQuery query,
    SearchResults? results,
    Map<String, void Function()> runners,
  ) {
    final needle = query.typed.toLowerCase();
    final chrome = ref.watch(shellChromeProvider);

    WaxPaletteEntry entry({
      required String id,
      required String label,
      String? detail,
      WaxGlyph? glyph,
      String? shortcut,
      required void Function() run,
    }) {
      runners[id] = run;
      return WaxPaletteEntry(
        id: id,
        label: label,
        detail: detail,
        glyph: glyph,
        shortcut: shortcut,
        semanticsId: SemanticsIds.commandPaletteEntry(id),
      );
    }

    final actions = <WaxPaletteEntry>[
      for (final command in _matchingCommands(ref, needle))
        entry(
          id: 'cmd-${command.id}',
          label: command.label,
          detail: command.section.title,
          glyph: command.glyph,
          shortcut: command.keys,
          run: () => command.run(host, ref),
        ),
    ];

    final places = <WaxPaletteEntry>[
      for (final target in chrome.visible)
        if (target.section != WaxNavSection.curation &&
            _matches(target.label, needle))
          entry(
            id: 'go-${target.name}',
            label: target.label,
            detail: 'Go to',
            glyph: target.glyph,
            run: () => host.go(target.location),
          ),
      // Beneath the destinations: a destination match is exact and a hit
      // is a guess.
      for (final hit in _hits(results))
        entry(
          id: 'hit-${hit.pid}',
          label: hit.title,
          detail: hit.subtitle,
          glyph: searchHitGlyph(hit.kind),
          run: () => openSearchHit(host, ref, hit),
        ),
      // The library search does not answer for stations. Read only once
      // something is typed, so opening the palette fetches nothing.
      if (needle.isNotEmpty)
        for (final station in _stations(ref, needle))
          entry(
            id: 'station-${station.pid}',
            label: station.name,
            detail: 'Radio station',
            glyph: WaxIcons.radio,
            run: () => unawaited(tuneStation(host, ref, station)),
          ),
      if (query.typed.isNotEmpty)
        entry(
          id: 'search-all',
          label: 'Search the library for "${query.typed}"',
          detail: 'Everything that matches',
          glyph: WaxIcons.search,
          run: () {
            ref.read(searchQueryProvider.notifier).submit(query.typed);
            host.go(WaxRoute.searchFor(query.typed));
          },
        ),
    ];

    final matchedSettings = searchSettings(
      query.typed,
      isAdmin: ref.watch(isAdminProvider),
      isNative: !kIsWeb,
      isDesktop: ref.watch(desktopProvider),
    );
    final settings = <WaxPaletteEntry>[
      for (final setting in matchedSettings.take(kPaletteSettingLimit))
        entry(
          id: 'set-${setting.id}',
          label: setting.title,
          detail: setting.section.title,
          glyph: setting.section.glyph,
          run: () => host.go(WaxRoute.settingsSection(setting.section)),
        ),
      // The cap says so. A settings search is screen state rather than a
      // location, so this row promises the screen, not the query.
      if (matchedSettings.length > kPaletteSettingLimit)
        entry(
          id: 'set-all',
          label: 'All settings',
          detail: '${matchedSettings.length} match "${query.typed}"',
          glyph: WaxIcons.settings,
          run: () => host.go(WaxRoute.settings),
        ),
    ];

    // Role-gated by construction: the chrome carries only what this
    // account may be offered.
    final admin = <WaxPaletteEntry>[
      for (final target in chrome.visible)
        if (target.section == WaxNavSection.curation &&
            _matches(target.label, needle))
          entry(
            id: 'go-${target.name}',
            label: target.label,
            detail: 'Curation',
            glyph: target.glyph,
            run: () => host.go(target.location),
          ),
    ];

    return <WaxPaletteGroup>[
      WaxPaletteGroup(title: 'Actions', entries: actions),
      WaxPaletteGroup(title: 'Go to', entries: places),
      WaxPaletteGroup(title: 'Settings', entries: settings),
      WaxPaletteGroup(title: 'Admin areas', entries: admin),
    ];
  }

  /// The commands that can run right now and whose names match, best
  /// first.
  List<WaxCommand> _matchingCommands(WidgetRef ref, String needle) {
    final starts = <WaxCommand>[];
    final contains = <WaxCommand>[];
    for (final command in ref.watch(commandRegistryProvider)) {
      if (!command.inPalette || !command.isEnabled(ref)) continue;
      final label = command.label.toLowerCase();
      if (needle.isEmpty || label.startsWith(needle)) {
        starts.add(command);
      } else if (label.contains(needle)) {
        contains.add(command);
      }
    }
    return <WaxCommand>[...starts, ...contains];
  }

  /// The stations whose names match. A list that has not loaded answers
  /// empty rather than making every query wait on it.
  List<RadioStation> _stations(WidgetRef ref, String needle) {
    final stations = ref.watch(radioStationsProvider).value;
    if (stations == null) return const <RadioStation>[];
    final matched = <RadioStation>[
      for (final station in stations)
        if (station.name.toLowerCase().contains(needle)) station,
    ];
    return matched.length <= kPaletteStationLimit
        ? matched
        : matched.sublist(0, kPaletteStationLimit);
  }

  /// The hits, round-robin by kind: a flat cut over the concatenation
  /// keeps the head, so several matching artists would leave no room for
  /// the album anybody was after.
  List<SearchHit> _hits(SearchResults? results) {
    if (results == null) return const <SearchHit>[];
    final byKind = <List<SearchHit>>[
      for (final kind in SearchHitKind.values) kind.from(results),
    ];
    final taken = <SearchHit>[];
    for (var depth = 0; depth < kPaletteHitsPerKind; depth++) {
      for (final hits in byKind) {
        if (depth >= hits.length) continue;
        taken.add(hits[depth]);
        if (taken.length == kPaletteHitLimit) return taken;
      }
    }
    return taken;
  }

  static bool _matches(String label, String needle) =>
      needle.isEmpty || label.toLowerCase().contains(needle);
}
