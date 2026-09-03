import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../discovery/discovery_actions.dart';
import '../home/pin_action.dart';
import '../home/pinned_controller.dart';
import '../l10n/l10n.dart';
import '../music/album_detail.dart';
import '../music/music_controllers.dart';
import '../settings/settings_registry.dart';
import '../sharing/share_dialog.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../uploads/add_to_library.dart';
import 'item_detach.dart';

/// Whether this session gets an editor door on item rows: what the
/// session already knows - the admin role, or the upload right while a
/// server is reachable - rather than a per-item fetch, which would be a
/// request per row for a menu entry. An uploader tapping an item they
/// do not own is caught by the editor's own refusal screen, which
/// exists for exactly this.
bool mayOfferItemEdit(WidgetRef ref) =>
    ref.watch(isAdminProvider) || canAddToLibrary(ref);

/// [showItemMenuSheet] for a caller holding a full summary, which is
/// most of them; the field-by-field form exists for the search hits,
/// which carry no summary, and the album screen, which substitutes its
/// own release handle for the row's.
Future<void> showItemMenuForSummary(
  BuildContext context,
  WidgetRef ref,
  ItemSummary item, {
  bool withPin = false,
}) => showItemMenuSheet(
  context,
  ref,
  pid: item.pid,
  title: item.title,
  mediaType: item.mediaType,
  artist: item.artist,
  artistPid: item.artistPid,
  album: item.album,
  albumPid: item.albumPid,
  withPin: withPin,
);

/// The overflow sheet behind an item row, one component for every
/// surface that lists items: album tracks, playlist members, search
/// hits, queue entries, the listing rows, and the home shelves. A row
/// opens it from its kebab, a right click, or - where the surface has
/// not claimed the gesture for multi-select - a long press.
///
/// What it holds follows the item, and it always holds something: the
/// editor door for the sessions that can use it, then per medium - a
/// track's entity navigation, pin rows where the caller had a pin
/// affordance to keep, the instant mix, and the album share; a share
/// link for an episode or a book, whose only handles are themselves.
/// The music-only gating on the navigation rows is load-bearing: an
/// audiobook carries its author as `artistPid`, and routing that into
/// the Music hub's artist bucket would be a wrong answer dressed as a
/// door.
Future<void> showItemMenuSheet(
  BuildContext context,
  WidgetRef ref, {
  required String pid,
  required String title,
  required MediaType mediaType,
  String? artist,
  String? album,
  String? artistPid,
  String? albumPid,
  bool withGoToAlbum = true,
  bool withPin = false,
}) async {
  // Captured before the sheet, which outlives the row that opened it: a
  // queue entry scrolls into collapsed history, a sync delta rewrites a
  // playlist. The root navigator, the router, and the messenger all
  // outlive the row, so what was tapped still happens.
  final rootContext = Navigator.of(context, rootNavigator: true).context;
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final pinnedController = ref.read(pinnedEntitiesProvider.notifier);
  // Which navigator this row sits in decides the verb, and it has to be
  // read before anything is popped. On the root navigator (the queue
  // and player overlays) an in-shell location is gone to, never pushed,
  // or a second shell is built beside the mounted one; inside the shell
  // (every listing, and the queue's side panel) `push` is the better
  // answer - it leaves the screen underneath for the way back, where
  // `go` would reset the branch. The same derivation, for the same
  // hazard, as the lyrics panel's editor door.
  final overRoot =
      Navigator.of(context) == Navigator.of(context, rootNavigator: true);
  final music = mediaType == MediaType.music;
  await showWaxOptionSheet(
    context,
    builder: (sheetContext) => Consumer(
      // Its own Consumer, as the pin sheet's: the pin rows flip live
      // under a tap, and the gating reads roles through a ref that is
      // the sheet's own rather than the possibly-gone row's.
      builder: (_, sheetRef, _) {
        void close() => Navigator.of(sheetContext).pop();
        void open(String location) {
          close();
          if (overRoot) {
            router.go(location);
          } else {
            unawaited(router.push(location));
          }
        }

        // The sheet names the item it was raised for. The rows are
        // shared ids on every surface, so without this a menu on the
        // wrong row is indistinguishable from the right one to a test -
        // which is how a misaimed right click on a home card once
        // passed for the card beside it. `container` keeps the handle
        // its own node and `explicitChildNodes` leaves the rows theirs,
        // as the shelf's region does.
        return Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.itemMenuSheet(pid),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (mayOfferItemEdit(sheetRef))
                WaxOptionRow(
                  title: l10n.reviewEditMetadata,
                  glyph: WaxIcons.edit,
                  semanticsId: SemanticsIds.editMetadata(pid),
                  onTap: () => open(WaxRoute.metadata(pid)),
                ),
              if (music && withGoToAlbum && albumPid != null)
                WaxOptionRow(
                  title: l10n.libraryMenuGoToAlbum,
                  subtitle: album,
                  glyph: WaxIcons.albums,
                  semanticsId: SemanticsIds.itemMenuGoAlbum,
                  onTap: () => open(
                    WaxRoute.musicBucket(MusicDimension.albums, albumPid),
                  ),
                ),
              if (music && artistPid != null)
                WaxOptionRow(
                  title: l10n.libraryMenuGoToArtist,
                  subtitle: artist,
                  glyph: WaxIcons.artists,
                  semanticsId: SemanticsIds.itemMenuGoArtist,
                  onTap: () => open(
                    WaxRoute.musicBucket(MusicDimension.artists, artistPid),
                  ),
                ),
              if (music && withPin)
                for (final target in <PinTarget>[
                  if (albumPid != null)
                    (pid: albumPid, what: 'album', name: album ?? title),
                  if (artistPid != null)
                    (pid: artistPid, what: 'artist', name: artist ?? ''),
                ])
                  pinSheetRow(
                    sheetContext,
                    sheetRef,
                    target,
                    onTap: () {
                      close();
                      unawaited(
                        togglePinCaptured(
                          messenger: messenger,
                          l10n: l10n,
                          pinned: pinnedController,
                          pid: target.pid,
                          label: target.name,
                        ),
                      );
                    },
                  ),
              if (music)
                WaxOptionRow(
                  title: l10n.playerInstantMix,
                  glyph: WaxIcons.waveform,
                  semanticsId: SemanticsIds.itemMenuMix,
                  onTap: () {
                    close();
                    unawaited(
                      showInstantMixSheet(rootContext, (
                        pid: pid,
                        title: title,
                      )),
                    );
                  },
                ),
              // The escape hatch for a track a release id put on the
              // wrong album: it leaves for the album its own tags
              // imply. Behind the editor gate, because it is a catalog
              // write - and behind the album's own mbid, because the
              // server refuses a chain that carries none, which is
              // every album in a library that has never run matching.
              // Offering it there would be a confirmation promising to
              // rewrite tags, answered by a refusal.
              if (music &&
                  albumPid != null &&
                  mayOfferItemEdit(sheetRef) &&
                  (sheetRef.watch(albumDetailProvider(albumPid)).value?.mbid ??
                          '')
                      .isNotEmpty)
                WaxOptionRow(
                  title: l10n.libraryMenuDetach,
                  glyph: WaxIcons.detach,
                  semanticsId: SemanticsIds.itemMenuDetach,
                  onTap: () {
                    close();
                    unawaited(confirmDetachItem(rootContext, pid: pid));
                  },
                ),
              if (music && albumPid != null)
                WaxOptionRow(
                  title: l10n.libraryMenuShareAlbum,
                  subtitle: album,
                  glyph: WaxIcons.share,
                  semanticsId: SemanticsIds.itemMenuShare,
                  onTap: () {
                    close();
                    unawaited(showShareLinkDialog(rootContext, pid: albumPid));
                  },
                ),
              // A track's share rides its album, above; an episode or a
              // book shares itself, the way its own screen and the player
              // do.
              if (!music)
                WaxOptionRow(
                  title: l10n.playerShareLink,
                  glyph: WaxIcons.share,
                  semanticsId: SemanticsIds.itemMenuShareItem,
                  onTap: () {
                    close();
                    unawaited(showShareLinkDialog(rootContext, pid: pid));
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// The overflow sheet behind an album entity row - an index bucket, a
/// search hit - where the row names a release rather than an item in
/// one. Pin, which is the affordance these rows always had, plus the
/// two things an album pid supports from anywhere: a share link and an
/// instant mix seeded by the release.
Future<void> showAlbumMenuSheet(
  BuildContext context,
  WidgetRef ref, {
  required String pid,
  required String title,
}) async {
  // Captured for the reason the item menu writes out.
  final rootContext = Navigator.of(context, rootNavigator: true).context;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final pinnedController = ref.read(pinnedEntitiesProvider.notifier);
  final PinTarget target = (pid: pid, what: 'album', name: title);
  await showWaxOptionSheet(
    context,
    builder: (sheetContext) => Consumer(
      builder: (_, sheetRef, _) {
        void close() => Navigator.of(sheetContext).pop();
        // Named for its entity, for the reason the item sheet's is.
        return Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.itemMenuSheet(pid),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              pinSheetRow(
                sheetContext,
                sheetRef,
                target,
                onTap: () {
                  close();
                  unawaited(
                    togglePinCaptured(
                      messenger: messenger,
                      l10n: l10n,
                      pinned: pinnedController,
                      pid: pid,
                      label: title,
                    ),
                  );
                },
              ),
              WaxOptionRow(
                title: l10n.playerInstantMix,
                glyph: WaxIcons.waveform,
                semanticsId: SemanticsIds.itemMenuMix,
                onTap: () {
                  close();
                  unawaited(
                    showInstantMixSheet(rootContext, (pid: pid, title: title)),
                  );
                },
              ),
              WaxOptionRow(
                title: l10n.libraryMenuShareAlbum,
                glyph: WaxIcons.share,
                semanticsId: SemanticsIds.itemMenuShare,
                onTap: () {
                  close();
                  unawaited(showShareLinkDialog(rootContext, pid: pid));
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}
