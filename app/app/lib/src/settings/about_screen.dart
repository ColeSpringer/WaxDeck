import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/app_version.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// The server's own version, read once per settings visit.
///
/// `GET /health` is unauthenticated and cheap, and the numbers on it are
/// the first thing anybody filing a bug is asked for.
final serverHealthProvider = FutureProvider<ServerHealth>(
  (ref) => ref.watch(repositoryProvider).health(),
);

/// The row that opens About, for the two places that offer it.
///
/// Account has it because that is where the blueprint puts it and where a
/// listener looks; the Server section has it because an administrator
/// reading about this instance wants the version without going back.
class AboutRow extends ConsumerWidget {
  const AboutRow({required this.semanticsId, super.key});

  final String semanticsId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(serverHealthProvider).value;
    final l10n = context.l10n;
    return WaxOptionRow(
      title: l10n.aboutRowTitle,
      subtitle: health == null
          ? l10n.aboutRowVersion(kAppVersion)
          : l10n.aboutRowVersions(kAppVersion, health.version),
      glyph: WaxIcons.info,
      semanticsId: SemanticsIds.setting(semanticsId),
      trailing: const WaxIcon(WaxIcons.forward, size: 16),
      // Gone to, not pushed. About answers 8.3's question the same way a
      // section does - a stranger opening the location gets the page -
      // so it is a link, it survives a reload, and the route table
      // covers it. Back lands on the settings home rather than on the
      // section it was opened from, which is what a location declared
      // beneath `/settings` means and is true of every section too.
      onTap: () => context.go(WaxRoute.settingsAbout),
    );
  }
}

/// What this build is, what it is talking to, and what it is made of.
///
/// Self-hosters check this page: when something misbehaves, the two
/// versions and the API number are the whole of what a bug report needs,
/// and a page that reports them costs an hour to write and saves an
/// exchange every time.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final health = ref.watch(serverHealthProvider);
    // About is one tap from Account, which spaces at the section gap, so
    // it takes the same rhythm rather than a hand-written neighbour of it.
    final sectionGap = WaxLayout.of(context).sectionGap;
    final l10n = context.l10n;
    return WaxScaffold(
      title: l10n.aboutTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.aboutOpen,
      onBack: () => context.leave(fallback: WaxRoute.settings),
      slivers: <Widget>[
        SliverPadding(
          padding: sizeClass.gutter,
          sliver: SliverToBoxAdapter(
            child: ReadingColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(height: sectionGap),
                  const WaxWordmark(),
                  const SizedBox(height: WaxSpace.s8),
                  Text(
                    l10n.aboutTagline,
                    style: WaxType.body.copyWith(
                      color: WaxColors.of(context).textSecondary,
                    ),
                  ),
                  SizedBox(height: sectionGap),
                  SectionHeader(title: l10n.aboutVersionsTitle),
                  MonoDetailRow(
                    label: l10n.aboutVersionApp,
                    value: appVersionLabel,
                  ),
                  switch (health) {
                    AsyncData(:final value) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        MonoDetailRow(
                          label: l10n.aboutVersionServer,
                          value: value.version,
                        ),
                        MonoDetailRow(
                          label: l10n.aboutVersionApi,
                          value: 'v${value.apiVersion}',
                        ),
                      ],
                    ),
                    // Not an error state: this page's job is to report
                    // the app's own version, and it still can.
                    AsyncError() => MonoDetailRow(
                      label: l10n.aboutVersionServer,
                      value: l10n.aboutServerUnreachable,
                    ),
                    _ => MonoDetailRow(
                      label: l10n.aboutVersionServer,
                      value: '...',
                    ),
                  },
                  SizedBox(height: sectionGap),
                  SectionHeader(title: l10n.aboutLicensingTitle),
                  WaxOptionRow(
                    title: l10n.aboutLicenses,
                    subtitle: l10n.aboutLicensesSubtitle,
                    glyph: WaxIcons.info,
                    semanticsId: SemanticsIds.aboutLicenses,
                    trailing: const WaxIcon(WaxIcons.forward, size: 16),
                    // Flutter's own license page, which reads the NOTICES
                    // every package's LICENSE is folded into at build
                    // time - so the OFL texts for the bundled faces and
                    // the icon set's MIT notice arrive here without this
                    // screen collecting them: they are in waxdeck_ui's
                    // package LICENSE, which is what conveys them.
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'WaxDeck',
                      applicationVersion: appVersionLabel,
                    ),
                  ),
                  SizedBox(height: sectionGap),
                  SectionHeader(title: l10n.aboutDiagnosticsTitle),
                  WaxOptionRow(
                    title: l10n.defectsTitle,
                    subtitle: l10n.aboutDefectsSubtitle,
                    glyph: WaxIcons.warning,
                    semanticsId: SemanticsIds.aboutDefects,
                    trailing: const WaxIcon(WaxIcons.forward, size: 16),
                    // A location beneath this one, so the same reasoning
                    // as the About row above: it can be linked to.
                    onTap: () => context.go(WaxRoute.settingsDefects),
                  ),
                  const SizedBox(height: WaxSpace.s32),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
