import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import 'adaptive_shell.dart';

/// The account menu, in a screen's top app bar.
///
/// The layout system puts the avatar in the top app bar and the shell
/// owns no app bar, so the control lives here and every tab root adds it
/// to its own bar, exactly as the search control does. Until this existed
/// the shell drew it into a fixed cell at the trailing end of the compact
/// tab bar, because the screens that had bars were the ones written
/// before the design system and none of them was a tab root.
///
/// It carries the secondary destinations with it, because below rail
/// width the tab bar holds the domains and nothing else and this is the
/// only route to settings, downloads, stats, and curation.
///
/// Compact only, and that is the whole of the deviation from 3.2 that
/// remains: the rail's footer and the sidebar's already draw an account
/// control at their own widths, so a second one in the app bar there
/// would be two identical controls on screen wearing one handle.
class AccountAction extends ConsumerWidget {
  const AccountAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!WaxSizeClass.of(context).isCompact) return const SizedBox.shrink();
    final chrome = ref.watch(shellChromeProvider);
    final l10n = context.l10n;
    return WaxAccountButton(
      account: chrome.accountOf(l10n),
      onAction: (name) {
        final verb = WaxAccountVerb.named(name);
        if (verb != null) runAccountVerb(ref, verb);
      },
      entries: chrome.secondaryOf(l10n),
      onSelect: (name) => goToNavTarget(context, chrome.byName[name]),
      // Which secondary destination is current, so the menu marks it.
      // Resolved from the location without the branch tie-break the shell
      // applies: that one exists to keep a domain lit for a location no
      // destination claims, and nothing in this menu is a domain.
      selected: activeNavTarget(
        GoRouterState.of(context).uri.path,
        chrome.visible,
      )?.name,
    );
  }
}
