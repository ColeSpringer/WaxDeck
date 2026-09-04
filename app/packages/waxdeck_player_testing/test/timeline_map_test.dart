import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// The arithmetic every timeline engine and the feeder both depend on.
/// Tested without an engine on purpose: a seam in the wrong place is a
/// track credited to its neighbour, and that is worth pinning where
/// nothing else can be blamed.
void main() {
  const rate = 48000;
  int samples(int ms) => ms * rate ~/ 1000;

  TimelineMedia build(List<(int offsetMs, int durationMs)> members) =>
      TimelineMedia(
        url: '/media/hls/master.m3u8?tl=t',
        mimeType: 'application/vnd.apple.mpegurl',
        durationMs: members.last.$1 + members.last.$2,
        envelopeRate: rate,
        expiresAt: DateTime.utc(2030),
        members: <TimelineMember>[
          for (var i = 0; i < members.length; i++)
            TimelineMember(
              pid: 'tr-$i',
              offsetSamples: samples(members[i].$1),
              durationSamples: samples(members[i].$2),
            ),
        ],
      );

  test('a gapless queue tiles exactly', () {
    final tl = build([(0, 1000), (1000, 2000), (3000, 500)]);

    expect(tl.offsetMs(0), 0);
    expect(tl.offsetMs(2), 3000);
    expect(tl.memberDurationMs(1), 2000);
    expect(tl.seamMs(0), 1000);
    expect(tl.seamMs(1), 3000);

    // The last member has nothing after it, so its seam is its own end.
    expect(tl.seamMs(2), 3500);
  });

  test('a position locates the member that has begun', () {
    final tl = build([(0, 1000), (1000, 2000), (3000, 500)]);

    expect(tl.locate(0), 0);
    expect(tl.locate(999), 0);
    expect(tl.locate(1000), 1);
    expect(tl.locate(2999), 1);
    expect(tl.locate(3000), 2);

    // Clamped at both ends rather than throwing: a browser reports a
    // currentTime a hair past the end of the stream, and a negative one
    // after a seek to zero on a stream that has not settled.
    expect(tl.locate(-5), 0);
    expect(tl.locate(99999), 2);
  });

  test('positions convert both ways', () {
    final tl = build([(0, 1000), (1000, 2000)]);

    expect(tl.memberPosition(1, 1500), 500);
    expect(tl.absolute(1, 500), 1500);

    // Never negative: a keyframe snap can put the element a few
    // milliseconds before the member the caller asked for.
    expect(tl.memberPosition(1, 980), 0);
  });

  test('a crossfade overlaps members and the seam still comes first', () {
    // Two-second crossfade: the second member starts two seconds before
    // the first one's own end. Summing durations would put the seam at
    // ten seconds, which is two seconds of the second track credited to
    // the first.
    final tl = build([(0, 10000), (8000, 10000)]);

    expect(tl.seamMs(0), 8000);
    expect(tl.memberDurationMs(0), 10000);
    expect(tl.locate(8000), 1);

    // The member's own duration is still what a finished listen is
    // credited with, so the progress bar ends early and the listen does
    // not.
    expect(tl.memberDurationMs(1), 10000);
    expect(tl.seamMs(1), 18000);
  });

  test('samples convert to milliseconds the way the server converts them', () {
    // 44100 does not divide evenly, which is exactly where two
    // implementations drift apart if either rounds instead of truncating.
    final tl = TimelineMedia(
      url: '/media/hls/master.m3u8?tl=t',
      mimeType: 'application/vnd.apple.mpegurl',
      durationMs: 1000,
      envelopeRate: 44100,
      expiresAt: DateTime.utc(2030),
      members: const <TimelineMember>[
        TimelineMember(pid: 'tr-0', offsetSamples: 0, durationSamples: 44149),
        TimelineMember(
          pid: 'tr-1',
          offsetSamples: 44149,
          durationSamples: 44100,
        ),
      ],
    );

    expect(tl.memberDurationMs(0), 1001);
    expect(tl.offsetMs(1), 1001);
    expect(tl.seamMs(0), 1001);
  });

  test('a rate of zero maps everything to the head rather than dividing', () {
    final tl = TimelineMedia(
      url: '/media/hls/master.m3u8?tl=t',
      mimeType: 'application/vnd.apple.mpegurl',
      durationMs: 0,
      envelopeRate: 0,
      expiresAt: DateTime.utc(2030),
      members: const <TimelineMember>[
        TimelineMember(pid: 'tr-0', offsetSamples: 0, durationSamples: 48000),
      ],
    );

    expect(tl.offsetMs(0), 0);
    expect(tl.memberDurationMs(0), 0);
    expect(tl.locate(5000), 0);
  });
}
