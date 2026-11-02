import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Which control started the work a surface runs one piece at a time.
///
/// The control keyed by what [runAs] was given draws busy, every other one
/// stands unavailable while [busy], and nothing draws busy while the work
/// waits on the person in a dialog over the surface ([whileAsking]). The
/// key is the surface's own: an enum of its verbs, a semantics id, a feed
/// URL. Errors stay the surface's to word, inside the work.
mixin InFlight<W extends StatefulWidget, K extends Object> on State<W> {
  K? _running;
  var _asking = false;

  /// Whether work is in flight: no control but its starter takes a press.
  bool get busy => _running != null;

  /// Whether the control keyed [key] started the work in flight. False
  /// while that work waits on the person.
  bool busyBy(K key) => _running == key && !_asking;

  /// Runs [work] as [key]'s, unless work already runs.
  ///
  /// The key clears however the work ends, except on a surface the work
  /// closed: that one keeps it on its way out, so nothing on it takes a
  /// press as it leaves.
  Future<void> runAs(K key, Future<void> Function() work) async {
    if (busy) return;
    final route = ModalRoute.of(context);
    setState(() => _running = key);
    try {
      await work();
    } finally {
      if (mounted && (route?.isActive ?? true)) {
        setState(() => _running = null);
      }
    }
  }

  /// Runs [ask], a dialog over the surface, as waiting on the person:
  /// the work is still in flight, but nothing draws busy.
  Future<T> whileAsking<T>(Future<T> Function() ask) async {
    setState(() => _asking = true);
    try {
      return await ask();
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }
}
