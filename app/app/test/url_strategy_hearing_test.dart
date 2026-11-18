import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/browser_history/browser_history_port.dart';
// The wrapper itself is plain Dart, and the url strategy library has a
// stub off the web, so the wrapper is read on the VM.
import 'package:waxdeck/src/shell/url_strategy/url_strategy_web.dart';

import 'fake_browser.dart';

void main() {
  // What the file keeps is module state: each test starts from a fresh
  // document's, in whatever order the tests run.
  setUp(resetUrlStrategyState);
  tearDown(resetUrlStrategyState);

  test('the app hears a browser move before the engine does', () {
    final heard = <String>[];
    addTearDown(
      hearBrowserMoves(() {
        heard.add('app');
        return false;
      }),
    );

    heardFirst((state) => heard.add('engine $state'))('entry');

    expect(heard, <String>['app', 'engine entry']);
  });

  group('the engine holding more than one handler', () {
    // The engine's history registers one, and its `go` another while it
    // waits for the move it made, which removes itself once heard.
    late List<void Function(Object? state)> browser;
    late EngineMoveHandlers engine;
    setUp(() {
      browser = <void Function(Object? state)>[];
      engine = EngineMoveHandlers((fn) {
        browser.add(fn);
        return () => browser.remove(fn);
      });
    });

    void popState(Object? state) {
      for (final fn in List.of(browser)) {
        fn(state);
      }
    }

    test('the app hears each move once', () {
      final heard = <String>[];
      addTearDown(
        hearBrowserMoves(() {
          heard.add('app');
          return false;
        }),
      );
      engine.add((state) => heard.add('history $state'));
      late void Function() stop;
      stop = engine.add((state) {
        stop();
        heard.add('go $state');
      });

      popState('entry');
      expect(heard, <String>['app', 'history entry', 'go entry']);

      heard.clear();
      popState('next');
      expect(heard, <String>['app', 'history next']);
    });

    test('a move the app takes reaches none of them, and is handed to '
        'each', () {
      final heard = <String>[];
      final stop = hearBrowserMoves(() => true);
      engine
        ..add((state) => heard.add('history'))
        ..add((state) => heard.add('go'));

      popState(<Object?, Object?>{'serialCount': 3.0});
      stop();
      expect(heard, isEmpty);

      handOnTaken();
      expect(heard, <String>['history', 'go']);
    });

    test('with every handler removed, the browser is not listened to', () {
      final first = engine.add((state) {});
      final second = engine.add((state) {});
      expect(browser, isNotEmpty);

      first();
      second();
      second();

      expect(browser, isEmpty);
    });
  });

  test('a move the app takes never reaches the engine', () {
    final heard = <String>[];
    heardFirst((state) {})(<Object?, Object?>{'serialCount': 4.0});
    addTearDown(hearBrowserMoves(() => true));

    heardFirst((state) => heard.add('engine'))(<Object?, Object?>{
      'serialCount': 3.0,
    });

    expect(heard, isEmpty);
    expect(shownEntry, 4, reason: 'still the entry the engine is on');
  });

  test('a move handed on is the entry shown', () {
    heardFirst((state) {})(<Object?, Object?>{'serialCount': 2.0});

    expect(shownEntry, 2);
  });

  test('the newest entry the engine pushed is the last of the app', () {
    entryWritten(<Object?, Object?>{'serialCount': 0.0}, pushed: false);
    expect(topEntry, isNull, reason: 'what lies ahead is not known yet');

    entryWritten(<Object?, Object?>{'serialCount': 5.0}, pushed: true);
    expect(topEntry, 5);
    entryWritten(<Object?, Object?>{'serialCount': 3.0}, pushed: true);
    expect(topEntry, 3, reason: 'a push drops the entries ahead');
    entryWritten(<Object?, Object?>{'serialCount': 2.0}, pushed: false);
    expect(topEntry, 3, reason: 'written over one behind it');
    expect(shownEntry, 2);
    entryWritten(<Object?, Object?>{'serialCount': 4.0}, pushed: false);
    expect(topEntry, 4, reason: 'an entry renumbered past it');
  });

  test('the newest entry is told as it moves, and a reload takes it up '
      'again', () {
    final told = <int>[];
    topEntryMoved = told.add;
    addTearDown(() => topEntryMoved = null);
    entryWritten(<Object?, Object?>{'serialCount': 6.0}, pushed: true);
    entryWritten(<Object?, Object?>{'serialCount': 6.0}, pushed: false);
    entryWritten(<Object?, Object?>{'serialCount': 2.0}, pushed: true);
    expect(told, [6, 2], reason: 'each move once, a push dropping those ahead');

    seedTopEntry(9);
    expect(topEntry, 9);
    expect(newestAcrossLoad('reload', kept: 9), 9);
    expect(newestAcrossLoad('reload', kept: null), isNull);
    expect(
      newestAcrossLoad('back_forward', kept: 9),
      isNull,
      reason: 'the tab may have dropped entries ahead since',
    );
    expect(newestAcrossLoad('navigate', kept: 9), isNull);
  });

  testWidgets('after a reload or a return, the fake answers a step forward '
      'as this half does', (tester) async {
    // This half keeps the newest entry the engine pushed for the tab, and a
    // reload takes it up again: the entries ahead are still the tab's. A
    // return to the document from another keeps nothing, so no step
    // forward is asked into what lies ahead until the engine pushes.
    final browser = FakeBrowser();
    Future<void> report(String uri, {required bool replace}) =>
        SystemNavigator.routeInformationUpdated(
          uri: Uri.parse(uri),
          replace: replace,
        );
    await report('/', replace: true);
    await report('/tasks', replace: false);
    await report('/radio', replace: false);
    browser
      ..goBack()
      ..goBack();
    await tester.pump(Duration.zero);
    expect(browser.index, 0);
    expect(browser.canStepForward, isTrue);
    expect(browser.newestKnown, isTrue);

    browser.reload();
    expect(browser.canStepForward, isTrue, reason: 'kept across the reload');
    expect(browser.newestKnown, isTrue);
    await report('/', replace: true);
    expect(browser.canStepForward, isTrue, reason: 'a write in place');

    browser.reload(returning: true);
    expect(browser.canStepForward, isFalse, reason: 'nothing kept');
    expect(browser.newestKnown, isFalse);
    await report('/', replace: true);
    expect(browser.canStepForward, isFalse, reason: 'a write in place');
    expect(browser.newestKnown, isFalse);

    await report('/notifications', replace: false);
    expect(browser.canStepForward, isFalse, reason: 'the newest');
    expect(browser.newestKnown, isTrue);
    browser.goBack();
    await tester.pump(Duration.zero);
    expect(browser.canStepForward, isTrue);
  });

  testWidgets('the fake numbers an entry written away from the one the '
      'engine is on as this half does', (tester) async {
    // The engine, on its third entry, pushes a fourth while the browser
    // is on the first: written there, it is the second.
    final browser = FakeBrowser();
    Future<void> report(String uri, {required bool replace}) =>
        SystemNavigator.routeInformationUpdated(
          uri: Uri.parse(uri),
          replace: replace,
        );
    await report('/', replace: true);
    await report('/tasks', replace: false);
    await report('/radio', replace: false);
    browser
      ..listen(() => true)
      ..hold()
      ..jump(-2);
    await tester.pump(Duration.zero);
    expect(browser.position, 0);
    await report('/uploads', replace: false);

    expect(browser.release(past: true), isTrue);

    expect([for (final entry in browser.entries) entry.serial], <int>[0, 1]);
    expect(
      numberedFrom(
        <Object?, Object?>{'serialCount': 0.0},
        <Object?, Object?>{'serialCount': 3.0, 'state': null},
        pushed: true,
      ),
      <Object?, Object?>{'serialCount': 1.0, 'state': null},
    );
    expect(browser.shown, 1, reason: 'where the engine now is');
  });

  group('an entry the engine writes is numbered', () {
    Map<Object?, Object?> entry(int count, [Object? state]) =>
        <Object?, Object?>{'serialCount': count.toDouble(), 'state': state};

    test('one up from the entry the browser is on where it is pushed', () {
      // The engine holds the app to be on its sixth entry.
      expect(
        numberedFrom(entry(2), entry(6, 'radio'), pushed: true),
        entry(3, 'radio'),
      );
    });

    test('as the entry the browser is on where it is written in place', () {
      expect(
        numberedFrom(entry(2), entry(5, 'radio'), pushed: false),
        entry(2, 'radio'),
      );
    });

    test('as the engine numbers it where the browser is on its entry', () {
      expect(
        numberedFrom(entry(5), entry(6, 'radio'), pushed: true),
        entry(6, 'radio'),
      );
      expect(
        numberedFrom(entry(5), entry(5, 'radio'), pushed: false),
        entry(5, 'radio'),
      );
    });

    test('by the engine alone on an entry the browser made itself', () {
      expect(numberedFrom(null, entry(4), pushed: false), entry(4));
      expect(
        numberedFrom(<Object?, Object?>{}, entry(4), pushed: false),
        entry(4),
      );
    });

    test('not at all where the engine writes no number', () {
      // The engine unwraps the first entry's state as it shuts down.
      expect(numberedFrom(entry(0), 'bare', pushed: false), 'bare');
    });
  });

  test('an entry the engine numbers as it is handed on is the newest', () {
    // One the browser made itself, which drops what lay ahead; the
    // engine numbers it one up from the entry it was on.
    entryWritten(<Object?, Object?>{'serialCount': 7.0}, pushed: true);
    entryWritten(<Object?, Object?>{'serialCount': 2.0}, pushed: false);

    heardFirst(
      (state) => entryWritten(<Object?, Object?>{
        'serialCount': 3.0,
        'state': state,
      }, pushed: false),
    )(null);

    expect(shownEntry, 3);
    expect(topEntry, 3);
  });

  test('a move taken is handed to the engine later, once', () {
    final heard = <Object?>[];
    final stop = hearBrowserMoves(() => true);
    final engine = heardFirst(heard.add);
    engine(<Object?, Object?>{'serialCount': 5.0});
    stop();
    expect(heard, isEmpty);

    handOnTaken();
    handOnTaken();

    expect(heard, <Object?>[
      <Object?, Object?>{'serialCount': 5.0},
    ]);
    expect(shownEntry, 5);
  });

  test('a move taken is not handed on after a later move or a write', () {
    final heard = <Object?>[];
    final stop = hearBrowserMoves(() => true);
    final engine = heardFirst(heard.add);
    engine(<Object?, Object?>{'serialCount': 5.0});
    stop();
    entryWritten(<Object?, Object?>{'serialCount': 6.0}, pushed: true);
    handOnTaken();
    expect(heard, isEmpty, reason: 'written over');

    addTearDown(hearBrowserMoves(() => true));
    engine(<Object?, Object?>{'serialCount': 5.0});
    engine(<Object?, Object?>{'serialCount': 4.0});
    handOnTaken();
    expect(heard, <Object?>[
      <Object?, Object?>{'serialCount': 4.0},
    ], reason: 'the later move');
  });

  test('a listener that throws does not keep the move from the engine', () {
    final heard = <String>[];
    addTearDown(hearBrowserMoves(() => throw StateError('listener')));

    expect(
      () => heardFirst((state) => heard.add('engine $state'))('entry'),
      throwsStateError,
    );
    expect(heard, <String>['engine entry']);
  });

  test('a listener stopped hears nothing more', () {
    final heard = <String>[];
    hearBrowserMoves(() {
      heard.add('app');
      return false;
    })();

    heardFirst((state) => heard.add('engine'))(null);

    expect(heard, <String>['engine']);
  });

  group('the entries the engine writes', () {
    // While the browser is behind the entry the engine writes to, a write
    // would land on the wrong one: held, then written once it is back.
    late List<String> browser;
    late EngineWrites writes;
    setUp(() {
      browser = <String>[];
      writes = EngineWrites(
        (write) => browser.add(
          '${write.pushed ? 'push' : 'replace'} '
          '${write.url}',
        ),
      );
    });

    EngineWrite pushed(String url) =>
        (state: null, title: 'flutter', url: url, pushed: true);
    EngineWrite replaced(String url) =>
        (state: null, title: 'flutter', url: url, pushed: false);

    test('go through while nothing holds them', () {
      writes
        ..write(pushed('/radio'))
        ..write(replaced('/uploads'));

      expect(browser, <String>['push /radio', 'replace /uploads']);
    });

    test('held, wait, then go in order once released', () {
      writes
        ..hold()
        ..write(replaced('/uploads'))
        ..write(pushed('/radio'));
      expect(browser, isEmpty);

      expect(writes.release(), isTrue);

      expect(browser, <String>['replace /uploads', 'push /radio']);
      writes.write(pushed('/tasks'));
      expect(browser.last, 'push /tasks', reason: 'no longer held');
    });

    test('released past the entry the browser is on push the first', () {
      writes
        ..hold()
        ..write(replaced('/uploads'))
        ..write(replaced('/uploads?q=a'));

      expect(writes.release(past: true), isTrue);

      expect(browser, <String>['push /uploads', 'replace /uploads?q=a']);
    });

    test('released over the entry the browser is on write the first in '
        'place', () {
      writes
        ..hold()
        ..write(pushed('/podcasts'))
        ..write(pushed('/radio'));

      expect(writes.release(over: true), isTrue);

      expect(browser, <String>['replace /podcasts', 'push /radio']);
    });

    test('held twice are one hold', () {
      writes
        ..hold()
        ..write(pushed('/radio'))
        ..hold();

      writes.release();

      expect(browser, <String>['push /radio']);
    });

    test('dropped never reach the browser', () {
      writes
        ..hold()
        ..write(pushed('/radio'))
        ..drop();

      expect(writes.release(), isFalse, reason: 'nothing held any more');
      expect(browser, isEmpty);
    });
  });
}
