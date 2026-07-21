import 'package:flutter/material.dart';

/// A compact marker for feed-declared explicit content: a bordered E
/// in the row's text color, quiet enough to sit inside a title line.
/// Podcasts are the one medium with a canonical explicit flag (the
/// RSS itunes tag), so this currently appears on shows and episodes.
class ExplicitBadge extends StatelessWidget {
  const ExplicitBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Explicit',
      child: Tooltip(
        message: 'Explicit',
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.onSurfaceVariant),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'E',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
