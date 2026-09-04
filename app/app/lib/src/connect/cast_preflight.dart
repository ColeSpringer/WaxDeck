import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'connect_providers.dart';

/// The bases a cast session will offer a device, with the server's verdict
/// on each.
final castPreflightProvider =
    FutureProvider.autoDispose<List<CastPreflightBase>>(
      (ref) => ref.watch(repositoryProvider).getCastPreflight(),
    );

/// Opens the connection check.
///
/// A sheet rather than a location: the answer is a snapshot of a network
/// at a moment, so there is nothing here a stranger could open a link to,
/// and it is read on the way to fixing a cast rather than visited.
Future<void> showCastPreflight(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CastPreflightSheet(),
  );
}

/// What a cast device would have to reach, and whether the server can.
///
/// The endpoint has answered plain-language diagnostics since it shipped
/// and nothing rendered them, so the only way to read them was to curl the
/// API - which is what the deferred entry this closes said. The notes are
/// the server's own words and are printed as they arrive: they name
/// certificates, schemes, and DNS, and rewording them here would be a
/// second vocabulary for one set of facts.
class _CastPreflightSheet extends ConsumerWidget {
  const _CastPreflightSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bases = ref.watch(castPreflightProvider);
    final l10n = context.l10n;
    return SafeArea(
      child: Semantics(
        identifier: SemanticsIds.preflight,
        container: true,
        explicitChildNodes: true,
        label: l10n.devicesConnectionCheck,
        child: ConstrainedBox(
          // Bounded, because the notes are prose of unknown length and a
          // sheet is not a page: three unreachable bases with four notes
          // each would otherwise cover the window.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: WaxSpace.s16),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WaxSpace.s16,
                  WaxSpace.s8,
                  0,
                  0,
                ),
                child: SectionHeader(
                  overline: l10n.devicesCastingOverline,
                  title: l10n.devicesConnectionCheck,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WaxSpace.s16,
                  0,
                  WaxSpace.s16,
                  WaxSpace.s8,
                ),
                child: Text(
                  l10n.devicesCastBlurb,
                  style: WaxType.caption.copyWith(
                    color: WaxColors.of(context).textSecondary,
                  ),
                ),
              ),
              ...switch (bases) {
                AsyncData(:final value) when value.isEmpty => <Widget>[
                  EmptyState(
                    title: l10n.devicesNoAddresses,
                    message: l10n.devicesNoAddressesMessage,
                    glyph: WaxIcons.warning,
                  ),
                ],
                AsyncData(:final value) => <Widget>[
                  for (var i = 0; i < value.length; i++)
                    _Base(base: value[i], index: i),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WaxSpace.s16,
                      WaxSpace.s8,
                      WaxSpace.s16,
                      0,
                    ),
                    child: Text(
                      // The endpoint's own caveat, said once here rather
                      // than repeated per row: the server checking itself
                      // is not the device checking, and a reader deciding
                      // what to fix needs to know which of the two this
                      // is.
                      l10n.devicesCastCaveat,
                      style: WaxType.caption.copyWith(
                        color: WaxColors.of(context).textTertiary,
                      ),
                    ),
                  ),
                ],
                AsyncError(:final error) => <Widget>[
                  ErrorState(
                    title: l10n.devicesCheckError,
                    message: context.explain(error),
                    onRetry: () => ref.invalidate(castPreflightProvider),
                    retrySemanticsId: SemanticsIds.preflightRetry,
                  ),
                ],
                _ => const <Widget>[SkeletonShapes(shape: SkeletonShape.list)],
              },
              const _DeviceTests(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The other half of the check: a device fetching this server, rather
/// than the server fetching itself.
///
/// This is the half that catches what the server cannot see, because
/// what fails is the device's - a name it resolves differently, an
/// authority it does not trust, a route it does not have. It runs on a
/// tap rather than with the sheet: it takes a speaker over for a
/// second, and nothing should do that because somebody opened a
/// diagnostic.
class _DeviceTests extends ConsumerStatefulWidget {
  const _DeviceTests();

  @override
  ConsumerState<_DeviceTests> createState() => _DeviceTestsState();
}

class _DeviceTestsState extends ConsumerState<_DeviceTests> {
  /// The endpoint being tested, and the last answer with the endpoint
  /// it belongs to - a probe or a refusal. One at a time, because a new
  /// test replaces the last one's answer, and named by endpoint so a
  /// refusal hangs under the device that refused rather than under
  /// every row.
  String? _running;
  ({String endpointId, CastDeviceProbe? probe, Object? error})? _answer;

  Future<void> _test(PlayerEndpoint endpoint) async {
    setState(() {
      _running = endpoint.id;
      _answer = null;
    });
    final repo = ref.read(repositoryProvider);
    try {
      final probe = await repo.probeCastEndpoint(endpoint.id);
      if (!mounted) return;
      setState(() {
        _running = null;
        _answer = (endpointId: endpoint.id, probe: probe, error: null);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _running = null;
        _answer = (endpointId: endpoint.id, probe: null, error: error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final endpoints = ref.watch(playerEndpointsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(WaxSpace.s16, WaxSpace.s16, 0, 0),
          child: SectionHeader(title: l10n.devicesTestOnDevice),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WaxSpace.s16,
            0,
            WaxSpace.s16,
            WaxSpace.s8,
          ),
          child: Text(
            l10n.devicesTestOnDeviceBlurb,
            style: WaxType.caption.copyWith(
              color: WaxColors.of(context).textSecondary,
            ),
          ),
        ),
        // The list is fetched, and "nothing found on this network" is a
        // diagnosis: drawing it while the answer is still coming tells
        // a listener to go and look at their Docker networking over a
        // round trip that had not landed.
        ...switch (endpoints) {
          AsyncData(:final value) => _devices(context, value),
          AsyncError(:final error) => <Widget>[
            _Detail(text: context.explain(error), tone: _DetailTone.warning),
          ],
          _ => const <Widget>[SkeletonShapes(shape: SkeletonShape.list)],
        },
      ],
    );
  }

  /// The endpoints worth testing, or why there are none.
  ///
  /// Only the ones that fetch media for themselves: another WaxDeck
  /// client holds a session with the server it signed in to, and the
  /// jukebox is the server, so neither can fail the way this exists to
  /// catch.
  List<Widget> _devices(BuildContext context, List<PlayerEndpoint> endpoints) {
    final l10n = context.l10n;
    final devices = endpoints
        .where((e) => e.online && (e.kind == 'cast' || e.kind == 'dlna'))
        .toList(growable: false);
    if (devices.isEmpty) {
      return <Widget>[
        EmptyState(
          title: l10n.devicesNoDevicesToTest,
          message: l10n.devicesNoDevicesToTestMessage,
          glyph: WaxIcons.cast,
          semanticsId: SemanticsIds.preflightDevices,
        ),
      ];
    }
    return <Widget>[
      for (final device in devices) ..._deviceRows(context, device),
    ];
  }

  List<Widget> _deviceRows(BuildContext context, PlayerEndpoint device) {
    final l10n = context.l10n;
    final answer = _answer?.endpointId == device.id ? _answer : null;
    return <Widget>[
      WaxOptionRow(
        title: device.name,
        subtitle: _running == device.id ? l10n.devicesTesting : null,
        glyph: WaxIcons.cast,
        // Off while any test runs: they drive one device each, and the
        // answer on screen belongs to one of them.
        enabled: _running == null,
        onTap: () => unawaited(_test(device)),
        semanticsId: SemanticsIds.preflightDevice(device.id),
      ),
      if (answer?.probe case final probe?)
        for (var i = 0; i < probe.bases.length; i++)
          _DeviceBase(base: probe.bases[i], index: i),
      if (answer?.error case final error?)
        // The refusal's own sentence, not the table's: `endpoint-busy`
        // exists to name what is playing, and "something else" is not
        // a thing anybody can go and stop.
        _Detail(
          text: explainRefusal(context.l10n, error),
          tone: _DetailTone.warning,
        ),
    ];
  }
}

/// One base as the device found it.
///
/// The address again rather than a reference to the row above: for a
/// renderer this list can hold an address the server-side check has no
/// row for at all (this server's own loopback, which nothing on another
/// host can fetch), and a reader comparing two verdicts should not have
/// to hold one of them in their head.
class _DeviceBase extends StatelessWidget {
  const _DeviceBase({required this.base, required this.index});

  final CastPreflightBase base;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final device = base.device;
    if (device == null) return const SizedBox.shrink();
    final played = device.verdict == 'played';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WaxOptionRow(
          title: base.base,
          subtitle: switch (device.verdict) {
            'played' => l10n.devicesProbePlayed(device.latencyMs),
            'failed' => l10n.devicesProbeFailed,
            'timeout' => l10n.devicesProbeTimeout,
            // `verdict` is an open string: an unrecognised one is still
            // the server's answer and worth showing as it was written.
            final other => other,
          },
          glyph: played ? WaxIcons.check : WaxIcons.warning,
          // Highlighted for having played, which is not playback here:
          // the row's default announcement prefixes "Playing".
          active: played,
          activeLabel: null,
          semanticsId: SemanticsIds.preflightDeviceBase(index),
        ),
        // The device's own words, printed as they arrive like the
        // server's notes above: they name idle reasons and UPnP faults,
        // and rewording them here would be a second vocabulary for one
        // set of facts.
        if (device.detail case final detail? when detail.isNotEmpty)
          _Detail(text: detail, tone: _DetailTone.plain),
      ],
    );
  }
}

enum _DetailTone { plain, warning }

/// A line hanging under the row above it, indented to that row's text.
class _Detail extends StatelessWidget {
  const _Detail({required this.text, required this.tone});

  final String text;
  final _DetailTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WaxSpace.s16 + 22 + WaxSpace.s12,
        0,
        WaxSpace.s16,
        WaxSpace.s8,
      ),
      child: Text(
        text,
        style: WaxType.caption.copyWith(
          color: switch (tone) {
            _DetailTone.plain => colors.textSecondary,
            _DetailTone.warning => colors.error,
          },
        ),
      ),
    );
  }
}

/// One candidate address and what the server found.
class _Base extends StatelessWidget {
  const _Base({required this.base, required this.index});

  final CastPreflightBase base;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WaxOptionRow(
          title: base.base,
          subtitle: l10n.devicesBaseLine(
            switch (base.source) {
              'configured' => l10n.devicesBaseConfigured,
              'detected' => l10n.devicesBaseDetected,
              // `source` is an open string: an unrecognised one is still
              // worth naming, because it is what a server operator set.
              final other => other,
            },
            base.reachable
                ? l10n.devicesBaseReachable
                : l10n.devicesBaseUnreachable,
          ),
          glyph: base.reachable ? WaxIcons.check : WaxIcons.warning,
          // Highlighted for being reachable, which is not playback: the
          // row's default announcement prefixes "Playing".
          active: base.reachable,
          activeLabel: null,
          semanticsId: SemanticsIds.preflightBase(index),
        ),
        for (final note in base.notes)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              // Indented to the row's text column, so a note reads as
              // belonging to the address above it rather than as another
              // row.
              WaxSpace.s16 + 22 + WaxSpace.s12,
              0,
              WaxSpace.s16,
              WaxSpace.s4,
            ),
            child: Text(
              note,
              style: WaxType.caption.copyWith(color: colors.textSecondary),
            ),
          ),
        const SizedBox(height: WaxSpace.s8),
      ],
    );
  }
}
