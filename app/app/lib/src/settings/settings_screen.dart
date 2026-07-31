import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'settings_registry.dart';

/// The settings home: a search field and the sections behind it.
///
/// Nine sections is more than anybody navigates by memory, so the field
/// is pinned at the top and the sections are what it falls back to. A
/// query matches leaf settings rather than sections, because "crossfade"
/// is what somebody types and "Playback" is what they would have to have
/// guessed.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final isAdmin = ref.watch(isAdminProvider);
    final query = _query.text;
    final results = searchSettings(query, isAdmin: isAdmin, isNative: !kIsWeb);
    final sections = <SettingsSection>[
      for (final section in SettingsSection.values)
        if (!section.adminOnly || isAdmin) section,
    ];

    return WaxScaffold(
      title: 'Settings',
      semanticsId: SemanticsIds.settingsScreen,
      slivers: <Widget>[
        SliverPadding(
          padding: sizeClass.gutter + const EdgeInsets.only(top: WaxSpace.s8),
          sliver: SliverToBoxAdapter(
            child: SearchField(
              controller: _query,
              hint: 'Search settings',
              label: 'Search settings',
              semanticsId: SemanticsIds.settingsSearch,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        if (query.trim().isNotEmpty)
          _Results(results: results, query: query)
        else
          SliverPadding(
            padding: sizeClass.gutter,
            sliver: SliverList.builder(
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                return WaxOptionRow(
                  title: section.title,
                  subtitle: section.blurb,
                  glyph: section.glyph,
                  semanticsId: SemanticsIds.settingsSection(section.segment),
                  trailing: const WaxIcon(WaxIcons.forward, size: 16),
                  // A section is a location a stranger can open, so it
                  // is gone to and takes its place beneath settings in
                  // the table rather than being pushed as an overlay.
                  onTap: () => context.go(WaxRoute.settingsSection(section)),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// What a query found, each row saying which section it lives in.
///
/// The section is on the row rather than being a heading over a group,
/// because the useful answer to "where is crossfade" is "Playback" said
/// next to it, and a result set of three rows under three headings is
/// mostly headings.
class _Results extends StatelessWidget {
  const _Results({required this.results, required this.query});

  final List<SettingEntry> results;
  final String query;

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    if (results.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          title: 'No setting matches "${query.trim()}"',
          message:
              'Server-wide settings live in the admin console, not here. '
              'A per-show or per-book setting is on that show or book.',
          glyph: WaxIcons.search,
        ),
      );
    }
    return SliverPadding(
      padding: sizeClass.gutter,
      sliver: SliverList.builder(
        itemCount: results.length,
        itemBuilder: (context, index) {
          final entry = results[index];
          return WaxOptionRow(
            title: entry.title,
            subtitle: entry.section.title,
            glyph: entry.section.glyph,
            semanticsId: SemanticsIds.settingsResult(entry.id),
            trailing: const WaxIcon(WaxIcons.forward, size: 16),
            onTap: () => context.go(WaxRoute.settingsSection(entry.section)),
          );
        },
      ),
    );
  }
}
