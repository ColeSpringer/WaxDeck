import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// The one retry policy the app's server-backed providers share.
void main() {
  test('a refusal is final', () {
    for (final status in <int>[400, 401, 404, 409, 429]) {
      expect(
        retryUnlessRefused(
          0,
          WaxDeckApiException(code: 'no', message: 'no', statusCode: status),
        ),
        isNull,
        reason: 'http $status',
      );
    }
  });

  test('anything else keeps the default ladder, cap included', () {
    // A supplied policy replaces Riverpod's default rather than wrapping
    // it, so the cap only holds because this asks for it: without it an
    // unreachable server had a provider re-asking forever.
    final outage = WaxDeckApiException(
      code: 'internal',
      message: 'down',
      statusCode: 503,
    );
    expect(retryUnlessRefused(0, outage), isNotNull);
    expect(retryUnlessRefused(0, Exception('socket')), isNotNull);
    expect(retryUnlessRefused(9, outage), isNotNull);
    expect(retryUnlessRefused(10, outage), isNull, reason: 'the cap');
    expect(
      retryUnlessRefused(3, StateError('bug')),
      isNull,
      reason: 'a defect does not become a retry loop',
    );
    // The same schedule the default runs, so the two are one behaviour.
    expect(
      retryUnlessRefused(2, outage),
      ProviderContainer.defaultRetry(2, outage),
    );
  });
}
