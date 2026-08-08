import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/semantics_ids.dart';
import 'podcasts_controller.dart';

/// Per-subscription settings. Save PUTs the complete object, so every
/// field the sheet does not edit rides through untouched: the endpoint
/// replaces the document, and a sender that dropped one would erase a
/// setting made somewhere else.
class SubscriptionSettingsSheet extends ConsumerStatefulWidget {
  const SubscriptionSettingsSheet({
    super.key,
    required this.pid,
    required this.initial,
  });

  final String pid;
  final SubscriptionSettings initial;

  @override
  ConsumerState<SubscriptionSettingsSheet> createState() =>
      _SubscriptionSettingsSheetState();
}

class _SubscriptionSettingsSheetState
    extends ConsumerState<SubscriptionSettingsSheet> {
  late double _speed;
  late bool _trimSilence;
  late bool _voiceBoost;
  late bool _autoDownload;
  late final TextEditingController _retention;
  late final TextEditingController _include;
  late final TextEditingController _exclude;
  late final TextEditingController _skipIntro;
  late final TextEditingController _skipOutro;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _speed = widget.initial.speed ?? 1.0;
    _trimSilence = widget.initial.trimSilence ?? false;
    _voiceBoost = widget.initial.voiceBoost ?? false;
    _autoDownload = widget.initial.autoDownload;
    _retention = TextEditingController(
      text: widget.initial.retentionKeep?.toString() ?? '',
    );
    final filter = widget.initial.autoDownloadFilter;
    _include = TextEditingController(text: _joinTerms(filter?.include));
    _exclude = TextEditingController(text: _joinTerms(filter?.exclude));
    _skipIntro = TextEditingController(
      text: widget.initial.skipIntroSeconds?.toString() ?? '',
    );
    _skipOutro = TextEditingController(
      text: widget.initial.skipOutroSeconds?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _retention.dispose();
    _include.dispose();
    _exclude.dispose();
    _skipIntro.dispose();
    _skipOutro.dispose();
    super.dispose();
  }

  /// Terms are edited as one comma-separated line rather than as a chip
  /// editor: a filter is two or three words in practice, and a line of
  /// text is the shape a listener can read back at a glance and paste
  /// between shows.
  static String _joinTerms(List<String>? terms) =>
      (terms ?? const <String>[]).join(', ');

  static List<String> _splitTerms(String raw) => <String>[
    for (final term in raw.split(','))
      if (term.trim().isNotEmpty) term.trim(),
  ];

  /// A whole-number field, held to the range the contract accepts.
  ///
  /// Empty means "the server default", which is a real answer and stays
  /// null. Anything else is clamped rather than sent: a number keyboard
  /// still offers a minus sign on most platforms, and a refusal from the
  /// server for something the field could have prevented is a round trip
  /// spent telling a listener off for typing.
  static int? _bounded(String raw, {required int max}) {
    final value = int.tryParse(raw.trim());
    if (value == null) return null;
    return value.clamp(0, max);
  }

  /// The contract's own ceiling on the skip fields (ten minutes).
  static const _maxSkipSeconds = 600;

  /// No ceiling in the contract for retention, so this is only a sane
  /// stop: a feed nobody has published a million episodes of.
  static const _maxRetention = 100000;

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final include = _splitTerms(_include.text);
    final exclude = _splitTerms(_exclude.text);
    final settings = SubscriptionSettings(
      // No ceiling: keeping N episodes is bounded by the feed, and the
      // contract sets only a floor.
      retentionKeep: _bounded(_retention.text, max: _maxRetention),
      autoDownload: _autoDownload,
      // An empty filter is sent as absent rather than as two empty
      // lists: absent is what the contract calls "take everything", and
      // storing an empty document to mean the same thing invites the
      // next reader to think a filter is set.
      autoDownloadFilter: include.isEmpty && exclude.isEmpty
          ? null
          : EpisodeFilter(include: include, exclude: exclude),
      folder: widget.initial.folder,
      private: widget.initial.private,
      speed: _speed,
      trimSilence: _trimSilence,
      voiceBoost: _voiceBoost,
      skipIntroSeconds: _bounded(_skipIntro.text, max: _maxSkipSeconds),
      skipOutroSeconds: _bounded(_skipOutro.text, max: _maxSkipSeconds),
    );
    try {
      await ref
          .read(podcastDetailProvider(widget.pid).notifier)
          .saveSettings(settings);
      // Only while this sheet is still up: a save outlives a sheet
      // somebody swiped away, and popping then takes the show screen
      // underneath with it.
      if (mounted) navigator.pop();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: WaxSpace.s16,
        right: WaxSpace.s16,
        top: WaxSpace.s16,
        bottom: WaxSpace.s16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              title: 'Subscription settings',
              overline: 'This show',
            ),
            Text(
              'Speed ${_speed.toStringAsFixed(2)}x',
              style: WaxType.label.copyWith(color: colors.textSecondary),
            ),
            Semantics(
              identifier: SemanticsIds.podcastSettingsSpeed,
              label: 'Playback speed',
              child: Slider(
                key: const Key(SemanticsIds.podcastSettingsSpeed),
                value: _speed,
                min: 0.5,
                max: 3.5,
                divisions: 60,
                label: _speed.toStringAsFixed(2),
                onChanged: (v) => setState(() => _speed = v),
              ),
            ),
            WaxSettingRow(
              key: const Key('podcast-settings-trim'),
              title: 'Trim silence',
              help:
                  'Needs the episode fetched: silence is mapped from the '
                  'audio this server holds',
              control: WaxSwitch(
                value: _trimSilence,
                label: 'Trim silence',
                onChanged: (v) => setState(() => _trimSilence = v),
              ),
            ),
            WaxSettingRow(
              key: const Key('podcast-settings-boost'),
              title: 'Voice boost',
              help: 'Lifts speech over a noisy room',
              control: WaxSwitch(
                value: _voiceBoost,
                label: 'Voice boost',
                onChanged: (v) => setState(() => _voiceBoost = v),
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('podcast-settings-skip-intro'),
                    controller: _skipIntro,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Skip intro (seconds)',
                    ),
                  ),
                ),
                const SizedBox(width: WaxSpace.s12),
                Expanded(
                  child: TextField(
                    key: const Key('podcast-settings-skip-outro'),
                    controller: _skipOutro,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Skip outro (seconds)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: WaxSpace.s16),
            WaxSettingRow(
              key: const Key('podcast-settings-autodownload'),
              title: 'Auto-download new episodes',
              help: 'Keeps arrivals on this device as the feed refreshes',
              control: WaxSwitch(
                value: _autoDownload,
                label: 'Auto-download new episodes',
                onChanged: (v) => setState(() => _autoDownload = v),
              ),
            ),
            // The filter is only consulted where auto-download decides
            // what a refresh just added, so it says so rather than
            // sitting there looking active with the switch off.
            Text(
              _autoDownload
                  ? 'Matched against episode titles only, and against new '
                        'arrivals only: editing this never re-evaluates the '
                        'backlog or removes anything already fetched.'
                  : 'Turn auto-download on for these to do anything.',
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: WaxSpace.s8),
            Semantics(
              identifier: SemanticsIds.podcastSettingsInclude,
              textField: true,
              child: TextField(
                key: const Key(SemanticsIds.podcastSettingsInclude),
                controller: _include,
                enabled: _autoDownload,
                decoration: const InputDecoration(
                  labelText: 'Only titles containing',
                  helperText: 'Comma separated. Empty takes every episode.',
                ),
              ),
            ),
            const SizedBox(height: WaxSpace.s8),
            Semantics(
              identifier: SemanticsIds.podcastSettingsExclude,
              textField: true,
              child: TextField(
                key: const Key(SemanticsIds.podcastSettingsExclude),
                controller: _exclude,
                enabled: _autoDownload,
                decoration: const InputDecoration(
                  labelText: 'Never titles containing',
                  helperText: 'Comma separated. Wins where both match.',
                ),
              ),
            ),
            const SizedBox(height: WaxSpace.s16),
            Semantics(
              identifier: SemanticsIds.podcastSettingsRetention,
              textField: true,
              child: TextField(
                key: const Key(SemanticsIds.podcastSettingsRetention),
                controller: _retention,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Episodes to keep',
                  helperText: 'Empty uses the server default; 0 keeps all',
                ),
              ),
            ),
            const SizedBox(height: WaxSpace.s16),
            Align(
              alignment: Alignment.centerRight,
              child: WaxButton(
                label: 'Save',
                semanticsId: SemanticsIds.podcastSettingsSave,
                onPressed: _busy ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
