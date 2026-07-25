import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../podcasts/episode_screen.dart' show formatCueTimestamp;
import '../podcasts/show_notes.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../tools/tasks_screen.dart' show toolTasksProvider;

/// One audiobook's detail.
final bookDetailProvider = FutureProvider.autoDispose
    .family<BookDetail, String>(
      (ref, pid) => ref.watch(repositoryProvider).getBook(pid),
    );

/// One audiobook: header, description, resume, chapters, and per-book
/// playback settings.
class BookScreen extends ConsumerWidget {
  const BookScreen({super.key, required this.pid});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(bookDetailProvider(pid));
    return Scaffold(
      appBar: AppBar(
        title: Text(detail.value?.title ?? 'Audiobook'),
        actions: [
          if (detail.value != null) _BookToolsMenu(book: detail.value!),
          if (detail.hasValue)
            Semantics(
              identifier: SemanticsIds.bookSettingsOpen,
              label: 'Playback settings',
              button: true,
              child: IconButton(
                key: const Key(SemanticsIds.bookSettingsOpen),
                tooltip: 'Playback settings',
                icon: const Icon(Icons.tune),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _BookSettingsSheet(
                    pid: pid,
                    initial: detail.value?.settings ?? const BookSettings(),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: switch (detail) {
        AsyncData(:final value) => _BookBody(book: value),
        AsyncError(:final error) => Center(
          child: Text(
            error is WaxDeckApiException
                ? error.message
                : 'Could not load the book',
            textAlign: TextAlign.center,
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Builds the summary the player needs from the book detail.
ItemSummary bookItemSummary(BookDetail book) => ItemSummary(
  pid: book.pid,
  mediaType: MediaType.audiobook,
  title: book.title,
  artist: book.authors.isEmpty ? null : book.authors.join(', '),
  album: book.series,
  durationMs: book.durationMs,
  artUrl: book.artUrl,
);

class _BookBody extends ConsumerWidget {
  const _BookBody({required this.book});

  final BookDetail book;

  void _play(BuildContext context, {required int positionMs}) {
    context.push(
      WaxRoute.nowPlaying,
      extra: NowPlayingArgs(
        item: bookItemSummary(book),
        initialPositionMs: positionMs,
      ),
    );
  }

  Future<void> _resume(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resume = await ref.read(repositoryProvider).getBookResume(book.pid);
      if (!context.mounted) return;
      _play(context, positionMs: resume.positionMs);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final artUrl = book.artUrl;
    final descriptionHtml = book.descriptionHtml;
    final duration = Duration(milliseconds: book.durationMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 112,
                height: 112,
                child: artUrl == null
                    ? ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.menu_book, size: 48),
                      )
                    : Image.network(
                        artUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.menu_book, size: 48),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title, style: textTheme.titleLarge),
                  if (book.subtitle != null)
                    Text(book.subtitle!, style: textTheme.bodyMedium),
                  if (book.authors.isNotEmpty)
                    Text(
                      'By ${book.authors.join(', ')}',
                      style: textTheme.bodyMedium,
                    ),
                  if (book.narrators.isNotEmpty)
                    Text(
                      'Read by ${book.narrators.join(', ')}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (book.series != null)
                    Text(
                      book.seriesSequence == null
                          ? book.series!
                          : '${book.series!} #${book.seriesSequence}',
                      style: textTheme.bodySmall,
                    ),
                  Text(
                    hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          identifier: SemanticsIds.bookResume,
          label: 'Continue listening',
          button: true,
          child: FilledButton.icon(
            key: const Key(SemanticsIds.bookResume),
            onPressed: () => _resume(context, ref),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Continue'),
          ),
        ),
        if (descriptionHtml != null && descriptionHtml.isNotEmpty) ...[
          const SizedBox(height: 16),
          ShowNotesView(
            html: descriptionHtml,
            onOpenLink: ref.read(urlOpenerProvider).open,
          ),
        ],
        if (book.chapters.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Chapters', style: textTheme.titleMedium),
          for (final chapter in book.chapters)
            Semantics(
              identifier: SemanticsIds.chapter(chapter.index),
              button: true,
              child: ListTile(
                key: ValueKey(SemanticsIds.chapter(chapter.index)),
                dense: true,
                leading: Text(formatCueTimestamp(chapter.startMs)),
                title: Text(chapter.title ?? 'Chapter ${chapter.index + 1}'),
                onTap: () => _play(context, positionMs: chapter.startMs),
              ),
            ),
        ],
      ],
    );
  }
}

/// Per-book playback settings editor; Save PUTs the complete object.
class _BookSettingsSheet extends ConsumerStatefulWidget {
  const _BookSettingsSheet({required this.pid, required this.initial});

  final String pid;
  final BookSettings initial;

  @override
  ConsumerState<_BookSettingsSheet> createState() => _BookSettingsSheetState();
}

class _BookSettingsSheetState extends ConsumerState<_BookSettingsSheet> {
  late double _speed;
  late bool _voiceBoost;
  late bool _trimSilence;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _speed = widget.initial.speed ?? 1.0;
    _voiceBoost = widget.initial.voiceBoost ?? false;
    _trimSilence = widget.initial.trimSilence ?? false;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(repositoryProvider)
          .putBookSettings(
            widget.pid,
            BookSettings(
              speed: _speed,
              voiceBoost: _voiceBoost,
              trimSilence: _trimSilence,
            ),
          );
      ref.invalidate(bookDetailProvider(widget.pid));
      navigator.pop();
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
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Playback settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Speed ${_speed.toStringAsFixed(2)}x'),
          Semantics(
            identifier: SemanticsIds.bookSettingsSpeed,
            label: 'Playback speed',
            child: Slider(
              key: const Key(SemanticsIds.bookSettingsSpeed),
              value: _speed,
              min: 0.5,
              max: 3.5,
              divisions: 60,
              label: _speed.toStringAsFixed(2),
              onChanged: (v) => setState(() => _speed = v),
            ),
          ),
          SwitchListTile(
            key: const Key('book-settings-boost'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Voice boost'),
            value: _voiceBoost,
            onChanged: (v) => setState(() => _voiceBoost = v),
          ),
          SwitchListTile(
            key: const Key('book-settings-trim'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Trim silence'),
            value: _trimSilence,
            onChanged: (v) => setState(() => _trimSilence = v),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              identifier: SemanticsIds.bookSettingsSave,
              label: 'Save settings',
              button: true,
              child: FilledButton(
                key: const Key(SemanticsIds.bookSettingsSave),
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The audiobook file tools, admin only. A multi-file book offers a
/// merge into one chaptered file; a single-file book with chapters
/// offers a split into per-chapter files. Both run through the
/// streaming engine as background tasks, so the menu explains that the
/// result appears in the tasks list.
class _BookToolsMenu extends ConsumerWidget {
  const _BookToolsMenu({required this.book});

  final BookDetail book;

  bool get _canMerge => book.parts.length > 1;
  bool get _canSplit => book.parts.length <= 1 && book.chapters.isNotEmpty;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<ToolTask> Function() start,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await start();
      ref.invalidate(toolTasksProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Queued. Follow it in Tasks.'),
            action: SnackBarAction(
              label: 'Tasks',
              onPressed: () => router.push(WaxRoute.tasks),
            ),
          ),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref
            .watch(authControllerProvider)
            .value
            ?.user
            ?.roles
            .contains('admin') ??
        false;
    if (!isAdmin || (!_canMerge && !_canSplit)) {
      return const SizedBox.shrink();
    }
    final repo = ref.read(repositoryProvider);
    return Semantics(
      identifier: SemanticsIds.bookToolsMenu,
      label: 'Audiobook tools',
      button: true,
      child: PopupMenuButton<String>(
        key: const Key(SemanticsIds.bookToolsMenu),
        tooltip: 'Audiobook tools',
        icon: const Icon(Icons.auto_awesome_motion_outlined),
        onSelected: (action) {
          switch (action) {
            case 'merge':
              _run(context, ref, () => repo.mergeBook(book.pid));
            case 'split':
              _run(context, ref, () => repo.splitBook(book.pid));
          }
        },
        itemBuilder: (context) => [
          if (_canMerge)
            PopupMenuItem(
              key: const Key('book-merge'),
              value: 'merge',
              child: const Text('Merge into one chaptered file'),
            ),
          if (_canSplit)
            PopupMenuItem(
              key: const Key('book-split'),
              value: 'split',
              child: const Text('Split at chapters'),
            ),
        ],
      ),
    );
  }
}
