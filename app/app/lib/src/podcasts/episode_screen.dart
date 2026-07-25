import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../player/session_registry.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'credits.dart';
import 'explicit_badge.dart';
import 'podcasts_controller.dart';
import 'show_notes.dart';

String formatCueTimestamp(int ms) {
  final d = Duration(milliseconds: ms);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Seeks the live player to [ms] when [pid] is the episode currently loaded;
/// otherwise reports the offset in a SnackBar. [label] names what is being
/// pointed at ("Clip", "Cue"). Loosely coupled on purpose: the timestamp
/// stays useful even when this episode is not the one playing.
void seekLiveOrReport(
  BuildContext context,
  WidgetRef ref,
  String pid,
  int ms,
  String label,
) {
  final session = ref.read(currentSessionRegistryProvider).current;
  if (session != null && session.item.pid == pid) {
    session.seek(Duration(milliseconds: ms));
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('$label starts at ${formatCueTimestamp(ms)}')),
    );
}

/// One episode's detail: show notes, chapter marks, and a lazy-loading
/// transcript whose cues seek the live player when this episode is the
/// one loaded.
class EpisodeScreen extends ConsumerWidget {
  const EpisodeScreen({super.key, required this.pid});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(episodeDetailProvider(pid));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.title ?? 'Episode')),
      body: switch (detail) {
        AsyncData(:final value) => _EpisodeBody(episode: value),
        AsyncError(:final error) => Center(
          child: Text(
            error is WaxDeckApiException
                ? error.message
                : 'Could not load the episode',
            textAlign: TextAlign.center,
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _EpisodeBody extends ConsumerWidget {
  const _EpisodeBody({required this.episode});

  final EpisodeDetail episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final descriptionHtml = episode.descriptionHtml;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            if (episode.explicit)
              ExplicitBadge(key: ValueKey('episode-explicit-${episode.pid}')),
            Expanded(child: Text(episode.title, style: textTheme.titleLarge)),
          ],
        ),
        Text(
          formatEpisodeMeta(episode),
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (descriptionHtml != null && descriptionHtml.isNotEmpty) ...[
          const SizedBox(height: 16),
          ShowNotesView(
            html: descriptionHtml,
            onOpenLink: ref.read(urlOpenerProvider).open,
          ),
        ],
        if (episode.chapters.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Chapters', style: textTheme.titleMedium),
          for (final chapter in episode.chapters)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(formatCueTimestamp(chapter.startMs)),
              title: Text(chapter.title ?? 'Chapter ${chapter.index + 1}'),
            ),
        ],
        if (episode.soundbites.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Highlights', style: textTheme.titleMedium),
          for (final (i, bite) in episode.soundbites.indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(formatCueTimestamp(bite.startMs)),
              title: Text(bite.title ?? 'Highlight ${i + 1}'),
              onTap: () => seekLiveOrReport(
                context,
                ref,
                episode.pid,
                bite.startMs,
                'Clip',
              ),
            ),
        ],
        if (episode.persons.isNotEmpty) ...[
          const SizedBox(height: 16),
          PodcastCredits(
            persons: episode.persons,
            onOpenLink: ref.read(urlOpenerProvider).open,
          ),
        ],
        if (episode.hasTranscript) ...[
          const SizedBox(height: 16),
          _TranscriptSection(pid: episode.pid),
        ],
      ],
    );
  }

  static String formatEpisodeMeta(EpisodeDetail episode) {
    final local = episode.publishedAt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final parts = <String>['${local.year}-$month-$day'];
    if (episode.season != null && episode.episodeNumber != null) {
      parts.add('S${episode.season} E${episode.episodeNumber}');
    } else if (episode.episodeNumber != null) {
      parts.add('E${episode.episodeNumber}');
    }
    return parts.join(' | ');
  }
}

/// Transcript cues, fetched only when the section is first expanded.
class _TranscriptSection extends ConsumerStatefulWidget {
  const _TranscriptSection({required this.pid});

  final String pid;

  @override
  ConsumerState<_TranscriptSection> createState() => _TranscriptSectionState();
}

class _TranscriptSectionState extends ConsumerState<_TranscriptSection> {
  Future<Transcript>? _loading;
  var _captured = false;

  void _onExpanded(bool expanded) {
    if (!expanded || _loading != null) return;
    setState(() {
      _loading = ref.read(repositoryProvider).getEpisodeTranscript(widget.pid);
    });
    // Opening the transcript also indexes it for search, so an episode a
    // listener streams but never downloads becomes findable by its words.
    // Best-effort: a capture failure never affects the display transcript.
    if (!_captured) {
      _captured = true;
      unawaited(
        ref
            .read(repositoryProvider)
            .captureEpisodeTranscript(widget.pid)
            .catchError((_) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: SemanticsIds.transcriptOpen,
      child: ExpansionTile(
        key: const Key(SemanticsIds.transcriptOpen),
        tilePadding: EdgeInsets.zero,
        title: const Text('Transcript'),
        onExpansionChanged: _onExpanded,
        children: [
          FutureBuilder<Transcript>(
            future: _loading,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    error is WaxDeckApiException
                        ? error.message
                        : 'Could not load the transcript',
                  ),
                );
              }
              final transcript = snapshot.data;
              if (transcript == null) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(
                children: [
                  for (final (i, cue) in transcript.cues.indexed)
                    Semantics(
                      identifier: SemanticsIds.transcriptCue(i),
                      button: true,
                      child: ListTile(
                        key: ValueKey(SemanticsIds.transcriptCue(i)),
                        dense: true,
                        leading: Text(formatCueTimestamp(cue.startMs)),
                        title: Text(
                          cue.speaker == null
                              ? cue.text
                              : '${cue.speaker}: ${cue.text}',
                        ),
                        onTap: () => seekLiveOrReport(
                          context,
                          ref,
                          widget.pid,
                          cue.startMs,
                          'Cue',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
