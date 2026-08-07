import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// Where a console section sits in the console's own navigation.
enum AdminGroup {
  /// The dashboard. Not in a group: it is the console's own front page.
  overview('Overview'),

  /// What is in the library and what shape it is in.
  library('Library'),

  /// Accounts and the invitations that make them.
  people('People'),

  /// The instance itself: what it is set to, what it keeps, what it did.
  server('Server');

  const AdminGroup(this.label);

  final String label;
}

/// Every surface the admin console holds.
///
/// One declaration, because the second-level sidebar, the compact list,
/// the active-section highlight, and the router's own table all have to
/// agree about what the console is. A section that existed only in the
/// router would be a page nothing links to; one that existed only here
/// would be a link to nowhere.
enum AdminSection {
  dashboard(
    'Dashboard',
    'What needs attention, and what is running',
    WaxIcons.stats,
    WaxRoute.admin,
    AdminGroup.overview,
  ),
  libraries(
    'Libraries',
    'The roots WaxDeck scans, and what each one holds',
    WaxIcons.albums,
    WaxRoute.libraries,
    AdminGroup.library,
  ),
  review(
    'Review queue',
    'Albums waiting for an identification decision',
    WaxIcons.check,
    WaxRoute.review,
    AdminGroup.library,
  ),
  health(
    'Health',
    'What is missing, mistagged, or duplicated',
    WaxIcons.warning,
    WaxRoute.health,
    AdminGroup.library,
  ),
  diagnostics(
    'Diagnostics',
    'Files the catalog could not read',
    WaxIcons.info,
    WaxRoute.diagnostics,
    AdminGroup.library,
  ),
  genres(
    'Genre tree',
    'The canonical vocabulary every genre folds onto',
    WaxIcons.filter,
    WaxRoute.genres,
    AdminGroup.library,
  ),
  organize(
    'Organize',
    'Move files into a naming scheme',
    WaxIcons.sort,
    WaxRoute.organize,
    AdminGroup.library,
  ),
  users(
    'Users',
    'Accounts, invites, and what each one may do',
    WaxIcons.artists,
    WaxRoute.users,
    AdminGroup.people,
  ),
  settings(
    'Server settings',
    'Signups, read-only mode, transcoding, retention',
    WaxIcons.settings,
    WaxRoute.adminSettings,
    AdminGroup.server,
  ),
  notifications(
    'Notifications',
    'Where this server reports operations events',
    WaxIcons.bell,
    WaxRoute.adminNotifications,
    AdminGroup.server,
  ),
  schedules(
    'Schedules',
    'When scans, backups, and pruning run',
    WaxIcons.recent,
    WaxRoute.schedules,
    AdminGroup.server,
  ),
  backups(
    'Backups',
    'Archives, imports, and staged restores',
    WaxIcons.bookmark,
    WaxRoute.backups,
    AdminGroup.server,
  ),
  trash(
    'Trash',
    'Deleted files, until they are purged',
    WaxIcons.delete,
    WaxRoute.trash,
    AdminGroup.server,
  ),
  audit(
    'Audit log',
    'Who did what, and to what',
    WaxIcons.info,
    WaxRoute.audit,
    AdminGroup.server,
  ),
  migrate(
    'Import from another server',
    'Bring a library, its stars, and its history across',
    WaxIcons.downloads,
    WaxRoute.migrate,
    AdminGroup.server,
  );

  const AdminSection(
    this.title,
    this.blurb,
    this.glyph,
    this.location,
    this.group,
  );

  final String title;

  /// The line under the section's name on the compact list. The sidebar
  /// draws the title alone.
  final String blurb;

  final WaxGlyph glyph;
  final String location;
  final AdminGroup group;

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
class AdminConsole extends StatelessWidget {
  const AdminConsole({required this.child, required this.location, super.key});

  final Widget child;

  /// The matched location, from the router rather than a listener, so the
  /// highlight cannot disagree with what is on screen.
  final String location;

  @override
  Widget build(BuildContext context) {
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

/// The console's second-level navigation, grouped.
class _SectionList extends StatelessWidget {
  const _SectionList({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
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
                  group.label,
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
    final tint = selected ? colors.accent : colors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
      child: WaxTappable(
        label: section.title,
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
                      section.title,
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
