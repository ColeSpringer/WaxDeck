import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
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
