import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'navigation_history.dart';

/// What a system back press does from where the shell stands.
enum SystemBackAnswer {
  /// A dialog, sheet or menu closes; the screen under it stays.
  closeOverlay,

  /// Back to the last place recorded.
  historyStep,

  /// The page on top pops.
  routerPop,

  /// The ladder's step from a tab's root to Home.
  ladder,

  /// Out of the app.
  leave,
}

/// Keeps Android told whether a system back press is the app's to answer.
///
/// Android 16 hands a press to Flutter only while the framework says it
/// handles back, and Flutter says so from its navigators alone, so a
/// press the shell would turn into a history step or a ladder rung from a
/// screen nothing can pop left the app instead. While a shell is up its
/// answer is what Android hears, told again whenever it may have changed;
/// with none (the sign-in screens) the navigators' report stands, as
/// Flutter sends it by default.
class SystemBackSignal with WidgetsBindingObserver {
  SystemBackSignal() {
    WidgetsBinding.instance.addObserver(this);
  }

  final _shells = <SystemBackAnswer Function()>[];
  var _navigators = false;
  bool? _told;
  var _microtask = false;
  var _postFrame = false;
  var _disposed = false;

  /// What a press would do now, by the shell up last; null with none.
  SystemBackAnswer? get answer => _shells.lastOrNull?.call();

  /// Takes the navigators' report in place of Flutter's default handling,
  /// and stops it there as that does.
  bool onNavigation(NavigationNotification notification) {
    _navigators = notification.canHandlePop;
    _soon();
    return true;
  }

  /// Lets [answer] decide for the shell on [router] until the returned
  /// callback runs.
  ///
  /// A navigation needs no trigger of its own: go_router notifies only
  /// with a changed match list, which rebuilds the root navigator's pages,
  /// and the navigator announces its new history after that frame.
  VoidCallback attach(GoRouter router, SystemBackAnswer Function() answer) {
    _shells.add(answer);
    final history = WaxHistory.of(router);
    history?.changes.addListener(_soon);
    _afterFrame();
    return () {
      history?.changes.removeListener(_soon);
      _shells.remove(answer);
      _soon();
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Told again on resuming: a report made before the app ran was never
    // sent, and the activity may be a new one.
    if (state == AppLifecycleState.resumed) _told = null;
    _afterFrame();
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// For a change that moves no page: once the code making it is done.
  void _soon() {
    if (_microtask) return;
    _microtask = true;
    scheduleMicrotask(() {
      _microtask = false;
      _tell();
    });
  }

  /// Once the next frame has laid out what is on screen.
  void _afterFrame() {
    if (_postFrame) return;
    _postFrame = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _postFrame = false;
        _tell();
      }, debugLabel: 'SystemBackSignal')
      ..ensureVisualUpdate();
  }

  void _tell() {
    if (_disposed) return;
    // As Flutter's own: nothing before the app runs or once it has gone.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.detached) return;
    final handles = switch (answer) {
      null => _navigators,
      final answer => answer != SystemBackAnswer.leave,
    };
    if (handles == _told) return;
    _told = handles;
    unawaited(SystemNavigator.setFrameworkHandlesBack(handles));
  }
}

/// The app's [SystemBackSignal]; null off Android, the one platform that
/// reads it, where Flutter's own report stands.
final systemBackSignalProvider = Provider<SystemBackSignal?>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  final signal = SystemBackSignal();
  ref.onDispose(signal.dispose);
  return signal;
});
