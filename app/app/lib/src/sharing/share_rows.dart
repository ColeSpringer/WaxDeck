import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';

/// The share-link rows both listings draw: a listener auditing their own
/// links, and the console's oversight of everyone's.
///
/// One widget because a link reads the same either way - what it opens,
/// how much it has been used, when it dies - and the actions are the
/// same two. The only difference is the owner, which the personal
/// listing never carries because every row there would name the caller.
class ShareRows extends StatelessWidget {
  const ShareRows({
    required this.rows,
    required this.onCopy,
    required this.onRevoke,
    super.key,
  });

  final List<Share> rows;
  final Future<void> Function(Share share) onCopy;
  final Future<void> Function(Share share) onRevoke;

  /// A share's target reads as its own medium, so the row's glyph says
  /// what the link opens rather than that it is a link. A playlist has
  /// no domain of its own and takes the music glyph, which is what it is
  /// made of.
  static WaxGlyph glyphFor(String kind) => switch (kind) {
    'episode' => WaxIcons.podcasts,
    'book' => WaxIcons.audiobooks,
    'playlist' => WaxIcons.playlists,
    _ => WaxIcons.music,
  };

  /// What a row says under its title: who minted it where that is not
  /// obvious, then what it opens, how much it has been used, and when it
  /// dies. That is the order somebody auditing links reads them in, and
  /// on the oversight listing the owner comes first because it is what
  /// turns a row into somebody's.
  static String captionFor(AppLocalizations l10n, Share share) {
    final expiresAt = share.expiresAt;
    final expired = expiresAt != null && expiresAt.isBefore(DateTime.now());
    final owner = share.owner;
    return <String>[
      if (owner != null && owner.isNotEmpty) owner,
      share.targetKind,
      share.plays == 1 ? '1 play' : '${share.plays} plays',
      if (expiresAt == null)
        'never expires'
      else if (expired)
        'expired ${l10n.formatDate(expiresAt)}'
      else
        'expires ${l10n.formatDate(expiresAt)}',
      if (share.allowDownload) 'download allowed',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    return SliverPadding(
      padding: sizeClass.gutter,
      sliver: SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final share = rows[index];
          return WaxOptionRow(
            glyph: glyphFor(share.targetKind),
            title: share.targetTitle,
            subtitle: captionFor(l10n, share),
            semanticsId: SemanticsIds.shareRow(share.pid),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                WaxIconButton(
                  glyph: WaxIcons.share,
                  label: 'Copy link',
                  semanticsId: SemanticsIds.shareCopy(share.pid),
                  onPressed: () => onCopy(share),
                ),
                WaxIconButton(
                  glyph: WaxIcons.close,
                  label: 'Revoke link',
                  semanticsId: SemanticsIds.shareRevoke(share.pid),
                  onPressed: () => onRevoke(share),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
