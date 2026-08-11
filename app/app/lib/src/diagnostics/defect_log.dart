import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/app_version.dart';

/// One defect the app caught, as much of it as is worth keeping.
class DefectRecord {
  const DefectRecord({
    required this.at,
    required this.source,
    required this.summary,
    required this.details,
    this.count = 1,
  });

  final DateTime at;

  /// Which handler caught it: `framework` for a build, layout or paint
  /// error, `async` for anything that escaped a future. The two arrive
  /// through different channels and mean different things to whoever
  /// reads the log.
  final String source;

  final String summary;
  final String details;

  /// How many times in a row this same defect has arrived. A build error
  /// repeats once per frame, so the count is what keeps one broken
  /// screen from being the whole log.
  final int count;
}

/// The last few defects, newest first.
///
/// The controllers that page a listing catch the transport failure they
/// expect and rethrow everything else - a decode failure, a bad cast -
/// deliberately, so it reaches something. This is that something. There
/// is no telemetry to send it to and no listener who wants a dialog
/// about it, so it is kept where somebody filing a bug can copy it out:
/// Settings, under About.
///
/// A ring, because a log that grows without bound on a device is a leak,
/// and the defects worth reading are the recent ones.
class DefectLogController extends Notifier<List<DefectRecord>> {
  static const capacity = 50;
  static const summaryCap = 400;
  static const detailsCap = 4000;

  /// Guards against a defect raised while recording one. The recorder
  /// runs inside the framework's error handler, and anything it touches
  /// - a listener rebuilding a widget - can raise again from in here.
  var _recording = false;

  @override
  List<DefectRecord> build() => const <DefectRecord>[];

  /// Records a defect. Never throws: it is called from the handlers of
  /// last resort, so a failure here would have nowhere left to go.
  void record({
    required String source,
    required Object error,
    StackTrace? stack,
  }) {
    if (_recording) return;
    _recording = true;
    try {
      final summary = _clip('$error', summaryCap);
      final head = state.isEmpty ? null : state.first;
      // Coalesced on source and summary alone. Two frames of the same
      // build error carry different stacks often enough that keying on
      // the details would coalesce nothing at all - and then the frame
      // loop this exists for would fill the ring in a second.
      if (head != null && head.source == source && head.summary == summary) {
        state = <DefectRecord>[
          DefectRecord(
            at: DateTime.now(),
            source: source,
            summary: summary,
            // The first stack, not the newest: they are the same defect,
            // and the first one is the one from before anything else
            // started failing around it.
            details: head.details,
            count: head.count + 1,
          ),
          ...state.skip(1),
        ];
        return;
      }
      // Stringified only past the coalesce: a build error's stack runs
      // to kilobytes, and the frame-loop storm the coalescer exists for
      // must not build one per frame just to throw it away.
      final details = _clip(stack == null ? '' : '$stack', detailsCap);
      state = <DefectRecord>[
        DefectRecord(
          at: DateTime.now(),
          source: source,
          summary: summary,
          details: details,
        ),
        ...state.take(capacity - 1),
      ];
    } catch (_) {
      // Deliberately swallowed. See the doc above.
    } finally {
      _recording = false;
    }
  }

  void clear() => state = const <DefectRecord>[];

  /// The whole log as one pasteable block, for a bug report.
  String report() {
    final buffer = StringBuffer('WaxDeck defect log, app $kAppVersion\n');
    if (state.isEmpty) {
      buffer.writeln('(empty)');
      return buffer.toString();
    }
    for (final d in state) {
      buffer.writeln('');
      buffer.write('${d.at.toIso8601String()} [${d.source}]');
      if (d.count > 1) buffer.write(' x${d.count}');
      buffer.writeln('');
      buffer.writeln(d.summary);
      if (d.details.isNotEmpty) buffer.writeln(d.details);
    }
    return buffer.toString();
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...';
}

final defectLogProvider =
    NotifierProvider<DefectLogController, List<DefectRecord>>(
      DefectLogController.new,
    );

/// Points the two framework-level error channels at the log.
///
/// Called once, from main, with the container the app runs on. Both
/// handlers read the controller at call time rather than capturing it:
/// riverpod is free to dispose and rebuild a notifier, and a captured
/// one would go on recording into an instance nothing watches.
///
/// No `runZonedGuarded`: `PlatformDispatcher.onError` catches what the
/// zone would, and a guarded zone around `runApp` is the arrangement
/// that makes a plugin's own zone mismatch a startup crash.
void installDefectHandlers(
  ProviderContainer container, {
  bool forwardToConsole = true,
}) {
  FlutterError.onError = (details) {
    try {
      container
          .read(defectLogProvider.notifier)
          .record(
            source: 'framework',
            error: details.exception,
            stack: details.stack,
          );
    } catch (_) {
      // A disposed container must not turn the error handler into an
      // error source; the console line below still tells the story.
    }
    // Console in every mode, matching the framework's own default: a
    // self-hoster's logcat and the e2e suite's console listeners (hang
    // evidence is built from them) both read the release stream, and
    // going quiet there is a regression, not a cleanup. The flag exists
    // for tests that assert on a silent console.
    if (forwardToConsole) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    try {
      container
          .read(defectLogProvider.notifier)
          .record(source: 'async', error: error, stack: stack);
    } catch (_) {
      // Same guard as above.
    }
    if (forwardToConsole) debugPrint('$error\n$stack');
    // Handled: the log is where it went. Returning false here would
    // print it and, on some platforms, take the app down with it.
    return true;
  };
}
