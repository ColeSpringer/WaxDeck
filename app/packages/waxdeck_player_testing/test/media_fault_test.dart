import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerException;
import 'package:waxdeck_player/waxdeck_player.dart';

import 'scripted_platform.dart';

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

  group('on the web', () {
    // A `MediaError.code`, read with the browser's table on the VM.
    PlayerException element(int code) => PlayerException(code, 'media', 0);

    ProbeAnswer refused(int status, String code) => ProbeAnswer(
      StreamProbe.unreachable,
      StreamRefusal(status: status, code: code),
    );

    test('a decode error is the file, without asking anybody', () async {
      expect(mediaFaultOf(element(3), isWeb: true), MediaFault.source);
      var asked = false;
      final read = await probedMediaFailureOf(
        element(3),
        '/media/stream?mt=a',
        isWeb: true,
        ask: (_, {segmentAt}) async {
          asked = true;
          return ProbeAnswer.unreachable;
        },
      );
      expect(read.fault, MediaFault.source);
      expect(asked, isFalse);
    });

    test('a failed first fetch is asked about, never assumed the file', () {
      // Code 4 is the HTML spec's answer for any first fetch that did not
      // produce media: a 401, a 429, a 502, a browser that is offline.
      expect(mediaFaultOf(element(4), isWeb: true), MediaFault.transport);
    });

    test(
      'a URL that serves bytes the browser cannot decode is the file',
      () async {
        final read = await probedMediaFailureOf(
          element(4),
          '/media/stream?mt=a',
          isWeb: true,
          ask: answering(const ProbeAnswer(StreamProbe.answered)),
        );
        expect(read.fault, MediaFault.source);
        expect(read.refusal, isNull);
      },
    );

    test('a first fetch nothing answered is the transport', () async {
      final read = await probedMediaFailureOf(
        element(4),
        '/media/stream?mt=a',
        isWeb: true,
        ask: answering(const ProbeAnswer(StreamProbe.unreachable)),
      );
      expect(read.fault, MediaFault.transport);
    });

    test('the transcode cap is a refusal, never the file', () async {
      final read = await probedMediaFailureOf(
        element(4),
        '/media/stream?mt=a',
        isWeb: true,
        ask: answering(refused(429, 'transcode-limited')),
      );
      expect(read.fault, MediaFault.transport);
      expect(read.refusal?.code, 'transcode-limited');
    });

    test('the engine being away is a refusal too', () async {
      final read = await probedMediaFailureOf(
        element(4),
        '/media/stream?mt=a',
        isWeb: true,
        ask: answering(refused(502, 'internal')),
      );
      expect(read.fault, MediaFault.transport);
      expect(read.refusal?.engineDown, isTrue);
    });

    test('a network error whose URL still answers is the transport', () async {
      // The element said network. A URL that answers afterwards is a
      // connection that dropped and came back, not a file to step past.
      final read = await probedMediaFailureOf(
        element(2),
        '/media/stream?mt=a',
        isWeb: true,
        ask: answering(const ProbeAnswer(StreamProbe.answered)),
      );
      expect(read.fault, MediaFault.transport);
    });

    test(
      'a network error the server explains as the file is the file',
      () async {
        final read = await probedMediaFailureOf(
          element(2),
          '/media/stream?mt=a',
          isWeb: true,
          ask: answering(const ProbeAnswer(StreamProbe.unplayable)),
        );
        expect(read.fault, MediaFault.source);
      },
    );

    test('a network error met by an expired token says so', () async {
      final read = await probedMediaFailureOf(
        element(2),
        '/media/stream?mt=a',
        isWeb: true,
        ask: answering(refused(401, 'unauthenticated')),
      );
      expect(read.fault, MediaFault.transport);
      expect(read.refusal?.stale, isTrue);
    });
  });

  group('mid-play', () {
    // What fails partway through is far more often the way to a file than
    // a file that decoded until then, so an answering URL is no evidence
    // against it - whatever code the platform gave.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('a renderer failure is weighed like any other', () async {
      // TYPE_RENDERER covers an audio sink that went away as much as a
      // decoder that would not take the stream.
      final read = await probedMediaFailureOf(
        PlayerException(1, 'AudioTrack write failed', null),
        'http://x/a.flac',
        ask: answering(const ProbeAnswer(StreamProbe.answered)),
        isWeb: false,
        midPlay: true,
      );
      expect(read.fault, MediaFault.transport);
    });

    test('a decode error in the browser is weighed the same way', () async {
      final read = await probedMediaFailureOf(
        PlayerException(3, 'decode', 0),
        '/media/stream?mt=a',
        ask: answering(const ProbeAnswer(StreamProbe.answered)),
        isWeb: true,
        midPlay: true,
      );
      expect(read.fault, MediaFault.transport);
    });

    test('the server calling the file unplayable is still the file', () async {
      final read = await probedMediaFailureOf(
        PlayerException(1, 'AudioTrack write failed', null),
        'http://x/a.flac',
        ask: answering(const ProbeAnswer(StreamProbe.unplayable)),
        isWeb: false,
        midPlay: true,
      );
      expect(read.fault, MediaFault.source);
    });

    test('a downloaded file that stops decoding is the file', () async {
      // Nothing stands between the player and a file on disk, so one
      // that is there and will not decode is the bytes.
      final dir = Directory.systemTemp.createTempSync('media_fault');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/a.flac')..writeAsBytesSync(const [0]);
      final read = await probedMediaFailureOf(
        PlayerException(0, 'Source error', null),
        file.uri.toString(),
        isWeb: false,
        midPlay: true,
      );
      expect(read.fault, MediaFault.source);
      final gone = await probedMediaFailureOf(
        PlayerException(0, 'Source error', null),
        '${dir.uri}absent.flac',
        isWeb: false,
        midPlay: true,
      );
      expect(gone.fault, MediaFault.transport);
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
        final read = await probedMediaFailureOf(
          sourceError(),
          'http://x/a.mp3',
          ask: answering(const ProbeAnswer(StreamProbe.answered)),
        );
        expect(read.fault, MediaFault.source);
      },
    );

    test(
      'an HLS presentation that answers says nothing against the file',
      () async {
        // A presentation fails at its segments (an engine with no slot
        // free, a worker that failed), and the one holding where it
        // failed is what is asked: an answer there is no evidence against
        // the file, while the server calling it unplayable is.
        const master = 'http://x/media/hls/master.m3u8?it=k&mt=t';
        final asked = <Duration?>[];
        StreamAsk finding(StreamProbe found) => (_, {segmentAt}) async {
          asked.add(segmentAt);
          return ProbeAnswer(found);
        };
        final answered = await probedMediaFailureOf(
          sourceError(),
          master,
          ask: finding(StreamProbe.answered),
          isWeb: false,
          presentation: true,
          at: const Duration(seconds: 9),
        );
        expect(answered.fault, MediaFault.transport);
        final unplayable = await probedMediaFailureOf(
          sourceError(),
          master,
          ask: finding(StreamProbe.unplayable),
          isWeb: false,
          presentation: true,
          at: const Duration(seconds: 9),
        );
        expect(unplayable.fault, MediaFault.source);
        // A hair past where it stopped: that is where the segment it
        // could not fetch begins.
        expect(
          asked,
          everyElement(
            allOf(
              greaterThan(const Duration(seconds: 9)),
              lessThan(const Duration(seconds: 10)),
            ),
          ),
        );
      },
    );

    test('a URL that refuses the file is the file too', () async {
      // 415 from our own endpoint: the server would not make audio out
      // of that file either, so the player giving up on it is one
      // verdict twice. Standing on the retry pane here offers a press
      // that cannot come out differently, and stops a queue that has
      // nothing wrong with the rest of it.
      final read = await probedMediaFailureOf(
        sourceError(),
        'http://x/a.flac',
        ask: answering(const ProbeAnswer(StreamProbe.unplayable)),
      );
      expect(read.fault, MediaFault.source);
    });

    test('a URL that reaches nothing leaves transport standing', () async {
      final read = await probedMediaFailureOf(
        sourceError(),
        'http://x/a.mp3',
        ask: answering(ProbeAnswer.unreachable),
      );
      expect(read.fault, MediaFault.transport);
    });

    test('a verdict from the table is never second-guessed', () async {
      // TYPE_RENDERER already says the file; a probe could only unsay
      // it, and it must not be spent at all.
      var asked = false;
      final read = await probedMediaFailureOf(
        PlayerException(1, 'Decoder init failed', null),
        'http://x/a.mp3',
        ask: (_, {segmentAt}) async {
          asked = true;
          return ProbeAnswer.unreachable;
        },
      );
      expect(read.fault, MediaFault.source);
      expect(asked, isFalse);
    });

    test('a failure that is not the player is never probed', () async {
      // The probe resolves the player refusing without a reason. A
      // failure from anywhere else says nothing about the media, and a
      // URL that answers must not turn it into a skip.
      var asked = false;
      final read = await probedMediaFailureOf(
        StateError('not the player'),
        'http://x/a.mp3',
        ask: (_, {segmentAt}) async {
          asked = true;
          return const ProbeAnswer(StreamProbe.answered);
        },
      );
      expect(read.fault, MediaFault.transport);
      expect(asked, isFalse);
    });

    test('a refusal the probe read rides along with the fault', () async {
      final read = await probedMediaFailureOf(
        sourceError(),
        'http://x/a.mp3',
        ask: answering(
          const ProbeAnswer(
            StreamProbe.unreachable,
            StreamRefusal(status: 429, code: 'transcode-limited'),
          ),
        ),
      );
      expect(read.fault, MediaFault.transport);
      expect(read.refusal?.code, 'transcode-limited');
    });

    test('a probe that breaks leaves transport standing', () async {
      final read = await probedMediaFailureOf(
        sourceError(),
        'http://x/a.mp3',
        ask: (_, {segmentAt}) => throw StateError('probe broke'),
      );
      expect(read.fault, MediaFault.transport);
    });
  });
}
