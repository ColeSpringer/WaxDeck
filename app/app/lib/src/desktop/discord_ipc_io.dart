/// The Discord IPC client (a handshake and one command over the desktop
/// client's local socket; small enough to write rather than bind), and the
/// cover lookup presence shows. The application id is public; no credential.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../shell/app_version.dart';
import 'discord_presence.dart';

DiscordPresencePort createDiscordPresencePort() =>
    _isDesktop ? DiscordIpcPresence() : const NoDiscordPresence();

bool get _isDesktop => Platform.isLinux || Platform.isWindows;

/// The IPC opcodes this client uses. There are two more (CLOSE and
/// PONG) and both are things Discord says, not things it is told.
const int _opHandshake = 0;
const int _opFrame = 1;

/// Discord listens on the first free one of ten sockets, so a second
/// client (a beta build beside a stable one) is why this is a range
/// rather than a path.
const int _socketSlots = 10;

class DiscordIpcPresence implements DiscordPresencePort {
  DiscordIpcPresence({
    Iterable<String> Function()? paths,
    Duration? answerWithin,
  }) : _paths = paths ?? _candidatePaths,
       _answerWithin = answerWithin ?? const Duration(minutes: 1);

  final Iterable<String> Function() _paths;

  /// How long Discord gets to answer. It has taken 29 s to say READY; a
  /// minute of silence is a Discord that will not, or not Discord at all.
  final Duration _answerWithin;

  _Transport? _transport;

  /// Discord refused an activity's image URL on this connection, so covers
  /// go back to [kDiscordCoverAsset] until it is dialled again.
  bool _urlsRefused = false;

  @override
  bool get takesImageUrls => !_urlsRefused;

  @override
  void Function()? onImageRefused;

  /// The newest command whose image was a URL, until answered: a reply
  /// to an older one is about a cover no longer in view.
  String? _urlNonce;

  /// Writes go one at a time: a socket refuses a write mid-flush.
  Future<void> _writes = Future<void>.value();

  /// Who this connects as, remembered so a dropped connection can be
  /// dialled again without the app being told to reconfigure.
  String? _applicationId;

  /// Counts the frames sent, for the nonce every command carries: Discord
  /// matches its reply to the command by it, and so does [_onReply].
  int _nonce = 0;

  /// Which dial is current. One still waiting on Discord when the app
  /// stopped or dialled again is let go rather than kept.
  int _generation = 0;

  /// The dial that updates made while Discord gets ready all wait on.
  Future<bool>? _dialling;

  @override
  Future<bool> connect(String applicationId) async {
    final generation = ++_generation;
    _applicationId = applicationId.isEmpty ? null : applicationId;
    if (applicationId.isEmpty) return false;
    await _drop();
    // A Discord dialled again (restarted, another id) is asked again.
    _urlsRefused = false;
    final hello = _frame(_opHandshake, <String, Object?>{
      'v': 1,
      'client_id': applicationId,
    });
    for (final path in _paths()) {
      final transport = await _open(path);
      if (transport == null) continue;
      var ready = false;
      try {
        // Discord drops a command sent before its READY, so the connection
        // is not handed out until then.
        ready = await transport.handshake(hello).timeout(_answerWithin);
      } on Object catch (failure) {
        // Another program on a discord-ipc path, or one that never says
        // READY. Try the next slot rather than giving up on all of them.
        debugPrint('discord handshake refused on $path: $failure');
      }
      if (ready && generation == _generation) {
        _transport = transport;
        return true;
      }
      await transport.close();
      if (generation != _generation) return false;
    }
    return false;
  }

  @override
  Future<void> publish(DiscordActivity? activity) async {
    // Discord quit and came back. Dialled here rather than left to the
    // app, whose settings did not change; publishes are already spaced
    // fifteen seconds apart, so a retry costs one sweep of dead paths.
    if (_transport == null) {
      final id = _applicationId;
      if (id == null || activity == null) return;
      final dial = _dialling ??= connect(
        id,
      ).whenComplete(() => _dialling = null);
      if (!await dial) return;
    }
    final nonce = '${++_nonce}';
    final image = _urlsRefused ? null : activity?.largeImageUrl;
    if (image != null) _urlNonce = nonce;
    try {
      await _send(_opFrame, <String, Object?>{
        'cmd': 'SET_ACTIVITY',
        'nonce': nonce,
        'args': <String, Object?>{
          'pid': pid,
          'activity': activity == null ? null : _activity(activity, image),
        },
      });
    } on Object catch (failure) {
      // Discord was closed under us. Dropped rather than retried inside
      // this call - the socket is gone and a loop against it is a loop -
      // and picked up again by the reconnect above on the next publish.
      debugPrint('discord presence dropped: $failure');
      await _drop();
    }
  }

  /// Stops entirely: the app turning presence off, or reconfiguring.
  /// Forgets who to publish as, so nothing here dials again on its own.
  @override
  Future<void> close() async {
    _generation++;
    _applicationId = null;
    await _drop();
  }

  /// Lets go of the socket and keeps the identity, which is the
  /// difference between "Discord went away" and "stop".
  Future<void> _drop() async {
    final transport = _transport;
    _transport = null;
    _urlNonce = null;
    await transport?.close();
  }

  /// Fits a line to Discord's two-to-128 limit. Padded rather than
  /// dropped at the short end: one-character titles are real ("7",
  /// "X", "i"), and a rejected field fails the whole update.
  String? _line(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    if (text.length < 2) return text.padRight(2);
    return text.length <= 128 ? text : text.substring(0, 128);
  }

  /// A reply to a command. An error about the image, answering the newest
  /// one whose image was a URL, is Discord refusing external images; the
  /// resend is the caller's to pace.
  void _onReply(Map<String, Object?> reply) {
    final nonce = reply['nonce'];
    if (nonce is! String || nonce != _urlNonce) return;
    _urlNonce = null;
    final data = reply['data'];
    final message = data is Map ? '${data['message']}' : '';
    if (reply['evt'] != 'ERROR' || !message.contains('large_image')) return;
    debugPrint('discord refused a cover URL: $message');
    _urlsRefused = true;
    onImageRefused?.call();
  }

  Map<String, Object?> _activity(DiscordActivity activity, String? image) {
    return <String, Object?>{
      // Type 2 is what renders as "Listening to WaxDeck" with a progress
      // bar rather than "Playing".
      'type': 2,
      if (_line(activity.title) != null) 'details': _line(activity.title),
      if (_line(activity.artist) != null) 'state': _line(activity.artist),
      if (activity.start != null)
        'timestamps': <String, Object?>{
          'start': activity.start!.millisecondsSinceEpoch,
          if (activity.end != null) 'end': activity.end!.millisecondsSinceEpoch,
        },
      'assets': <String, Object?>{
        'large_image': image ?? kDiscordCoverAsset,
        if (_line(activity.album) != null) 'large_text': _line(activity.album),
      },
      'instance': false,
    };
  }

  Future<void> _send(int opcode, Map<String, Object?> payload) {
    final transport = _transport;
    if (transport == null) return Future<void>.value();
    final frame = _frame(opcode, payload);
    final write = _writes.then(
      (_) => transport.write(frame).timeout(_answerWithin),
    );
    _writes = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<_Transport?> _open(String path) async {
    try {
      if (Platform.isWindows) {
        final pipe = await File(path).open(mode: FileMode.append);
        return _PipeTransport(pipe, _onReply);
      }
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      return _SocketTransport(socket, _onReply);
    } on Object {
      // No socket at this path is the ordinary case: nine of the ten
      // slots are empty on a machine running one Discord.
      return null;
    }
  }
}

/// Every path a Discord client might be listening on, in the order worth
/// trying. A Flatpak or Snap Discord puts its socket inside its own
/// runtime directory, which is why this walks several.
Iterable<String> _candidatePaths() sync* {
  if (Platform.isWindows) {
    for (var slot = 0; slot < _socketSlots; slot++) {
      // Not \\.\pipe\: dart:io takes that for a network share, and fails.
      yield r'\\?\pipe\discord-ipc-'
          '$slot';
    }
    return;
  }
  final environment = Platform.environment;
  final roots = <String>[
    for (final name in const <String>[
      'XDG_RUNTIME_DIR',
      'TMPDIR',
      'TMP',
      'TEMP',
    ])
      if (environment[name]?.isNotEmpty ?? false) environment[name]!,
    '/tmp',
  ];
  const sandboxes = <String>[
    '',
    '/app/com.discordapp.Discord',
    '/app/com.discordapp.DiscordCanary',
    '/snap.discord',
  ];
  for (final root in roots) {
    for (final sandbox in sandboxes) {
      for (var slot = 0; slot < _socketSlots; slot++) {
        yield '${root.replaceAll(RegExp(r'/+$'), '')}'
            '$sandbox/discord-ipc-$slot';
      }
    }
  }
}

/// One end of the IPC connection, whichever shape the platform gives it.
abstract class _Transport {
  /// Sends [hello]; true once Discord says READY, false if it hangs up.
  Future<bool> handshake(Uint8List hello);

  Future<void> write(Uint8List bytes);

  Future<void> close();
}

class _SocketTransport implements _Transport {
  _SocketTransport(this._socket, void Function(Map<String, Object?>) onReply) {
    // Read, and not only drained: a socket nobody reads fills its buffer
    // and stops accepting writes, and READY and a refused image are only
    // ever said in a reply.
    _socket.listen(
      _FrameReader((reply) {
        if (reply['evt'] == 'READY') _settle(true);
        onReply(reply);
      }).add,
      onError: (Object _) => _settle(false),
      onDone: () => _settle(false),
      cancelOnError: false,
    );
  }

  final Socket _socket;
  final Completer<bool> _ready = Completer<bool>();

  void _settle(bool ready) {
    if (!_ready.isCompleted) _ready.complete(ready);
  }

  @override
  Future<bool> handshake(Uint8List hello) async {
    await write(hello);
    return _ready.future;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } on Object {
      // Already gone, which is the usual reason for closing.
    }
    _socket.destroy();
  }
}

/// Discord's pipe on Windows, read only for the answer to what was just
/// written: Discord answers every command, so a read never waits under a
/// write. One that goes unanswered is given up on by the caller's clock.
class _PipeTransport implements _Transport {
  _PipeTransport(this._pipe, this._onReply);

  final RandomAccessFile _pipe;
  final void Function(Map<String, Object?>) _onReply;

  /// The file's operations in order. A timeout gives up on one without
  /// ending it, and the file will not close under it.
  Future<void> _io = Future<void>.value();

  Future<T> _next<T>(Future<T> Function() operation) {
    final next = _io.then((_) => operation());
    _io = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<bool> handshake(Uint8List hello) => _next(() async {
    await _pipe.writeFrom(hello);
    return (await _answer())?['evt'] == 'READY';
  });

  @override
  Future<void> write(Uint8List bytes) => _next(() async {
    // No flush: on a pipe that is FlushFileBuffers, which blocks until
    // the far end reads, so a wedged Discord would hang every publish.
    await _pipe.writeFrom(bytes);
    final answer = await _answer();
    if (answer != null) _onReply(answer);
  });

  /// The next frame's JSON, or null for one this client cannot read.
  Future<Map<String, Object?>?> _answer() async {
    final header = ByteData.sublistView(await _read(8));
    final length = header.getUint32(4, Endian.little);
    if (length > _maxFrame) throw const FormatException('not Discord');
    final body = await _read(length);
    if (header.getUint32(0, Endian.little) != _opFrame) return null;
    try {
      final reply = jsonDecode(utf8.decode(body));
      return reply is Map<String, Object?> ? reply : null;
    } on FormatException {
      return null;
    }
  }

  Future<Uint8List> _read(int count) async {
    final bytes = BytesBuilder(copy: false);
    while (bytes.length < count) {
      final chunk = await _pipe.read(count - bytes.length);
      if (chunk.isEmpty) throw const FileSystemException('Discord hung up');
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  /// Closes once the operation in flight ends, without holding the caller
  /// for it: a Discord that never answers would hold it for good.
  @override
  Future<void> close() async {
    unawaited(_next(_pipe.close).then<void>((_) {}, onError: (Object _) {}));
  }
}

/// [payload] as one IPC frame: opcode and length, then the JSON.
Uint8List _frame(int opcode, Map<String, Object?> payload) {
  final body = utf8.encode(jsonEncode(payload));
  final frame = Uint8List(8 + body.length);
  ByteData.view(frame.buffer)
    ..setUint32(0, opcode, Endian.little)
    ..setUint32(4, body.length, Endian.little);
  frame.setRange(8, frame.length, body);
  return frame;
}

const int _maxFrame = 1 << 20;

/// Splits what Discord sends into frames and hands on each JSON reply.
class _FrameReader {
  _FrameReader(this._onFrame);

  final void Function(Map<String, Object?>) _onFrame;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  void add(Uint8List chunk) {
    _buffer.add(chunk);
    var bytes = _buffer.takeBytes();
    while (bytes.length >= 8) {
      final header = ByteData.sublistView(bytes, 0, 8);
      final length = header.getUint32(4, Endian.little);
      // Not Discord: nothing it says comes near this.
      if (length > _maxFrame) return;
      if (bytes.length < 8 + length) break;
      if (header.getUint32(0, Endian.little) == _opFrame) {
        try {
          final body = jsonDecode(utf8.decode(bytes.sublist(8, 8 + length)));
          if (body is Map<String, Object?>) _onFrame(body);
        } on FormatException {
          // Not a reply this client can read; the next frame may be.
        }
      }
      bytes = bytes.sublist(8 + length);
    }
    _buffer.add(bytes);
  }
}

/// [coverArtFront] over one client, kept for as long as the lookup is.
Future<String?> Function(String mbid) coverArtLookup() {
  final client = _archiveClient();
  return (mbid) => coverArtFront(mbid, client: client);
}

HttpClient _archiveClient() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 5)
  ..userAgent =
      'WaxDeck/$kAppVersion (+https://github.com/colespringer/waxdeck)';

/// The Cover Art Archive's own address for release [mbid]'s front image,
/// once its redirects end on one, or null when it has none. Throws when
/// the archive cannot answer, so a miss is only ever its 404.
Future<String?> coverArtFront(
  String mbid, {
  Uri? archive,
  HttpClient? client,
}) async {
  final base = archive ?? Uri.https('coverartarchive.org');
  final http = client ?? _archiveClient();
  try {
    final front = base.replace(
      path: '/release/${Uri.encodeComponent(mbid)}/front-500',
    );
    final request = await http.headUrl(front);
    final response = await request.close().timeout(const Duration(seconds: 10));
    await response.drain<void>();
    final status = response.statusCode;
    if (status == HttpStatus.notFound) return null;
    if (status != HttpStatus.ok) {
      throw HttpException('the archive answered $status', uri: request.uri);
    }
    var at = front;
    for (final hop in response.redirects) {
      at = at.resolveUri(hop.location);
    }
    // No downgrade on the way: Discord fetches through the same redirects.
    // The address given is the archive's, not the storage node's.
    return at.scheme == base.scheme ? front.toString() : null;
  } finally {
    if (client == null) http.close(force: true);
  }
}
