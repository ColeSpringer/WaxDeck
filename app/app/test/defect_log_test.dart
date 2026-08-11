import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/diagnostics/defect_log.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/sharing/shares_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

/// A server whose second page is not the shape the client was promised.
/// The cast below raises a real TypeError rather than a stand-in, which
/// is the whole class of defect the controllers rethrow.
class _MiscastRepository extends FakeRepository {
  int calls = 0;

  @override
  Future<SharePage> listShares({
    String? cursor,
    int? limit,
    bool all = false,
  }) async {
    calls++;
    if (calls == 1) {
      return const SharePage(shares: <Share>[], nextCursor: 'page-2');
    }
    final Object wrong = 'not a page at all';
    return wrong as SharePage;
  }
}

void main() {
  // flutter_test owns both handlers for the duration of a test, and
  // installDefectHandlers replaces them. Restored here rather than
  // trusted, or the first test that installs takes the reporting out of
  // every test after it in the same file.
  late FlutterExceptionHandler? savedFlutter;
  late bool Function(Object, StackTrace)? savedPlatform;
  setUp(() {
    savedFlutter = FlutterError.onError;
    savedPlatform = PlatformDispatcher.instance.onError;
  });
  tearDown(() {
    FlutterError.onError = savedFlutter;
    PlatformDispatcher.instance.onError = savedPlatform;
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('the ring keeps the newest entries and no more than its cap', () {
    final c = container();
    final log = c.read(defectLogProvider.notifier);
    for (var i = 0; i < DefectLogController.capacity + 10; i++) {
      log.record(source: 'async', error: 'defect $i');
    }
    final entries = c.read(defectLogProvider);
    expect(entries, hasLength(DefectLogController.capacity));
    expect(entries.first.summary, contains('defect 59'));
    expect(entries.last.summary, contains('defect 10'));
  });

  test('a defect repeating counts up instead of filling the ring', () {
    final c = container();
    final log = c.read(defectLogProvider.notifier);
    for (var i = 0; i < 5; i++) {
      log.record(source: 'framework', error: 'the same build error');
    }
    final entries = c.read(defectLogProvider);
    expect(entries, hasLength(1));
    expect(entries.single.count, 5);
  });

  test('coalescing keeps the first stack, not the newest', () {
    final c = container();
    final log = c.read(defectLogProvider.notifier);
    log.record(
      source: 'framework',
      error: 'boom',
      stack: StackTrace.fromString('first'),
    );
    log.record(
      source: 'framework',
      error: 'boom',
      stack: StackTrace.fromString('second'),
    );
    expect(c.read(defectLogProvider).single.details, 'first');
  });

  test('a different source is a different entry', () {
    final c = container();
    final log = c.read(defectLogProvider.notifier);
    log.record(source: 'framework', error: 'boom');
    log.record(source: 'async', error: 'boom');
    expect(c.read(defectLogProvider), hasLength(2));
  });

  test('long errors and stacks are clipped', () {
    final c = container();
    final log = c.read(defectLogProvider.notifier);
    log.record(
      source: 'async',
      error: 'x' * 5000,
      stack: StackTrace.fromString('y' * 9000),
    );
    final entry = c.read(defectLogProvider).single;
    expect(entry.summary.length, DefectLogController.summaryCap + 3);
    expect(entry.details.length, DefectLogController.detailsCap + 3);
  });

  test('a defect raised while recording one does not recurse', () {
    final c = container();
    final log = c.read(defectLogProvider.notifier);
    var reentered = 0;
    c.listen(defectLogProvider, (_, _) {
      reentered++;
      log.record(source: 'async', error: 'raised by a listener');
    });
    log.record(source: 'async', error: 'the original');
    expect(reentered, 1);
    expect(c.read(defectLogProvider).single.summary, 'the original');
  });

  test('both framework channels reach the log once installed', () {
    final c = container();
    installDefectHandlers(c, forwardToConsole: false);

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('a build error'),
        stack: StackTrace.fromString('build stack'),
      ),
    );
    final handled = PlatformDispatcher.instance.onError!(
      StateError('an async error'),
      StackTrace.fromString('async stack'),
    );

    expect(handled, isTrue, reason: 'the log is where it went');
    final entries = c.read(defectLogProvider);
    expect(entries, hasLength(2));
    expect(entries.first.source, 'async');
    expect(entries.last.source, 'framework');
  });

  test('a disposed container does not turn the handlers into throwers', () {
    // The handlers outlive the container they read on shutdown paths,
    // and an error reporter that raises from inside the framework's
    // error hook is the one failure with nowhere left to go.
    final c = ProviderContainer();
    installDefectHandlers(c, forwardToConsole: false);
    c.dispose();

    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('after dispose')),
    );
    final handled = PlatformDispatcher.instance.onError!(
      StateError('after dispose'),
      StackTrace.empty,
    );
    expect(handled, isTrue);
  });

  test('the report is pasteable and names the app version', () {
    final c = container();
    final log = c.read(defectLogProvider.notifier);
    expect(log.report(), contains('(empty)'));
    log.record(
      source: 'async',
      error: 'boom',
      stack: StackTrace.fromString('s'),
    );
    final report = log.report();
    expect(report, startsWith('WaxDeck defect log, app '));
    expect(report, contains('[async]'));
    expect(report, contains('boom'));
    expect(report, contains('s'));
  });

  test('clear empties the log', () {
    final c = container();
    final log = c.read(defectLogProvider.notifier);
    log.record(source: 'async', error: 'boom');
    log.clear();
    expect(c.read(defectLogProvider), isEmpty);
  });

  test(
    'a controller rethrow reaches the log, and paging is not wedged',
    () async {
      final c = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(_MiscastRepository())],
      );
      addTearDown(c.dispose);
      installDefectHandlers(c, forwardToConsole: false);

      final provider = AsyncNotifierProvider<SharesController, SharesState>(
        SharesController.new,
      );
      await c.read(provider.future);
      Object? escaped;
      StackTrace? escapedStack;
      try {
        await c.read(provider.notifier).loadMore();
      } catch (e, s) {
        escaped = e;
        escapedStack = s;
      }
      expect(
        escaped,
        isA<TypeError>(),
        reason: 'the defect is rethrown, not swallowed',
      );

      // What the app does with it: the async handler, which is installed.
      expect(
        PlatformDispatcher.instance.onError!(escaped!, escapedStack!),
        isTrue,
      );
      final entry = c.read(defectLogProvider).single;
      expect(entry.source, 'async');
      expect(entry.summary, contains('type'));
      // The guard is released, so scrolling again can retry rather than
      // finding paging permanently stuck.
      expect(c.read(provider).value!.loadingMore, isFalse);
    },
  );
}
