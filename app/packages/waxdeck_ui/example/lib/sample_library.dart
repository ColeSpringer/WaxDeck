import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:waxdeck_ui/waxdeck_ui.dart';

/// An invented catalogue, realistic enough to judge the design by.
///
/// Screens read very differently with placeholder text than with the
/// long artist names, mixed-script titles, and awkward durations a real
/// library has, so the composites use records that behave like real ones:
/// a 200-character classical title, a two-line podcast episode, an
/// audiobook with a portrait cover, a station with a circular logo.
abstract final class SampleLibrary {
  static const String longClassicalTitle =
      'Symphony No. 9 in D minor, Op. 125 "Choral": IV. Presto - Allegro '
      'assai - Rezitativ "O Freunde, nicht diese Toene!" (Live at the '
      'Musikverein, remastered)';

  static List<MediaTileData> continueListening(SampleArt art) =>
      <MediaTileData>[
        MediaTileData(
          title: 'Salt Harbour',
          subtitle: 'Nightjar',
          artwork: art.of('Salt Harbour'),
          progress: 0.62,
          trailingText: '14 min left',
        ),
        MediaTileData(
          title: 'The Quiet Part',
          subtitle: 'Field Recordings, ep. 112',
          artwork: art.of('The Quiet Part'),
          domain: WaxDomain.podcasts,
          progress: 0.28,
          trailingText: '41 min left',
        ),
        MediaTileData(
          title: 'A History of Tides',
          subtitle: 'Mirren Vaux',
          artwork: art.of('A History of Tides'),
          domain: WaxDomain.audiobooks,
          shape: ArtworkShape.portrait,
          progress: 0.44,
          trailingText: '6 hr 12 min left',
          downloaded: true,
        ),
        MediaTileData(
          title: 'Late Night Reprise',
          subtitle: 'Hollow Coast',
          artwork: art.of('Late Night Reprise'),
          progress: 0.81,
          trailingText: '8 min left',
        ),
      ];

  static List<MediaTileData> recentlyAdded(SampleArt art) => <MediaTileData>[
    MediaTileData(
      title: 'Ceremony for Small Rooms',
      subtitle: 'Halden Ives',
      artwork: art.of('Ceremony for Small Rooms'),
    ),
    MediaTileData(
      title: 'Marginalia',
      subtitle: 'The Paper Kites Society',
      artwork: art.of('Marginalia'),
    ),
    MediaTileData(
      title: 'حديقة الليل',
      subtitle: 'Amal Rasheed',
      artwork: art.of('Night Garden'),
    ),
    MediaTileData(
      title: 'Winterreise',
      subtitle: 'Schubert - Fischer-Dieskau, Moore',
      artwork: art.of('Winterreise'),
    ),
    MediaTileData(
      title: 'Bell Tower Sessions',
      subtitle: 'Ora Lune',
      artwork: art.of('Bell Tower Sessions'),
      starred: true,
    ),
  ];

  static List<MediaTileData> newEpisodes(SampleArt art) => <MediaTileData>[
    MediaTileData(
      title: 'What the harbour remembers',
      subtitle: 'Field Recordings',
      artwork: art.of('Field Recordings'),
      domain: WaxDomain.podcasts,
      trailingText: '58 min',
    ),
    MediaTileData(
      title: 'Two hundred tape machines',
      subtitle: 'The Long Signal',
      artwork: art.of('The Long Signal'),
      domain: WaxDomain.podcasts,
      trailingText: '1 hr 12 min',
    ),
    MediaTileData(
      title: 'Rooms that sound like rooms',
      subtitle: 'Field Recordings',
      artwork: art.of('Rooms'),
      domain: WaxDomain.podcasts,
      trailingText: '44 min',
      downloaded: true,
    ),
    MediaTileData(
      title: 'The archive nobody asked for',
      subtitle: 'Signal to Noise',
      artwork: art.of('Signal to Noise'),
      domain: WaxDomain.podcasts,
      trailingText: '32 min',
      unavailableOffline: true,
    ),
  ];

  static List<MediaTileData> stations(SampleArt art) => <MediaTileData>[
    MediaTileData(
      title: 'Coastal FM',
      subtitle: 'Ambient, 128 kbps',
      artwork: art.of('Coastal FM'),
      domain: WaxDomain.radio,
      shape: ArtworkShape.circle,
    ),
    MediaTileData(
      title: 'Night Bus',
      subtitle: 'Jazz, 192 kbps',
      artwork: art.of('Night Bus'),
      domain: WaxDomain.radio,
      shape: ArtworkShape.circle,
    ),
    MediaTileData(
      title: 'Radio Meridian',
      subtitle: 'Talk, 96 kbps',
      artwork: art.of('Radio Meridian'),
      domain: WaxDomain.radio,
      shape: ArtworkShape.circle,
    ),
  ];

  /// The album the detail composite is built around.
  static const String albumTitle = 'Salt Harbour';
  static const String albumArtist = 'Nightjar';
  static const String albumMeta = '2024 · 9 tracks · 41 min · FLAC 24/96';
  static const String albumNote =
      'Recorded over two winters in a converted lifeboat station, mostly '
      'at night, mostly in one take.';

  static List<MediaTileData> albumTracks() => const <MediaTileData>[
    MediaTileData(
      title: 'Low Water',
      subtitle: 'Nightjar',
      trailingText: '3:12',
    ),
    MediaTileData(
      title: 'Salt Harbour',
      subtitle: 'Nightjar',
      trailingText: '4:05',
      starred: true,
    ),
    MediaTileData(
      title: 'Gullwing',
      subtitle: 'Nightjar',
      trailingText: '5:41',
    ),
    MediaTileData(
      title: 'Winter Berth',
      subtitle: 'Nightjar, Ora Lune',
      trailingText: '6:18',
    ),
    MediaTileData(
      title: 'Ropework',
      subtitle: 'Nightjar',
      trailingText: '2:57',
    ),
    MediaTileData(
      title: 'The Lifeboat Station',
      subtitle: 'Nightjar',
      trailingText: '7:44',
    ),
    MediaTileData(
      title: 'Slack Tide',
      subtitle: 'Nightjar',
      trailingText: '4:02',
    ),
    MediaTileData(
      title: 'Nightjar',
      subtitle: 'Nightjar',
      trailingText: '3:33',
    ),
    MediaTileData(
      title: 'Harbour Light',
      subtitle: 'Nightjar',
      trailingText: '4:11',
    ),
  ];

  static NowPlayingData nowPlayingMusic(SampleArt art) => NowPlayingData(
    title: 'Salt Harbour',
    subtitle: 'Nightjar · Salt Harbour',
    provenance: 'Playing from Salt Harbour',
    artwork: art.of('Salt Harbour'),
    position: const Duration(minutes: 2, seconds: 41),
    duration: const Duration(minutes: 4, seconds: 5),
    buffered: const Duration(minutes: 3, seconds: 30),
    playing: true,
    starred: true,
  );

  static NowPlayingData nowPlayingPodcast(SampleArt art) => NowPlayingData(
    title: 'What the harbour remembers',
    subtitle: 'Field Recordings',
    provenance: 'Episode 113',
    artwork: art.of('Field Recordings'),
    domain: WaxDomain.podcasts,
    position: const Duration(minutes: 18, seconds: 6),
    duration: const Duration(minutes: 58, seconds: 12),
    playing: true,
    speed: 1.2,
  );

  static NowPlayingData nowPlayingBook(SampleArt art) => NowPlayingData(
    title: 'Chapter 14: The Neap',
    subtitle: 'A History of Tides · Mirren Vaux',
    provenance: '42 percent · 6 hr 12 min left',
    artwork: art.of('A History of Tides'),
    domain: WaxDomain.audiobooks,
    shape: ArtworkShape.portrait,
    position: const Duration(minutes: 12, seconds: 30),
    duration: const Duration(minutes: 34, seconds: 10),
    playing: false,
    speed: 1.35,
  );

  static NowPlayingData nowPlayingRadio(SampleArt art) => NowPlayingData(
    title: 'Coastal FM',
    subtitle: 'Ora Lune - Bell Tower',
    artwork: art.of('Coastal FM'),
    domain: WaxDomain.radio,
    shape: ArtworkShape.circle,
    position: Duration.zero,
    duration: Duration.zero,
    playing: true,
    live: true,
  );

  /// Timed lines for the lyrics view, spaced far enough apart that the
  /// highlight is somewhere to look at rather than a flicker.
  static List<LyricLine> lyrics() => const <LyricLine>[
    LyricLine(at: Duration(seconds: 8), text: 'The tide comes in'),
    LyricLine(
      at: Duration(seconds: 21),
      text: 'and the harbour lights go out, one at a time',
    ),
    LyricLine(at: Duration(minutes: 1), text: 'Nobody counts them but me'),
    LyricLine(
      at: Duration(minutes: 1, seconds: 42),
      text: 'and I have lost my place again',
    ),
    LyricLine(at: Duration(minutes: 2, seconds: 30), text: 'So the tide'),
    LyricLine(
      at: Duration(minutes: 3, seconds: 4),
      text: 'comes in, and I am still counting',
    ),
  ];

  /// The other shape the same view draws: words a tag carried with no
  /// timings on them.
  static const String unsyncedLyrics =
      'The tide comes in\n'
      'and the harbour lights go out, one at a time\n\n'
      'Nobody counts them but me\n'
      'and I have lost my place again';

  /// Peaks for the waveform seek bar. Real peaks come from the server;
  /// these are shaped like a track rather than like noise so the
  /// composite reads honestly.
  static List<double> peaks({int count = 96}) =>
      List<double>.generate(count, (i) {
        final t = i / count;
        final envelope = 0.35 + 0.65 * (1 - (2 * t - 1).abs());
        final detail =
            0.5 +
            0.5 *
                ((i * 7919) % 23) /
                23; // deterministic, no Random: goldens must not drift
        return (envelope * detail).clamp(0.08, 1);
      });
}

/// Deterministic cover art, generated at runtime.
///
/// No binary media in the repo: the catalogue paints its own covers from
/// the title string, so every composite has real artwork to sit on
/// without a single image file being committed.
class SampleArt {
  SampleArt._(this._covers);

  final Map<String, ImageProvider> _covers;

  /// One cover at every size: the catalogue paints at 512 and the
  /// components draw it down. The app's store is what varies the fetch
  /// by size; there is nothing to fetch here.
  WaxArtwork of(String seed) =>
      fixedArtwork(_covers[seed] ?? _covers.values.first);

  static Future<SampleArt> generate(
    List<String> seeds, {
    int size = 512,
  }) async {
    final covers = <String, ImageProvider>{};
    for (final seed in seeds) {
      covers[seed] = MemoryImage(await _paint(seed, size));
    }
    return SampleArt._(covers);
  }

  static Future<Uint8List> _paint(String seed, int size) async {
    final hash = seed.codeUnits.fold<int>(17, (a, b) => (a * 31 + b) & 0xFFFFF);
    final hue = (hash % 360).toDouble();
    final base = HSLColor.fromAHSL(1, hue, 0.32, 0.28).toColor();
    final accent = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.55, 0.58).toColor();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[base, accent.withValues(alpha: 0.75)],
        ).createShader(rect),
    );
    // A few concentric grooves: enough to read as a sleeve, never enough
    // to compete with the interface on top of it.
    final grooves = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size / 120
      ..color = const Color(0x1A000000);
    for (var i = 1; i < 9; i++) {
      canvas.drawCircle(
        Offset(size * 0.62, size * 0.42),
        size * 0.06 * i,
        grooves,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, size * 0.72, size.toDouble(), size / 90),
      Paint()..color = accent,
    );

    final image = await recorder.endRecording().toImage(size, size);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// Every seed the catalogue draws, so one call warms them all.
  static const List<String> seeds = <String>[
    'Salt Harbour',
    'The Quiet Part',
    'A History of Tides',
    'Late Night Reprise',
    'Ceremony for Small Rooms',
    'Marginalia',
    'Night Garden',
    'Winterreise',
    'Bell Tower Sessions',
    'Field Recordings',
    'The Long Signal',
    'Rooms',
    'Signal to Noise',
    'Coastal FM',
    'Night Bus',
    'Radio Meridian',
  ];
}
