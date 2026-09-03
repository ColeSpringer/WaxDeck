import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerException;
import 'package:waxdeck_player/waxdeck_player.dart';

/// The one decision a failed load feeds: skip past the item, or stand on
/// the retry pane. Reading it wrong in one direction costs a press, and
/// in the other it walks a listener's queue on a dropped connection - so
/// the table is worth pinning per platform rather than being trusted.
///
/// Here rather than in waxdeck_player, which carries no test directory
/// of its own: this package is where its behaviour is asserted from.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('anything that is not the plugin type is the transport', () {
    // The fallback the whole table rests on. Only positive evidence
    // says "the file", because that is the answer that moves the queue.
    expect(mediaFaultOf(StateError('something else')), MediaFault.transport);
    expect(mediaFaultOf(Exception('bare')), MediaFault.transport);
  });

  group('on Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('a renderer that would not take the stream is the file', () {
      // ExoPlaybackException.TYPE_RENDERER: a decoder refused it.
      expect(
        mediaFaultOf(PlayerException(1, 'Decoder init failed', null)),
        MediaFault.source,
      );
    });

    test('a source failure is not read as the file', () {
      // TYPE_SOURCE carries an unreadable container and a refused HTTP
      // request under one number, so the table alone goes the safe
      // way; the stream probe below is what can say more.
      expect(
        mediaFaultOf(PlayerException(0, 'Source error', null)),
        MediaFault.transport,
      );
    });
  });

  group('on Apple', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('a format the framework will not parse is the file', () {
      // AVErrorFileFormatNotRecognized, AVErrorFileFailedToParse.
      expect(
        mediaFaultOf(PlayerException(-11828, 'unrecognized', null)),
        MediaFault.source,
      );
      expect(
        mediaFaultOf(PlayerException(-11829, 'failed to parse', null)),
        MediaFault.source,
      );
    });

    test('being offline is not the file', () {
      // NSURLErrorNotConnectedToInternet, and the unknown catch-all.
      expect(
        mediaFaultOf(PlayerException(-1009, 'offline', null)),
        MediaFault.transport,
      );
      expect(
        mediaFaultOf(PlayerException(-11800, 'unknown', null)),
        MediaFault.transport,
      );
    });
  });

  group('on the desktop bridge', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);

    test('nothing classifies, so nothing skips', () {
      // media_kit does not fill the code in, so every failure there is
      // the safe answer.
      expect(
        mediaFaultOf(PlayerException(1, 'whatever', null)),
        MediaFault.transport,
      );
    });
  });

  group('the stream probe', () {
    // Android is where the table has no verdict to give, so it is
    // where the probe's gate matters most.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    // ExoPlayer's TYPE_SOURCE: every failure the emulator measured.
    PlayerException sourceError() => PlayerException(0, 'Source error', null);

    test(
      'a URL that answers turns an unexplained failure into the file',
      () async {
        expect(
          await probedMediaFaultOf(
            sourceError(),
            'http://x/a.mp3',
            probe: (_) async => StreamProbe.answered,
          ),
          MediaFault.source,
        );
      },
    );

    test('a URL that refuses the file is the file too', () async {
      // 415 from our own endpoint: the server would not make audio out
      // of that file either, so the player giving up on it is one
      // verdict twice. Standing on the retry pane here offers a press
      // that cannot come out differently, and stops a queue that has
      // nothing wrong with the rest of it.
      expect(
        await probedMediaFaultOf(
          sourceError(),
          'http://x/a.flac',
          probe: (_) async => StreamProbe.unplayable,
        ),
        MediaFault.source,
      );
    });

    test('a URL that reaches nothing leaves transport standing', () async {
      expect(
        await probedMediaFaultOf(
          sourceError(),
          'http://x/a.mp3',
          probe: (_) async => StreamProbe.unreachable,
        ),
        MediaFault.transport,
      );
    });

    test('a verdict from the table is never second-guessed', () async {
      // TYPE_RENDERER already says the file; a probe could only unsay
      // it, and it must not be spent at all.
      var asked = false;
      expect(
        await probedMediaFaultOf(
          PlayerException(1, 'Decoder init failed', null),
          'http://x/a.mp3',
          probe: (_) async {
            asked = true;
            return StreamProbe.unreachable;
          },
        ),
        MediaFault.source,
      );
      expect(asked, isFalse);
    });

    test('a failure that is not the player is never probed', () async {
      // The probe resolves the player refusing without a reason. A
      // failure from anywhere else says nothing about the media, and a
      // URL that answers must not turn it into a skip.
      var asked = false;
      expect(
        await probedMediaFaultOf(
          StateError('not the player'),
          'http://x/a.mp3',
          probe: (_) async {
            asked = true;
            return StreamProbe.answered;
          },
        ),
        MediaFault.transport,
      );
      expect(asked, isFalse);
    });

    test('a probe that breaks leaves transport standing', () async {
      expect(
        await probedMediaFaultOf(
          sourceError(),
          'http://x/a.mp3',
          probe: (_) => throw StateError('probe broke'),
        ),
        MediaFault.transport,
      );
    });
  });
}
