import '../l10n/l10n.dart';

/// Why a move is held back, from its hold code; a code this build does
/// not name reads as held back for no named cause. A dry run's read-only
/// holds are the server's ([planned]): it leaves a read-only library's
/// files out instead. A run's are a library's, made read-only since.
String organizeHoldLabel(
  AppLocalizations l10n,
  String code, {
  bool planned = false,
}) => switch (code) {
  'collision' => l10n.organizeHoldCollision,
  'occupied' => l10n.organizeHoldOccupied,
  'occupied-case' => l10n.organizeHoldOccupiedCase,
  'untagged' => l10n.organizeHoldUntagged,
  'missing' => l10n.organizeHoldMissing,
  'virtual' => l10n.organizeHoldVirtual,
  'book-held' => l10n.organizeHoldBookHeld,
  'read-only' when planned => l10n.organizeHoldServerReadOnly,
  'read-only' => l10n.organizeHoldReadOnly,
  'moved-since' => l10n.organizeHoldMovedSince,
  'uncataloged' => l10n.organizeHoldUncataloged,
  _ => l10n.organizeHeldTile,
};
