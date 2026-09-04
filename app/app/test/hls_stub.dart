import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// A stand-in for the vendored hls.js, planted on `window` so the
/// timeline engine finds it instead of injecting the real script.
///
/// The engine deliberately skips its own loader when `window.Hls`
/// already exists, which is the seam this uses. What the stub does is
/// the one thing that matters for the engine's own logic: attaching to
/// a media element gives that element real, playable media, so
/// `currentTime`, `seeked`, `ended` and the rest are the browser's own
/// behaviour and not a fake's idea of it.
///
/// The media is silence generated here rather than a file in the repo,
/// and the elements the tests drive are muted besides: a suite that
/// plays audible sound through whatever machine runs it is a suite
/// nobody wants to run.
void installHlsStub({required String src}) {
  _setGlobal('__waxdeckTimelineSrc', src.toJS);
  _setGlobal('__waxdeckMse', true.toJS);
  _setGlobal('__waxdeckStall', false.toJS);
  globalContext.callMethod<JSAny?>('eval'.toJS, _stub.toJS);
}

/// Makes the stub answer that this browser has no Media Source
/// Extensions, which is what an engine refusing to play a timeline at
/// all has to be told.
void setStubMseSupported(bool supported) =>
    _setGlobal('__waxdeckMse', supported.toJS);

/// Fires an hls.js error at whatever the engine last constructed.
/// [status] is the HTTP status the fetch answered, which is what the
/// engine actually branches on.
void fireHlsError({
  int? status,
  bool fatal = true,
  String type = 'networkError',
}) {
  final data = JSObject();
  data['fatal'] = fatal.toJS;
  data['type'] = type.toJS;
  if (status != null) {
    final response = JSObject();
    response['code'] = status.toJS;
    data['response'] = response;
  }
  globalContext.callMethod<JSAny?>('__waxdeckHlsError'.toJS, data);
}

/// Stands in for the user gesture a headless runner cannot give.
///
/// Chrome refuses `play()` with no interaction behind it - muted or
/// not, and there is no flag `flutter test` will pass through to change
/// that - so the suites move the element's clock themselves. The engine
/// reads playback off the element's own events either way, which is
/// exactly the path this drives: what a real gesture would have
/// produced, produced directly.
void grantPlayback(web.HTMLMediaElement element) =>
    element.dispatchEvent(web.Event('play'));

/// Moves the element's clock and announces it the way a playing element
/// does.
void stepElement(web.HTMLMediaElement element, Duration to) {
  element.currentTime = to.inMilliseconds / 1000;
  element.dispatchEvent(web.Event('timeupdate'));
}

/// Runs the element off the end of its media.
void endElement(web.HTMLMediaElement element) =>
    element.dispatchEvent(web.Event('ended'));

/// Removes the stub, so a test that wants the loader path sees a window
/// with no `Hls` on it.
void removeHlsStub() =>
    globalContext.callMethod<JSAny?>('eval'.toJS, 'delete window.Hls;'.toJS);

/// Makes the stub attach no media, so a load stays open until the test
/// answers it - which is the only way to reach the engine's load-time
/// error branches, since a stub that attaches real media answers every
/// load before a test can say anything about it.
void setStubStalled(bool stalled) => _setGlobal('__waxdeckStall', stalled.toJS);

/// Forgets the player the stub last constructed, so a test can wait for
/// the next one before firing an error at it.
void forgetHlsPlayer() => globalContext.callMethod<JSAny?>(
  'eval'.toJS,
  'window.__waxdeckHls = null;'.toJS,
);

/// Whether the stub has constructed a player since [forgetHlsPlayer].
bool hlsPlayerExists() => globalContext['__waxdeckHls'].isDefinedAndNotNull;

void _setGlobal(String name, JSAny value) => globalContext[name] = value;

/// A `data:` URI holding [seconds] of 8 kHz 8-bit mono silence.
///
/// Small enough to inline (a second is eight thousand bytes before
/// base64) and playable by every browser without a codec question, so
/// what a test asserts is the engine's arithmetic rather than the
/// decoder's opinion of a container.
String silentWavDataUri({int seconds = 3}) {
  const rate = 8000;
  final samples = rate * seconds;
  final bytes = BytesBuilder();
  void ascii(String s) => bytes.add(s.codeUnits);
  void u32(int v) => bytes.add(
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little),
  );
  void u16(int v) => bytes.add(
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little),
  );
  ascii('RIFF');
  u32(36 + samples);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(rate);
  u32(rate); // byte rate: one byte a sample
  u16(1); // block align
  u16(8); // bits a sample
  ascii('data');
  u32(samples);
  // 8-bit PCM is unsigned, so silence is the midpoint rather than zero.
  bytes.add(Uint8List(samples)..fillRange(0, samples, 128));
  return 'data:audio/wav;base64,${base64Encode(bytes.takeBytes())}';
}

const String _stub = r'''
(function () {
  function Hls(config) {
    this.config = config;
    this.handlers = {};
    window.__waxdeckHls = this;
  }
  Hls.isMSESupported = function () { return window.__waxdeckMse !== false; };
  Hls.prototype.on = function (event, cb) { this.handlers[event] = cb; };
  Hls.prototype.attachMedia = function (media) {
    this.media = media;
    media.muted = true;
    // A stall stands in for a fetch that never became media: the
    // element is emptied and given no source, so `canplay` never fires
    // and the load stays open for whatever the test answers it with.
    // Emptied rather than merely left alone, because an element still
    // holding a decoded source from an earlier load fires `canplay`
    // again the moment anybody moves its clock.
    if (window.__waxdeckStall === true) {
      media.removeAttribute("src");
      media.load();
      return;
    }
    media.src = window.__waxdeckTimelineSrc;
    media.load();
  };
  Hls.prototype.loadSource = function (url) { this.url = url; };
  Hls.prototype.startLoad = function () {};
  Hls.prototype.stopLoad = function () { this.stopped = true; };
  Hls.prototype.detachMedia = function () {
    if (this.media) { this.media.pause(); this.media.removeAttribute("src"); }
  };
  Hls.prototype.destroy = function () { this.destroyed = true; };
  window.Hls = Hls;
  window.__waxdeckHlsError = function (data) {
    var hls = window.__waxdeckHls;
    if (hls && hls.handlers["hlsError"]) {
      hls.handlers["hlsError"]("hlsError", data);
    }
  };
})();
''';
