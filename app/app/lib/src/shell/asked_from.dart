import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import 'shell_messages.dart';

/// The surface a piece of work was asked from, read there before the
/// work's await, so its answer is said where the visitor is once it lands:
/// on the surface while it is still there, else in the shell, through a
/// messenger taken in the session that asked.
///
/// Read before the await because after it the surface may have gone, and
/// with it the context and the `ref` it would have read them through.
class AskedFrom {
  AskedFrom._(
    this._context,
    this._container,
    this._root,
    this._account, {
    required this.route,
    required this.messenger,
  });

  factory AskedFrom.of(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    return AskedFrom._(
      context,
      container,
      Navigator.maybeOf(context, rootNavigator: true),
      container.read(signedInAccountProvider),
      route: ModalRoute.of(context),
      messenger: container.read(shellMessengerProvider),
    );
  }

  final BuildContext _context;
  final ProviderContainer _container;
  final NavigatorState? _root;
  final String? _account;

  /// The surface's own route, for closing it once the work is done (see
  /// `closeFinished`); null for a surface in no navigator.
  final Route<Object?>? route;

  /// The shell's messenger, for the session that asked.
  final ShellMessenger messenger;

  /// Whether the surface is still there to say something on: mounted, and
  /// its route still in its navigator, which a dismissal ends while the
  /// surface is still on its way out. Something opened over it leaves it
  /// there. A surface in no route has no navigator to be dismissed from,
  /// so it is there while it is mounted.
  bool get stillThere => _context.mounted && (route?.isActive ?? true);

  /// Says [refusal] through [inline], on the surface, while it is
  /// [stillThere]; else, or with no [inline], in the shell on [channel].
  void refused(
    String refusal, {
    void Function(String refusal)? inline,
    ShellChannel? channel,
  }) {
    if (inline != null && stillThere) {
      inline(refusal);
    } else {
      messenger.show(refusal, channel: channel);
    }
  }

  /// Shows [builder]'s dialog over whatever is on screen, through the
  /// app's root navigator, there or not: for an answer no bar can carry,
  /// such as a secret shown once. Nothing once the session that asked has
  /// ended, as a message would not be either.
  Future<T?> showDialogOnScreen<T>({required WidgetBuilder builder}) async {
    final root = _root;
    if (root == null || !root.mounted) return null;
    if (_container.read(signedInAccountProvider) != _account) return null;
    return showDialog<T>(context: root.context, builder: builder);
  }
}
