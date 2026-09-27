import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Keyboard bindings for a subtree, guarded so a key reaches whatever has
/// focus first: text fields keep their letters and arrows, and a focused
/// control keeps its space (WCAG 2.1.1).
///
/// [typingBindings] are the exception, for chords no field can receive as
/// text. A declined key is reported ignored, so it goes on to the
/// ancestors that own it.
class AppShortcuts extends StatelessWidget {
  const AppShortcuts({
    super.key,
    required this.bindings,
    required this.child,
    this.typingBindings = const <ShortcutActivator, VoidCallback>{},
    this.autofocus = true,
  });

  final Map<ShortcutActivator, VoidCallback> bindings;
  final Map<ShortcutActivator, VoidCallback> typingBindings;
  final Widget child;

  /// Whether to grab focus on mount, for a screen whose keys must be live
  /// before anything is clicked.
  final bool autofocus;

  /// The editor can host the primary focus itself or through a [Focus] in
  /// its build, so the lookup covers both.
  static bool _editingText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    return context.findAncestorStateOfType<EditableTextState>() != null;
  }

  /// A focused selection keeps the shift-arrows that stretch it.
  static bool _stretchingSelection(KeyEvent event) {
    if (!HardwareKeyboard.instance.isShiftPressed ||
        !_stretchKeys.contains(event.logicalKey)) {
      return false;
    }
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.findAncestorStateOfType<SelectableRegionState>() != null;
  }

  static final Set<LogicalKeyboardKey> _stretchKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
  };

  static bool _focusActivates() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return Actions.maybeFind<ActivateIntent>(context) != null;
  }

  static bool _isBareSpace(ShortcutActivator activator) =>
      activator is SingleActivator &&
      activator.trigger == LogicalKeyboardKey.space &&
      !activator.control &&
      !activator.meta &&
      !activator.alt &&
      !activator.shift;

  KeyEventResult _dispatch(KeyEvent event) {
    var result = KeyEventResult.ignored;
    for (final entry in typingBindings.entries) {
      if (!entry.key.accepts(event, HardwareKeyboard.instance)) continue;
      entry.value();
      result = KeyEventResult.handled;
    }
    if (_editingText() || _stretchingSelection(event)) return result;
    for (final entry in bindings.entries) {
      if (!entry.key.accepts(event, HardwareKeyboard.instance)) continue;
      if (_isBareSpace(entry.key) && _focusActivates()) continue;
      entry.value();
      result = KeyEventResult.handled;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _dispatch(event),
      child: autofocus ? Focus(autofocus: true, child: child) : child,
    );
  }
}
