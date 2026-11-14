import 'dart:async';

import 'package:waxdeck_data/waxdeck_data.dart';

import '../auth/auth_controller.dart';

/// The session a transport says is in doubt, asked about until the server
/// answers.
///
/// One read at a time: an ask while one is out joins it. A read the server
/// did not answer is asked again a second later, then two, doubling to a
/// minute, until one is answered; an ask meanwhile reads at once and keeps
/// the step. The account leaving, or [dispose], ends the asking for good.
class SessionDoubt {
  SessionDoubt({required this.read});

  /// One session read, and what it made of the account.
  final Future<SessionRecheck> Function() read;

  /// Fires on each answer that the account stands.
  void Function()? onStands;

  Future<SessionRecheck>? _out;
  Timer? _again;
  final _wait = Backoff();
  var _over = false;

  /// Reads the session, or joins the read already out. After the account
  /// left, or once disposed, answers [SessionRecheck.left] without one.
  Future<SessionRecheck> ask() {
    if (_over) return Future.value(SessionRecheck.left);
    if (_out case final out?) return out;
    _again?.cancel();
    _again = null;
    return _out = _read();
  }

  Future<SessionRecheck> _read() async {
    SessionRecheck answer;
    try {
      // Awaited even when it throws at once, so this lets go of the read
      // out only after `ask` has taken it.
      answer = await Future.sync(read);
    } on Object {
      answer = SessionRecheck.unanswered;
    }
    _out = null;
    if (_over) return SessionRecheck.left;
    switch (answer) {
      case SessionRecheck.unanswered:
        _again = Timer(_wait.take(), () => ask().ignore());
      case SessionRecheck.stands:
        _wait.reset();
        onStands?.call();
      case SessionRecheck.left:
        _over = true;
    }
    return answer;
  }

  void dispose() {
    _over = true;
    _again?.cancel();
    _again = null;
  }
}
