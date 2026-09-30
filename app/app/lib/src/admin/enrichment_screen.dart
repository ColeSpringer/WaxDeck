import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/art_source_label.dart';
import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// Where artwork, lyrics and details come from: whether a pass can run,
/// how much of the library it has covered, the sources in the order they
/// are asked, what the last pass did, and the cache of their answers.
class EnrichmentScreen extends ConsumerWidget {
  const EnrichmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final status = ref.watch(enrichmentStatusProvider);
    // Asked for now, beside the status, rather than once its section draws.
    ref.listen(enrichmentCacheProvider, (_, _) {});
    // A pass fills the cache, so its end is when the cache is read again.
    ref.listen(enrichmentStatusProvider, (was, now) {
      if (was?.value?.running == true && now.value?.running == false) {
        ref.invalidate(enrichmentCacheProvider);
      }
    });
    final l10n = context.l10n;
    final gap = SizedBox(height: WaxLayout.of(context).sectionGap);
    return WaxScaffold(
      title: l10n.adminEnrichmentTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.adminEnrichment,
      onBack: adminBack(context),
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        // Capped like the other settings screens: past the reading width
        // a row's help and its controls drift too far apart.
        child: ReadingColumn(
          // A failed refresh keeps the page, and what is being edited on
          // it, under a notice; only a first read that fails replaces it.
          child: switch (status) {
            AsyncValue(:final value?) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (status.hasError && !status.isLoading) ...<Widget>[
                  WaxBanner(
                    message: l10n.adminEnrichmentStale,
                    tone: WaxBannerTone.notice,
                    actionLabel: l10n.commonRetry,
                    onAction: () => ref.invalidate(enrichmentStatusProvider),
                  ),
                  gap,
                ],
                _Standing(status: value),
                gap,
                _Coverage(coverage: value.coverage),
                gap,
                _RunPass(status: value),
                gap,
                _Sources(status: value),
                gap,
                _LastRun(run: value.lastRun),
                gap,
                const _ResponseCache(),
              ],
            ),
            AsyncError(:final error) => ErrorState(
              title: l10n.adminEnrichmentLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(enrichmentStatusProvider),
            ),
            _ => const SkeletonShapes(shape: SkeletonShape.list),
          },
        ),
      ),
    );
  }
}

class _Standing extends StatelessWidget {
  const _Standing({required this.status});

  final EnrichmentStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mb = status.musicbrainzConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminEnrichmentStandingGroup),
        // Running first: a pass keeps walking whatever was switched since.
        if (status.running)
          WaxBanner(message: l10n.adminEnrichmentRunningNow)
        else if (!status.configured)
          WaxBanner(
            message: status.providers.any((p) => p.configured && !p.enabled)
                ? l10n.adminEnrichmentNothingToDoSwitchedOff
                : l10n.adminEnrichmentNothingToDo,
            tone: WaxBannerTone.notice,
          ),
        WaxSettingRow(
          title: l10n.adminEnrichmentMusicbrainzTitle,
          help: mb
              ? l10n.adminEnrichmentMusicbrainzOnHelp
              : l10n.adminEnrichmentMusicbrainzOffHelp,
          control: Text(
            mb ? l10n.adminEnrichmentStateOn : l10n.adminEnrichmentStateOff,
            style: WaxType.label,
          ),
        ),
      ],
    );
  }
}

class _Coverage extends StatelessWidget {
  const _Coverage({required this.coverage});

  final EnrichmentCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget tile(String label, CoverageCount count, {String? caption}) => _Tile(
      label: label,
      // A total of zero is one the server could not count, not an empty
      // library, so it is left unsaid.
      value: count.total > 0
          ? l10n.adminEnrichmentCoverageOf(count.enriched, count.total)
          : '${count.enriched}',
      caption: caption,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminEnrichmentCoverageGroup),
        Wrap(
          spacing: WaxSpace.s12,
          runSpacing: WaxSpace.s12,
          children: <Widget>[
            tile(l10n.adminEnrichmentCoverageArtists, coverage.artists),
            tile(
              l10n.adminEnrichmentCoverageReleaseGroups,
              coverage.releaseGroups,
            ),
            tile(l10n.adminEnrichmentCoverageBooks, coverage.books),
            tile(
              l10n.adminEnrichmentCoverageLyrics,
              coverage.lyrics,
              caption: coverage.lyricsAsked > 0
                  ? l10n.adminEnrichmentCoverageLyricsAsked(
                      coverage.lyricsAsked,
                    )
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// One count on this screen, every one the same width.
class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: StatTile(label: label, value: value, caption: caption),
  );
}

/// A phase in the listener's words, with what it fills.
({String title, String help}) _phase(AppLocalizations l10n, String phase) =>
    switch (phase) {
      'identity' => (
        title: l10n.adminEnrichmentPhaseIdentity,
        help: l10n.adminEnrichmentPhaseIdentityHelp,
      ),
      'releases' => (
        title: l10n.adminEnrichmentPhaseReleases,
        help: l10n.adminEnrichmentPhaseReleasesHelp,
      ),
      'group-art' => (
        title: l10n.adminEnrichmentPhaseGroupArt,
        help: l10n.adminEnrichmentPhaseGroupArtHelp,
      ),
      'artist-art' => (
        title: l10n.adminEnrichmentPhaseArtistArt,
        help: l10n.adminEnrichmentPhaseArtistArtHelp,
      ),
      'album-art' => (
        title: l10n.adminEnrichmentPhaseAlbumArt,
        help: l10n.adminEnrichmentPhaseAlbumArtHelp,
      ),
      'lyrics' => (
        title: l10n.adminEnrichmentPhaseLyrics,
        help: l10n.adminEnrichmentPhaseLyricsHelp,
      ),
      'track-fields' => (
        title: l10n.adminEnrichmentPhaseTrackFields,
        help: l10n.adminEnrichmentPhaseTrackFieldsHelp,
      ),
      'book-fields' => (
        title: l10n.adminEnrichmentPhaseBookFields,
        help: l10n.adminEnrichmentPhaseBookFieldsHelp,
      ),
      'album-fields' => (
        title: l10n.adminEnrichmentPhaseAlbumFields,
        help: l10n.adminEnrichmentPhaseAlbumFieldsHelp,
      ),
      _ => (title: phase, help: phase),
    };

class _RunPass extends ConsumerStatefulWidget {
  const _RunPass({required this.status});

  final EnrichmentStatus status;

  @override
  ConsumerState<_RunPass> createState() => _RunPassState();
}

class _RunPassState extends ConsumerState<_RunPass> {
  var _mode = 'normal';
  final _phases = <String>{};
  var _busy = false;

  /// The chosen phases this server still offers.
  List<String> get _offered => [
    for (final p in widget.status.phases)
      if (_phases.contains(p)) p,
  ];

  Future<void> _run() async {
    setState(() => _busy = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    try {
      await ref
          .read(enrichmentStatusProvider.notifier)
          .run(
            force: _mode == 'all',
            forcePhases: _mode == 'phases' ? _offered : const [],
          );
      messenger.show(l10n.adminEnrichmentRunStarted);
    } on WaxDeckApiException catch (error) {
      // A refusal for want of a setting names it, which no copy here can.
      messenger.show(
        error.code == 'conflict'
            ? l10n.adminEnrichmentRunBusy
            : explainRefusal(l10n, error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = widget.status;
    final runnable = status.configured && !status.running && !_busy;
    final chosen = _mode != 'phases' || _offered.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminEnrichmentRunGroup),
        WaxRadioGroup<String>(
          value: _mode,
          onChanged: runnable ? (mode) => setState(() => _mode = mode) : null,
          options: <WaxRadioOption<String>>[
            WaxRadioOption(
              value: 'normal',
              label: l10n.adminEnrichmentRunNormal,
              help: l10n.adminEnrichmentRunNormalHelp,
              semanticsId: SemanticsIds.enrichmentRunMode('normal'),
            ),
            WaxRadioOption(
              value: 'all',
              label: l10n.adminEnrichmentRunAll,
              help: l10n.adminEnrichmentRunAllHelp,
              semanticsId: SemanticsIds.enrichmentRunMode('all'),
            ),
            WaxRadioOption(
              value: 'phases',
              label: l10n.adminEnrichmentRunPhases,
              help: l10n.adminEnrichmentRunPhasesHelp,
              semanticsId: SemanticsIds.enrichmentRunMode('phases'),
            ),
          ],
        ),
        if (_mode == 'phases')
          for (final phase in status.phases)
            WaxSettingRow(
              title: _phase(l10n, phase).title,
              help: _phase(l10n, phase).help,
              control: WaxSwitch(
                label: _phase(l10n, phase).title,
                value: _phases.contains(phase),
                semanticsId: SemanticsIds.enrichmentPhase(phase),
                onChanged: (on) => setState(
                  () => on ? _phases.add(phase) : _phases.remove(phase),
                ),
              ),
            ),
        const SizedBox(height: WaxSpace.s12),
        WaxButton(
          label: l10n.adminEnrichmentRunAction,
          semanticsId: SemanticsIds.enrichmentRun,
          busy: _busy,
          onPressed: runnable && chosen ? () => unawaited(_run()) : null,
        ),
      ],
    );
  }
}

String _capability(AppLocalizations l10n, String cap) => switch (cap) {
  'identity' => l10n.adminEnrichmentCapIdentity,
  'genres' => l10n.adminEnrichmentCapGenres,
  'cover' => l10n.adminEnrichmentCapCover,
  'aux-art' => l10n.adminEnrichmentCapAuxArt,
  'artist-art' => l10n.adminEnrichmentPhaseArtistArt,
  'artist-front' => l10n.adminEnrichmentCapArtistFront,
  'artist-background' => l10n.adminEnrichmentCapArtistBackground,
  'lyrics' => l10n.adminEnrichmentPhaseLyrics,
  'book' => l10n.adminEnrichmentCapBook,
  'fields' => l10n.adminEnrichmentCapFields,
  _ => cap,
};

class _Sources extends ConsumerStatefulWidget {
  const _Sources({required this.status});

  final EnrichmentStatus status;

  @override
  ConsumerState<_Sources> createState() => _SourcesState();
}

class _SourcesState extends ConsumerState<_Sources> {
  /// The order being edited, over the one the server holds; null when
  /// nothing is.
  List<EnrichmentSource>? _draft;
  var _busy = false;

  List<EnrichmentSource> get _served => [
    for (final p in widget.status.providers)
      EnrichmentSource(name: p.name, enabled: p.enabled),
  ];

  static bool _same(List<EnrichmentSource> a, List<EnrichmentSource> b) =>
      a.length == b.length &&
      Iterable<int>.generate(
        a.length,
      ).every((i) => a[i].name == b[i].name && a[i].enabled == b[i].enabled);

  bool get _dirty => _draft != null && !_same(_draft!, _served);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    final providers = {for (final p in widget.status.providers) p.name: p};
    final order = _draft ?? _served;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminEnrichmentSourcesGroup),
        Text(
          l10n.adminEnrichmentSourcesBlurb,
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s12),
        for (final (i, source) in order.indexed)
          // Keyed, so a moved row keeps its element and the focus in it.
          _SourceRow(
            key: ValueKey(source.name),
            name: source.name,
            capabilities: providers[source.name]?.capabilities ?? const [],
            builtin: providers[source.name]?.builtin ?? false,
            configured: providers[source.name]?.configured ?? true,
            source: source,
            onEnabled: (on) => _set(source.name, on),
            onUp: i > 0 ? () => _move(i, i - 1) : null,
            onDown: i < order.length - 1 ? () => _move(i, i + 1) : null,
          ),
        const SizedBox(height: WaxSpace.s12),
        Wrap(
          spacing: WaxSpace.s8,
          children: <Widget>[
            WaxButton(
              label: l10n.adminEnrichmentSourcesSave,
              semanticsId: SemanticsIds.enrichmentSourcesSave,
              busy: _busy,
              onPressed: _dirty && !_busy ? () => unawaited(_save()) : null,
            ),
            WaxButton(
              label: l10n.adminEnrichmentSourcesRevert,
              kind: WaxButtonKind.text,
              semanticsId: SemanticsIds.enrichmentSourcesRevert,
              onPressed: _dirty && !_busy
                  ? () => setState(() => _draft = null)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  void _move(int from, int to) => setState(() {
    final next = [...(_draft ?? _served)];
    next.insert(to, next.removeAt(from));
    _draft = next;
  });

  void _set(String name, bool enabled) => setState(() {
    _draft = [
      for (final s in _draft ?? _served)
        s.name == name ? EnrichmentSource(name: name, enabled: enabled) : s,
    ];
  });

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    try {
      final saved = await ref
          .read(enrichmentStatusProvider.notifier)
          .saveSources(_draft!);
      if (mounted) setState(() => _draft = null);
      messenger.show(
        saved.running
            ? l10n.adminEnrichmentSourcesSavedAfterPass
            : l10n.adminEnrichmentSourcesSaved,
      );
    } on WaxDeckApiException catch (e) {
      if (e.code == 'invalid-request') {
        // The roster moved under the edit; the status has been read again.
        if (mounted) setState(() => _draft = null);
        messenger.show(l10n.adminEnrichmentSourcesStale);
      } else {
        // Nothing was saved, so the edit stays for another try.
        messenger.show(explainError(l10n, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// One source: its name, what it supplies, its switch and its place.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.name,
    required this.capabilities,
    required this.builtin,
    required this.configured,
    required this.source,
    this.onEnabled,
    this.onUp,
    this.onDown,
    super.key,
  });

  final String name;
  final List<String> capabilities;
  final bool builtin;
  final bool configured;
  final EnrichmentSource source;
  final ValueChanged<bool>? onEnabled;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final named = provenanceProducerName(l10n, name);
    final supplies = capabilities.map((c) => _capability(l10n, c)).join(', ');
    // The MusicBrainz entry ranks only its genres; the identity walk stays.
    final genresOnly = name == 'musicbrainz';
    return Semantics(
      identifier: SemanticsIds.enrichmentSource(name),
      container: true,
      explicitChildNodes: true,
      child: WaxSettingRow(
        title: named,
        help: switch ((builtin, configured, genresOnly)) {
          (false, _, _) => supplies,
          (true, false, _) =>
            '$supplies. ${l10n.adminEnrichmentBuiltinNeedsContact}',
          (true, true, true) =>
            '$supplies. ${l10n.adminEnrichmentBuiltinMusicbrainz}',
          (true, true, false) => '$supplies. ${l10n.adminEnrichmentBuiltin}',
        },
        control: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            WaxSwitch(
              label: l10n.adminEnrichmentSourceSwitch(named),
              value: source.enabled,
              semanticsId: SemanticsIds.enrichmentSourceEnabled(name),
              onChanged: onEnabled,
            ),
            WaxIconButton(
              glyph: WaxIcons.expand,
              label: l10n.adminEnrichmentSourceUp(named),
              semanticsId: SemanticsIds.enrichmentSourceUp(name),
              onPressed: onUp,
            ),
            WaxIconButton(
              glyph: WaxIcons.collapse,
              label: l10n.adminEnrichmentSourceDown(named),
              semanticsId: SemanticsIds.enrichmentSourceDown(name),
              onPressed: onDown,
            ),
          ],
        ),
      ),
    );
  }
}

class _LastRun extends StatelessWidget {
  const _LastRun({required this.run});

  final EnrichmentLastRun? run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    final run = this.run;
    if (run == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: l10n.adminEnrichmentLastRunGroup),
          Text(
            l10n.adminEnrichmentLastRunNone,
            style: WaxType.body.copyWith(color: colors.textSecondary),
          ),
        ],
      );
    }
    final walks = <(String, int, int)>[
      (
        l10n.adminEnrichmentCoverageArtists,
        run.artistsEnriched,
        run.artistsMatched,
      ),
      (
        l10n.adminEnrichmentCoverageReleaseGroups,
        run.releaseGroupsEnriched,
        run.releaseGroupsMatched,
      ),
      (l10n.adminEnrichmentWalkAlbums, run.albumsSearched, run.albumsMatched),
      (l10n.adminEnrichmentCoverageBooks, run.booksEnriched, run.booksMatched),
      (
        l10n.adminEnrichmentCoverageLyrics,
        run.lyricsEnriched,
        run.lyricsMatched,
      ),
      (
        l10n.adminEnrichmentPhaseGroupArt,
        run.groupArtEnriched,
        run.groupArtMatched,
      ),
      (
        l10n.adminEnrichmentPhaseArtistArt,
        run.artistArtEnriched,
        run.artistArtMatched,
      ),
      (
        l10n.adminEnrichmentPhaseAlbumArt,
        run.albumArtEnriched,
        run.albumArtMatched,
      ),
      (
        l10n.adminEnrichmentPhaseTrackFields,
        run.trackFieldsEnriched,
        run.trackFieldsMatched,
      ),
      (
        l10n.adminEnrichmentPhaseBookFields,
        run.bookFieldsEnriched,
        run.bookFieldsMatched,
      ),
      (
        l10n.adminEnrichmentPhaseAlbumFields,
        run.albumFieldsEnriched,
        run.albumFieldsMatched,
      ),
    ];
    final tallies = <(String, int)>[
      (l10n.adminEnrichmentRetried, run.retried),
      (l10n.adminEnrichmentDeferred, run.deferred),
      (l10n.adminEnrichmentArtFetched, run.artFetched),
      (l10n.adminEnrichmentAuxArtFetched, run.auxArtFetched),
      (l10n.adminEnrichmentArtReused, run.artReused),
      (l10n.adminEnrichmentTagsWritten, run.tagsWritten),
      (l10n.adminEnrichmentTagsFailed, run.tagsFailed),
      (l10n.adminEnrichmentTagsUnrepresented, run.tagsUnrepresented),
      (l10n.adminEnrichmentTagsSkipped, run.tagsSkipped),
    ];
    final finished = run.finishedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminEnrichmentLastRunGroup),
        if (finished != null)
          Text(
            l10n.adminEnrichmentLastRunFinished(l10n.relativeSpaced(finished)),
            style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
          ),
        if (run.stalled.isNotEmpty) ...<Widget>[
          const SizedBox(height: WaxSpace.s12),
          WaxBanner(
            message: l10n.adminEnrichmentStalled(
              run.stalled.map((p) => _phase(l10n, p).title).join(', '),
            ),
            tone: WaxBannerTone.notice,
          ),
        ],
        const SizedBox(height: WaxSpace.s12),
        WaxTable<(String, int, int)>(
          rows: walks,
          rowId: (w) => w.$1,
          columns: <WaxColumn<(String, int, int)>>[
            WaxColumn(
              label: l10n.adminEnrichmentWalkColumn,
              priority: WaxColumnPriority.primary,
              text: (w) => w.$1,
              cell: (context, w) => Text(w.$1, style: WaxType.body),
            ),
            WaxColumn(
              label: l10n.adminEnrichmentLookedUpColumn,
              numeric: true,
              text: (w) => '${w.$2}',
              cell: (context, w) => Text('${w.$2}', style: WaxType.body),
            ),
            WaxColumn(
              label: l10n.adminEnrichmentAnsweredColumn,
              numeric: true,
              text: (w) => '${w.$3}',
              cell: (context, w) => Text('${w.$3}', style: WaxType.body),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s16),
        Wrap(
          spacing: WaxSpace.s12,
          runSpacing: WaxSpace.s12,
          children: <Widget>[
            for (final (label, value) in tallies)
              _Tile(label: label, value: '$value'),
          ],
        ),
      ],
    );
  }
}

class _ResponseCache extends ConsumerStatefulWidget {
  const _ResponseCache();

  @override
  ConsumerState<_ResponseCache> createState() => _ResponseCacheState();
}

class _ResponseCacheState extends ConsumerState<_ResponseCache> {
  final _olderThanDays = TextEditingController();
  final _maxMegabytes = TextEditingController();

  @override
  void dispose() {
    _olderThanDays.dispose();
    _maxMegabytes.dispose();
    super.dispose();
  }

  /// The largest bound each box takes: past these the byte and second
  /// counts would not fit the wire's integers.
  static const _dayCap = 36500;
  static const _megabyteCap = 1024 * 1024;

  /// What each box is refusing, once a prune has looked at it.
  String? _daysError;
  String? _megabytesError;

  /// A whole number in [0, max], null for an empty box, and a refusal
  /// for anything else.
  static ({int? value, bool bad}) _bound(String text, int max) {
    final typed = text.trim();
    if (typed.isEmpty) return (value: null, bad: false);
    final parsed = int.tryParse(typed);
    return parsed == null || parsed < 0 || parsed > max
        ? (value: null, bad: true)
        : (value: parsed, bad: false);
  }

  /// Pruning takes the typed word: what goes is asked for again, one
  /// request at a time, the next time a pass needs it.
  Future<void> _prune() async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final l10n = context.l10n;
    final days = _bound(_olderThanDays.text, _dayCap);
    final megabytes = _bound(_maxMegabytes.text, _megabyteCap);
    setState(() {
      _daysError = days.bad
          ? l10n.adminEnrichmentCacheNeedsWhole(_dayCap)
          : null;
      _megabytesError = megabytes.bad
          ? l10n.adminEnrichmentCacheNeedsWhole(_megabyteCap)
          : null;
    });
    if (days.bad || megabytes.bad) return;
    final confirmed = await showTypedConfirm(
      context,
      title: l10n.adminEnrichmentCachePruneTitle,
      message: l10n.adminEnrichmentCachePruneBody,
      confirmWord: l10n.adminEnrichmentCachePruneWord,
      confirmLabel: l10n.adminEnrichmentCachePrune,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    // Gone while the dialog was up: whoever left did not mean to prune.
    if (!confirmed || !mounted) return;
    try {
      final result = await ref
          .read(enrichmentCacheProvider.notifier)
          .prune(
            olderThanSeconds: days.value == null ? null : days.value! * 86400,
            maxBytes: megabytes.value == null
                ? null
                : megabytes.value! * 1024 * 1024,
          );
      messenger.show(
        l10n.adminEnrichmentCachePruned(
          result.removed,
          l10n.formatBytes(result.freedBytes),
        ),
      );
    } on WaxDeckApiException catch (error) {
      messenger.show(explainRefusal(l10n, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    final cache = ref.watch(enrichmentCacheProvider);
    final asked =
        _olderThanDays.text.trim().isNotEmpty ||
        _maxMegabytes.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminEnrichmentCacheGroup),
        Text(
          l10n.adminEnrichmentCacheBlurb,
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s12),
        switch (cache) {
          AsyncError(:final error) => ErrorState(
            title: l10n.adminEnrichmentCacheLoadError,
            message: context.explain(error),
            onRetry: () => ref.invalidate(enrichmentCacheProvider),
          ),
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: WaxSpace.s12,
                runSpacing: WaxSpace.s12,
                children: <Widget>[
                  _Tile(
                    label: l10n.adminEnrichmentCacheAnswers,
                    value: '${value.rows}',
                  ),
                  _Tile(
                    label: l10n.adminEnrichmentCacheSize,
                    value: l10n.formatBytes(value.bytes),
                  ),
                  _Tile(
                    label: l10n.adminEnrichmentCacheExempt,
                    value: l10n.formatBytes(value.exemptBytes),
                  ),
                ],
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTable<EnrichmentCacheKind>(
                rows: value.kinds,
                rowId: (k) => k.kind,
                empty: Text(
                  l10n.adminEnrichmentCacheEmpty,
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
                columns: <WaxColumn<EnrichmentCacheKind>>[
                  WaxColumn(
                    label: l10n.adminEnrichmentCacheKindColumn,
                    priority: WaxColumnPriority.primary,
                    text: (k) => k.kind,
                    cell: (context, k) => Text(k.kind, style: WaxType.body),
                  ),
                  WaxColumn(
                    label: l10n.adminEnrichmentCacheRowsColumn,
                    numeric: true,
                    text: (k) => '${k.rows}',
                    cell: (context, k) =>
                        Text('${k.rows}', style: WaxType.body),
                  ),
                  WaxColumn(
                    label: l10n.adminEnrichmentCacheBytesColumn,
                    numeric: true,
                    text: (k) => l10n.formatBytes(k.bytes),
                    cell: (context, k) =>
                        Text(l10n.formatBytes(k.bytes), style: WaxType.body),
                  ),
                ],
              ),
            ],
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
        const SizedBox(height: WaxSpace.s16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WaxTextField(
                label: l10n.adminEnrichmentCacheOlderThan,
                keyboardType: TextInputType.number,
                controller: _olderThanDays,
                errorText: _daysError,
                semanticsId: SemanticsIds.enrichmentCacheOlderThan,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTextField(
                label: l10n.adminEnrichmentCacheMaxMegabytes,
                keyboardType: TextInputType.number,
                controller: _maxMegabytes,
                errorText: _megabytesError,
                semanticsId: SemanticsIds.enrichmentCacheMaxBytes,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxButton(
                label: l10n.adminEnrichmentCachePrune,
                semanticsId: SemanticsIds.enrichmentCachePrune,
                onPressed: asked ? () => unawaited(_prune()) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
