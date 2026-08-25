import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/uploads/file_picker_port.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';

import 'fakes.dart';

// What pickers and drop zones filter against: the health payload's
// sets where the server reports them, the hardcoded mirror where it
// predates the fields - and, through resolveUploadFormats, the mirror
// for one ask when the read failed or stalled, never memoized for the
// session.
void main() {
  Future<void> host(
    WidgetTester tester,
    FakeRepository repo,
    Future<void> Function(WidgetRef ref) body,
  ) async {
    // The body runs inside runAsync: resolveUploadFormats carries a
    // real timeout, and a timer minted in the test zone would wait on
    // pumps that never come.
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.runAsync(() => body(captured));
  }

  testWidgets('the server-reported sets win when present', (tester) async {
    final repo = FakeRepository()
      ..serverUploadFormats = ['wv', 'ape', 'flac']
      ..serverRejectedFormats = ['aax', 'aaxc', 'kmz'];
    await host(tester, repo, (ref) async {
      final formats = await resolveUploadFormats(ref);
      expect(formats.accepted, {'wv', 'ape', 'flac'});
      expect(formats.rejected, {'aax', 'aaxc', 'kmz'});
    });
  });

  testWidgets('a server older than the fields falls back to the mirror', (
    tester,
  ) async {
    await host(tester, FakeRepository(), (ref) async {
      final formats = await resolveUploadFormats(ref);
      expect(formats.accepted, kAcceptedAudioExtensions);
      expect(formats.rejected, kRejectedAudioExtensions);
    });
  });

  testWidgets('a failed read answers the mirror once, not for the session', (
    tester,
  ) async {
    // The blip case this design exists for: the first ask meets a dead
    // network and gets the mirror; the failure is retired rather than
    // cached, so the next ask fetches fresh and gets the server's set.
    final repo = FakeRepository()
      ..serverUploadFormats = ['wv']
      ..serverHealthError = StateError('handover');
    await host(tester, repo, (ref) async {
      expect(
        (await resolveUploadFormats(ref)).accepted,
        kAcceptedAudioExtensions,
      );
      repo.serverHealthError = null;
      expect((await resolveUploadFormats(ref)).accepted, {'wv'});
    });
  });

  test('the deny-list wins over the accepted set', () {
    // The precedence the server's own gate has: a set that somehow
    // lists a DRM extension still counts those files as "can never
    // play" instead of admitting them to be refused one by one.
    const formats = UploadFormatSets(
      accepted: {'aax', 'flac'},
      rejected: {'aax'},
    );
    expect(formats.accepts('album.flac'), isTrue);
    expect(formats.accepts('book.aax'), isFalse);
    expect(formats.refuses('book.aax'), isTrue);
    final builder = FolderPickBuilder(formats);
    expect(builder.keep('book.aax'), isFalse);
    expect(builder.keep('notes.txt'), isFalse);
    expect(builder.keep('album.flac'), isTrue);
    final pick = builder.build();
    expect(pick.skippedDrm, 1);
    expect(pick.skippedUnsupported, 1);
  });
}
