import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../shell/semantics_ids.dart';

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
    return SafeArea(
      child: Semantics(
        identifier: SemanticsIds.preflight,
        container: true,
        explicitChildNodes: true,
        label: 'Connection check',
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
              const Padding(
                padding: EdgeInsets.fromLTRB(WaxSpace.s16, WaxSpace.s8, 0, 0),
                child: SectionHeader(
                  overline: 'Casting',
                  title: 'Connection check',
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
                  'A cast device fetches audio from this server by address. '
                  'These are the addresses it will try, in order.',
                  style: WaxType.caption.copyWith(
                    color: WaxColors.of(context).textSecondary,
                  ),
                ),
              ),
              ...switch (bases) {
                AsyncData(:final value) when value.isEmpty => const <Widget>[
                  EmptyState(
                    title: 'No addresses to try',
                    message:
                        'This server has not been told a public address and '
                        'could not detect one on the network. Casting needs '
                        'one; set it in the server settings.',
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
                      'The server checked these itself. An address it '
                      'cannot reach will not work from a speaker either; '
                      'one it can may still fail if the speaker is on '
                      'another network.',
                      style: WaxType.caption.copyWith(
                        color: WaxColors.of(context).textTertiary,
                      ),
                    ),
                  ),
                ],
                AsyncError(:final error) => <Widget>[
                  ErrorState(
                    title: 'Could not check',
                    message: error is WaxDeckApiException
                        ? error.message
                        : 'The server did not answer.',
                    onRetry: () => ref.invalidate(castPreflightProvider),
                    retrySemanticsId: SemanticsIds.preflightRetry,
                  ),
                ],
                _ => const <Widget>[SkeletonShapes(shape: SkeletonShape.list)],
              },
            ],
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WaxOptionRow(
          title: base.base,
          subtitle: switch (base.source) {
            'configured' =>
              base.reachable
                  ? 'Configured address, reachable'
                  : 'Configured address, not reachable',
            'detected' =>
              base.reachable
                  ? 'Detected on this network, reachable'
                  : 'Detected on this network, not reachable',
            // `source` is an open string: an unrecognised one is still
            // worth naming, because it is what a server operator set.
            final other =>
              base.reachable ? '$other, reachable' : '$other, not reachable',
          },
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
