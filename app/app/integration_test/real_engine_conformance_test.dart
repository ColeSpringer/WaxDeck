// Runs the shared engine conformance suite against whatever real player
// just_audio resolves to here - mpv via media_kit on the desktops,
// ExoPlayer on Android - with real decoding and wall-clock waits. The
// suite lives in waxdeck_player_testing; this file only supplies the
// real-engine harness. The caller synthesizes the tone fixture and names
// it in WAXDECK_CONFORMANCE_MEDIA: run-desktop.sh as a path in the
// environment, the emulator workflow as a loopback URL in a define. The
// tone's HLS presentations sit beside it, in conformance-hls-<format>/.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:integration_test/integration_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

class RealEngineHarness extends AudioEngineHarness {
  RealEngineHarness(this.mediaUrl);

  @override
  final String mediaUrl;

  @override
  Duration get mediaDuration => const Duration(seconds: 8);

  @override
  Duration get tolerance => const Duration(milliseconds: 500);

  @override
  Future<AudioEnginePort> createEngine() async {
    final engine = await createUnsilencedEngine();
    // Silent: this suite plays several minutes of a test tone through
    // the machine's real audio output, and whoever is at the keyboard
    // should not have to hear it. The one case that does assert on the
    // engine's own initial volume asks for an unsilenced engine instead,
    // and never plays through it.
    await engine.setVolume(0);
    return engine;
  }

  @override
  Future<AudioEnginePort> createUnsilencedEngine() async {
    ensureAudioEngineInitialized();
    return JustAudioEngine();
  }

  @override
  Future<void> advance(AudioEnginePort engine, Duration amount) async {
    // Media time is wall time on a real engine. Short amounts play out
    // for real; large ones seek to just before the target and play the
    // remainder, so reaching the end never costs the whole file.
    if (amount <= Duration.zero) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }
    final duration = engine.duration;
    if (amount > const Duration(seconds: 3) && duration != null) {
      const runway = Duration(milliseconds: 500);
      var target = engine.position + amount;
      if (target > duration - runway) {
        target = duration - runway;
      }
      await engine.seek(target);
      // The wall clock is not the media clock behind this seek: the
      // seam only arrives once the audio pipeline drains, and a pulse
      // null sink holds about two seconds where CoreAudio holds under
      // one - a fixed wait raced that drain and lost on exactly one
      // platform, which read as eight engine failures on linux CI. So
      // the wait is for evidence the seam passed: the position falling
      // away from the runway (a boundary reset), or playback ending
      // (completion), with a cap for an engine that does neither.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!engine.playing) break;
        if (engine.position < target - const Duration(seconds: 1)) break;
      }
      // A beat for the seam's own events to reach their listeners.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }
    // Short amounts play out for real, measured on the engine's own
    // clock rather than the wall: a fresh pipeline (a replay's reload,
    // a cold sink) spends wall time before the position moves, and a
    // fixed sleep charged that spin-up against the media time it was
    // supposed to advance. A paused or completed engine cannot advance
    // media time at all, so the wait ends rather than burning the cap.
    final from = engine.position;
    final deadline = DateTime.now().add(amount + const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!engine.playing) break;
      if (engine.position - from >= amount) break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  // Neither the desktop's file nor the workflow's server can be cut on
  // demand, so the failure group plays the tone from the harness's own.
  @override
  bool get canFailPlayback => true;

  Future<Uint8List>? _tone;
  _CuttableTone? _served;

  @override
  Future<String> failableMedia() async {
    await _served?.close();
    final bytes = await (_tone ??= _readBytes(Uri.parse(mediaUrl)));
    final served = _served = await _CuttableTone.serve(bytes);
    return served.url;
  }

  @override
  Future<void> failPlayback(AudioEnginePort engine) async {
    final served = _served;
    if (served == null) {
      throw StateError('failPlayback cuts only what failableMedia served');
    }
    await served.cut();
  }

  // Served by the harness, like the cuttable tone, so a segment can be
  // refused on demand. The fixture generator's formats.
  @override
  List<String> get presentationFormats => const ['opus', 'flac'];

  final _presentationFiles = <String, Future<Map<String, Uint8List>>>{};
  _ServedPresentation? _presentation;

  @override
  Future<String> presentation(String format, {int? refuseFrom}) async {
    await _presentation?.close();
    final files = await (_presentationFiles[format] ??= _readPresentation(
      Uri.parse(mediaUrl),
      format,
    ));
    final served = _presentation = await _ServedPresentation.serve(
      files,
      refuseFrom: refuseFrom,
    );
    return served.url;
  }

  @override
  Future<void> disposeEngine(AudioEnginePort engine) async {
    await engine.dispose();
    await _served?.close();
    _served = null;
    await _presentation?.close();
    _presentation = null;
  }
}

/// A fixture's bytes: the file on the desktop, the workflow's server on
/// Android.
Future<Uint8List> _readBytes(Uri uri) async {
  if (uri.isScheme('file')) return File.fromUri(uri).readAsBytes();
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('$uri answered ${response.statusCode}', uri: uri);
    }
    final bytes = BytesBuilder(copy: false);
    await response.forEach(bytes.add);
    return bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
}

/// The tone over loopback HTTP, served like a slow stream and cut like a
/// dropped connection.
///
/// Half goes out at once, so a load and the seconds of play before a cut
/// never wait on it. The rest trickles far below the tone's own rate (its
/// tail takes about a minute), so the transfer is still running whenever
/// the test cuts it, yet a sliver lands often enough that no engine's read
/// timeout fires: 5s under mpv, 8s in ExoPlayer.
class _CuttableTone {
  _CuttableTone._(this._server, this._bytes)
    : url = 'http://127.0.0.1:${_server.port}/conformance-tone.flac';

  static Future<_CuttableTone> serve(Uint8List bytes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final tone = _CuttableTone._(server, bytes);
    // A connection the cut tears down is no error of the test's.
    server.listen(tone._answer, onError: (Object _) {});
    return tone;
  }

  static const _sliver = 512;
  static const _sliverEvery = Duration(milliseconds: 250);

  final HttpServer _server;
  final Uint8List _bytes;
  var _sending = 0;
  var _cut = false;
  var _closed = false;

  /// Read at the start: a closed server has no port to ask.
  final String url;

  /// Drops the transfer for good: the response in flight dies mid-body and
  /// the port closes, so every reconnect is refused. The refusal is what
  /// makes the cut unambiguous. ExoPlayer resumes a progressive load with a
  /// range from where it stopped, and gives up only once its retries are
  /// spent; ffmpeg under mpv takes a body that ends short for the end of the
  /// file unless its reconnect fails, and a refused connect is the line
  /// media_kit reports as an error.
  Future<void> cut() async {
    if (_sending == 0) {
      throw StateError(
        'nothing was fetching the tone, so there was nothing to cut',
      );
    }
    _cut = true;
    await close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
  }

  Future<void> _answer(HttpRequest request) async {
    final response = request.response;
    final length = _bytes.length;
    final asked = RegExp(
      r'^bytes=(\d+)-(\d*)$',
    ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    final start = asked == null ? 0 : int.parse(asked[1]!);
    final end = asked == null || asked[2]!.isEmpty
        ? length
        : min(int.parse(asked[2]!) + 1, length);
    try {
      if (start >= end) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await response.close();
        return;
      }
      // Ranges and a length, never chunks, or a cut reads as the end of the
      // file: ffmpeg reconnects only to a response it can seek and knows
      // the end of, and Android's HTTP stack calls a body short only
      // against the length it was promised.
      response.headers
        ..contentType = ContentType('audio', 'flac')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (asked != null) {
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${end - 1}/$length',
          );
      }
      response.contentLength = end - start;
      // Unbuffered, or flush leaves each sliver waiting for 8 KB of company.
      response.bufferOutput = false;
      _sending++;
      try {
        var at = max(start, min(end, length ~/ 2));
        if (at > start) response.add(Uint8List.sublistView(_bytes, start, at));
        await response.flush();
        while (at < end) {
          await Future<void>.delayed(_sliverEvery);
          if (_cut) return;
          final next = min(at + _sliver, end);
          response.add(Uint8List.sublistView(_bytes, at, next));
          await response.flush();
          at = next;
        }
        await response.close();
      } finally {
        _sending--;
      }
    } on Object {
      // The cut, landing mid-write.
    }
  }
}

/// The tone's HLS presentation in [format], which the fixture generator
/// writes beside it, read once by name: the master, its media playlist and
/// every file that lists.
Future<Map<String, Uint8List>> _readPresentation(
  Uri tone,
  String format,
) async {
  final base = tone.resolve('conformance-hls-$format/');
  final files = <String, Uint8List>{};
  Future<String> playlist(String name) async =>
      utf8.decode(files[name] = await _readBytes(base.resolve(name)));
  for (final media in _named(await playlist('master.m3u8'))) {
    for (final name in _named(await playlist(media))) {
      files[name] = await _readBytes(base.resolve(name));
    }
  }
  return files;
}

/// What a playlist names: its URI lines and its URI attributes.
Iterable<String> _named(String playlist) sync* {
  for (final line in const LineSplitter().convert(playlist)) {
    final attribute = RegExp(r'URI="([^"]+)"').firstMatch(line);
    if (attribute != null) {
      yield attribute[1]!;
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      yield line;
    }
  }
}

/// The presentation over loopback HTTP, the way the server hands one out.
/// With refuseFrom, every segment from that index on answers the server's
/// busy refusal: a listen let go of on a server that filled meanwhile.
class _ServedPresentation {
  _ServedPresentation._(this._server, this._files, this._refuseFrom)
    : url = 'http://127.0.0.1:${_server.port}/master.m3u8';

  static Future<_ServedPresentation> serve(
    Map<String, Uint8List> files, {
    int? refuseFrom,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final served = _ServedPresentation._(server, files, refuseFrom);
    server.listen(served._answer, onError: (Object _) {});
    return served;
  }

  final HttpServer _server;
  final Map<String, Uint8List> _files;
  final int? _refuseFrom;

  /// Read at the start: a closed server has no port to ask.
  final String url;

  Future<void> close() => _server.close(force: true);

  Future<void> _answer(HttpRequest request) async {
    final response = request.response;
    final name = request.uri.path.substring(1);
    final segment = RegExp(r'^seg-(\d+)\.m4s$').firstMatch(name);
    final refuseFrom = _refuseFrom;
    try {
      if (segment != null &&
          refuseFrom != null &&
          int.parse(segment[1]!) >= refuseFrom) {
        response
          ..statusCode = HttpStatus.tooManyRequests
          ..headers.contentType = ContentType.json
          ..write(
            '{"code":"transcode-limited",'
            '"message":"the streaming engine is busy; retry shortly"}',
          );
        await response.close();
        return;
      }
      final bytes = _files[name];
      if (bytes == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      response.headers.contentType = name.endsWith('.m3u8')
          ? ContentType('application', 'vnd.apple.mpegurl')
          : ContentType('audio', 'mp4');
      response.contentLength = bytes.length;
      response.add(bytes);
      await response.close();
    } on Object {
      // A player that hung up mid-answer.
    }
  }
}

/// The tone's location, compiled in.
///
/// `flutter test -d <device>` runs the test inside the app process on
/// the device, which cannot see the shell that launched it, so a define
/// is the only channel that reaches an emulator or a phone. Empty when
/// the caller uses the environment instead - which is what
/// run-desktop.sh does, because it runs the suite on this machine and a
/// define would mean recompiling per invocation.
const _mediaDefine = String.fromEnvironment('WAXDECK_CONFORMANCE_MEDIA');

/// A local path becomes a file URI; a URL is passed through.
///
/// An app on a device has no host path to open, so the emulator run
/// serves the tone over loopback HTTP instead - which is also the shape
/// a real library stream takes.
String _mediaUrl(String value) =>
    value.startsWith('http://') || value.startsWith('https://')
    ? value
    : Uri.file(value).toString();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final media = _mediaDefine.isNotEmpty
      ? _mediaDefine
      : Platform.environment['WAXDECK_CONFORMANCE_MEDIA'] ?? '';
  if (media.isEmpty) {
    // Without media there is nothing honest to test; fail loudly rather
    // than skip silently.
    throw StateError(
      'WAXDECK_CONFORMANCE_MEDIA must name the synthesized tone, as a '
      '--dart-define or in the environment; run this through '
      'e2e/run-desktop.sh or the android-conformance workflow',
    );
  }

  runAudioEngineConformance(
    'JustAudioEngine on ${Platform.operatingSystem}',
    RealEngineHarness(_mediaUrl(media)),
  );
}
