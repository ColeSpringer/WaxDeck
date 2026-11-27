import 'dart:async';

import 'package:waxdeck_data/waxdeck_data.dart';

import '../auth/auth_controller.dart';
import 'session_gate.dart';

/// The session a transport says is in doubt, asked about until the server
/// answers.
///
/// One read at a time: an ask while one is out joins it. A read the server
/// did not answer is asked again a second later, then two, doubling to a
/// minute, until one is answered; an ask meanwhile reads at once and keeps
/// the step. The account leaving, or [dispose], ends the asking for good.
///
/// In doubt from an [ask] or a [suspect] until an answer that the account
/// stands, to a read sent since the last [suspect]; for good once it left.
/// What [pass] answers a request meanwhile.
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
  var _inDoubt = false;

  /// Moves at each [suspect]: a read sent before the last one does not end
  /// the doubt.
  var _suspicions = 0;

  /// Reads the session, or joins the read already out. After the account
  /// left, or once disposed, answers [SessionRecheck.left] without one.
  Future<SessionRecheck> ask() {
    if (_over) return Future.value(SessionRecheck.left);
    _inDoubt = true;
    if (_out case final out?) return out;
    _again?.cancel();
    _again = null;
    return _out = _read();
  }

  /// The session may have changed hands, with nothing read yet: a socket
  /// dropped, across whose absence another tab can sign in.
  void suspect() {
    if (_over) return;
    _inDoubt = true;
    _suspicions++;
  }

  /// Whether a request may go out for the account: at once while nothing
  /// is in doubt; otherwise once a read sent since the last [suspect]
  /// answers that it stands (one sent before it is asked again: its cookie
  /// went out before the suspicion). A read the server did not answer is a
  /// no, as the request would not have been answered either, and so is an
  /// account that left. Suspicions that outrun [passTurns] reads are a no
  /// too, as an outage is: the request fails rather than waits on.
  ///
  /// A request made in session work ([asSessionWork]: a read's own, or a
  /// road it joins) is a no at once while in doubt, never held on a read
  /// that may be waiting on it.
  Future<bool> pass() async {
    if (inDoubt && inSessionWork) return false;
    for (var turn = 0; turn < passTurns; turn++) {
      if (_over) return false;
      if (!_inDoubt) return true;
      if (await ask() != SessionRecheck.stands) return false;
    }
    return !_over && !_inDoubt;
  }

  /// The most reads one request waits on.
  static const passTurns = 3;

  /// In doubt and not over: what a binder rebuilt meanwhile carries over.
  bool get inDoubt => !_over && _inDoubt;

  Future<SessionRecheck> _read() async {
    final asked = _suspicions;
    SessionRecheck answer;
    try {
      // Awaited even when it throws at once, so this lets go of the read
      // out only after `ask` has taken it.
      answer = await asSessionWork(read);
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
        if (asked == _suspicions) _inDoubt = false;
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
