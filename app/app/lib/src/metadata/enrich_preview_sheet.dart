import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import 'metadata_form.dart';

/// Shows what a fetch would change and asks before anything lands.
/// Resolves true when the user chose to apply - the previewed diff
/// when there is one, or a blind fetch when the providers proposed
/// nothing (the catalog's built-ins cannot be previewed, so an empty
/// preview does not mean an empty fetch).
Future<bool> showEnrichPreviewSheet(
  BuildContext context, {
  required EnrichPreview preview,
}) async {
  final applied = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EnrichPreviewSheet(preview: preview),
  );
  return applied ?? false;
}

class _EnrichPreviewSheet extends StatelessWidget {
  const _EnrichPreviewSheet({required this.preview});

  final EnrichPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final cover = preview.cover;
    return SafeArea(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.enrichPreview,
        child: Padding(
          padding: const EdgeInsets.all(WaxSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.metadataPreviewTitle,
                style: WaxType.headline.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: WaxSpace.s12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (preview.isEmpty)
                        Text(
                          l10n.metadataPreviewEmpty,
                          style: WaxType.body.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      if (cover != null) _CoverRow(cover: cover),
                      if (preview.fields.isNotEmpty) ...<Widget>[
                        _headerRow(l10n, colors),
                        for (final field in preview.fields)
                          _FieldRow(field: field),
                      ],
                      if (preview.skipped.isNotEmpty) ...<Widget>[
                        const SizedBox(height: WaxSpace.s12),
                        Text(
                          l10n.metadataEnrichSkipped(
                            preview.skipped.join(', '),
                          ),
                          style: WaxType.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: WaxSpace.s12),
                      Text(
                        l10n.metadataPreviewBuiltinsNote,
                        style: WaxType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: WaxSpace.s16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  WaxButton(
                    label: l10n.commonCancel,
                    kind: WaxButtonKind.text,
                    semanticsId: SemanticsIds.enrichPreviewCancel,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: WaxSpace.s8),
                  WaxButton(
                    label: preview.isEmpty
                        ? l10n.metadataPreviewFetchAnyway
                        : l10n.metadataPreviewApply,
                    semanticsId: SemanticsIds.enrichPreviewApply,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow(AppLocalizations l10n, WaxColors colors) {
    final overline = WaxType.overline.copyWith(color: colors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s4),
      child: Row(
        children: <Widget>[
          const SizedBox(width: _FieldRow.labelWidth + WaxSpace.s8),
          Expanded(child: Text(l10n.reviewDiffCurrent, style: overline)),
          const SizedBox(width: WaxSpace.s8),
          Expanded(child: Text(l10n.reviewDiffProposed, style: overline)),
        ],
      ),
    );
  }
}

class _CoverRow extends StatelessWidget {
  const _CoverRow({required this.cover});

  static const _size = 96.0;

  final EnrichCoverProposal cover;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Semantics(
      container: true,
      identifier: SemanticsIds.enrichPreviewCover,
      child: Padding(
        padding: const EdgeInsets.only(bottom: WaxSpace.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(WaxRadius.r10),
              child: Image.memory(
                cover.data,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                // Decoded at the box, not the source: a provider answer
                // can be 3000px square, which is a ~36 MB raster for a
                // 96px thumbnail without this.
                cacheWidth: (_size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                // Bytes a provider answered with, not bytes the catalog
                // vetted: a picture that does not decode draws as the
                // slot label rather than throwing the sheet away.
                errorBuilder: (context, error, stack) => SizedBox(
                  width: _size,
                  height: _size,
                  child: ColoredBox(color: colors.surface2),
                ),
              ),
            ),
            const SizedBox(width: WaxSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.artSlotFront,
                    style: WaxType.label.copyWith(color: colors.textPrimary),
                  ),
                  Text(
                    l10n.metadataPreviewProvider(cover.provider),
                    style: WaxType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  static const labelWidth = 96.0;

  /// Lyrics arrive whole; past this the diff is a scroller, not a row.
  static const _maxLines = 6;

  final EnrichFieldProposal field;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final label = field.name == 'lyrics'
        ? l10n.metadataLyricsLabel
        : metadataFieldLabel(l10n, field.name);
    return Semantics(
      container: true,
      identifier: SemanticsIds.enrichPreviewRow(field.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WaxSpace.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: WaxType.label.copyWith(color: colors.textPrimary),
                  ),
                  Text(
                    l10n.metadataPreviewProvider(field.provider),
                    style: WaxType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            Expanded(
              child: Text(
                field.current,
                maxLines: _maxLines,
                overflow: TextOverflow.ellipsis,
                style: WaxType.body.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            Expanded(
              child: Text(
                field.proposed,
                maxLines: _maxLines,
                overflow: TextOverflow.ellipsis,
                style: WaxType.body.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
