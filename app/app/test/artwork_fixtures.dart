/// What the tests of the native artwork store share: its disk cache and
/// its server, both faked, and real pictures to decode.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show
        CacheManager,
        FileInfo,
        FileSource,
        HttpExceptionWithStatus,
        MemoryCacheSystem;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

/// A solid PNG, so a decode has something real to chew.
Future<Uint8List> artPng(
  int width, [
  int? height,
  Color color = const Color(0xFF2E6F9E),
]) async {
  final tall = height ?? width;
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), tall.toDouble()),
    Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(width, tall);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// How wide the first cover on screen is drawn, null before it has one.
int? coverDrawn(WidgetTester tester) {
  final held = tester.widgetList<RawImage>(find.byType(RawImage));
  return held.isEmpty ? null : held.first.image?.width;
}

/// Lets the store's real reads and the decode land, until the cover on
/// screen is [width] wide.
Future<void> coverDraws(WidgetTester tester, int width) async {
  for (var i = 0; i < 500 && coverDrawn(tester) != width; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(coverDrawn(tester), width);
}

/// A repository whose art URLs are under [base], as a native client's
/// are.
class ArtUnderBase extends FakeRepository {
  ArtUnderBase(this.base, {super.items});

  final String base;

  @override
  String artUrlFor(String pid, {String? role}) =>
      '$base${super.artUrlFor(pid, role: role)}';
}

/// A call a fake keeps waiting until the test lets it go.
class Hold {
  final Completer<void> _let = Completer<void>();

  /// Whether a call has come to it.
  bool reached = false;

  Future<T> wait<T>(FutureOr<T> Function() then) async {
    reached = true;
    await _let.future;
    return then();
  }

  void release() => _let.complete();
}

/// The store's disk cache, in front of a server that cannot be reached
/// until the test says what it [serve]s. Holds nothing but what it is
/// given ([hold]) or fetches, and records the name each fetch asked
/// under and each eviction dropped.
class FakeArtCache implements CacheManager {
  /// Every fetch of its own it was asked to make, by name.
  final List<String> asked = <String>[];

  /// The names an eviction asked it to drop.
  final List<String> removed = <String>[];

  /// How many times it was asked to drop everything.
  int emptied = 0;

  /// What it was asked to do, in order.
  final List<String> did = <String>[];

  /// Set, a read of what it holds waits on it: an index still opening.
  Hold? holdReads;

  /// Set, an emptying waits on it.
  Hold? holdEmptying;

  /// Answers this status for every fetch, while set: a server whose HTTP
  /// side fails with its socket up.
  int? refuseAll;

  final MemoryCacheSystem _files = MemoryCacheSystem();
  final Map<String, FileInfo> _held = <String, FileInfo>{};
  final Map<String, Uint8List> _served = <String, Uint8List>{};

  /// The names it holds a copy under.
  Iterable<String> get held => _held.keys;

  /// The server answers a fetch of [url] with [bytes] from here on,
  /// under whatever tag it is asked.
  void serve(String url, Uint8List bytes) => _served[url] = bytes;

  /// Keeps [bytes] under [name], as a fetch that answered would.
  Future<void> hold(String name, Uint8List bytes) async {
    final file = await _files.createFile('${_held.length}.img');
    await file.writeAsBytes(bytes);
    _held[name] = FileInfo(file, FileSource.Cache, DateTime.utc(2100), name);
  }

  /// [url] less the tag a replaced cover is asked under.
  static String _untagged(String url) {
    final uri = Uri.parse(url);
    final rest = <String, String>{...uri.queryParameters}..remove('v');
    return uri.replace(queryParameters: rest.isEmpty ? null : rest).toString();
  }

  // Through noSuchMethod rather than overrides: the manager's files are
  // package:file's, which this package has no business naming.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getSingleFile) {
      final url = invocation.positionalArguments.first as String;
      asked.add(url);
      did.add('asked');
      if (refuseAll case final status?) {
        throw HttpExceptionWithStatus(status, 'refused', uri: Uri.parse(url));
      }
      final bytes = _served[_untagged(url)];
      if (bytes == null) throw const SocketException('no route to host');
      return hold(url, bytes).then((_) => _held[url]!.file);
    }
    if (invocation.memberName == #getFileFromCache) {
      final name = invocation.positionalArguments.first as String;
      return holdReads?.wait(() => _held[name]) ??
          Future<FileInfo?>.value(_held[name]);
    }
    if (invocation.memberName == #removeFile) {
      final name = invocation.positionalArguments.first as String;
      removed.add(name);
      _held.remove(name);
      return Future<void>.value();
    }
    if (invocation.memberName == #emptyCache) {
      emptied++;
      did.add('emptied');
      void empty() => _held.clear();
      if (holdEmptying case final hold?) return hold.wait(empty);
      empty();
      return Future<void>.value();
    }
    if (invocation.memberName == #dispose) {
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// The server, as far as the store's own client can tell: canned replies
/// by URL, a connection error for everything else, and a record of what
/// was asked.
class FakeArtServer implements HttpClientAdapter {
  final Map<String, Uint8List> _bodies = <String, Uint8List>{};
  final Map<String, String?> _etags = <String, String?>{};
  final Set<String> _notModified = <String>{};
  final Map<String, Map<String, List<String>>> _headers =
      <String, Map<String, List<String>>>{};
  final List<String> requested = <String>[];
  final Stopwatch _clock = Stopwatch()..start();
  final Map<String, List<Duration>> _askedAt = <String, List<Duration>>{};

  /// Held open, a fetch waits on it before it answers: a cover on its way.
  Completer<void>? hold;

  /// Whether a request that presents the validator it would be sent
  /// again is answered 304, as the art endpoint answers.
  bool honoursValidators = false;

  /// Set, a held request answers with what was served when it was
  /// made, not when it is let go: a picture replaced, or one found for
  /// an item that had none, while it is on its way.
  bool answersAsAsked = false;

  final Set<String> _gone = <String>{};

  int _inFlight = 0;

  /// The most requests it ever had at once.
  int mostInFlight = 0;

  /// Answers 404 for [url]: a cover that was removed.
  void serveGone(String url) => _gone.add(url);

  final Map<String, int> _refused = <String, int>{};

  /// Answers [status] for [url] every time.
  void refuse(String url, int status) => _refused[url] = status;

  /// Answers this for everything, while set.
  int? refuseAll;

  /// Stops answering for [url], as an unreachable server does.
  void cut(String url) {
    _bodies.remove(url);
    _etags.remove(url);
    _gone.remove(url);
  }

  void serve(String url, String body, {String? etag}) =>
      serveBytes(url, Uint8List.fromList(utf8.encode(body)), etag: etag);

  void serveBytes(String url, Uint8List body, {String? etag}) {
    _refused.remove(url);
    _bodies[url] = body;
    _etags[url] = etag;
    _notModified.remove(url);
  }

  void serveNotModified(String url) => _notModified.add(url);

  Map<String, List<String>> headersFor(String url) =>
      _headers[url] ?? <String, List<String>>{};

  /// Every time [url] was asked since the server was made, on a clock
  /// started with it: clearing [requested] leaves these.
  List<Duration> askedAt(String url) => _askedAt[url] ?? const <Duration>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    (_askedAt[url] ??= <Duration>[]).add(_clock.elapsed);
    _inFlight++;
    if (_inFlight > mostInFlight) mostInFlight = _inFlight;
    final askedBody = _bodies[url];
    final askedEtag = _etags[url];
    final askedGone = _gone.contains(url);
    if (hold case final gate?) await gate.future;
    _inFlight--;
    _headers[url] = <String, List<String>>{
      for (final entry in options.headers.entries)
        entry.key: <String>['${entry.value}'],
    };
    if (refuseAll ?? _refused[url] case final status?) {
      return ResponseBody.fromBytes(Uint8List(0), status);
    }
    if (_notModified.contains(url)) {
      return ResponseBody.fromBytes(Uint8List(0), 304);
    }
    if (answersAsAsked ? askedGone : _gone.contains(url)) {
      return ResponseBody.fromBytes(Uint8List(0), 404);
    }
    final presented = options.headers['If-None-Match'];
    final servedEtag = answersAsAsked ? askedEtag : _etags[url];
    if (honoursValidators && presented != null && presented == servedEtag) {
      return ResponseBody.fromBytes(Uint8List(0), 304);
    }
    final body = answersAsAsked ? askedBody : _bodies[url];
    if (body == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    final etag = servedEtag;
    return ResponseBody.fromBytes(
      body,
      200,
      headers: <String, List<String>>{
        if (etag != null) 'etag': <String>[etag],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
