import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../settings/client_prefs.dart';
import '../shell/navigation_history.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'podcasts_controller.dart';
import 'speed_slider.dart';

/// Per-subscription settings. Save reads the stored settings and PUTs the
/// complete object back with only what was changed here laid over them:
/// the endpoint replaces the document, so a field dropped, or sent as the
/// sheet read it when it opened, would erase a setting made since, by the
/// player or another device.
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

  /// What the fields stand on while nobody has changed them: what the
  /// screen had, then what is stored once it is read.
  late SubscriptionSettings _base = widget.initial;
  var _busy = false;

  // A field with nothing stored is drawn as playback has it: at this
  // device's default.
  late final double _defaultSpeed = ref.read(podcastSpeedProvider);
  late final bool _defaultTrim = ref.read(trimSilenceDefaultProvider);
  late final bool _defaultBoost = ref.read(voiceBoostDefaultProvider);

  @override
  void initState() {
    super.initState();
    _speed = _base.speed ?? _defaultSpeed;
    _trimSilence = _base.trimSilence ?? _defaultTrim;
    _voiceBoost = _base.voiceBoost ?? _defaultBoost;
    _autoDownload = _base.autoDownload;
    _retention = TextEditingController(text: _number(_base.retentionKeep));
    final filter = _base.autoDownloadFilter;
    _include = TextEditingController(text: _joinTerms(filter?.include));
    _exclude = TextEditingController(text: _joinTerms(filter?.exclude));
    _skipIntro = TextEditingController(text: _number(_base.skipIntroSeconds));
    _skipOutro = TextEditingController(text: _number(_base.skipOutroSeconds));
    unawaited(_readStored(ref.read(repositoryProvider)));
  }

  static String _number(int? value) => value?.toString() ?? '';

  /// [value] for a copy to take, or null while it is still [atOpen].
  static T Function()? _changed<T>(T value, T atOpen) =>
      value == atOpen ? null : () => value;

  /// The stored settings, read as the sheet opens: the screen's copy may be
  /// older than a rate the player stored since, or another device's change.
  /// A field still as it opened takes them; one already changed here keeps
  /// its change. Unread, the sheet stays on what the screen had.
  Future<void> _readStored(WaxDeckRepository repository) async {
    final SubscriptionSettings stored;
    try {
      stored =
          (await repository.getPodcast(widget.pid)).settings ??
          const SubscriptionSettings();
    } on WaxDeckApiException {
      return;
    }
    if (!mounted) return;
    final base = _base;
    final baseFilter = base.autoDownloadFilter;
    final storedFilter = stored.autoDownloadFilter;
    final speed = _speed == (base.speed ?? _defaultSpeed);
    final trim = _trimSilence == (base.trimSilence ?? _defaultTrim);
    final boost = _voiceBoost == (base.voiceBoost ?? _defaultBoost);
    final autoDownload = _autoDownload == base.autoDownload;
    final retention =
        _bounded(_retention.text, max: _maxRetention) == base.retentionKeep;
    final intro =
        _bounded(_skipIntro.text, max: _maxSkipSeconds) ==
        base.skipIntroSeconds;
    final outro =
        _bounded(_skipOutro.text, max: _maxSkipSeconds) ==
        base.skipOutroSeconds;
    final include = listEquals(
      _splitTerms(_include.text),
      baseFilter?.include ?? const <String>[],
    );
    final exclude = listEquals(
      _splitTerms(_exclude.text),
      baseFilter?.exclude ?? const <String>[],
    );
    final includeTerms = include
        ? storedFilter?.include ?? const <String>[]
        : baseFilter?.include ?? const <String>[];
    final excludeTerms = exclude
        ? storedFilter?.exclude ?? const <String>[]
        : baseFilter?.exclude ?? const <String>[];
    setState(() {
      _base = stored.copyWith(
        retentionKeep: retention ? null : () => base.retentionKeep,
        autoDownload: autoDownload ? null : base.autoDownload,
        autoDownloadFilter: () => includeTerms.isEmpty && excludeTerms.isEmpty
            ? null
            : EpisodeFilter(include: includeTerms, exclude: excludeTerms),
        speed: speed ? null : () => base.speed,
        trimSilence: trim ? null : () => base.trimSilence,
        voiceBoost: boost ? null : () => base.voiceBoost,
        skipIntroSeconds: intro ? null : () => base.skipIntroSeconds,
        skipOutroSeconds: outro ? null : () => base.skipOutroSeconds,
      );
      if (speed) _speed = stored.speed ?? _defaultSpeed;
      if (trim) _trimSilence = stored.trimSilence ?? _defaultTrim;
      if (boost) _voiceBoost = stored.voiceBoost ?? _defaultBoost;
      if (autoDownload) _autoDownload = stored.autoDownload;
    });
    if (retention) _retention.text = _number(stored.retentionKeep);
    if (intro) _skipIntro.text = _number(stored.skipIntroSeconds);
    if (outro) _skipOutro.text = _number(stored.skipOutroSeconds);
    if (include) _include.text = _joinTerms(storedFilter?.include);
    if (exclude) _exclude.text = _joinTerms(storedFilter?.exclude);
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
    final messenger = ref.read(shellMessengerProvider);
    final route = ModalRoute.of(context);
    final l10n = context.l10n;
    // Read off the fields before the first await: a sheet swiped away
    // takes its controllers and its `ref` with it.
    final opened = _base;
    // No ceiling: keeping N episodes is bounded by the feed, and the
    // contract sets only a floor.
    final retention = _bounded(_retention.text, max: _maxRetention);
    final include = _splitTerms(_include.text);
    final exclude = _splitTerms(_exclude.text);
    final skipIntro = _bounded(_skipIntro.text, max: _maxSkipSeconds);
    final skipOutro = _bounded(_skipOutro.text, max: _maxSkipSeconds);
    final includeChanged = !listEquals(
      include,
      opened.autoDownloadFilter?.include ?? const <String>[],
    );
    final excludeChanged = !listEquals(
      exclude,
      opened.autoDownloadFilter?.exclude ?? const <String>[],
    );
    final speed = _changed(_speed, opened.speed ?? _defaultSpeed);
    final trim = _changed(_trimSilence, opened.trimSilence ?? _defaultTrim);
    final boost = _changed(_voiceBoost, opened.voiceBoost ?? _defaultBoost);
    final autoDownload = _autoDownload == opened.autoDownload
        ? null
        : _autoDownload;
    final repository = ref.read(repositoryProvider);
    final controller = ref.read(podcastDetailProvider(widget.pid).notifier);
    try {
      // A read that fails writes nothing, and is said as a failed save is.
      final stored =
          (await repository.getPodcast(widget.pid)).settings ??
          const SubscriptionSettings();
      final storedFilter = stored.autoDownloadFilter;
      final filterInclude = includeChanged
          ? include
          : storedFilter?.include ?? const <String>[];
      final filterExclude = excludeChanged
          ? exclude
          : storedFilter?.exclude ?? const <String>[];
      final settings = stored.copyWith(
        retentionKeep: _changed(retention, opened.retentionKeep),
        autoDownload: autoDownload,
        // An empty filter is sent as absent rather than as two empty
        // lists: absent is what the contract calls "take everything", and
        // storing an empty document to mean the same thing invites the
        // next reader to think a filter is set.
        autoDownloadFilter: !includeChanged && !excludeChanged
            ? null
            : () => filterInclude.isEmpty && filterExclude.isEmpty
                  ? null
                  : EpisodeFilter(
                      include: filterInclude,
                      exclude: filterExclude,
                    ),
        speed: speed,
        trimSilence: trim,
        voiceBoost: boost,
        skipIntroSeconds: _changed(skipIntro, opened.skipIntroSeconds),
        skipOutroSeconds: _changed(skipOutro, opened.skipOutroSeconds),
      );
      await controller.saveSettings(settings);
      // Only while this sheet is still there: a save outlives a sheet
      // somebody swiped away, and popping then takes the show screen
      // underneath with it.
      closeFinished(route);
    } on WaxDeckApiException catch (e) {
      // The fields carry values somebody just typed, so a refusal of one
      // keeps the server's own words about it.
      messenger.show(explainRefusal(l10n, e), channel: ShellChannel.podcasts);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
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
            SectionHeader(
              title: l10n.podcastSettingsTitle,
              overline: l10n.podcastSettingsOverline,
            ),
            Text(
              // Through the same formatter every other rate readout
              // goes through, so the decimal separator is the locale's
              // and the trailing zeros go.
              l10n.podcastSettingsSpeed(l10n.formatSpeed(_speed)),
              style: WaxType.label.copyWith(color: colors.textSecondary),
            ),
            SpeedSlider(
              speed: _speed,
              label: l10n.podcastSettingsSpeedLabel,
              semanticsId: SemanticsIds.podcastSettingsSpeed,
              onChanged: (v) => setState(() => _speed = v),
            ),
            WaxSettingRow(
              key: const Key('podcast-settings-trim'),
              title: l10n.podcastTrimSilence,
              help: l10n.podcastTrimSilenceHelp,
              control: WaxSwitch(
                value: _trimSilence,
                label: l10n.podcastTrimSilence,
                onChanged: (v) => setState(() => _trimSilence = v),
              ),
            ),
            WaxSettingRow(
              key: const Key('podcast-settings-boost'),
              title: l10n.podcastVoiceBoost,
              control: WaxSwitch(
                value: _voiceBoost,
                label: l10n.podcastVoiceBoost,
                onChanged: (v) => setState(() => _voiceBoost = v),
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: WaxTextField(
                    key: const Key('podcast-settings-skip-intro'),
                    controller: _skipIntro,
                    keyboardType: TextInputType.number,
                    label: l10n.podcastSkipIntro,
                  ),
                ),
                const SizedBox(width: WaxSpace.s12),
                Expanded(
                  child: WaxTextField(
                    key: const Key('podcast-settings-skip-outro'),
                    controller: _skipOutro,
                    keyboardType: TextInputType.number,
                    label: l10n.podcastSkipOutro,
                  ),
                ),
              ],
            ),
            const SizedBox(height: WaxSpace.s16),
            WaxSettingRow(
              key: const Key('podcast-settings-autodownload'),
              title: l10n.podcastAutoDownload,
              control: WaxSwitch(
                value: _autoDownload,
                label: l10n.podcastAutoDownload,
                onChanged: (v) => setState(() => _autoDownload = v),
              ),
            ),
            // The filter is only consulted where auto-download decides
            // what a refresh just added, so it says so rather than
            // sitting there looking active with the switch off.
            Text(
              _autoDownload
                  ? l10n.podcastFilterActiveHelp
                  : l10n.podcastFilterInactiveHelp,
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: WaxSpace.s8),
            WaxTextField(
              semanticsId: SemanticsIds.podcastSettingsInclude,
              controller: _include,
              enabled: _autoDownload,
              label: l10n.podcastIncludeLabel,
              helperText: l10n.podcastIncludeHelp,
            ),
            const SizedBox(height: WaxSpace.s8),
            WaxTextField(
              semanticsId: SemanticsIds.podcastSettingsExclude,
              controller: _exclude,
              enabled: _autoDownload,
              label: l10n.podcastExcludeLabel,
              helperText: l10n.podcastExcludeHelp,
            ),
            const SizedBox(height: WaxSpace.s16),
            WaxTextField(
              semanticsId: SemanticsIds.podcastSettingsRetention,
              controller: _retention,
              keyboardType: TextInputType.number,
              label: l10n.podcastRetentionLabel,
              helperText: l10n.podcastRetentionHelp,
            ),
            const SizedBox(height: WaxSpace.s16),
            Align(
              alignment: Alignment.centerRight,
              child: WaxButton(
                label: l10n.commonSave,
                semanticsId: SemanticsIds.podcastSettingsSave,
                busy: _busy,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
