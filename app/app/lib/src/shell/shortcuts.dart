import 'package:flutter/material.dart';

/// Reusable keyboard-shortcut layer for keyboard-first screens.
///
/// Wraps a subtree in [CallbackShortcuts] plus an autofocused [Focus]
/// node, so bindings are live the moment the screen appears without the
/// user clicking anything first. Screens pass plain
/// `Map<ShortcutActivator, VoidCallback>` bindings and reuse this
/// wrapper unchanged; the review queue is the first adopter.
///
/// Bindings are suppressed while a text-editing field has primary
/// focus: before invoking a callback the wrapper checks whether the
/// primary focus node's context widget is an [EditableText] and skips
/// the callback when it is. Key events from a focused text field still
/// bubble up through ancestor shortcut handlers, so without this guard
/// typing a bound letter into any form or search field would trigger
/// navigation or a decision mid-word.
class AppShortcuts extends StatelessWidget {
  const AppShortcuts({
    super.key,
    required this.bindings,
    required this.child,
    this.autofocus = true,
  });

  /// Shortcut activators to callbacks; only evaluated while no text
  /// field holds primary focus.
  final Map<ShortcutActivator, VoidCallback> bindings;

  final Widget child;

  /// Whether the wrapped [Focus] node grabs focus on mount.
  final bool autofocus;

  /// True while the focused widget is a text editor; bound keys must
  /// then act as typed text, never as commands. The primary focus node
  /// can be hosted either by the [EditableText] itself or by a [Focus]
  /// widget inside its build, so the ancestor lookup covers both.
  static bool _editingText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    return context.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        for (final entry in bindings.entries)
          entry.key: () {
            if (_editingText()) return;
            entry.value();
          },
      },
      child: Focus(autofocus: autofocus, child: child),
    );
  }
}
