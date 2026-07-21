import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'connect_bus.dart';
import 'connect_providers.dart';

/// Remote control for one session playing on another endpoint: live
/// state over watch frames, position extrapolated between them against
/// the server clock offset, verbs over the command bus, and the "Play
/// here" handoff that pulls the session onto this device.
class RemoteControlScreen extends ConsumerStatefulWidget {
  const RemoteControlScreen({super.key, required this.initial});

  final PlaybackSessionInfo initial;

  @override
  ConsumerState<RemoteControlScreen> createState() =>
      _RemoteControlScreenState();
}

class _RemoteControlScreenState extends ConsumerState<RemoteControlScreen> {
  // Captured in initState: ref is not usable inside dispose.
  late final ConnectBus _bus;
  late PlaybackSessionInfo _session;
  List<PlaybackSessionEntry> _entries = const [];
  StreamSubscription<PlaybackSessionInfo>? _frames;
  Timer? _ticker;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _session = widget.initial;
    _entries = widget.initial.entries;
    _bus = ref.read(connectBusProvider);
    _frames = _bus.watchFrames.listen(_onFrame);
    _bus.watch(_session.id);
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_session.playing && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _frames?.cancel();
    // Stop watching; harmless when the socket already dropped.
    _bus.watch(null);
    super.dispose();
  }

  void _onFrame(PlaybackSessionInfo session) {
    if (session.id != _session.id || !mounted) return;
    setState(() {
      _session = session;
      if (session.entries.isNotEmpty) _entries = session.entries;
      _ended = session.ended;
    });
  }

  /// The position implied right now: the last snapshot plus elapsed
  /// wall time scaled by rate, against the server clock offset.
  int get _positionMs {
    if (!_session.playing) return _session.positionMs;
    final offset = ref.read(connectBusProvider).serverClockOffset;
    final serverNow = DateTime.now().toUtc().add(offset);
    final elapsed = serverNow.difference(_session.positionAt).inMilliseconds;
    if (elapsed <= 0) return _session.positionMs;
    var pos = _session.positionMs + (elapsed * _session.rate).round();
    final duration = _currentDurationMs;
    if (duration > 0 && pos > duration) pos = duration;
    return pos;
  }

  PlaybackSessionEntry? get _currentEntry =>
      _session.index >= 0 && _session.index < _entries.length
      ? _entries[_session.index]
      : null;

  int get _currentDurationMs => _currentEntry?.durationMs ?? 0;

  Future<void> _cmd(String verb, {int? positionMs, double? volume}) async {
    try {
      await ref
          .read(connectBusProvider)
          .sendCmd(_session.id, verb, positionMs: positionMs, volume: volume);
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _playHere() async {
    final ownEndpoint = ref.read(connectControllerProvider).endpointId.value;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (ownEndpoint == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This device is not registered yet')),
      );
      return;
    }
    try {
      await ref
          .read(repositoryProvider)
          .transferPlaybackSession(_session.id, ownEndpoint);
      navigator.pop();
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _currentEntry;
    final durationMs = _currentDurationMs;
    final positionMs = _positionMs;
    return Scaffold(
      appBar: AppBar(title: Text(_session.endpointName ?? 'Remote playback')),
      body: _ended
          ? const Center(child: Text('This session has ended'))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    entry?.title ?? 'Playing',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (entry?.artist != null)
                    Text(
                      entry!.artist!,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  if (_session.ownerName != null)
                    Text(
                      'Started by ${_session.ownerName}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 24),
                  Semantics(
                    identifier: 'remote-seek',
                    label: 'Seek',
                    slider: true,
                    child: Slider(
                      value: durationMs > 0
                          ? (positionMs / durationMs).clamp(0.0, 1.0)
                          : 0,
                      onChanged: durationMs > 0
                          ? (v) => _cmd(
                              'seek',
                              positionMs: (v * durationMs).round(),
                            )
                          : null,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Semantics(
                        identifier: 'remote-previous',
                        label: 'Previous',
                        button: true,
                        excludeSemantics: true,
                        onTap: () => _cmd('previous'),
                        child: IconButton(
                          key: const Key('remote-previous'),
                          icon: const Icon(Icons.skip_previous),
                          onPressed: () => _cmd('previous'),
                        ),
                      ),
                      Semantics(
                        identifier: 'remote-toggle',
                        label: _session.playing ? 'Pause' : 'Play',
                        button: true,
                        excludeSemantics: true,
                        onTap: () => _cmd(_session.playing ? 'pause' : 'play'),
                        child: IconButton(
                          key: const Key('remote-toggle'),
                          iconSize: 48,
                          icon: Icon(
                            _session.playing
                                ? Icons.pause_circle
                                : Icons.play_circle,
                          ),
                          onPressed: () =>
                              _cmd(_session.playing ? 'pause' : 'play'),
                        ),
                      ),
                      Semantics(
                        identifier: 'remote-next',
                        label: 'Next',
                        button: true,
                        excludeSemantics: true,
                        onTap: () => _cmd('next'),
                        child: IconButton(
                          key: const Key('remote-next'),
                          icon: const Icon(Icons.skip_next),
                          onPressed: () => _cmd('next'),
                        ),
                      ),
                    ],
                  ),
                  if (_session.volume != null)
                    Semantics(
                      identifier: 'remote-volume',
                      label: 'Volume',
                      slider: true,
                      child: Slider(
                        value: (_session.volume ?? 1).clamp(0.0, 1.0),
                        onChanged: (v) => _cmd('set-volume', volume: v),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Semantics(
                    identifier: 'remote-play-here',
                    label: 'Play here',
                    button: true,
                    excludeSemantics: true,
                    onTap: _playHere,
                    child: FilledButton.tonal(
                      key: const Key('remote-play-here'),
                      onPressed: _playHere,
                      child: const Text('Play here'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
