import 'package:go_router/go_router.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';

/// The app-bar route to search.
///
/// The layout system puts a search field in the sidebar header and a
/// search control in the top app bar below that width, and the shell owns
/// no top app bar - every screen brings its own. So the control lives
/// here, and a screen adds it to its bar as it is rebuilt on
/// `WaxScaffold`.
///
/// Its own identifier, not the sidebar field's: at sidebar width both are
/// on screen at once, and a spec that has to disambiguate two controls
/// wearing one handle picks by document order rather than by intent.
class SearchAction extends StatelessWidget {
  const SearchAction({super.key});

  @override
  Widget build(BuildContext context) => WaxIconButton(
    glyph: WaxIcons.search,
    label: context.l10n.searchAction,
    semanticsId: SemanticsIds.searchAction,
    // A location, not an overlay: a search is shareable, so it gets a URL
    // and a place in the table rather than a pushed page.
    onPressed: () => context.go(WaxRoute.search),
  );
}
