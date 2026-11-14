import 'package:material_ui/material_ui.dart';

/// A popup menu row drawn in the theme the menu is under now.
///
/// An open menu follows a theme switch, since the app's theme sits above
/// the navigator it opens on, but `PopupMenuItem` eases the style its row
/// inherits into the new theme, and a colour read when the menu opened
/// never moves. [builder] runs inside the menu, under the item's resting
/// style held still, so the row lands with the theme.
PopupMenuItem<T> waxMenuEntry<T>({
  required WidgetBuilder builder,
  T? value,
  bool enabled = true,
  double height = kMinInteractiveDimension,
}) => PopupMenuItem<T>(
  value: value,
  enabled: enabled,
  height: height,
  child: _Landed(enabled: enabled, builder: builder),
);

class _Landed extends StatelessWidget {
  const _Landed({required this.enabled, required this.builder});

  final bool enabled;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: _restingStyle(context, enabled: enabled),
    child: Builder(builder: builder),
  );
}

/// What a Material 3 `PopupMenuItem` eases its row's style to: the theme's
/// label style for menus, else the label type in the surface's ink.
TextStyle _restingStyle(BuildContext context, {required bool enabled}) {
  final states = <WidgetState>{if (!enabled) WidgetState.disabled};
  final themed = PopupMenuTheme.of(context).labelTextStyle?.resolve(states);
  if (themed != null) return themed;
  final theme = Theme.of(context);
  final ink = theme.colorScheme.onSurface;
  return theme.textTheme.labelLarge!.apply(
    // The framework's disabled ink: 38 per cent, in eight bits.
    color: enabled ? ink : ink.withAlpha((255 * 0.38).round()),
  );
}
