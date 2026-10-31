import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The whole [MediaListRow] whose content carries [identifier], which is
/// what takes a gesture: the identifier sits on the content, and a gesture
/// at the content's centre can fall in the row's blank space.
Finder rowWithIdentifier(String identifier) => find.ancestor(
  of: find.bySemanticsIdentifier(identifier),
  matching: find.byType(MediaListRow),
);
