import 'package:material_ui/material_ui.dart';

import 'cards.dart';

/// The `actions` an app on this design system gives its `MaterialApp`:
/// what [WidgetsApp] installs when given none, its scroll action left
/// overridable from above as it leaves it, with arrow-key focus moves
/// that never stop on a card's hidden parts.
Map<Type, Action<Intent>> waxAppActions(BuildContext context) =>
    <Type, Action<Intent>>{
      ...WidgetsApp.defaultActions,
      ScrollIntent: Action<ScrollIntent>.overridable(
        context: context,
        defaultAction: ScrollAction(),
      ),
      DirectionalFocusIntent: _directionalFocus,
    };

final _directionalFocus = WaxDirectionalFocusAction();
