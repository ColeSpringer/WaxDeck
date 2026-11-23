import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/pin_refresh.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

const _pace = Duration(milliseconds: 250);
const _retry = Duration(minutes: 2);

String _name(ArtworkPinRecord pin) => '${pin.pid}/${pin.sizePx}';

/// A walk over pins held in memory, a gate the test moves, and a server
/// that answers what the test says.
class _Harness {
  _Harness({int pins = 5, PinWalk? left, int pageSize = 2, _Pins? over})
    : store = over ?? _Pins() {
    for (var i = 1; i <= pins; i++) {
      store.add('tr-$i', 256);
    }
    refresh = PinRefresh(
      pins: store,
      gate: gate,
      ask: _ask,
      make: _make,
      remember: (walk) async {
        remembered.add(walk);
        if (holdRemember case final held?) await held.future;
      },
      pace: _pace,
      retryAfter: _retry,
      pageSize: pageSize,
    );
    if (left != null) refresh.resume(left);
  }

  final _Pins store;
  final _Gate gate = _Gate();
  late final PinRefresh refresh;

  /// Every pin asked about, in order.
  final List<String> asked = <String>[];

  /// What the walk said of its place each time it said.
  final List<PinWalk?> remembered = <PinWalk?>[];

  /// What the server answers for a pin; anything else is unchanged.
  final Map<String, PinAnswer> answers = <String, PinAnswer>{};

  /// Set, the server refuses every pin, as one whose art reads broke.
  bool refuseAll = false;

  /// Held, a request waits on it: one in flight.
  Completer<void>? hold;

  /// Held, the walk's place is still being written.
  Completer<void>? holdRemember;

  int inFlight = 0;
  int mostInFlight = 0;

  Future<PinAnswer> _ask(ArtworkPinRecord pin) async {
    asked.add(_name(pin));
    inFlight++;
    if (inFlight > mostInFlight) mostInFlight = inFlight;
    if (hold case final held?) await held.future;
    inFlight--;
    if (refuseAll) return PinAnswer.refused;
    return answers[_name(pin)] ?? PinAnswer.unchanged;
  }

  /// A pin there was to make is asked for: named with a plus among
  /// [asked], and pinned unless [answers] says otherwise.
  Future<PinAnswer> _make(PinCursor at, String artUrl) async {
    final name = '${at.pid}/${at.sizePx}';
    asked.add('+$name');
    // As the server stood when it was asked.
    final answer = refuseAll
        ? PinAnswer.refused
        : answers[name] ?? PinAnswer.replaced;
    inFlight++;
    if (inFlight > mostInFlight) mostInFlight = inFlight;
    if (hold case final held?) await held.future;
    inFlight--;
    if (answer == PinAnswer.replaced) store.add(at.pid, at.sizePx);
    return answer;
  }

  /// Lets a whole walk run: more than its paces add up to.
  Future<void> run(WidgetTester tester) => tester.pump(_pace * 40);
}

/// Pins to make at [places], each `pid/size`, with an art URL apiece.
Map<PinCursor, String> _toMake(List<String> places) => {
  for (final place in places)
    (pid: place.split('/').first, sizePx: int.parse(place.split('/').last)):
        '/api/v1/items/${place.split('/').first}/art',
};

void main() {
  testWidgets('every pin is asked about once, one at a time, no faster than '
      'the pace', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.refresh.request();

    await tester.pump();
    expect(h.asked, ['tr-1/256']);
    await tester.pump(_pace - const Duration(milliseconds: 1));
    expect(h.asked, ['tr-1/256']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(h.asked, ['tr-1/256', 'tr-2/256']);

    await h.run(tester);
    expect(h.asked, [
      'tr-1/256',
      'tr-2/256',
      'tr-3/256',
      'tr-4/256',
      'tr-5/256',
    ]);
    expect(h.mostInFlight, 1);
    // Over, and said so, and nothing more is asked.
    expect(h.remembered.last, isNull);
    await h.run(tester);
    expect(h.asked, hasLength(5));
  });

  testWidgets('its place is remembered once a page, and at the end', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.refresh.request();
    await h.run(tester);

    expect(h.remembered, <PinWalk?>[
      PinWalk(after: null, again: false),
      PinWalk(after: (pid: 'tr-2', sizePx: 256), again: false),
      PinWalk(after: (pid: 'tr-4', sizePx: 256), again: false),
      PinWalk(after: (pid: 'tr-5', sizePx: 256), again: false),
      null,
    ]);
  });

  testWidgets('a walk the server stops keeps its place and goes on from it', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.answers['tr-3/256'] = PinAnswer.unanswered;
    h.refresh.request();
    await h.run(tester);

    expect(h.asked, ['tr-1/256', 'tr-2/256', 'tr-3/256']);
    expect(
      h.remembered.last,
      PinWalk(after: (pid: 'tr-2', sizePx: 256), again: false),
    );

    // Left alone until its wait is up.
    await tester.pump(_retry - _pace * 40 - const Duration(seconds: 1));
    expect(h.asked, hasLength(3));
    h.answers.clear();
    await tester.pump(const Duration(seconds: 1));
    await h.run(tester);
    expect(h.asked, [
      'tr-1/256',
      'tr-2/256',
      'tr-3/256',
      'tr-3/256',
      'tr-4/256',
      'tr-5/256',
    ]);
    expect(h.remembered.last, isNull);
  });

  testWidgets('a pin the server refuses does not hold the pins after it: it '
      'is passed, asked again only once the rest have been, and the walk '
      'ends', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.answers['tr-2/256'] = PinAnswer.refused;
    h.answers['tr-3/256'] = PinAnswer.refused;
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, [for (var i = 1; i <= 5; i++) 'tr-$i/256']);

    await tester.pump(_retry * 16);
    expect(h.asked.skip(5), [
      for (var round = 0; round < PinRefresh.retryRounds; round++) ...[
        'tr-2/256',
        'tr-3/256',
      ],
    ]);
    expect(h.remembered.last, isNull);
  });

  testWidgets('every pin refusing is the server: the walk stops at the first '
      'of them and goes on from it when the server answers again', (
    tester,
  ) async {
    final h = _Harness(pins: 8);
    addTearDown(h.refresh.dispose);
    h.refresh.request();
    await tester.pump();
    expect(h.asked, ['tr-1/256']);
    // Its art reads break once the first pin has answered.
    h.refuseAll = true;
    await h.run(tester);

    // Four in a row, and the pin that answered before them refused too.
    expect(h.asked, [
      'tr-1/256',
      'tr-2/256',
      'tr-3/256',
      'tr-4/256',
      'tr-5/256',
      'tr-1/256',
    ]);
    expect(
      h.remembered.last,
      const PinWalk(after: (pid: 'tr-1', sizePx: 256), tries: 1),
    );

    h.refuseAll = false;
    h.asked.clear();
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, [for (var i = 2; i <= 8; i++) 'tr-$i/256']);
    expect(h.remembered.last, isNull);
  });

  testWidgets('refusals that never end are tried three times and then '
      'passed, so the walk ends', (tester) async {
    final h = _Harness(pins: 6)..refuseAll = true;
    addTearDown(h.refresh.dispose);
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, hasLength(4));
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(8));
    await tester.pump(_retry);
    await h.run(tester);
    // The third time through, nothing stops it.
    expect(h.asked, hasLength(14));
    // And each passed pin is asked again a few times.
    await tester.pump(_retry * 16);
    expect(h.asked, hasLength(14 + 6 * PinRefresh.retryRounds));
    expect(h.remembered.last, isNull);

    await tester.pump(_retry * 16);
    expect(h.asked, hasLength(14 + 6 * PinRefresh.retryRounds));
  });

  testWidgets('a few refusals with nothing answered around them are tried '
      'three times too', (tester) async {
    // A device whose only pinned cover the server will not give.
    final h = _Harness(pins: 2)..refuseAll = true;
    addTearDown(h.refresh.dispose);
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, hasLength(2));
    expect(h.remembered.last, const PinWalk(tries: 1));
    await tester.pump(_retry);
    await h.run(tester);
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(6));
    await tester.pump(_retry * 16);
    expect(h.asked, hasLength(6 + 2 * PinRefresh.retryRounds));
    expect(h.remembered.last, isNull);
    await tester.pump(_retry * 16);
    expect(h.asked, hasLength(6 + 2 * PinRefresh.retryRounds));
  });

  testWidgets('a pin refused while the server was briefly in trouble is '
      'asked again once the rest have been, and refreshed in the same '
      'walk', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.answers['tr-2/256'] = PinAnswer.refused;
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, [for (var i = 1; i <= 5; i++) 'tr-$i/256']);

    h.answers.clear();
    // Not at once: it waits first.
    await tester.pump(_retry - _pace * 40);
    expect(h.asked, hasLength(5));
    await h.run(tester);
    expect(h.asked, [for (var i = 1; i <= 5; i++) 'tr-$i/256', 'tr-2/256']);
    expect(h.remembered.last, isNull);
  });

  testWidgets('what the server still refuses after a few tries, each wait '
      'longer than the last, is left for the next walk', (tester) async {
    final h = _Harness(pins: 3);
    addTearDown(h.refresh.dispose);
    h.answers['tr-2/256'] = PinAnswer.refused;
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, hasLength(3));

    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(4));
    // The gate opening is no news to a server that refused.
    h.gate
      ..set(false)
      ..set(true);
    await h.run(tester);
    expect(h.asked, hasLength(4));
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(4), reason: 'the second wait is longer');
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(5));
    await tester.pump(_retry * 3);
    await h.run(tester);
    expect(h.asked, hasLength(5), reason: 'the third longer still');
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(6));
    expect(h.asked.skip(3), everyElement('tr-2/256'));
    expect(h.remembered.last, isNull);

    await tester.pump(_retry * 16);
    expect(h.asked, hasLength(6));
  });

  testWidgets('covers changing again while refused pins wait their turn '
      'start the walk over at once, and it asks them with the rest', (
    tester,
  ) async {
    final h = _Harness(pins: 3);
    addTearDown(h.refresh.dispose);
    h.answers['tr-2/256'] = PinAnswer.refused;
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, hasLength(3));

    h.answers.clear();
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, [
      for (var i = 1; i <= 3; i++) 'tr-$i/256',
      for (var i = 1; i <= 3; i++) 'tr-$i/256',
    ]);
    expect(h.remembered.last, isNull);
    await tester.pump(_retry * 16);
    expect(h.asked, hasLength(6));
  });

  testWidgets('no more passed pins are kept to ask again than it holds', (
    tester,
  ) async {
    final h = _Harness(pins: 400, pageSize: 32);
    addTearDown(h.refresh.dispose);
    // Three of every four refused, so no run is long enough to stop it.
    final names = h.store.names;
    for (var i = 0; i < names.length; i++) {
      if (i % 4 != 0) h.answers[names[i]] = PinAnswer.refused;
    }
    h.refresh.request();
    await tester.pump(_pace * 420);
    expect(h.asked, hasLength(400));
    expect(h.remembered.last?.passed, hasLength(PinRefresh.passedHeld));
    h.refresh.dispose();
  });

  testWidgets('a run of refusals counts its stops across a restart, so '
      'short sessions still get past it', (tester) async {
    PinWalk? left;
    final asked = <int>[];
    for (var session = 0; session < 3; session++) {
      final h = _Harness(pins: 6, left: left)..refuseAll = true;
      if (left == null) h.refresh.request();
      await h.run(tester);
      asked.add(h.asked.length);
      left = h.remembered.last;
      // Over before its wait is up.
      h.refresh.dispose();
    }
    // Stopped twice, and the third session goes on past them.
    expect(asked, [4, 4, 6]);
  });

  testWidgets('a later walk in the same session is as patient with a '
      'refusing server as the first was', (tester) async {
    final h = _Harness(pins: 6)..refuseAll = true;
    addTearDown(h.refresh.dispose);
    h.refresh.request();
    await h.run(tester);
    await tester.pump(_retry);
    await h.run(tester);
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(14));
    await tester.pump(_retry * 16);
    expect(h.remembered.last, isNull);

    h.asked.clear();
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, hasLength(4));
    expect(h.remembered.last, const PinWalk(tries: 1));
    h.refresh.dispose();
  });

  testWidgets('a walk forgotten among refusals leaves none of them to the '
      'next', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.answers['tr-2/256'] = PinAnswer.refused;
    h.answers['tr-3/256'] = PinAnswer.refused;
    h.refresh.request();
    await tester.pump();
    await tester.pump(_pace);
    await tester.pump(_pace);
    expect(h.asked, ['tr-1/256', 'tr-2/256', 'tr-3/256']);
    h.refresh.forget();
    await h.run(tester);

    h.answers
      ..clear()
      ..['tr-1/256'] = PinAnswer.unanswered;
    h.refresh.request();
    await h.run(tester);
    // Stopped where this walk stands, not where the forgotten one did.
    expect(h.remembered.last, const PinWalk());
    h.refresh.dispose();
  });

  testWidgets('a pin store that fails waits before it reads again, whatever '
      'the gate says', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.store.fails = true;
    h.refresh.request();
    await h.run(tester);
    expect(h.store.reads, 1);
    h.gate.set(true);
    await h.run(tester);
    expect(h.store.reads, 1);

    h.store.fails = false;
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(5));
  });

  testWidgets('a word that the gate is open, when it already was, does not '
      'cut a stop short', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.answers['tr-3/256'] = PinAnswer.unanswered;
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, hasLength(3));

    h.gate.set(true);
    await h.run(tester);
    expect(h.asked, hasLength(3));
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(4));
    h.refresh.dispose();
  });

  testWidgets('one broken cover over many pins costs the walk no pause: the '
      'last pin that answered is asked again, and answers', (tester) async {
    // Four tracks that show one album cover the server cannot read.
    final h = _Harness(pins: 9);
    addTearDown(h.refresh.dispose);
    for (var i = 2; i <= 9; i++) {
      h.answers['tr-$i/256'] = PinAnswer.refused;
    }
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, [
      'tr-1/256',
      for (var i = 2; i <= 5; i++) 'tr-$i/256',
      'tr-1/256',
      for (var i = 6; i <= 9; i++) 'tr-$i/256',
      'tr-1/256',
    ]);
    // Past them all, and owing only them.
    expect(h.remembered.last?.after, (pid: 'tr-9', sizePx: 256));
    expect(h.remembered.last?.passed, hasLength(8));
    h.refresh.dispose();
  });

  testWidgets('a walk an earlier run left is taken up past its last pin', (
    tester,
  ) async {
    final h = _Harness(
      left: PinWalk(after: (pid: 'tr-3', sizePx: 256), again: false),
    );
    addTearDown(h.refresh.dispose);
    await h.run(tester);

    expect(h.asked, ['tr-4/256', 'tr-5/256']);
    expect(h.remembered.last, isNull);
  });

  testWidgets('a walk left owing another makes it', (tester) async {
    final h = _Harness(
      left: PinWalk(after: (pid: 'tr-4', sizePx: 256), again: true),
    );
    addTearDown(h.refresh.dispose);
    await h.run(tester);

    expect(h.asked, [
      'tr-5/256',
      'tr-1/256',
      'tr-2/256',
      'tr-3/256',
      'tr-4/256',
      'tr-5/256',
    ]);
  });

  testWidgets('nothing is asked while the gate is shut, and the walk sets '
      'out when it opens', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.gate.open = false;
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, isEmpty);
    // Owed all the same.
    expect(h.remembered.last, PinWalk(after: null, again: false));

    h.gate.set(true);
    await h.run(tester);
    expect(h.asked, hasLength(5));
  });

  testWidgets('a gate that shuts mid-walk stops it before the next pin, and '
      'it goes on from there', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.refresh.request();
    await tester.pump();
    await tester.pump(_pace);
    await tester.pump(_pace);
    expect(h.asked, ['tr-1/256', 'tr-2/256', 'tr-3/256']);

    h.gate.set(false);
    await h.run(tester);
    expect(h.asked, hasLength(3));
    expect(
      h.remembered.last,
      PinWalk(after: (pid: 'tr-3', sizePx: 256), again: false),
    );

    h.gate.set(true);
    await h.run(tester);
    expect(h.asked, [
      'tr-1/256',
      'tr-2/256',
      'tr-3/256',
      'tr-4/256',
      'tr-5/256',
    ]);
  });

  testWidgets('a gate that opens while a stopped walk is writing its place '
      'lets it on at once', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.refresh.request();
    await tester.pump();
    h.holdRemember = Completer<void>();
    h.gate.set(false);
    await tester.pump(_pace);
    expect(h.asked, ['tr-1/256']);

    h.gate.set(true);
    h.holdRemember!.complete();
    h.holdRemember = null;
    await h.run(tester);
    expect(h.asked, hasLength(5));
  });

  testWidgets('a gate nobody said had opened is looked at again in time', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.gate.open = false;
    h.refresh.request();
    await h.run(tester);
    h.gate.open = true;
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(5));
  });

  testWidgets('covers changing again during a walk start no second one: the '
      'walk in hand is followed by one more', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.refresh.request();
    await tester.pump();
    await tester.pump(_pace);
    expect(h.asked, ['tr-1/256', 'tr-2/256']);

    h.hold = Completer<void>();
    await tester.pump(_pace);
    expect(h.inFlight, 1);
    h.refresh.request();
    h.refresh.request();
    await tester.pump(_pace * 4);
    // Still the one request it had in flight.
    expect(h.asked, ['tr-1/256', 'tr-2/256', 'tr-3/256']);
    h.hold!.complete();
    h.hold = null;
    await h.run(tester);

    expect(h.mostInFlight, 1);
    expect(h.asked, [
      'tr-1/256',
      'tr-2/256',
      'tr-3/256',
      'tr-4/256',
      'tr-5/256',
      'tr-1/256',
      'tr-2/256',
      'tr-3/256',
      'tr-4/256',
      'tr-5/256',
    ]);
    expect(h.remembered.last, isNull);
  });

  testWidgets('asked for twice before it has set out is one walk', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.gate.open = false;
    h.refresh.request();
    await tester.pump();
    h.refresh.request();
    h.gate.set(true);
    await h.run(tester);
    expect(h.asked, hasLength(5));
  });

  testWidgets('forgotten or disposed, it asks nothing more', (tester) async {
    for (final end in <void Function(PinRefresh)>[
      (refresh) => refresh.forget(),
      (refresh) => refresh.dispose(),
    ]) {
      final h = _Harness();
      h.refresh.request();
      await tester.pump();
      expect(h.asked, ['tr-1/256']);
      end(h.refresh);
      await h.run(tester);
      await tester.pump(_retry);
      expect(h.asked, ['tr-1/256']);
      h.refresh.dispose();
    }
  });

  testWidgets('a pin store that fails stops the walk, which tries again', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.store.fails = true;
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, isEmpty);

    h.store.fails = false;
    await tester.pump(_retry);
    await h.run(tester);
    expect(h.asked, hasLength(5));
  });

  group('pins whose covers were replaced', () {
    const two = (pid: 'tr-2', sizePx: 256);
    const four = (pid: 'tr-4', sizePx: 256);

    testWidgets('are asked about alone, under the gate and at the pace, and '
        'nothing else is', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.gate.open = false;
      h.refresh.requestFor([two, four]);
      await h.run(tester);
      expect(h.asked, isEmpty);
      // Owed all the same, and only those.
      expect(
        h.remembered.last,
        const PinWalk(named: [two, four], whole: false),
      );

      h.gate.set(true);
      await tester.pump();
      expect(h.asked, ['tr-2/256']);
      await tester.pump(_pace - const Duration(milliseconds: 1));
      expect(h.asked, ['tr-2/256']);
      await h.run(tester);
      expect(h.asked, ['tr-2/256', 'tr-4/256']);
      expect(h.mostInFlight, 1);
      expect(h.remembered.last, isNull);
    });

    testWidgets('are asked about ahead of the rest of a walk under way', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.refresh.request();
      await tester.pump();
      expect(h.asked, ['tr-1/256']);
      h.refresh.requestFor([four]);
      await h.run(tester);
      expect(h.asked, [
        'tr-1/256',
        'tr-4/256',
        'tr-2/256',
        'tr-3/256',
        'tr-4/256',
        'tr-5/256',
      ]);
      expect(h.remembered.last, isNull);
    });

    testWidgets('one named again while it is being asked about is asked '
        'once more after', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.hold = Completer<void>();
      h.refresh.requestFor([two]);
      await tester.pump();
      expect(h.asked, ['tr-2/256']);

      h.refresh.requestFor([two]);
      h.hold!.complete();
      h.hold = null;
      await h.run(tester);
      expect(h.asked, ['tr-2/256', 'tr-2/256']);
      expect(h.remembered.last, isNull);

      // Named again once it was answered is one more ask, as ever.
      h.refresh.requestFor([two]);
      await h.run(tester);
      expect(h.asked, hasLength(3));
    });

    testWidgets('left by an earlier run are asked about at the next start', (
      tester,
    ) async {
      final h = _Harness(left: const PinWalk(named: [four], whole: false));
      addTearDown(h.refresh.dispose);
      await h.run(tester);
      expect(h.asked, ['tr-4/256']);
      expect(h.remembered.last, isNull);
    });

    testWidgets('a server that does not answer keeps them owed', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.unanswered;
      h.refresh.requestFor([two]);
      await h.run(tester);
      expect(h.asked, ['tr-2/256']);
      expect(h.remembered.last, const PinWalk(named: [two], whole: false));

      h.answers.clear();
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked, ['tr-2/256', 'tr-2/256']);
      expect(h.remembered.last, isNull);
    });

    testWidgets('then covers changed and nothing says which: every pin is '
        'walked once', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.gate.open = false;
      h.refresh.requestFor([four]);
      await tester.pump();
      h.refresh.request();
      h.gate.set(true);
      await h.run(tester);
      expect(h.asked, ['tr-4/256', for (var i = 1; i <= 5; i++) 'tr-$i/256']);
      await h.run(tester);
      expect(h.asked, hasLength(6));
      expect(h.remembered.last, isNull);
    });

    testWidgets('named while refused pins wait their turn are asked at once, '
        'and the wait goes on', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.refresh.request();
      await h.run(tester);
      expect(h.asked, hasLength(5));

      h.refresh.requestFor([four]);
      await h.run(tester);
      expect(h.asked.skip(5), ['tr-4/256']);
      // tr-2 is asked again when its wait is up, not sooner.
      await tester.pump(_retry - _pace * 80 - const Duration(seconds: 1));
      expect(h.asked, hasLength(6));
      await tester.pump(const Duration(seconds: 1));
      await h.run(tester);
      expect(h.asked.skip(6), ['tr-2/256']);
      h.refresh.dispose();
    });

    testWidgets('named at a shut gate while refused pins wait their turn are '
        'asked when it opens, and the wait goes on', (tester) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.refresh.request();
      await h.run(tester);
      await tester.pump(_retry);
      await h.run(tester);
      // Asked again once, and its next turn is two waits off.
      expect(h.asked, hasLength(4));

      h.gate.set(false);
      h.refresh.requestFor([(pid: 'tr-1', sizePx: 256)]);
      await h.run(tester);
      expect(h.asked, hasLength(4));
      h.gate.set(true);
      await h.run(tester);
      expect(h.asked.skip(4), ['tr-1/256']);

      await tester.pump(_retry);
      expect(h.asked, hasLength(5), reason: 'the wait was not cut short');
      await tester.pump(_retry);
      expect(h.asked.skip(5), ['tr-2/256']);
      h.refresh.dispose();
    });

    testWidgets('one the server does not answer for while refused pins wait '
        'their turn is asked again when the gate opens, and the wait goes '
        'on', (tester) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.refresh.request();
      await h.run(tester);
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked, hasLength(4));

      h.answers['tr-1/256'] = PinAnswer.unanswered;
      h.refresh.requestFor([(pid: 'tr-1', sizePx: 256)]);
      await h.run(tester);
      expect(h.asked.skip(4), ['tr-1/256']);
      h.answers.remove('tr-1/256');
      h.gate
        ..set(false)
        ..set(true);
      await h.run(tester);
      expect(h.asked.skip(4), ['tr-1/256', 'tr-1/256']);

      await tester.pump(_retry);
      expect(h.asked, hasLength(6), reason: 'the wait was not cut short');
      await tester.pump(_retry);
      expect(h.asked.skip(6), ['tr-2/256']);
      h.refresh.dispose();
    });

    testWidgets('a pin store that fails for one named while refused pins wait '
        'their turn is read again after a wait, whatever the gate says, and '
        'their wait goes on', (tester) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.refresh.request();
      await h.run(tester);
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked, hasLength(4));

      h.store.fails = true;
      h.refresh.requestFor([(pid: 'tr-1', sizePx: 256)]);
      await h.run(tester);
      final lookups = h.store.lookups;
      h.gate
        ..set(false)
        ..set(true);
      await h.run(tester);
      expect(h.store.lookups, lookups);

      h.store.fails = false;
      await tester.pump(_retry);
      expect(h.asked.skip(4), ['tr-1/256']);
      await tester.pump(_retry);
      expect(h.asked.skip(5), ['tr-2/256']);
      h.refresh.dispose();
    });

    testWidgets('one the server refuses is asked again with the walk\'s other '
        'refusals', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.refresh.requestFor([two]);
      await h.run(tester);
      expect(h.asked, ['tr-2/256']);
      expect(
        h.remembered.last,
        const PinWalk(passed: [two], retried: 0, whole: false),
      );

      h.answers.clear();
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked, ['tr-2/256', 'tr-2/256']);
      expect(h.remembered.last, isNull);
    });

    testWidgets('more than it holds are a walk of every pin', (tester) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.gate.open = false;
      h.refresh.requestFor([
        for (var i = 0; i <= PinRefresh.namedHeld; i++)
          (pid: 'tr-x$i', sizePx: 256),
      ]);
      await tester.pump();
      expect(h.remembered.last!.whole, isTrue);
      h.refresh.dispose();
    });
  });

  testWidgets('a pin the walk skips proves nothing of the server: refusals '
      'after it still stop the walk', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    // Not this walk's to ask (an item being freed), then a server whose
    // art reads broke.
    h.answers['tr-1/256'] = PinAnswer.skipped;
    for (var i = 2; i <= 5; i++) {
      h.answers['tr-$i/256'] = PinAnswer.refused;
    }
    h.refresh.request();
    await h.run(tester);

    expect(h.asked, [for (var i = 1; i <= 5; i++) 'tr-$i/256']);
    expect(
      h.remembered.last,
      const PinWalk(after: (pid: 'tr-1', sizePx: 256), tries: 1),
    );
    h.refresh.dispose();
  });

  testWidgets('a run forgotten while it asks goes no further, and the walk '
      'asked for since starts at the top', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.hold = Completer<void>();
    h.refresh.request();
    await tester.pump();
    expect(h.asked, ['tr-1/256']);

    // A sign-out, then covers changing, while the ask is in flight.
    h.refresh.forget();
    h.refresh.request();
    h.hold!.complete();
    h.hold = null;
    await h.run(tester);

    expect(h.asked, ['tr-1/256', for (var i = 1; i <= 5; i++) 'tr-$i/256']);
    expect(h.remembered.last, isNull);
  });

  testWidgets('a walk stopped at its first pin owes no second walk to the '
      'next request', (tester) async {
    final h = _Harness();
    addTearDown(h.refresh.dispose);
    h.answers['tr-1/256'] = PinAnswer.unanswered;
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, ['tr-1/256']);

    h.answers.clear();
    h.refresh.request();
    await h.run(tester);
    await tester.pump(_retry * 2);
    expect(h.asked, ['tr-1/256', for (var i = 1; i <= 5; i++) 'tr-$i/256']);
    expect(h.remembered.last, isNull);
  });

  testWidgets('a walk stalled back to its first pin owes no second walk '
      'either', (tester) async {
    final h = _Harness()..refuseAll = true;
    addTearDown(h.refresh.dispose);
    h.refresh.request();
    await h.run(tester);
    expect(h.asked, hasLength(4));
    expect(h.remembered.last, const PinWalk(tries: 1));

    h.refuseAll = false;
    h.refresh.request();
    await h.run(tester);
    await tester.pump(_retry * 2);
    expect(h.asked, hasLength(4 + 5));
    expect(h.remembered.last, isNull);
  });

  group('pins there are to make', () {
    testWidgets('are asked for one at a time at the pace, after the named '
        'and ahead of the rest of a walk, which is paced with them', (
      tester,
    ) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.refresh.request();
      await tester.pump();
      expect(h.asked, ['tr-1/256']);

      h.refresh.want(_toMake(['tr-0/1024', 'tr-0/256']));
      h.refresh.requestFor([(pid: 'tr-3', sizePx: 256)]);
      final expected = [
        'tr-1/256',
        'tr-3/256',
        '+tr-0/1024',
        '+tr-0/256',
        'tr-2/256',
        'tr-3/256',
      ];
      for (var n = 2; n <= expected.length; n++) {
        await tester.pump(_pace - const Duration(milliseconds: 1));
        expect(h.asked, expected.take(n - 1), reason: 'no sooner');
        await tester.pump(const Duration(milliseconds: 1));
        expect(h.asked, expected.take(n));
      }
      await h.run(tester);
      expect(h.asked, expected);
      expect(h.mostInFlight, 1);
      expect(h.remembered.last, isNull);
    });

    testWidgets('with none wanted the gate is not looked at and nothing is '
        'remembered', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.refresh.want(const {});
      await h.run(tester);
      expect(h.gate.asks, 0);
      expect(h.asked, isEmpty);
      expect(h.remembered, isEmpty);
    });

    testWidgets('are not the walk\'s to remember: with only those owed it '
        'remembers nothing', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.refresh.want(_toMake(['tr-0/1024', 'tr-0/256']));
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024', '+tr-0/256']);
      expect(h.remembered, everyElement(isNull));
    });

    testWidgets('wait at a shut gate, and a gate that shuts between two '
        'holds the next', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.gate.open = false;
      h.refresh.want(_toMake(['tr-0/1024', 'tr-0/256']));
      await h.run(tester);
      expect(h.asked, isEmpty);

      h.gate.set(true);
      await tester.pump();
      expect(h.asked, ['+tr-0/1024']);
      h.gate.set(false);
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024']);

      h.gate.set(true);
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024', '+tr-0/256']);
    });

    testWidgets('the gate is looked at once a page of them', (tester) async {
      final h = _Harness(pageSize: 2);
      addTearDown(h.refresh.dispose);
      h.refresh.want(
        _toMake(['tr-0/1024', 'tr-0/256', 'tr-00/1024', 'tr-00/256']),
      );
      await h.run(tester);
      expect(h.asked, hasLength(4));
      expect(h.gate.asks, 2);
    });

    testWidgets('one the server does not answer for stops the walk and goes '
        'behind the rest, its item\'s other sizes with it', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.answers['tr-0/1024'] = PinAnswer.unanswered;
      h.refresh.want(_toMake(['tr-0/1024', 'tr-0/256', 'tr-00/1024']));
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024']);

      // Left alone until the walk's wait is up.
      await tester.pump(_retry - _pace * 40 - const Duration(seconds: 1));
      expect(h.asked, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024', '+tr-00/1024', '+tr-0/1024']);

      h.answers.clear();
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked.skip(3), ['+tr-0/1024', '+tr-0/256']);
      expect(h.remembered.last, isNull);
    });

    testWidgets('wanted again, as each reach wants them, the rest are asked '
        'for at once where the walk had stopped for no answer, and the one '
        'that got none when its wait is up', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.answers['tr-0/1024'] = PinAnswer.unanswered;
      final wanted = _toMake(['tr-0/1024', 'tr-00/1024']);
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024']);

      h.answers.clear();
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024', '+tr-00/1024']);
      await tester.pump(_retry - _pace * 80 - const Duration(seconds: 1));
      expect(h.asked, hasLength(2));
      await tester.pump(const Duration(seconds: 1));
      expect(h.asked, ['+tr-0/1024', '+tr-00/1024', '+tr-0/1024']);
      h.refresh.dispose();
    });

    testWidgets('one the server refuses does not hold the rest, and is '
        'asked again in the rounds the walk asks its own refusals in', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.answers['tr-0/1024'] = PinAnswer.refused;
      final wanted = _toMake(['tr-0/1024', 'tr-0/256']);
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024', '+tr-0/256']);
      expect(
        h.remembered.last,
        const PinWalk(
          passed: [(pid: 'tr-0', sizePx: 1024)],
          retried: 0,
          whole: false,
        ),
      );

      // Wanted again meanwhile, it keeps its turn among the refusals.
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked, hasLength(2));

      await tester.pump(_retry * 16);
      expect(h.asked.skip(2), [
        for (var round = 0; round < PinRefresh.retryRounds; round++)
          '+tr-0/1024',
      ]);
      expect(h.remembered.last, isNull);

      // Out of rounds, it is given up: wanted again once its cover may
      // be another, and not by a reach before.
      await tester.pump(_retry * 16);
      expect(h.asked, hasLength(5));
      h.answers.clear();
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked, hasLength(5));
      h.refresh.wantAgain('tr-0');
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked.skip(5), ['+tr-0/1024']);
    });

    testWidgets('one pinned since it was wanted, or wanted no more, is not '
        'asked for', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.gate.open = false;
      h.refresh.want(_toMake(['tr-0/1024', 'tr-0/256', 'tr-00/1024']));
      await tester.pump();
      // Its download's own start pinned one; another was removed.
      h.store.add('tr-0', 1024);
      h.refresh.want(_toMake(['tr-0/1024', 'tr-0/256']));
      h.gate.set(true);
      await h.run(tester);
      expect(h.asked, ['+tr-0/256']);
    });

    testWidgets('forgotten, none is asked for, and one on its way is not '
        'taken for an answer to what is wanted after', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.hold = Completer<void>();
      final wanted = _toMake(['tr-0/1024', 'tr-0/256']);
      h.answers['tr-0/1024'] = PinAnswer.skipped;
      h.refresh.want(wanted);
      await tester.pump();
      expect(h.asked, ['+tr-0/1024']);

      // A sign-out, and the next account's reach, with it in flight.
      h.refresh.forget();
      h.refresh.want(wanted);
      h.answers.clear();
      h.hold!.complete();
      h.hold = null;
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024', '+tr-0/1024', '+tr-0/256']);

      h.refresh.want(_toMake(['tr-00/1024', 'tr-00/256']));
      h.refresh.forget();
      await h.run(tester);
      await tester.pump(_retry);
      expect(h.asked, hasLength(3));
    });

    testWidgets('one the server never answers for does not hold back the '
        'pinned covers owed a fresh ask: they go first, and it once its '
        'wait is up', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.answers['tr-0/1024'] = PinAnswer.unanswered;
      h.refresh.want(_toMake(['tr-0/1024']));
      h.refresh.request();
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024']);

      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked, [
        '+tr-0/1024',
        for (var i = 1; i <= 5; i++) 'tr-$i/256',
        '+tr-0/1024',
      ]);
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked.skip(7), ['+tr-0/1024']);
      h.refresh.dispose();
    });

    testWidgets('nor is it held back for good by a pinned cover that never '
        'answers: the two take turns', (tester) async {
      final h = _Harness(pins: 2);
      addTearDown(h.refresh.dispose);
      h.answers['tr-9/1024'] = PinAnswer.unanswered;
      h.answers['tr-1/256'] = PinAnswer.unanswered;
      h.refresh.want(_toMake(['tr-9/1024']));
      h.refresh.request();
      await h.run(tester);
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked, ['+tr-9/1024', 'tr-1/256']);

      h.answers.remove('tr-9/1024');
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked, ['+tr-9/1024', 'tr-1/256', '+tr-9/1024', 'tr-1/256']);
      h.refresh.dispose();
    });

    testWidgets('one the server never answers for is asked for no more than '
        'once a wait, however often the socket drops and comes back', (
      tester,
    ) async {
      final h = _Harness(pins: 0);
      addTearDown(h.refresh.dispose);
      h.answers['tr-0/1024'] = PinAnswer.unanswered;
      final wanted = _toMake(['tr-0/1024']);
      h.refresh.want(wanted);
      await tester.pump();
      expect(h.asked, ['+tr-0/1024']);

      // Once a second the gate shuts and opens, and the reach wants it
      // again.
      const second = Duration(seconds: 1);
      for (var at = second; at < _retry * 2; at += second) {
        await tester.pump(second);
        h.gate
          ..set(false)
          ..set(true);
        h.refresh.want(wanted);
        await tester.pump();
        expect(h.asked, hasLength(at < _retry ? 1 : 2), reason: 'after $at');
      }
      h.refresh.dispose();
    });

    testWidgets('a run of them refused stops the walk as a run of pinned '
        'covers refused does: the same are asked for three times, then '
        'passed', (tester) async {
      final h = _Harness(pins: 0)..refuseAll = true;
      addTearDown(h.refresh.dispose);
      final first = [for (var i = 0; i < 4; i++) '+tr-0$i/1024'];
      h.refresh.want(_toMake([for (var i = 0; i < 6; i++) 'tr-0$i/1024']));
      await h.run(tester);
      expect(h.asked, first);
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked.skip(4), first);
      await tester.pump(_retry);
      await h.run(tester);
      // The third time through, nothing stops it.
      expect(h.asked.skip(8), [...first, '+tr-04/1024', '+tr-05/1024']);
      // And each is asked for again in the rounds.
      await tester.pump(_retry * 16);
      expect(h.asked, hasLength(14 + 6 * PinRefresh.retryRounds));
      expect(h.remembered.last, isNull);
    });

    testWidgets('a run of them refused while refused pins wait their turn '
        'stops the walk too, and the turn of those is kept', (tester) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.refresh.request();
      await h.run(tester);
      expect(h.asked, hasLength(3));

      // Its art reads broke: the pin that answered last refuses too.
      h.refuseAll = true;
      final made = [for (var i = 0; i < 4; i++) '+tr-0$i/1024'];
      h.refresh.want(_toMake([for (var i = 0; i < 4; i++) 'tr-0$i/1024']));
      await h.run(tester);
      expect(h.asked.skip(3), [...made, 'tr-3/256']);
      expect(
        h.remembered.last,
        const PinWalk(
          after: (pid: 'tr-3', sizePx: 256),
          tries: 1,
          passed: [(pid: 'tr-2', sizePx: 256)],
          retried: 0,
        ),
      );

      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked.skip(8), [...made, 'tr-3/256']);
      // The third time they are passed, and asked again with the rest.
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked.skip(13), [...made, 'tr-3/256', 'tr-2/256', ...made]);
      h.refresh.dispose();
    });

    testWidgets('one refused while refused pins waited their turn is no run '
        'of refusals left over once their rounds are spent', (tester) async {
      final h = _Harness(pins: 2);
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.answers['tr-0/1024'] = PinAnswer.unanswered;
      h.answers['tr-00/1024'] = PinAnswer.refused;
      h.refresh.request();
      await h.run(tester);
      expect(h.asked, ['tr-1/256', 'tr-2/256']);

      // One that never answers keeps the walk in being, and one refused
      // joins the rounds.
      h.refresh.want(_toMake(['tr-0/1024', 'tr-00/1024']));
      await tester.pump(_retry * 16);
      expect(
        h.asked.where((name) => name == '+tr-00/1024'),
        hasLength(1 + PinRefresh.retryRounds),
      );
      expect(h.asked.where((name) => name == 'tr-1/256'), hasLength(1));
      h.refresh.dispose();
    });

    testWidgets('one broken cover over many of them costs the walk no pause: '
        'the last pin that answered is asked again, and answers', (
      tester,
    ) async {
      final h = _Harness(pins: 0);
      addTearDown(h.refresh.dispose);
      for (var i = 1; i <= 8; i++) {
        h.answers['tr-0$i/1024'] = PinAnswer.refused;
      }
      h.refresh.want(
        _toMake(['tr-0/1024', for (var i = 1; i <= 8; i++) 'tr-0$i/1024']),
      );
      await h.run(tester);
      expect(h.asked, [
        '+tr-0/1024',
        for (var i = 1; i <= 4; i++) '+tr-0$i/1024',
        'tr-0/1024',
        for (var i = 5; i <= 8; i++) '+tr-0$i/1024',
        'tr-0/1024',
      ]);
      expect(h.remembered.last?.passed, hasLength(8));
      h.refresh.dispose();
    });

    testWidgets('against a server that refuses every one, the covers of six '
        'hundred downloads are asked for once and those kept in their '
        'rounds, whatever reaches come in between', (tester) async {
      final h = _Harness(pins: 0, pageSize: 32)..refuseAll = true;
      addTearDown(h.refresh.dispose);
      final wanted = _toMake([
        for (var i = 0; i < 600; i++) ...[
          'tr-${1000 + i}/1024',
          'tr-${1000 + i}/256',
        ],
      ]);
      // Two reaches stop at the same four, and the third goes on past
      // them.
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked, hasLength(4));
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked, hasLength(8));
      h.refresh.want(wanted);
      await tester.pump(_pace * 1300);
      expect(h.asked, hasLength(8 + 1200));

      // Reaches while those kept wait their rounds ask for nothing.
      for (var reach = 0; reach < 3; reach++) {
        h.refresh.want(wanted);
        await h.run(tester);
      }
      expect(h.asked, hasLength(8 + 1200));
      await tester.pump(_retry * 16);
      expect(
        h.asked,
        hasLength(8 + 1200 + PinRefresh.passedHeld * PinRefresh.retryRounds),
      );
      expect(h.remembered.last, isNull);

      // Out of rounds they are given up, until every cover may be
      // another.
      h.asked.clear();
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked, isEmpty);
      h.refresh.wantAgain(null);
      h.refresh.want(wanted);
      await h.run(tester);
      expect(h.asked, hasLength(4));
      h.refresh.dispose();
    });

    testWidgets('wanted at a shut gate while refused pins wait their turn, '
        'they are asked for when it is looked at again, and the wait goes '
        'on', (tester) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.refresh.request();
      await h.run(tester);
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked, hasLength(4));

      h.gate.set(false);
      h.refresh.want(_toMake(['tr-0/1024']));
      await h.run(tester);
      expect(h.asked, hasLength(4));
      // Open again, and nobody said so.
      h.gate.open = true;
      await tester.pump(_retry);
      expect(h.asked.skip(4), ['+tr-0/1024']);
      await tester.pump(_retry);
      expect(h.asked.skip(5), ['tr-2/256']);
      h.refresh.dispose();
    });

    testWidgets('one not kept once it was asked for is followed by the pace '
        'all the same', (tester) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      // Its item freed while its cover was on the way.
      h.answers['tr-0/1024'] = PinAnswer.skipped;
      h.refresh.want(_toMake(['tr-0/1024', 'tr-0/256']));
      await tester.pump();
      expect(h.asked, ['+tr-0/1024']);
      await tester.pump(_pace - const Duration(milliseconds: 1));
      expect(h.asked, ['+tr-0/1024']);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.asked, ['+tr-0/1024', '+tr-0/256']);
      h.refresh.dispose();
    });

    testWidgets('nor is one asked for again among the refusals and not kept', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.refresh.dispose);
      h.answers['tr-0/1024'] = PinAnswer.refused;
      h.answers['tr-0/256'] = PinAnswer.refused;
      h.refresh.want(_toMake(['tr-0/1024', 'tr-0/256', 'tr-00/1024']));
      await h.run(tester);
      expect(h.asked, hasLength(3));

      h.answers['tr-0/1024'] = PinAnswer.skipped;
      // The round sets out a wait after the last of the three was paced.
      await tester.pump(
        _retry - _pace * 40 + _pace * 3 + const Duration(milliseconds: 50),
      );
      expect(h.asked.skip(3), ['+tr-0/1024']);
      await tester.pump(_pace ~/ 2);
      expect(h.asked.skip(3), ['+tr-0/1024']);
      await tester.pump(_pace);
      expect(h.asked.skip(3), ['+tr-0/1024', '+tr-0/256']);
      h.refresh.dispose();
    });

    testWidgets('one asked for again among the refusals that gets no answer '
        'leaves the round to the rest, and is asked for when its wait is '
        'up', (tester) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.answers['tr-0/1024'] = PinAnswer.refused;
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.refresh.want(_toMake(['tr-0/1024']));
      h.refresh.request();
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024', 'tr-1/256', 'tr-2/256', 'tr-3/256']);

      h.answers['tr-0/1024'] = PinAnswer.unanswered;
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked.skip(4), ['+tr-0/1024']);

      // The round goes on with the rest, and it is asked for after.
      h.answers.remove('tr-0/1024');
      await tester.pump(_retry);
      await h.run(tester);
      expect(h.asked.skip(5), ['tr-2/256', '+tr-0/1024']);
      h.refresh.dispose();
    });

    testWidgets('a gate that shuts and opens while the rest of the walk takes '
        'its turn does not cut short the wait that turn ends in', (
      tester,
    ) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.answers['tr-0/1024'] = PinAnswer.unanswered;
      h.refresh.want(_toMake(['tr-0/1024']));
      h.refresh.request();
      await h.run(tester);
      expect(h.asked, ['+tr-0/1024']);

      h.answers.remove('tr-0/1024');
      await tester.pump(_retry - _pace * 40);
      expect(h.asked, ['+tr-0/1024', 'tr-1/256']);
      await tester.pump(_pace ~/ 2);
      h.gate
        ..set(false)
        ..set(true);
      await h.run(tester);
      // The one set aside is asked for under the wait before the first
      // round, which stands.
      expect(h.asked, [
        '+tr-0/1024',
        'tr-1/256',
        'tr-2/256',
        'tr-3/256',
        '+tr-0/1024',
      ]);
      await tester.pump(_retry);
      expect(h.asked.skip(5), ['tr-2/256']);
      h.refresh.dispose();
    });

    testWidgets('wanted while the refused pins are being asked again, they '
        'are asked for when that round is done, and its wait goes on', (
      tester,
    ) async {
      final h = _Harness(pins: 6);
      addTearDown(h.refresh.dispose);
      for (final n in [2, 4, 6]) {
        h.answers['tr-$n/256'] = PinAnswer.refused;
      }
      h.refresh.request();
      await h.run(tester);
      expect(h.asked, hasLength(6));

      h.hold = Completer<void>();
      await tester.pump(_retry);
      expect(h.asked.skip(6), ['tr-2/256']);
      h.refresh.want(_toMake(['tr-0/1024']));
      h.hold!.complete();
      h.hold = null;
      await h.run(tester);
      expect(h.asked.skip(6), [
        'tr-2/256',
        'tr-4/256',
        'tr-6/256',
        '+tr-0/1024',
      ]);

      await tester.pump(_retry);
      expect(h.asked, hasLength(10), reason: 'the wait was not cut short');
      await tester.pump(_retry);
      expect(h.asked.skip(10), ['tr-2/256', 'tr-4/256', 'tr-6/256']);
      h.refresh.dispose();
    });

    testWidgets('covers changing while that wait is being written, with one '
        'wanted meanwhile, still start the walk over at once', (tester) async {
      final h = _Harness(pins: 3);
      addTearDown(h.refresh.dispose);
      h.answers['tr-2/256'] = PinAnswer.refused;
      h.refresh.request();
      await h.run(tester);
      expect(h.asked, hasLength(3));

      h.hold = Completer<void>();
      await tester.pump(_retry);
      expect(h.asked.skip(3), ['tr-2/256']);
      h.refresh.want(_toMake(['tr-9/1024']));
      h.holdRemember = Completer<void>();
      h.hold!.complete();
      h.hold = null;
      await tester.pump(_pace);
      h.refresh.request();
      h.holdRemember!.complete();
      h.holdRemember = null;
      await h.run(tester);
      expect(h.asked.skip(4), [
        '+tr-9/1024',
        'tr-1/256',
        'tr-2/256',
        'tr-3/256',
        'tr-9/1024',
      ]);
      h.refresh.dispose();
    });

    testWidgets('against a server that refuses every one, a socket that '
        'drops and comes back once a second for an hour has the covers of '
        'six hundred downloads asked for once through, and then no more', (
      tester,
    ) async {
      final h = _Harness(pins: 0, pageSize: 32)..refuseAll = true;
      addTearDown(h.refresh.dispose);
      final wanted = _toMake([
        for (var i = 0; i < 600; i++) ...[
          'tr-${1000 + i}/1024',
          'tr-${1000 + i}/256',
        ],
      ]);
      // The same four three times, each size once, and those kept in
      // each of the rounds.
      const through =
          2 * PinRefresh.refusedRun +
          1200 +
          PinRefresh.passedHeld * PinRefresh.retryRounds;
      h.refresh.want(wanted);
      await tester.pump();
      const second = Duration(seconds: 1);
      final byTenMinutes = <int>[];
      for (var s = 1; s <= 3600; s++) {
        await tester.pump(second);
        h.gate
          ..set(false)
          ..set(true);
        h.refresh.want(wanted);
        await tester.pump();
        if (s % 600 == 0) byTenMinutes.add(h.asked.length);
      }
      expect(through, 1976);
      expect(byTenMinutes.skip(2), everyElement(through));
      expect(h.remembered.last, isNull);

      // One item named replaced is asked for again at the next reach,
      // and no other.
      h.refresh.wantAgain('tr-1000');
      h.refresh.want(wanted);
      await tester.pump(_retry * 16);
      expect(h.asked.skip(through), [
        for (var n = 0; n < 3 + PinRefresh.retryRounds; n++) ...[
          '+tr-1000/1024',
          '+tr-1000/256',
        ],
      ]);
      h.refresh.dispose();

      // The next start wants them all, and the server answers by then.
      final next = _Harness(pins: 0, pageSize: 32, over: h.store);
      addTearDown(next.refresh.dispose);
      next.refresh.want(wanted);
      await tester.pump(_pace * 1300);
      expect(next.asked, hasLength(1200));
      expect(next.store.names, hasLength(1200));
      expect(next.remembered.last, isNull);
    });
  });

  test('a download is heard when it starts moving and when it stops, not '
      'for the progress between', () async {
    final progress = StreamController<DownloadProgress>.broadcast(sync: true);
    addTearDown(progress.close);
    var turns = 0;
    final heard = downloadTurns(progress.stream).listen((_) => turns++);
    addTearDown(heard.cancel);
    DownloadProgress at(
      String pid,
      double fraction, {
      bool complete = false,
      bool stopped = false,
      bool paused = false,
    }) => DownloadProgress(
      pid: pid,
      fraction: fraction,
      complete: complete,
      stopped: stopped,
      paused: paused,
    );

    progress.add(at('tr-1', 0.1));
    expect(turns, 1);
    for (var i = 2; i < 9; i++) {
      progress.add(at('tr-1', i / 10));
    }
    expect(turns, 1);
    progress.add(at('tr-2', 0.1));
    expect(turns, 2);
    progress.add(at('tr-1', 1, complete: true));
    expect(turns, 3);
    progress.add(at('tr-2', 0.5, paused: true));
    expect(turns, 4);
    // Lifted, it moves again.
    progress.add(at('tr-2', 0.5));
    progress.add(at('tr-2', 0.6));
    expect(turns, 5);
    // One this never saw moving still ends.
    progress.add(at('tr-3', 0, stopped: true));
    expect(turns, 6);
  });

  group('what holds a walk back', () {
    late bool reachable;
    late bool waiting;
    late bool downloading;
    late _Gate wifi;
    late StreamController<void> moved;
    late PinRefreshGate gate;

    setUp(() {
      reachable = true;
      waiting = false;
      downloading = false;
      wifi = _Gate();
      moved = StreamController<void>.broadcast(sync: true);
      gate = PinRefreshGate(
        reachable: () => reachable,
        playbackWaiting: () => waiting,
        transfers: () => wifi,
        downloading: () async => downloading,
        moved: () => <Stream<void>>[moved.stream],
      );
    });

    test('open with the server reachable, the network allowed, nothing '
        'downloading and playback not waiting on the network', () async {
      expect(await gate.isOpen(), isTrue);
    });

    test('shut by any one of them', () async {
      reachable = false;
      expect(await gate.isOpen(), isFalse);
      reachable = true;

      waiting = true;
      expect(await gate.isOpen(), isFalse);
      waiting = false;

      wifi.open = false;
      expect(await gate.isOpen(), isFalse);
      wifi.open = true;

      downloading = true;
      expect(await gate.isOpen(), isFalse);
      downloading = false;
      expect(await gate.isOpen(), isTrue);
    });

    test('shut where one of them cannot be read', () async {
      final broken = PinRefreshGate(
        reachable: () => throw StateError('disposed'),
        playbackWaiting: () => false,
        transfers: () => wifi,
        downloading: () async => false,
        moved: () => const <Stream<void>>[],
      );
      expect(await broken.isOpen(), isFalse);
    });

    test('says so when any of them moves, and only when its answer '
        'does', () async {
      final said = <bool>[];
      final listening = gate.changes.listen(said.add);
      addTearDown(listening.cancel);

      downloading = true;
      moved.add(null);
      await pumpEventQueue();
      expect(said, [false]);

      // Still held: another download's progress says nothing new.
      moved.add(null);
      await pumpEventQueue();
      expect(said, [false]);

      downloading = false;
      moved.add(null);
      await pumpEventQueue();
      expect(said, [false, true]);

      wifi.set(false);
      await pumpEventQueue();
      expect(said, [false, true, false]);
      wifi.set(true);
      await pumpEventQueue();
      expect(said, [false, true, false, true]);
    });
  });
}

class _Gate implements TransferGate {
  bool open = true;
  final StreamController<bool> _changes = StreamController<bool>.broadcast(
    sync: true,
  );

  void set(bool value) {
    open = value;
    _changes.add(value);
  }

  /// How often it was asked in full.
  int asks = 0;

  @override
  Future<bool> isOpen() async {
    asks++;
    return open;
  }

  /// Like the gate the app builds, it tells each new listener where it
  /// stands, a moment after it listens.
  @override
  Stream<bool> get changes => Stream<bool>.multi((listener) {
    final heard = _changes.stream.listen(listener.add);
    scheduleMicrotask(() {
      if (!listener.isClosed) listener.add(open);
    });
    listener.onCancel = heard.cancel;
  });
}

class _Pins implements ArtworkPinStore {
  final SplayTreeMap<String, ArtworkPinRecord> _held =
      SplayTreeMap<String, ArtworkPinRecord>();

  bool fails = false;

  /// How often a page was read, and how often one item's pins were.
  int reads = 0;
  int lookups = 0;

  /// Every pin's name, in the order they are walked.
  List<String> get names => _held.keys.toList();

  void add(String pid, int sizePx) => _held['$pid/$sizePx'] = ArtworkPinRecord(
    pid: pid,
    sizePx: sizePx,
    artUrl: '/api/v1/items/$pid/art',
    etag: '"a"',
    localPath: '/art/$pid-$sizePx.img',
    sizeBytes: 1,
    pinnedAt: DateTime.utc(2026, 11, 18),
  );

  @override
  Future<List<ArtworkPinRecord>> pinsAfter(
    PinCursor? after, {
    required int limit,
  }) async {
    reads++;
    // Bounded, so a walk that reads again with no wait fails the test
    // rather than spinning it.
    if (fails && reads < 50) throw StateError('the database is closed');
    final from = after == null ? null : '${after.pid}/${after.sizePx}';
    return [
      for (final entry in _held.entries)
        if (from == null || entry.key.compareTo(from) > 0) entry.value,
    ].take(limit).toList();
  }

  @override
  Future<List<ArtworkPinRecord>> pinsFor(String pid) async {
    lookups++;
    if (fails) throw StateError('the database is closed');
    return [
      for (final pin in _held.values)
        if (pin.pid == pid) pin,
    ].reversed.toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
