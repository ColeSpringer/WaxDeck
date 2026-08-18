import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../settings/settings_registry.dart';
import '../shell/forbidden_page.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// Where a console section sits in the console's own navigation.
enum AdminGroup {
  /// The dashboard. Not in a group: it is the console's own front page.
  overview,

  /// What is in the library and what shape it is in.
  library,

  /// Accounts and the invitations that make them.
  people,

  /// The instance itself: what it is set to, what it keeps, what it did.
  server;

  String labelOf(AppLocalizations l10n) => switch (this) {
    overview => l10n.adminGroupOverview,
    library => l10n.adminGroupLibrary,
    people => l10n.adminGroupPeople,
    server => l10n.adminGroupServer,
  };
}

/// Every surface the admin console holds.
///
/// One declaration, because the second-level sidebar, the compact list,
/// the active-section highlight, and the router's own table all have to
/// agree about what the console is. A section that existed only in the
/// router would be a page nothing links to; one that existed only here
/// would be a link to nowhere.
enum AdminSection {
  dashboard(WaxIcons.stats, WaxRoute.admin, AdminGroup.overview),
  libraries(WaxIcons.albums, WaxRoute.libraries, AdminGroup.library),
  health(WaxIcons.warning, WaxRoute.health, AdminGroup.library),
  diagnostics(WaxIcons.info, WaxRoute.diagnostics, AdminGroup.library),
  genres(WaxIcons.filter, WaxRoute.genres, AdminGroup.library),
  organize(WaxIcons.sort, WaxRoute.organize, AdminGroup.library),
  users(WaxIcons.artists, WaxRoute.users, AdminGroup.people),
  shares(WaxIcons.share, WaxRoute.adminShares, AdminGroup.people),
  settings(WaxIcons.settings, WaxRoute.adminSettings, AdminGroup.server),
  notifications(WaxIcons.bell, WaxRoute.adminNotifications, AdminGroup.server),
  schedules(WaxIcons.recent, WaxRoute.schedules, AdminGroup.server),
  backups(WaxIcons.bookmark, WaxRoute.backups, AdminGroup.server),
  trash(WaxIcons.delete, WaxRoute.trash, AdminGroup.server),
  audit(WaxIcons.info, WaxRoute.audit, AdminGroup.server),
  migrate(WaxIcons.downloads, WaxRoute.migrate, AdminGroup.server);

  const AdminSection(this.glyph, this.location, this.group);

  final WaxGlyph glyph;
  final String location;
  final AdminGroup group;

  /// The section's own name.
  ///
  /// Most read the same key as the screen they open, so a link and its
  /// page cannot drift apart. Two do not, and deliberately: the console
  /// front page is "Dashboard" in a list of sections and "Admin" as a
  /// page title, and the health screen is "Health" beside its siblings
  /// and "Library health" at the top of its own page.
  String titleOf(AppLocalizations l10n) => switch (this) {
    dashboard => l10n.adminSectionDashboard,
    libraries => l10n.adminLibrariesTitle,
    health => l10n.adminSectionHealth,
    diagnostics => l10n.adminSectionDiagnostics,
    genres => l10n.adminGenreTreeTitle,
    organize => l10n.adminSectionOrganize,
    users => l10n.adminUsersTitle,
    shares => l10n.adminSectionShares,
    settings => l10n.adminServerTitle,
    notifications => l10n.adminSectionNotifications,
    schedules => l10n.adminSchedulesTitle,
    backups => l10n.adminBackupsTitle,
    trash => l10n.adminTrashTitle,
    audit => l10n.adminSectionAudit,
    migrate => l10n.adminMigrateTitle,
  };

  /// The line under the section's name on the compact list. The sidebar
  /// draws the title alone.
  String blurbOf(AppLocalizations l10n) => switch (this) {
    dashboard => l10n.adminSectionDashboardBlurb,
    libraries => l10n.adminSectionLibrariesBlurb,
    health => l10n.adminSectionHealthBlurb,
    diagnostics => l10n.adminSectionDiagnosticsBlurb,
    genres => l10n.adminSectionGenresBlurb,
    organize => l10n.adminSectionOrganizeBlurb,
    users => l10n.adminSectionUsersBlurb,
    shares => l10n.adminSectionSharesBlurb,
    settings => l10n.adminSectionSettingsBlurb,
    notifications => l10n.adminSectionNotificationsBlurb,
    schedules => l10n.adminSectionSchedulesBlurb,
    backups => l10n.adminSectionBackupsBlurb,
    trash => l10n.adminSectionTrashBlurb,
    audit => l10n.adminSectionAuditBlurb,
    migrate => l10n.adminSectionMigrateBlurb,
  };

  String get semanticsId => SemanticsIds.adminSection(name);

  /// The section a console location belongs to: the longest declared
  /// location it sits under.
  ///
  /// A prefix match rather than equality, so `/admin/health/missing-art`
  /// keeps Health lit while a drill-in is open. The dashboard's own
  /// location is a prefix of every other one, so it wins only when
  /// nothing longer matches - which is what makes `/admin` itself the
  /// dashboard and `/admin/trash` the trash.
  static AdminSection? forLocation(String location) {
    AdminSection? best;
    for (final section in values) {
      final at = section.location;
      if (location != at && !location.startsWith('$at/')) continue;
      if (best == null || at.length > best.location.length) best = section;
    }
    return best;
  }
}

/// The console's frame: a section list beside the page where there is
/// room for one, and the page alone where there is not.
///
/// Wrapped around every `/admin` route rather than built into each
/// screen, so the section list keeps its scroll position and its
/// highlight across a move between sections, and a screen only has to
/// know how to be a page.
class AdminConsole extends ConsumerWidget {
  const AdminConsole({required this.child, required this.location, super.key});

  final Widget child;

  /// The matched location, from the router rather than a listener, so the
  /// highlight cannot disagree with what is on screen.
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Refused here rather than redirected in the router, which is the
    // decision this frame exists to hold: the chrome already hides what
    // an account cannot use and the server refuses every call behind it,
    // but neither covers a pasted link, and a member following one used
    // to get the whole console with panels that all answer 403.
    // `ForbiddenPage` carries the rest of the argument.
    if (!ref.watch(isAdminProvider)) return const _AdminForbidden();
    final sizeClass = WaxSizeClass.of(context);
    // Below sidebar width the console is one screen at a time: the
    // dashboard is the list of sections, and a section is a page with a
    // way back to it. A rail here would spend a phone's width on
    // navigation the page underneath already has.
    if (!sizeClass.hasSidebar) return child;
    final colors = WaxColors.of(context);
    return Semantics(
      identifier: SemanticsIds.adminConsole,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionList(location: location),
          VerticalDivider(width: 1, color: colors.hairline),
          // A boundary, like the shell frame's content region: `child` is
          // a navigator, and the `ModalBarrier` in its route would
          // otherwise block the section list painted before it.
          Expanded(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// What an account without the role gets at a console location.
///
/// A whole screen rather than an empty console: the section list beside
/// it would be a set of rows that all refuse, which is a worse answer
/// than one sentence.
class _AdminForbidden extends StatelessWidget {
  const _AdminForbidden();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ForbiddenPage(
      // The area's name rather than the page's: the refusal is the same
      // one at every console location, and "Dashboard" would name a
      // screen that is not being shown.
      pageTitle: l10n.shellNavAdmin,
      heading: l10n.adminForbiddenTitle,
      message: l10n.adminForbiddenMessage,
      glyph: WaxIcons.admin,
      semanticsId: SemanticsIds.adminForbidden,
    );
  }
}

/// The console's second-level navigation, grouped.
class _SectionList extends StatelessWidget {
  const _SectionList({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final active = AdminSection.forLocation(location);
    return Container(
      width: 224,
      color: colors.surface1,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: WaxSpace.s16),
        children: <Widget>[
          for (final group in AdminGroup.values) ...<Widget>[
            if (group != AdminGroup.overview)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WaxSpace.s16,
                  WaxSpace.s16,
                  WaxSpace.s16,
                  WaxSpace.s4,
                ),
                child: Text(
                  group.labelOf(l10n),
                  style: WaxType.overline.copyWith(color: colors.textTertiary),
                ),
              ),
            for (final section in AdminSection.values)
              if (section.group == group)
                _SectionRow(section: section, selected: section == active),
          ],
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section, required this.selected});

  final AdminSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final title = section.titleOf(context.l10n);
    final tint = selected ? colors.accent : colors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
      child: WaxTappable(
        label: title,
        semanticsId: section.semanticsId,
        selected: selected,
        borderRadius: WaxRadius.chip,
        surface: colors.surface1,
        onPressed: () => context.go(section.location),
        child: Material(
          color: selected ? colors.accentContainer : Colors.transparent,
          borderRadius: WaxRadius.chip,
          child: InkWell(
            onTap: () => context.go(section.location),
            borderRadius: WaxRadius.chip,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WaxSpace.s12,
                vertical: WaxSpace.s8,
              ),
              child: Row(
                children: <Widget>[
                  WaxIcon(
                    section.glyph,
                    size: 16,
                    color: selected ? colors.onAccentContainer : tint,
                  ),
                  const SizedBox(width: WaxSpace.s12),
                  Expanded(
                    child: Text(
                      title,
                      style: WaxType.label.copyWith(
                        color: selected
                            ? colors.onAccentContainer
                            : colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a console page's back control does below sidebar width.
///
/// The console is a stack on a phone (`/admin` lists the sections, a
/// section is a page on top), and one pane on a desktop, where the
/// section list is always there and a back arrow would be a control
/// pointing at what is already beside it.
VoidCallback? adminBack(BuildContext context) =>
    WaxSizeClass.of(context).hasSidebar
    ? null
    : () => context.leave(fallback: WaxRoute.admin);
