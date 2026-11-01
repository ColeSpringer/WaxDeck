import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [body] with [debugPrint] captured, and answers what it printed.
///
/// For a test that provokes a failure the app reports on the console:
/// each line goes to [printOnFailure], shown beside a failure and silent
/// on a pass, and to the list answered, for a test whose point is the
/// line. Restored before [body]'s test ends, which a widget test checks
/// before any teardown runs.
Future<List<String>> captureDebugPrints(FutureOr<void> Function() body) async {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    lines.add(message);
    printOnFailure(message);
  };
  try {
    await body();
  } finally {
    debugPrint = previous;
  }
  return lines;
}
