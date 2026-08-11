/// The Discord IPC client: a handshake and one command, over the socket
/// the desktop client listens on.
///
/// Written rather than depended on. The three published bindings all
/// wrap something heavy to send the same two JSON frames - a native
/// library through FFI, or a Rust bridge that would put a toolchain in
/// the Windows build - and the protocol is small enough to read in one
/// sitting: a four-byte little-endian opcode, a four-byte little-endian
/// length, and a UTF-8 JSON body.
///
/// Nothing here is a credential. The application id is a public
/// snowflake from the developer portal, there is no bot and no OAuth,
/// and the socket is local by construction.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
  _Transport? _transport;

  /// Who this connects as, remembered so a dropped connection can be
  /// dialled again without the app being told to reconfigure.
  String? _applicationId;

  /// Counts the frames sent, for the nonce every command carries.
  /// Discord uses it to match its reply to the command; nothing here
  /// reads the reply, but a command without one is rejected.
  int _nonce = 0;

  @override
  Future<bool> connect(String applicationId) async {
    _applicationId = applicationId.isEmpty ? null : applicationId;
    if (applicationId.isEmpty) return false;
    await _drop();
    for (final path in _candidatePaths()) {
      final transport = await _open(path);
      if (transport == null) continue;
      _transport = transport;
      try {
        await _send(_opHandshake, <String, Object?>{
          'v': 1,
          'client_id': applicationId,
        });
        return true;
      } on Object catch (failure) {
        // The socket existed and would not take the handshake: another
        // program on a discord-ipc path, or an id this client will not
        // accept. Try the next slot rather than giving up on all of
        // them.
        debugPrint('discord handshake refused on $path: $failure');
        await _drop();
      }
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
      if (!await connect(id)) return;
    }
    try {
      await _send(_opFrame, <String, Object?>{
        'cmd': 'SET_ACTIVITY',
        'nonce': '${++_nonce}',
        'args': <String, Object?>{
          'pid': pid,
          'activity': activity == null ? null : _activity(activity),
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
    _applicationId = null;
    await _drop();
  }

  /// Lets go of the socket and keeps the identity, which is the
  /// difference between "Discord went away" and "stop".
  Future<void> _drop() async {
    final transport = _transport;
    _transport = null;
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

  Map<String, Object?> _activity(DiscordActivity activity) {
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
        'large_image': kDiscordCoverAsset,
        if (_line(activity.album) != null) 'large_text': _line(activity.album),
      },
      'instance': false,
    };
  }

  Future<void> _send(int opcode, Map<String, Object?> payload) async {
    final transport = _transport;
    if (transport == null) return;
    final body = utf8.encode(jsonEncode(payload));
    final frame = Uint8List(8 + body.length);
    final header = ByteData.view(frame.buffer);
    header.setUint32(0, opcode, Endian.little);
    header.setUint32(4, body.length, Endian.little);
    frame.setRange(8, frame.length, body);
    await transport.write(frame);
  }

  Future<_Transport?> _open(String path) async {
    try {
      if (Platform.isWindows) {
        // A named pipe opened as a file. Write-only on purpose: Dart can
        // open the pipe for writing on every Windows build, and reading
        // one back needs overlapped IO it does not expose - which costs
        // nothing here, because the only reply worth having is the
        // handshake's and a bad handshake shows up as the next write
        // failing anyway.
        final pipe = await File(path).open(mode: FileMode.writeOnlyAppend);
        return _PipeTransport(pipe);
      }
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      // Drained rather than parsed: Discord answers every frame, and a
      // socket nobody reads fills its buffer and stops accepting writes.
      socket.listen(
        (_) {},
        onError: (Object _) {},
        onDone: () {},
        cancelOnError: false,
      );
      return _SocketTransport(socket);
    } on Object {
      // No socket at this path is the ordinary case: nine of the ten
      // slots are empty on a machine running one Discord.
      return null;
    }
  }

  /// Every path a Discord client might be listening on, in the order
  /// worth trying.
  ///
  /// The sandboxed installs are why this is a list of directories rather
  /// than one: a Flatpak or Snap Discord puts its socket inside its own
  /// runtime directory, and a WaxDeck outside the sandbox has to look
  /// there to find it.
  Iterable<String> _candidatePaths() sync* {
    if (Platform.isWindows) {
      for (var slot = 0; slot < _socketSlots; slot++) {
        yield r'\\.\pipe\discord-ipc-'
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
}

/// One end of the IPC connection, whichever shape the platform gives it.
abstract class _Transport {
  Future<void> write(Uint8List bytes);

  Future<void> close();
}

class _SocketTransport implements _Transport {
  _SocketTransport(this._socket);

  final Socket _socket;

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

class _PipeTransport implements _Transport {
  _PipeTransport(this._pipe);

  final RandomAccessFile _pipe;

  @override
  Future<void> write(Uint8List bytes) async {
    // No flush: on a pipe that is FlushFileBuffers, which blocks until
    // the far end reads, so a wedged Discord would hang every publish.
    await _pipe.writeFrom(bytes);
  }

  @override
  Future<void> close() async {
    try {
      await _pipe.close();
    } on Object {
      // See above.
    }
  }
}
