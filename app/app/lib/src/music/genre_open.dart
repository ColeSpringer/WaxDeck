import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show BuildContext;

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/navigation_history.dart';
import '../shell/routes.dart';
import '../shell/shell_messages.dart';
import 'music_controllers.dart';

/// Opens the music genre named [genre], for a place that knows a genre
/// only by its label: a top genre carries no pid, so its bucket is found
/// by the name, matched without regard to case. A name no bucket answers
/// goes to the genres index instead.
///
/// The bucket is pushed, in the shell: it is declared under the music
/// hub, so `go` would throw away the page the visitor is on. [channel] is
/// the run the caller's own messages coalesce in.
Future<void> openGenreByLabel(
  BuildContext context,
  WidgetRef ref,
  String genre, {
  ShellChannel? channel,
}) async {
  final router = GoRouter.of(context);
  final from = pageOnTop(router);
  final messenger = ref.read(shellMessengerProvider);
  final l10n = context.l10n;
  try {
    final page = await ref
        .read(repositoryProvider)
        .listFacets(
          MusicDimension.genres.wireName,
          sort: FacetSort.label,
          startsAt: genre,
          limit: 5,
        );
    final bucket = page.buckets
        .where((b) => b.label.toLowerCase() == genre.toLowerCase())
        .firstOrNull;
    void open() {
      if (bucket == null) {
        // The index has a place of its own in the chrome, so it is gone
        // to; only a bucket is a drill-in that keeps the page beneath it.
        router.go(WaxRoute.musicIndex(MusicDimension.genres));
        return;
      }
      // In the shell, past an overlay the offer may be taken from.
      unawaited(
        router.pushInShell<void>(
          WaxRoute.musicBucket(
            MusicDimension.genres,
            musicBucketSegment(MusicDimension.genres, bucket),
          ),
          extra: bucket.label,
        ),
      );
    }

    // The router outlives the caller: a visitor who walked on meanwhile,
    // or opened something over the page, is offered the bucket there
    // instead.
    if (await stillShowing(router, from)) {
      open();
    } else {
      messenger.show(
        l10n.musicGenreReady(genre),
        actionLabel: l10n.commonOpen,
        onAction: open,
        channel: channel,
      );
    }
  } on WaxDeckApiException catch (e) {
    messenger.show(explainError(l10n, e), channel: channel);
  }
}
