import '../l10n/l10n.dart';

/// One artwork slot an item can hold. Only `front` walks the album and
/// artist chain; the rest resolve at the item's own level.
enum ArtSlot {
  front('front'),
  back('back'),
  disc('disc'),
  booklet('booklet'),
  background('background');

  const ArtSlot(this.role);

  final String role;

  /// The slot's name where it stands on its own, over its tile.
  String labelOf(AppLocalizations l10n) => switch (this) {
    front => l10n.artSlotFront,
    back => l10n.artSlotBack,
    disc => l10n.artSlotDisc,
    booklet => l10n.artSlotBooklet,
    background => l10n.artSlotBackground,
  };

  /// The same name inside a sentence, which English lower-cases and
  /// other languages may need an article for. A key of its own rather
  /// than a fold applied to the label: lower-casing is an English rule
  /// wearing a formatting disguise, and the sentences around it cannot
  /// know the gender of the words in this list.
  String inlineOf(AppLocalizations l10n) => switch (this) {
    front => l10n.artSlotFrontInline,
    back => l10n.artSlotBackInline,
    disc => l10n.artSlotDiscInline,
    booklet => l10n.artSlotBookletInline,
    background => l10n.artSlotBackgroundInline,
  };
}
