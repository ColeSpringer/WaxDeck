import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show ClientSettingKeys;
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../player/deck_bar_host.dart';
import '../providers.dart';
import '../search/search_controller.dart';
import '../settings/client_settings_providers.dart';
import '../sync/sync_providers.dart';
import 'lifecycle_banners.dart';
import 'routes.dart';
import 'semantics_ids.dart';
import 'shell_messages.dart';
import 'side_panel.dart';

/// Where a target sits in the navigation chrome.
enum WaxNavSection {
  /// A domain: a tab at every width.
  primary,

  /// A way into a domain the sidebar lists beneath its hub. Not a tab and
  /// not in the overflow: the hub itself offers every one of them, so
  /// narrower chrome spends its room on destinations that are reachable
  /// nowhere else.
  domainIndex,

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

  music('Music', WaxIcons.music, WaxRoute.music, WaxNavSection.primary),

  // The ways into music, in the order the hub's tiles list them. They sit
  // under Music in the sidebar; everywhere else the hub is the way to
  // them, which is why they are not tabs and not in the rail's overflow.
  artists(
    'Artists',
    WaxIcons.artists,
    '${WaxRoute.music}/artists',
    WaxNavSection.domainIndex,
  ),
  albums(
    'Albums',
    WaxIcons.albums,
    '${WaxRoute.music}/albums',
    WaxNavSection.domainIndex,
  ),
  tracks(
    'Tracks',
    WaxIcons.music,
    WaxRoute.musicTracks,
    WaxNavSection.domainIndex,
  ),
  genres(
    'Genres',
    WaxIcons.filter,
    '${WaxRoute.music}/genres',
    WaxNavSection.domainIndex,
  ),
  years(
    'Years',
    WaxIcons.recent,
    '${WaxRoute.music}/years',
    WaxNavSection.domainIndex,
  ),
  // Playlists moves under Music now that there is a group to hold it. It
  // is a way into the collection like the others, and the hub lists it
  // beside them.
  playlists(
    'Playlists',
    WaxIcons.playlists,
    WaxRoute.playlists,
    WaxNavSection.domainIndex,
  ),

  podcasts(
    'Podcasts',
    WaxIcons.podcasts,
    WaxRoute.podcasts,
    WaxNavSection.primary,
  ),
  // "Books" rather than "Audiobooks" on the chrome, which is what the
  // layout system's own tab row says: five labels share a phone's width,
  // and the hub's own title is where the long name belongs.
  books(
    'Books',
    WaxIcons.audiobooks,
    WaxRoute.books,
    WaxNavSection.primary,
    hidesWhenEmpty: true,
  ),
  radio('Radio', WaxIcons.radio, WaxRoute.radio, WaxNavSection.primary),

  stats(
    'Listening stats',
    WaxIcons.stats,
    WaxRoute.stats,
    WaxNavSection.secondary,
  ),
  // Native only: the web build keeps nothing offline, so there is no
  // manager to reach and the destination is not offered.
  downloads(
    'Downloads',
    WaxIcons.downloads,
    WaxRoute.downloads,
    WaxNavSection.secondary,
    needsDownloads: true,
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
  // The review queue keeps a shell entry of its own as well as a place
  // in the console: it is the surface an administrator opens daily, and
  // burying the keyboard-first screen one level deeper to tidy the group
  // would cost more than the tidiness is worth.
  review(
    'Review queue',
    WaxIcons.check,
    WaxRoute.review,
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
  // One entry for the console, which is where the other nine
  // administrative surfaces live now. They were nine sidebar rows in a
  // Curation group that told nobody how they related; the console's own
  // section list groups them and says what each is for.
  admin(
    'Admin console',
    WaxIcons.admin,
    WaxRoute.admin,
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
    this.needsDownloads = false,
    this.hidesWhenEmpty = false,
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

  /// Hidden where this build keeps nothing offline (web). Not a
  /// permission: it is a platform capability, and the screen behind it
  /// has no data source at all there.
  final bool needsDownloads;

  /// Hidden while the server has nothing behind it.
  ///
  /// The layout system's rule: a domain tab goes away where the library
  /// holds none of that medium, and home absorbs the gap. Only
  /// audiobooks gates on it so far - a tab per medium is what makes the
  /// count tight on a phone, and books is the medium a library most
  /// often has none of. Podcasts and Radio stay unconditional until
  /// their own phases have a count to gate on.
  final bool hidesWhenEmpty;

  /// Whether [user] may be offered this target at all. The server refuses
  /// the calls behind it regardless; this keeps the chrome honest.
  ///
  /// [emptyDomains] names the domains a probe has found nothing for.
  /// Absence means "not answered yet", which shows the tab: a tab that
  /// arrives late shifts the row under a thumb already moving, and the
  /// libraries that would gain one are the ones nobody is aiming at it
  /// on.
  bool visibleTo(
    WaxDeckUser? user, {
    bool hasDownloads = false,
    Set<WaxNavTarget> emptyDomains = const <WaxNavTarget>{},
  }) {
    final isAdmin = user?.roles.contains('admin') ?? false;
    if (adminOnly && !isAdmin) return false;
    if (needsUpload && !(user?.uploadEnabled ?? false)) return false;
    if (needsDownloads && !hasDownloads) return false;
    if (hidesWhenEmpty && emptyDomains.contains(this)) return false;
    return true;
  }

  /// The indexes the sidebar lists beneath this target, for the domains
  /// that have any.
  List<WaxNavTarget> get indexes => this == WaxNavTarget.music
      ? WaxNavTarget.values
            .where((t) => t.section == WaxNavSection.domainIndex)
            .toList()
      : const <WaxNavTarget>[];

  WaxDestination get destination => WaxDestination(
    name: name,
    label: label,
    glyph: glyph,
    semanticsId: SemanticsIds.navDestination(name),
    discloseSemanticsId: SemanticsIds.navDisclose(name),
    children: <WaxDestination>[for (final index in indexes) index.destination],
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
  WaxNavTarget.books,
  WaxNavTarget.radio,
];

/// The domains the server has nothing behind, probed once per session.
///
/// One cheap request per gating domain, cached for the app's lifetime
/// rather than auto-disposed: the answer is a property of the library,
/// the chrome asks on every build, and a library does not gain its first
/// audiobook while somebody is looking at the tab bar. A catalog
/// invalidation is what refreshes it (`sync_binder` drops it), which is
/// also what makes a first scan's books turn the tab on without a
/// relaunch.
final emptyDomainsProvider = FutureProvider<Set<WaxNavTarget>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  final empty = <WaxNavTarget>{};
  // One item is all the question needs: the tab is about whether there
  // is anything at all, not about how much.
  final books = await repository.listItems(
    mediaType: MediaType.audiobook,
    limit: 1,
  );
  if (books.items.isEmpty) empty.add(WaxNavTarget.books);
  return empty;
});

/// Whether [location] is [base] or something declared beneath it.
bool _isUnder(String location, String base) =>
    base == WaxRoute.home || location == base || location.startsWith('$base/');

/// Which target the chrome shows as active: the longest declared location
/// this one sits under, with the branch on screen breaking the tie.
///
/// `/podcasts/pc-1` is Podcasts and `/books/bk-1` is Books, each claimed
/// by prefix. A curation area lights its own row rather than the tab whose
/// branch happens to declare it.
///
/// Home is the only target that claims a location by being home; every
/// other match is a prefix, which is the stronger signal. So a location
/// only home would claim goes to whichever branch [branchIndex] names -
/// the show-less `/episodes/:pid`, which a search hit opens because it
/// has no show to name, is a podcasts location whose path cannot sit
/// under `/podcasts`, and lighting Home while the podcasts branch is on
/// screen would have the chrome contradict the router. The shared branch
/// names no destination, so a location nothing there claims lights
/// nothing, which is honest: Home would be a lie about where the visitor
/// is.
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
/// A per-device preference: a rail is a choice about this screen and
/// this pointer, not something to carry to a listener's phone. Stored
/// where those go, so the first frame is drawn expanded and
/// collapses once the read lands - a launch does not wait on a disk to
/// lay itself out.
class SidebarCollapsed extends Notifier<bool> with StoredSetting<bool> {
  @override
  String get settingKey => ClientSettingKeys.sidebarCollapsed;

  @override
  bool get defaultValue => false;

  @override
  bool? decode(String raw) => switch (raw) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  @override
  String encode(bool value) => '$value';

  @override
  bool build() => hydrate();

  void toggle() => put(!state);
}

final sidebarCollapsedProvider = NotifierProvider<SidebarCollapsed, bool>(
  SidebarCollapsed.new,
);

/// What the account menu can do, as opposed to where it can send you.
///
/// One entry today. It is an enum rather than a string so the shell's
/// switch stays exhaustive as the menu grows.
enum WaxAccountVerb {
  signOut('Sign out', WaxIcons.close);

  const WaxAccountVerb(this.label, this.glyph);

  final String label;
  final WaxGlyph glyph;

  WaxAccountAction get action => WaxAccountAction(
    name: name,
    label: label,
    glyph: glyph,
    semanticsId: SemanticsIds.navAccountAction(name),
  );

  /// The verb the menu reported, or null if it named one this build does
  /// not have.
  ///
  /// The menu can only report a name this enum minted - the design
  /// system carries the actions it is handed and invents none - so a
  /// miss is a programming error rather than input. It is looked up
  /// rather than resolved by `byName` because the callback that runs it
  /// is fired and forgotten from a menu, where a throw has no handler at
  /// all; the assert is what makes it loud in development.
  static WaxAccountVerb? named(String name) {
    final verb = values.asNameMap()[name];
    assert(verb != null, 'the account menu reported an unknown verb: $name');
    return verb;
  }
}

/// What the chrome offers this session, in one declaration.
///
/// The shell frame is not the only thing that draws it: the account menu
/// lives in each tab root's own top app bar below rail width (3.2), and
/// there it is the only route to the destinations that are not domains.
/// Two places computing "which targets is this account allowed, and what
/// does its menu carry" would be two places to get role gating wrong, so
/// they read this.
class ShellChrome {
  const ShellChrome({
    required this.visible,
    required this.byName,
    required this.destinations,
    required this.secondary,
    required this.account,
  });

  /// Every target this account may be offered, in declaration order.
  final List<WaxNavTarget> visible;

  final Map<String, WaxNavTarget> byName;

  /// The domains, as the tabs, rail, and sidebar draw them.
  final List<WaxDestination> destinations;

  /// Everything that is not a domain, as menu entries.
  final List<WaxNavEntry> secondary;

  final WaxAccount account;
}

/// The chrome for the signed-in account.
///
/// Never withholds the account menu for want of a name. `SessionInfo`
/// requires only `authenticated`, so a session with no user payload is a
/// legal answer, and the redirect that decides what is reachable gates on
/// that flag alone. Hiding the menu there would leave a phone with no
/// route to settings and no way to sign out, which is a worse answer than
/// a disc with no initial on it.
final shellChromeProvider = Provider.autoDispose<ShellChrome>((ref) {
  final user = ref.watch(authControllerProvider).value?.user;
  final hasDownloads = ref.watch(downloadManagerProvider) != null;
  final empty = ref.watch(emptyDomainsProvider).value ?? const <WaxNavTarget>{};
  final visible = WaxNavTarget.values
      .where(
        (target) => target.visibleTo(
          user,
          hasDownloads: hasDownloads,
          emptyDomains: empty,
        ),
      )
      .toList();
  final curation = visible
      .where((target) => target.section == WaxNavSection.curation)
      .toList();
  return ShellChrome(
    visible: visible,
    byName: <String, WaxNavTarget>{
      for (final target in visible) target.name: target,
    },
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
    account: WaxAccount(
      name: user?.username ?? '',
      actions: <WaxAccountAction>[
        for (final verb in WaxAccountVerb.values) verb.action,
      ],
      semanticsId: SemanticsIds.navAccount,
    ),
  );
});

/// Runs an account verb, from whichever chrome reported it.
void runAccountVerb(WidgetRef ref, WaxAccountVerb verb) {
  switch (verb) {
    // Nothing to unwind by hand: dropping the session moves the auth
    // redirect, which replaces the whole signed-in stack with login.
    case WaxAccountVerb.signOut:
      ref.read(authControllerProvider.notifier).logout();
  }
}

/// Goes to a target the account menu named.
///
/// A plain `go`, never `goBranch`: the menu only ever carries what is not
/// a domain, and everything that is not a domain shares one branch, so
/// the domain the visitor came from keeps the stack it had.
void goToNavTarget(BuildContext context, WaxNavTarget? target) {
  if (target != null) context.go(target.location);
}

/// The shell: navigation chrome around the branch navigator that renders
/// the active screen.
///
/// It owns where a visitor can go and what is highlighted; the screens
/// still own their own app bars, because the bar is contextual per screen.
/// The deck bar and the side panel take their slots in the frame.
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
  /// The action of the last message raised, so a repeat of the same
  /// offer replaces its predecessor rather than queueing behind it.
  String? _lastRaised;

  /// The sidebar header's search field, owned here and nowhere else.
  ///
  /// They belong to the shell frame, above the routed navigator, and that
  /// is the whole reason the live field works: results swap in underneath
  /// while the field keeps its focus and its cursor. Owned by anything
  /// the router rebuilds and every keystroke would drop focus, which is
  /// worse than the launcher this replaces.
  final TextEditingController _searchField = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'shell-search');

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocus);
    // Seeded, not left empty: `_listenForQuery` below only fires on a
    // change, so a shell built over a query that was already set - a deep
    // link the router resolved before this State existed - would draw an
    // empty header field over somebody's results.
    _searchField.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocus);
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Opens the search screen when the field takes the caret.
  ///
  /// On focus rather than on the first keystroke, which is the whole
  /// answer to the bug: the header used to be a launcher that navigated
  /// on click and left the field somebody was already aiming at behind,
  /// so the click and the typing landed in different places. The field
  /// lives above the routed navigator, so it keeps the caret across the
  /// navigation it triggers, and typing carries on into results that
  /// swap in underneath. Focusing it is also the only way to reach the
  /// screen with nothing typed, which the Radio chip needs.
  void _onSearchFocus() {
    if (!_searchFocus.hasFocus || !mounted) return;
    if (widget.location.startsWith(WaxRoute.search)) return;
    // Carrying whatever is already in the field, not a bare `/search`.
    // The arriving screen adopts the location's query as the one being
    // answered, so a bare arrival submits an empty one - and the listener
    // below then writes that emptiness back into the field, clearing the
    // text under the caret that just landed there. Which is the failure
    // this whole change exists to stop, on the way in instead of the way
    // out. An empty field yields a bare `/search` anyway.
    context.go(WaxRoute.searchFor(_searchField.text.trim()));
  }

  @override
  void didUpdateWidget(AdaptiveShell old) {
    super.didUpdateWidget(old);
    // Arriving at search puts the caret in the field, which is what the
    // screen's own autofocus used to do before the header took the field
    // over. On the transition only: this rebuilds on every navigation,
    // and asking for focus on each one would pull it out of whatever a
    // visitor already had it in.
    if (old.location.startsWith(WaxRoute.search)) return;
    if (!widget.location.startsWith(WaxRoute.search)) return;
    if (!_headerFieldShowing) return;
    unawaited(_focusHeaderField());
  }

  /// Puts the caret in the header field once the arriving route has
  /// settled, which is what the search screen's own autofocus used to do
  /// before the header took the field over.
  ///
  /// Two frames rather than one, and the reason is worth writing down:
  /// navigating installs the arriving page's focus scope on the frame
  /// after this shell rebuilds, and a scope that finds nothing focused
  /// inside itself claims the focus. Asking any earlier is asking and
  /// then losing it a frame later.
  /// The location is re-checked with the other two, and it is the one
  /// that matters most: two frames is long enough to tap a nav-rail
  /// destination, and focusing the field after leaving search calls
  /// `_onSearchFocus` with its own guard now false, which navigates
  /// straight back to the screen the visitor just left.
  Future<void> _focusHeaderField() async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_headerFieldShowing) return;
    if (!widget.location.startsWith(WaxRoute.search)) return;
    _searchFocus.requestFocus();
  }

  /// Whether the sidebar header (and so the live field) is on screen.
  /// Below sidebar width there is no header, and a collapsed sidebar
  /// drops it too; the search screen draws its own field in both cases.
  bool get _headerFieldShowing =>
      WaxSizeClass.of(context).hasSidebar &&
      !ref.read(sidebarCollapsedProvider);

  /// Keeps the header field in step with the query, whoever set it.
  ///
  /// A recent search, a command-palette hit, and a link all write the
  /// provider, and the field has to follow them. Typing writes it too, so
  /// the guard is what stops that from feeding back: the text is already
  /// what the query says, and assigning it anyway would move the caret to
  /// the end mid-word.
  void _listenForQuery() {
    ref.listen<String>(searchQueryProvider, (previous, next) {
      if (_searchField.text.trim() == next) return;
      _searchField.text = next;
    });
  }

  /// Takes a keystroke from the header field.
  ///
  /// No navigation here: focusing the field already did it, so by the
  /// time anything is typed the screen is up and the settled query
  /// reaches the URL through the screen's own debounced `replace`. Going
  /// per keystroke would mint a browser history entry per character on
  /// web, which turns "nightjar" into eight back presses.
  ///
  /// The guard covers the one case focus does not: text set into the
  /// field without the caret ever landing in it. It carries the query, so
  /// the arriving screen adopts what was typed instead of adopting an
  /// empty location and wiping it.
  void _onSearchChanged(String value) {
    ref.read(searchQueryProvider.notifier).type(value);
    final query = value.trim();
    if (query.isEmpty) return;
    if (widget.location.startsWith(WaxRoute.search)) return;
    context.go(WaxRoute.searchFor(query));
  }

  /// Takes a submit from the header field.
  ///
  /// The same two steps the search screen's own field takes, because at
  /// sidebar width the screen draws no field and this is the only one
  /// there is: without the second, a desktop session never accumulates a
  /// recent search and the surface that offers them back stays empty
  /// forever. Library queries only, matching the screen: recents are
  /// offered under the library chips and not the Radio one, so an entry
  /// stored here would be a shortcut that runs a library search for a
  /// station name.
  void _onSearchSubmitted(String value) {
    final query = value.trim();
    ref.read(searchQueryProvider.notifier).submit(query);
    if (query.isEmpty) return;
    if (ref.read(searchScopeProvider).source.asksLibrary) {
      ref.read(recentSearchesProvider.notifier).remember(query);
    }
  }

  /// Raises the shell's transient messages.
  void _listenForMessages() {
    ref.listen(shellMessengerProvider, (_, next) {
      if (next == null) return;
      final action = next.onAction;
      final label = next.actionLabel;
      final messenger = ScaffoldMessenger.of(context);
      // Only an offer this one supersedes. One messenger serves the
      // whole app, so hiding unconditionally eats unread errors.
      if (_lastRaised != null && _lastRaised == next.actionSemanticsId) {
        messenger.removeCurrentSnackBar();
      }
      _lastRaised = next.actionSemanticsId;
      // Delivered, so the action closure is not held for the session.
      ref.read(shellMessengerProvider.notifier).clear();
      messenger.showSnackBar(
        SnackBar(
          // In the content, not the bar's action slot: SnackBarAction
          // takes no semantics identifier, and the e2e suite drives
          // the UI through those.
          content: Row(
            children: <Widget>[
              Expanded(child: Text(next.text)),
              if (action != null && label != null)
                WaxButton(
                  label: label,
                  kind: WaxButtonKind.text,
                  semanticsId: next.actionSemanticsId,
                  onPressed: () {
                    action();
                    // Spent, so it must not invite a second undo.
                    messenger.hideCurrentSnackBar();
                  },
                ),
            ],
          ),
        ),
      );
    });
  }

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
    final chrome = ref.watch(shellChromeProvider);
    _listenForMessages();
    _listenForQuery();

    final router = GoRouter.of(context);
    final frame = WaxShellFrame(
      destinations: chrome.destinations,
      secondary: chrome.secondary,
      selected: activeNavTarget(
        widget.location,
        chrome.visible,
        // The branch on screen, so a location no destination claims by
        // prefix still lights the domain that is showing it.
        branchIndex: widget.shell.currentIndex,
      )?.name,
      onSelect: (name) {
        final target = chrome.byName[name];
        if (target != null) _select(target);
      },
      // Who is signed in, for the rail's footer and the sidebar's. The
      // frame draws none at compact: below rail width the avatar is in
      // the screen's own top app bar (`AccountAction`), where the layout
      // system puts it and where it carries the secondary destinations.
      account: chrome.account,
      onAccountAction: (name) {
        final verb = WaxAccountVerb.named(name);
        if (verb != null) runAccountVerb(ref, verb);
      },
      // The search field, where the layout system puts it, and a real one:
      // it was a launcher that only opened the screen, so the field
      // somebody had just clicked went dead under the cursor and the
      // typing started somewhere else. The screen draws no field of its
      // own while this one is showing, so there is still exactly one
      // field holding the query.
      sidebarHeader: SearchField(
        controller: _searchField,
        focusNode: _searchFocus,
        hint: 'Artists, albums, shows, books',
        semanticsId: SemanticsIds.searchField,
        clearSemanticsId: SemanticsIds.searchClear,
        onChanged: _onSearchChanged,
        onSubmitted: _onSearchSubmitted,
      ),
      collapsed: ref.watch(sidebarCollapsedProvider),
      onToggleCollapsed: ref.read(sidebarCollapsedProvider.notifier).toggle,
      navSemanticsId: SemanticsIds.navRegion,
      collapseSemanticsId: SemanticsIds.navSidebarCollapse,
      overflowSemanticsId: SemanticsIds.navOverflow,
      skipSemanticsId: SemanticsIds.skipToContent,
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
    // at a shell navigator whose enclosing route is not current - which is
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
