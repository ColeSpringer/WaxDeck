import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../player/deck_bar_host.dart';
import 'lifecycle_banners.dart';
import 'routes.dart';
import 'semantics_ids.dart';
import 'side_panel.dart';

/// Whether the adaptive shell is in charge of navigation.
///
/// Compile-time: `--dart-define=WAXDECK_NEW_SHELL=true` builds the new
/// shell, and every other build keeps the navigation that is on the
/// screens' own app bars. The flag exists only across the shell's
/// development window — the flip commit turns it on, deletes it, and
/// removes the old navigation with it — so no long-lived untested
/// configuration accumulates.
const bool waxNewShellDefault = bool.fromEnvironment('WAXDECK_NEW_SHELL');

/// The flag as a provider, so a test can mount either shell without a
/// second compilation of the app. Deleted with the flag.
final newShellProvider = Provider<bool>((ref) => waxNewShellDefault);

/// Where a target sits in the navigation chrome.
enum WaxNavSection {
  /// A domain: a tab at every width.
  primary,

  /// Not a tab. Listed in the sidebar under a rule, and behind the icon
  /// rail's overflow.
  secondary,

  /// Inside the curation group, and hidden from accounts that cannot use
  /// it.
  curation,
}

/// Every place the shell's chrome can send a visitor.
///
/// One list, so the chrome, the role gating, and the active-destination
/// highlight all read the same declaration. The four primaries are the
/// domains the plan gives tabs to; audiobooks joins them when there is a
/// books hub to send anyone to, and search and downloads when those
/// screens exist.
enum WaxNavTarget {
  home('Home', WaxIcons.home, WaxRoute.home, WaxNavSection.primary),

  /// Browse stands in until the music hub exists.
  music('Music', WaxIcons.music, WaxRoute.browse, WaxNavSection.primary),
  podcasts(
    'Podcasts',
    WaxIcons.podcasts,
    WaxRoute.podcasts,
    WaxNavSection.primary,
  ),
  radio('Radio', WaxIcons.radio, WaxRoute.radio, WaxNavSection.primary),

  playlists(
    'Playlists',
    WaxIcons.playlists,
    WaxRoute.playlists,
    WaxNavSection.secondary,
  ),
  stats(
    'Listening stats',
    WaxIcons.stats,
    WaxRoute.stats,
    WaxNavSection.secondary,
  ),
  settings(
    'Settings',
    WaxIcons.settings,
    WaxRoute.settings,
    WaxNavSection.secondary,
  ),

  uploads(
    'Uploads',
    WaxIcons.add,
    WaxRoute.uploads,
    WaxNavSection.curation,
    needsUpload: true,
  ),
  review(
    'Review queue',
    WaxIcons.check,
    WaxRoute.review,
    WaxNavSection.curation,
    adminOnly: true,
  ),
  health(
    'Health',
    WaxIcons.warning,
    WaxRoute.health,
    WaxNavSection.curation,
    adminOnly: true,
  ),
  diagnostics(
    'Diagnostics',
    WaxIcons.info,
    WaxRoute.diagnostics,
    WaxNavSection.curation,
    adminOnly: true,
  ),
  organize(
    'Organize',
    WaxIcons.sort,
    WaxRoute.organize,
    WaxNavSection.curation,
    adminOnly: true,
  ),
  // Gated on the upload right rather than the role: the endpoint serves
  // administrators every task and everyone else their own, and starting
  // one (an upload, an acquisition) is what needs the right. A listener
  // who can start none is the only account with nothing to see here.
  tasks(
    'Tasks',
    WaxIcons.refresh,
    WaxRoute.tasks,
    WaxNavSection.curation,
    needsUpload: true,
  ),
  users(
    'Users',
    WaxIcons.artists,
    WaxRoute.users,
    WaxNavSection.curation,
    adminOnly: true,
  ),
  audit(
    'Audit log',
    WaxIcons.recent,
    WaxRoute.audit,
    WaxNavSection.curation,
    adminOnly: true,
  ),
  backups(
    'Backups',
    WaxIcons.bookmark,
    WaxRoute.backups,
    WaxNavSection.curation,
    adminOnly: true,
  ),
  trash(
    'Trash',
    WaxIcons.delete,
    WaxRoute.trash,
    WaxNavSection.curation,
    adminOnly: true,
  ),
  migrate(
    'Import from another server',
    WaxIcons.downloads,
    WaxRoute.migrate,
    WaxNavSection.curation,
    adminOnly: true,
  );

  const WaxNavTarget(
    this.label,
    this.glyph,
    this.location,
    this.section, {
    this.adminOnly = false,
    this.needsUpload = false,
  });

  final String label;
  final WaxGlyph glyph;
  final String location;
  final WaxNavSection section;
  final bool adminOnly;

  /// Hidden without the effective upload right, which the server reports
  /// and administrators always hold. Without it the uploads screen is an
  /// empty list nothing can be done on.
  final bool needsUpload;

  /// Whether [user] may be offered this target at all. The server refuses
  /// the calls behind it regardless; this keeps the chrome honest.
  bool visibleTo(WaxDeckUser? user) {
    final isAdmin = user?.roles.contains('admin') ?? false;
    if (adminOnly && !isAdmin) return false;
    if (needsUpload && !(user?.uploadEnabled ?? false)) return false;
    return true;
  }

  WaxDestination get destination => WaxDestination(
    name: name,
    label: label,
    glyph: glyph,
    semanticsId: SemanticsIds.navDestination(name),
  );
}

/// The shell's branches, in the order the router declares them.
///
/// The index is the contract: `goBranch` takes a number, so this list and
/// the router's branch list are one declaration split in two, and
/// `route_table_test.dart` pins them together. Everything that is not a
/// domain shares the last branch, so switching to settings never rewrites
/// the stack a domain tab would restore.
const List<WaxNavTarget> waxShellBranches = <WaxNavTarget>[
  WaxNavTarget.home,
  WaxNavTarget.music,
  WaxNavTarget.podcasts,
  WaxNavTarget.radio,
];

/// Whether [location] is [base] or something declared beneath it.
bool _isUnder(String location, String base) =>
    base == WaxRoute.home || location == base || location.startsWith('$base/');

/// Which target the chrome shows as active: the longest declared location
/// this one sits under, with the branch on screen breaking the tie.
///
/// `/podcasts/pc-1` is Podcasts and `/books/bk-1` is Home, because home is
/// what every location sits under when nothing more specific claims it. A
/// curation area lights its own row rather than the tab whose branch
/// happens to declare it.
///
/// Home is the only target that claims a location by being home; every
/// other match is a prefix, which is the stronger signal. So a location
/// only home would claim goes to whichever branch [branchIndex] names —
/// `/episodes/:pid` is a podcasts location whose path cannot sit under
/// `/podcasts` (it names no show), and lighting Home while the podcasts
/// branch is on screen would have the chrome contradict the router. The
/// shared branch names no destination, so a location nothing there claims
/// lights nothing, which is honest: Home would be a lie about where the
/// visitor is.
WaxNavTarget? activeNavTarget(
  String location,
  Iterable<WaxNavTarget> targets, {
  int? branchIndex,
}) {
  WaxNavTarget? best;
  for (final target in targets) {
    if (!_isUnder(location, target.location)) continue;
    if (best == null || target.location.length > best.location.length) {
      best = target;
    }
  }
  if (best != WaxNavTarget.home || branchIndex == null) return best;
  return waxShellBranches.elementAtOrNull(branchIndex);
}

/// Whether the sidebar is collapsed to an icon rail.
///
/// In memory for now: this is a per-device client setting, and the store
/// that persists those lands with the settings phase.
class SidebarCollapsed extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final sidebarCollapsedProvider = NotifierProvider<SidebarCollapsed, bool>(
  SidebarCollapsed.new,
);

/// The shell: navigation chrome around the branch navigator that renders
/// the active screen.
///
/// It owns where a visitor can go and what is highlighted; the screens
/// still own their own app bars, because the bar is contextual per screen.
/// The deck bar and the side panel take their slots in the frame in the
/// next phase.
class AdaptiveShell extends ConsumerStatefulWidget {
  const AdaptiveShell({required this.shell, required this.location, super.key});

  final StatefulNavigationShell shell;

  /// The matched location, from the router rather than from a listener, so
  /// the highlight can never disagree with what is on screen.
  final String location;

  @override
  ConsumerState<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends ConsumerState<AdaptiveShell> {
  void _select(WaxNavTarget target) {
    final branch = waxShellBranches.indexOf(target);
    if (branch < 0) {
      // Everything else shares one branch, so a plain `go` puts it there
      // and the domain a visitor came from keeps the stack it had.
      context.go(target.location);
      return;
    }
    // Tapping the tab you are already on returns to its root, which is
    // the convention every tabbed app shares.
    widget.shell.goBranch(
      branch,
      initialLocation: branch == widget.shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value?.user;
    final visible = WaxNavTarget.values
        .where((target) => target.visibleTo(user))
        .toList();
    final byName = <String, WaxNavTarget>{
      for (final target in visible) target.name: target,
    };
    final curation = visible
        .where((target) => target.section == WaxNavSection.curation)
        .toList();

    final router = GoRouter.of(context);
    final frame = WaxShellFrame(
      destinations: <WaxDestination>[
        for (final target in visible)
          if (target.section == WaxNavSection.primary) target.destination,
      ],
      secondary: <WaxNavEntry>[
        for (final target in visible)
          if (target.section == WaxNavSection.secondary)
            WaxNavLink(target.destination),
        if (curation.isNotEmpty)
          WaxNavGroup(
            label: 'Curation',
            glyph: WaxIcons.admin,
            semanticsId: SemanticsIds.navGroup('curation'),
            children: <WaxDestination>[
              for (final target in curation) target.destination,
            ],
          ),
      ],
      selected: activeNavTarget(
        widget.location,
        visible,
        // The branch on screen, so a location no destination claims by
        // prefix still lights the domain that is showing it.
        branchIndex: widget.shell.currentIndex,
      )?.name,
      onSelect: (name) {
        final target = byName[name];
        if (target != null) _select(target);
      },
      // The brand today; the search field takes this slot when there is a
      // search screen to drive.
      sidebarHeader: const WaxWordmark(size: 20),
      collapsed: ref.watch(sidebarCollapsedProvider),
      onToggleCollapsed: ref.read(sidebarCollapsedProvider.notifier).toggle,
      navSemanticsId: SemanticsIds.navRegion,
      collapseSemanticsId: SemanticsIds.navSidebarCollapse,
      overflowSemanticsId: SemanticsIds.navOverflow,
      // Playback's one home on every screen, outside the branch
      // navigators so it survives every navigation, and the panel it
      // opens beside the content where there is room for one.
      bottom: const DeckBarHost(),
      panel: shellSidePanel(ref),
      banners: lifecycleBanners(ref),
      content: widget.shell,
    );

    // Android convention: back leaves a drilled-in screen first, then
    // steps from a domain tab to home once, and only then leaves the app.
    //
    // Through the router's back-button dispatcher rather than a
    // `PopScope`. A PopScope here registers with the shell page's route,
    // and `popRoute` walks the navigator chain from the root down, halting
    // at a shell navigator whose enclosing route is not current — which is
    // the state a branch lands in after it has been drilled into and
    // stepped back out of, so the scope is simply never consulted and the
    // press reaches the platform from a domain root. The dispatcher is
    // consulted before any of that walk, and `canPop` is read when the
    // press happens rather than during a build that may not run again.
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (router.canPop() || widget.shell.currentIndex == 0) return false;
        widget.shell.goBranch(0);
        return true;
      },
      child: frame,
    );
  }
}
