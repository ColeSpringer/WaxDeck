/// A wait that doubles each time it is taken, from [first] to at most
/// [last], until [reset] starts it over.
class Backoff {
  /// With [startsAtOnce], the first wait is none and the one after it is
  /// [first].
  Backoff({
    this.first = const Duration(seconds: 1),
    this.last = const Duration(minutes: 1),
    this.startsAtOnce = false,
  }) : assert(first > Duration.zero, 'a first wait of none never grows'),
       _next = startsAtOnce ? Duration.zero : first;

  final Duration first;
  final Duration last;
  final bool startsAtOnce;

  Duration _next;

  /// The wait to make now; the next is twice as long, at most [last].
  Duration take() {
    final wait = _next;
    final doubled = wait == Duration.zero ? first : wait * 2;
    _next = doubled > last ? last : doubled;
    return wait;
  }

  /// The next wait is the first again.
  void reset() => _next = startsAtOnce ? Duration.zero : first;
}
