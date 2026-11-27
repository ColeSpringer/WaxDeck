import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Whether the engine answers `TextInput.finishAutofillContext`: the web,
/// Android and iOS do. The desktop embedders answer "not implemented",
/// which the framework reports as an error, and have nothing to finish.
bool get _engineFinishesAutofill =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// The topmost autofill group, above every route.
///
/// A topmost group finishes the autofill context as it is disposed, and on
/// the web that closes whatever text connection is live by then: a page
/// disposed at the end of its exit transition would drop the keyboard from
/// a field on the screen it uncovered. Under this one no screen's group is
/// topmost, and credential screens finish their own ([CredentialAutofill]).
class AutofillRoot extends StatelessWidget {
  const AutofillRoot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _engineFinishesAutofill
      ? AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: child,
        )
      : child;
}

/// How a credential screen ends its form's autofill context.
class CredentialAutofillController {
  var _finished = false;

  /// Ends it, offering what was typed for saving when [accepted]: the
  /// credentials were taken, so a password manager may keep them. On the
  /// web this also takes the engine's hidden form, and the values typed
  /// into it, out of the page. Called before the screen moves on, while
  /// any live text connection is still its own field's.
  void finish({required bool accepted}) {
    if (_finished) return;
    _finished = true;
    if (_engineFinishesAutofill) {
      TextInput.finishAutofillContext(shouldSave: accepted);
    }
  }
}

/// A credential form's fields in one autofill context, so a password
/// manager fills them together. Its screen ends the context through
/// [controller]; a form taken down without that is ended unsaved.
class CredentialAutofill extends StatefulWidget {
  const CredentialAutofill({
    super.key,
    required this.controller,
    required this.child,
  });

  final CredentialAutofillController controller;
  final Widget child;

  @override
  State<CredentialAutofill> createState() => _CredentialAutofillState();
}

class _CredentialAutofillState extends State<CredentialAutofill> {
  @override
  void initState() {
    super.initState();
    widget.controller._finished = false;
  }

  @override
  void dispose() {
    final controller = widget.controller;
    if (!controller._finished && _engineFinishesAutofill) {
      // After the frame, once focus has settled where the screen went. A
      // text field focused there by then holds the live connection, which
      // finishing would close under its typing; the context is then left
      // for the next finish.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_textFieldFocused()) controller.finish(accepted: false);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _engineFinishesAutofill
      ? AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: widget.child,
        )
      : widget.child;
}

bool _textFieldFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      context.mounted &&
      context.findAncestorStateOfType<EditableTextState>() != null;
}
