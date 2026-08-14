import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'cast_preflight.dart';
import 'connect_providers.dart';
import 'remote_session.dart';

/// Where playback can go, and how to stop sending it somewhere else.
///
/// One sheet for the whole of 5.5: this device, every endpoint the caller
/// can play to grouped by what it is, the sessions already playing
/// elsewhere, and - while this client is driving one of those - the
/// three-way choice for stepping away from it. The connection check hangs
/// off the overflow, because a diagnostic belongs near the thing it
/// diagnoses and nowhere near the front of it.
///
/// [currentPid] is what would start playing on a freshly picked endpoint,
/// and is null when there is nothing local to send: the deck bar's remote
/// face opens this sheet to *leave* a session, not to start one, and an
/// empty queue has nothing to hand over either. Endpoints still list in
/// that case - picking one with nothing to play is a transfer when a
/// remote session is in hand, and refused with a reason when it is not.
Future<void> showDevicePicker(
  BuildContext context, {
  required CastSource from,
  String? currentPid,
  int positionMs = 0,
}) {
  final handles = _HostHandles(
    router: GoRouter.of(context),
    rootContext: Navigator.of(context, rootNavigator: true).context,
    messenger: ScaffoldMessenger.of(context),
  );
  return showModalBottomSheet<void>(
    context: context,
    // The list sizes the sheet. Left to the default the sheet stops at
    // nine sixteenths of the window with no sign it has more to show, and
    // "Playing elsewhere" - the section the picker exists for - falls
    // below the fold on a short window.
    isScrollControlled: true,
    builder: (sheetContext) => _DevicePickerSheet(
      handles: handles,
      source: from,
      currentPid: currentPid,
      positionMs: positionMs,
    ),
  );
}

/// Which playback the picker was opened over.
///
/// Both can be live at once: opening someone else's session leaves the bar
/// on the album playing here. So a picker that inferred its subject sent
/// the wrong one, and the face that opened it says instead.
enum CastSource {
  /// This device. A mirror session moves if there is one; otherwise
  /// [currentPid] starts fresh on the endpoint that is picked.
  here,

  /// The session this client drives elsewhere, off the endpoint it is on.
  elsewhere,
}

/// The handles the sheet reaches the app through, captured where it opened.
///
/// Never the host's own context: a sheet outlives the deck bar that opened
/// it, which is replaced by clearing the queue, by a routed command, or by
/// a station taking the engine. The bar's action sheet captures for the
/// same reason.
@immutable
class _HostHandles {
  const _HostHandles({
    required this.router,
    required this.rootContext,
    required this.messenger,
  });

  final GoRouter router;
  final BuildContext rootContext;
  final ScaffoldMessengerState messenger;
}

class _DevicePickerSheet extends ConsumerWidget {
  const _DevicePickerSheet({
    required this.handles,
    required this.source,
    required this.currentPid,
    required this.positionMs,
  });

  final _HostHandles handles;
  final CastSource source;
  final String? currentPid;
  final int positionMs;

  /// Whether the picker is over playback on this device.
  bool get _here => source == CastSource.here;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every watch belongs to this build, never to a nested builder: a ref
    // used from a descendant's build runs after this element has closed
    // the dependencies it did not see re-read, so the subscriptions would
    // be torn down and re-listened every time the sheet rebuilt.
    final endpoints = ref.watch(playerEndpointsProvider);
    final sessions = ref.watch(playbackSessionsProvider);
    final remote = ref.watch(remoteSessionProvider);
    final l10n = context.l10n;
    // This device's own endpoint id arrives with registration, which may
    // land after the sheet opens: listened to rather than read once, or
    // the picker offers to play here, on the device already playing.
    return SafeArea(
      child: ValueListenableBuilder<String?>(
        valueListenable: ref.watch(connectControllerProvider).endpointId,
        builder: (context, ownEndpoint, _) => Semantics(
          identifier: SemanticsIds.picker,
          container: true,
          explicitChildNodes: true,
          label: l10n.devicesPlayOn,
          child: _rows(context, ref, ownEndpoint, endpoints, sessions, remote),
        ),
      ),
    );
  }

  Widget _rows(
    BuildContext context,
    WidgetRef ref,
    String? ownEndpoint,
    AsyncValue<List<PlayerEndpoint>> endpoints,
    AsyncValue<List<PlaybackSessionInfo>> sessions,
    RemoteSession? remote,
  ) {
    final l10n = context.l10n;
    // Whatever was listed last stays listed while a refetch runs: both
    // lists are invalidated whenever any session anywhere starts, ends,
    // or changes its queue, and a sheet that empties for the length of
    // every one of those is one whose rows move under a finger already on
    // the way to them. (Riverpod keeps the value across a refresh, so
    // this is about the error case: stale devices beat none.)
    final devices = endpoints.value;
    final playing = sessions.value ?? const <PlaybackSessionInfo>[];
    // Sessions this client is already driving, and its own mirror, are not
    // somewhere else to go: listing them would offer a trip to where the
    // visitor already is.
    final elsewhere = playing
        .where((s) => s.endpointId != ownEndpoint && s.id != remote?.id)
        .toList(growable: false);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: WaxSpace.s8),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WaxSpace.s16,
            WaxSpace.s8,
            WaxSpace.s8,
            0,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SectionHeader(
                  title: l10n.devicesPlayOn,
                  // Only when the sheet is over the session elsewhere;
                  // opened over the album playing here it would describe
                  // something other than what the sheet is about.
                  overline: _here ? null : l10n.devicesCurrentlyElsewhere,
                ),
              ),
              // The diagnostic, one level in. A cast that fails is silent,
              // and this is the surface that says why; it is not the first
              // thing anyone opening a picker wants.
              WaxMenuButton<String>(
                glyph: WaxIcons.more,
                label: l10n.devicesMore,
                semanticsId: SemanticsIds.pickerOverflow,
                items: <WaxMenuItem<String>>[
                  WaxMenuItem<String>(
                    value: 'check',
                    label: l10n.devicesConnectionCheck,
                    semanticsId: SemanticsIds.pickerCheck,
                  ),
                ],
                onSelected: (_) => _openPreflight(context),
              ),
            ],
          ),
        ),
        _ThisDevice(
          remote: remote,
          here: _here,
          onSelect: () => unawaited(_leaveRemote(context, ref, remote!)),
        ),
        ...switch (devices) {
          null when endpoints.hasError => <Widget>[
            WaxOptionRow(
              title: l10n.devicesListError,
              subtitle: l10n.devicesListErrorMessage,
              glyph: WaxIcons.warning,
              enabled: false,
            ),
          ],
          null => <Widget>[
            WaxOptionRow(
              title: l10n.devicesLooking,
              glyph: WaxIcons.refresh,
              enabled: false,
            ),
          ],
          final value => _deviceRows(context, ref, value, ownEndpoint, remote),
        },
        if (elsewhere.isNotEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(WaxSpace.s16, WaxSpace.s8, 0, 0),
            child: SectionHeader(title: l10n.devicesPlayingElsewhere),
          ),
          for (final session in elsewhere)
            WaxOptionRow(
              title: session.currentEntry?.title ?? l10n.devicesPlaying,
              subtitle: l10n.devicesOnEndpoint(
                session.endpointName ?? session.endpointId,
              ),
              glyph: WaxIcons.play,
              active: session.playing,
              semanticsId: SemanticsIds.session(session.id),
              onTap: () => _control(context, ref, session),
            ),
        ],
      ],
    );
  }

  /// The endpoints, grouped by what they are.
  ///
  /// Grouped rather than listed flat because the kinds behave differently
  /// and a listener knows it: another WaxDeck client can play anything and
  /// is somebody's phone, a cast device or a renderer is a speaker in a
  /// room, and the jukebox is the server's own output. Unknown kinds fall
  /// into "Other devices", per the contract's own instruction to render
  /// them generically rather than guess.
  List<Widget> _deviceRows(
    BuildContext context,
    WidgetRef ref,
    List<PlayerEndpoint> endpoints,
    String? ownEndpoint,
    RemoteSession? remote,
  ) {
    final l10n = context.l10n;
    // Where the thing being sent already is. Null when it is here, which
    // [_ThisDevice] is the row for.
    final fromEndpoint = _here ? null : remote?.session.endpointId;
    final rows = <Widget>[];
    for (final group in _EndpointGroup.values) {
      final members = endpoints
          .where((e) => e.id != ownEndpoint && group.claims(e.kind))
          .toList(growable: false);
      if (members.isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(WaxSpace.s16, WaxSpace.s8, 0, 0),
          child: SectionHeader(title: group.labelOf(l10n)),
        ),
      );
      for (final endpoint in members) {
        rows.add(
          WaxOptionRow(
            title: endpoint.name,
            subtitle: _endpointLine(endpoint),
            glyph: group.glyph,
            enabled: endpoint.online,
            // Active says sound is coming out here; selected says it is
            // where the thing being sent already is. Different rows.
            active: remote?.session.endpointId == endpoint.id,
            selected: endpoint.id == fromEndpoint,
            semanticsId: SemanticsIds.endpoint(endpoint.id),
            // The server answers a transfer to the current endpoint with a
            // 200 no-op, so a live row there is one that does nothing.
            onTap: endpoint.id == fromEndpoint
                ? null
                : () => unawaited(_playOn(context, ref, endpoint)),
          ),
        );
      }
    }
    return rows;
  }

  /// What an endpoint's row says under its name: why it cannot be used, or
  /// what it can be told once it is.
  ///
  /// The capability hints are here rather than as glyphs because they
  /// answer a question asked before picking ("will I be able to turn this
  /// down from my phone?") and because two more icons on a row is two more
  /// things to learn.
  static String? _endpointLine(PlayerEndpoint endpoint) {
    if (!endpoint.online) return 'Offline';
    final can = <String>[
      if (endpoint.volumeControl) 'volume',
      if (endpoint.rateControl) 'speed',
    ];
    if (endpoint.activeSessionId != null) {
      return can.isEmpty ? 'In use' : 'In use, ${can.join(' and ')} control';
    }
    return can.isEmpty ? null : 'Remote ${can.join(' and ')} control';
  }

  /// Sends playback to [endpoint].
  ///
  /// Three cases, and they are genuinely different: a session already in
  /// hand transfers (queue and position intact), local playback with a
  /// mirror session transfers too, and anything else starts fresh from the
  /// item the caller named.
  Future<void> _playOn(
    BuildContext context,
    WidgetRef ref,
    PlayerEndpoint endpoint,
  ) async {
    final repository = ref.read(repositoryProvider);
    final messenger = handles.messenger;
    final remoteController = ref.read(remoteSessionProvider.notifier);
    final l10n = context.l10n;
    final pid = currentPid;
    // The face decides, never which sessions exist: both can be live.
    final sessionId = _here
        ? ref.read(connectControllerProvider).mirrorSessionId
        : ref.read(remoteSessionProvider)?.id;
    Navigator.of(context).pop();
    try {
      final PlaybackSessionInfo started;
      if (sessionId != null) {
        started = await repository.transferPlaybackSession(
          sessionId,
          endpoint.id,
        );
      } else {
        if (pid == null) {
          // Said plainly rather than minted as an API failure: nothing
          // was refused, because nothing was ever sent.
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(l10n.devicesNothingToSend)));
          return;
        }
        started = await repository.createPlaybackSession(
          endpointId: endpoint.id,
          itemPids: <String>[pid],
          positionMs: positionMs,
        );
      }
      // The bar follows the sound: a session on another endpoint is what
      // it now shows, and the transport on it is routed there.
      remoteController.adopt(started);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.devicesPlayingOn(endpoint.name))),
      );
    } on WaxDeckApiException catch (e) {
      _explain(l10n, messenger, e, endpoint: endpoint);
    }
  }

  /// Opens the remote control for a session playing elsewhere, and makes
  /// the shell aware of it: the screen is a viewer, and the deck bar's
  /// remote face is the other one.
  void _control(
    BuildContext context,
    WidgetRef ref,
    PlaybackSessionInfo session,
  ) {
    Navigator.of(context).pop();
    ref.read(remoteSessionProvider.notifier).adopt(session);
    handles.router.push<void>(WaxRoute.remote);
  }

  /// The disconnect triad: what "This device" means while a session is
  /// being driven elsewhere.
  ///
  /// Three real outcomes, spelled out rather than guessed at, because the
  /// wrong guess is unrecoverable in both directions - silencing a room
  /// somebody is listening to, or walking away from a queue and finding it
  /// still going an hour later.
  Future<void> _leaveRemote(
    BuildContext context,
    WidgetRef ref,
    RemoteSession remote,
  ) async {
    final messenger = handles.messenger;
    final controller = ref.read(remoteSessionProvider.notifier);
    final l10n = context.l10n;
    final name = remote.endpointName;
    Navigator.of(context).pop();
    final choice = await showDialog<_LeaveChoice>(
      context: handles.rootContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.devicesPlayingOn(name)),
        content: Text(l10n.devicesTakeOverBody),
        actions: <Widget>[
          TextButton(
            key: const Key(SemanticsIds.remoteLeave),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LeaveChoice.leave),
            child: Text(l10n.devicesLeaveItPlaying),
          ),
          TextButton(
            key: const Key(SemanticsIds.remoteStopThere),
            onPressed: () => Navigator.of(dialogContext).pop(_LeaveChoice.stop),
            child: Text(l10n.devicesStopOn(name)),
          ),
          FilledButton(
            key: const Key(SemanticsIds.remotePlayHere),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LeaveChoice.transfer),
            child: Text(l10n.devicesTransferHere),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      switch (choice) {
        case _LeaveChoice.leave:
          controller.release();
        case _LeaveChoice.stop:
          await controller.stopThere();
        case _LeaveChoice.transfer:
          await controller.transferHere();
      }
    } on WaxDeckApiException catch (e) {
      _explain(l10n, messenger, e);
    }
  }

  void _openPreflight(BuildContext context) {
    Navigator.of(context).pop();
    unawaited(showCastPreflight(handles.rootContext));
  }

  /// Says why a command was refused, in words that name a way out.
  ///
  /// [explainError] words every code, and this adds the one refinement
  /// only the picker can make: a multi-part audiobook cannot play on a
  /// cast device or a renderer, and naming the device it was sent to
  /// turns a dead end into an offer.
  ///
  /// The refusal is keyed on the params the server now carries. The
  /// phrase match beside it is the fallback for a server older than
  /// those params; both die together when part-aware playback lands.
  static void _explain(
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
    WaxDeckApiException error, {
    PlayerEndpoint? endpoint,
  }) {
    final multiPart =
        error.code == 'feature-unavailable' &&
        (error.params?['feature'] == 'multi-part-audiobook' ||
            error.message.contains('multi-part audiobook'));
    // Named where there is a device to name, and general on the
    // leave-and-transfer path, which has none. Without the second arm a
    // pre-params server's refusal - recognised only by the phrase - would
    // fall through to the umbrella sentence and lose the way out.
    final message = switch ((multiPart, endpoint)) {
      (true, final target?) => l10n.devicesMultiPartAudiobook(target.name),
      (true, null) => l10n.errorMultiPartAudiobook,
      _ => explainError(l10n, error),
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The choices for stepping away from a remote session.
enum _LeaveChoice { leave, stop, transfer }

/// This device's own row: where playback is when nothing is elsewhere, and
/// the way back when something is.
class _ThisDevice extends StatelessWidget {
  const _ThisDevice({
    required this.remote,
    required this.here,
    required this.onSelect,
  });

  final RemoteSession? remote;

  /// Whether the sheet is over playback on this device, which is what
  /// makes this row the one it is already on.
  final bool here;

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    // Two questions that come apart: whether there is a session to step
    // away from, and whether this row is the one being sent from.
    final l10n = context.l10n;
    final elsewhere = remote != null;
    return WaxOptionRow(
      title: l10n.devicesThisDevice,
      subtitle: elsewhere
          ? l10n.devicesTakeOverOrLeave
          : l10n.devicesPlayingHere,
      glyph: WaxIcons.home,
      active: here,
      selected: here,
      semanticsId: SemanticsIds.pickerThisDevice,
      // No tap with nothing elsewhere to step away from: a row that
      // reports where you are is not a control.
      onTap: elsewhere ? onSelect : null,
      trailing: here
          ? const WaxIcon(WaxIcons.check, size: 18, active: true)
          : null,
    );
  }
}

/// How the picker groups endpoints, and what each group is drawn as.
enum _EndpointGroup {
  clients(WaxIcons.devices, <String>{'client'}),
  speakers(WaxIcons.cast, <String>{'cast', 'dlna'}),
  server(WaxIcons.volume, <String>{'jukebox'}),
  other(WaxIcons.devices, <String>{});

  const _EndpointGroup(this.glyph, this.kinds);

  final WaxGlyph glyph;
  final Set<String> kinds;

  String labelOf(AppLocalizations l10n) => switch (this) {
    clients => l10n.devicesGroupApps,
    speakers => l10n.devicesGroupSpeakers,
    server => l10n.devicesGroupServer,
    other => l10n.devicesGroupOther,
  };

  /// Whether [kind] belongs in this group. `kind` is an open string by
  /// contract, so the last group takes whatever the others do not
  /// recognise rather than dropping an endpoint nobody can then reach.
  bool claims(String kind) {
    if (kinds.isNotEmpty) return kinds.contains(kind);
    return !_EndpointGroup.values
        .where((g) => g.kinds.isNotEmpty)
        .any((g) => g.kinds.contains(kind));
  }
}
