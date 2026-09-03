import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';

/// What a completed origin edit asks for. Null from the sheet means the
/// edit was abandoned; [clear] means the row should come off entirely.
class AcquisitionEditRequest {
  const AcquisitionEditRequest.set({
    required this.sourceType,
    required this.sourceUrl,
    required this.sourceId,
    required this.provider,
    required this.writeBack,
  }) : clear = false;

  const AcquisitionEditRequest.clear({required this.writeBack})
    : sourceType = '',
      sourceUrl = null,
      sourceId = '',
      provider = '',
      clear = true;

  final String sourceType;

  /// The address to store, or null to leave the stored one alone.
  ///
  /// Null rather than "unchanged means resend what was shown": the read
  /// redacts this field, so the box was never holding the whole value.
  /// Saving a sheet nobody typed an address into would otherwise
  /// replace a stored `?v=XYZ` with the truncated form on screen - and
  /// with write-back on, in the file's tags as well. An empty string is
  /// how the address comes off.
  final String? sourceUrl;

  final String sourceId;
  final String provider;
  final bool writeBack;
  final bool clear;
}

/// Corrects where an item came from.
///
/// The origin is recorded evidence first - what the import saw, or the
/// file's own `SOURCE_URL` tag - and this is the one place it becomes a
/// field. It stays a sheet rather than a form line for that reason: the
/// edit has its own replacement rule (every column is written as sent,
/// so a box left empty clears) and its own clear verb, neither of which
/// the scalar form expresses.
Future<AcquisitionEditRequest?> showAcquisitionSheet(
  BuildContext context, {
  required ItemAcquisition? acquisition,
}) => showModalBottomSheet<AcquisitionEditRequest>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _AcquisitionSheet(acquisition: acquisition),
);

/// The source types this client offers. The field is an open set on the
/// wire - an acquisition provider stamps its own - so a stored value
/// outside this list is added as a segment of its own rather than
/// silently rewritten to one of these.
const _knownSourceTypes = <String>['manual', 'rss', 'youtube'];

class _AcquisitionSheet extends StatefulWidget {
  const _AcquisitionSheet({required this.acquisition});

  final ItemAcquisition? acquisition;

  @override
  State<_AcquisitionSheet> createState() => _AcquisitionSheetState();
}

class _AcquisitionSheetState extends State<_AcquisitionSheet> {
  late final TextEditingController _url;
  late final TextEditingController _id;
  late final TextEditingController _provider;
  late final String _seededUrl;
  late String _sourceType;
  bool _writeBack = false;

  @override
  void initState() {
    super.initState();
    final acq = widget.acquisition;
    _seededUrl = acq?.sourceUrl ?? '';
    _url = TextEditingController(text: _seededUrl);
    _id = TextEditingController(text: acq?.sourceId ?? '');
    _provider = TextEditingController(text: acq?.provider ?? '');
    _sourceType = acq?.sourceType ?? 'manual';
  }

  /// What to send for the address: null when the box still holds what
  /// it was seeded with, since that value is the server's redaction and
  /// not the stored string. Only a typed change is authoritative.
  String? get _urlToSend {
    final typed = _url.text.trim();
    return typed == _seededUrl.trim() ? null : typed;
  }

  @override
  void dispose() {
    _url.dispose();
    _id.dispose();
    _provider.dispose();
    super.dispose();
  }

  /// The segments to draw: the known set, plus whatever the row already
  /// says when that is something else.
  List<String> get _types {
    final stored = widget.acquisition?.sourceType;
    if (stored == null ||
        stored.isEmpty ||
        _knownSourceTypes.contains(stored)) {
      return _knownSourceTypes;
    }
    return <String>[..._knownSourceTypes, stored];
  }

  /// The segment's own label, short: these sit three-across in a
  /// segmented control, where the origin sentence's noun phrases ("a
  /// podcast feed") read as instructions rather than choices.
  String _typeLabel(AppLocalizations l10n, String type) => switch (type) {
    'rss' => l10n.metadataOriginTypeRss,
    'manual' => l10n.metadataOriginTypeManual,
    // A brand, so it is spelled rather than translated - the origin
    // line beside this reads it the same way.
    'youtube' => 'YouTube',
    _ => type,
  };

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Padding(
      // Over the keyboard the three fields below raise. A scroll-
      // controlled sheet is not offset for it, and SafeArea covers
      // display padding rather than view insets, so without this the
      // actions sit under the keys.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.originSheet,
          child: Padding(
            padding: const EdgeInsets.all(WaxSpace.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.metadataOriginEditTitle,
                  style: WaxType.headline.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: WaxSpace.s4),
                Text(
                  l10n.metadataOriginEditHelp,
                  style: WaxType.caption.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: WaxSpace.s12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        WaxSegmented(
                          label: l10n.metadataOriginSourceType,
                          semanticsId: SemanticsIds.originSourceType,
                          segments: <WaxSegment>[
                            for (final type in _types)
                              WaxSegment(
                                name: type,
                                label: _typeLabel(l10n, type),
                              ),
                          ],
                          selected: _sourceType,
                          onSelect: (name) =>
                              setState(() => _sourceType = name),
                        ),
                        const SizedBox(height: WaxSpace.s12),
                        WaxTextField(
                          label: l10n.metadataOriginUrl,
                          // The read redacts, so what is in this box is
                          // what the server was willing to show, not
                          // necessarily what it stored. Saying so stops a
                          // correction from silently dropping a token the
                          // reader never saw.
                          helperText: l10n.metadataOriginUrlHelp,
                          controller: _url,
                          semanticsId: SemanticsIds.originUrl,
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: WaxSpace.s12),
                        WaxTextField(
                          label: l10n.metadataOriginId,
                          controller: _id,
                          semanticsId: SemanticsIds.originId,
                        ),
                        const SizedBox(height: WaxSpace.s12),
                        WaxTextField(
                          label: l10n.metadataOriginProvider,
                          controller: _provider,
                          semanticsId: SemanticsIds.originProvider,
                        ),
                        const SizedBox(height: WaxSpace.s12),
                        WaxSettingRow(
                          title: l10n.metadataOriginWriteBack,
                          help: l10n.metadataOriginWriteBackHelp,
                          control: WaxSwitch(
                            label: l10n.metadataOriginWriteBack,
                            value: _writeBack,
                            semanticsId: SemanticsIds.originWriteBack,
                            onChanged: (on) => setState(() => _writeBack = on),
                          ),
                        ),
                        const SizedBox(height: WaxSpace.s16),
                        // Inside the scroll view, not below it: with the
                        // keyboard up the fields take the height, and an
                        // action row pinned outside would be reachable
                        // only by dismissing it first.
                        Row(
                          children: <Widget>[
                            if (widget.acquisition != null)
                              WaxButton(
                                label: l10n.metadataOriginClear,
                                kind: WaxButtonKind.destructive,
                                semanticsId: SemanticsIds.originClear,
                                onPressed: () => Navigator.of(context).pop(
                                  AcquisitionEditRequest.clear(
                                    writeBack: _writeBack,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            WaxButton(
                              label: l10n.commonCancel,
                              kind: WaxButtonKind.text,
                              semanticsId: SemanticsIds.originCancel,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: WaxSpace.s8),
                            WaxButton(
                              label: l10n.commonSave,
                              semanticsId: SemanticsIds.originSave,
                              onPressed: () => Navigator.of(context).pop(
                                AcquisitionEditRequest.set(
                                  sourceType: _sourceType,
                                  sourceUrl: _urlToSend,
                                  sourceId: _id.text.trim(),
                                  provider: _provider.text.trim(),
                                  writeBack: _writeBack,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
