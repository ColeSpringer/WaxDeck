import 'package:flutter/widgets.dart';

/// A lazy list's `findChildIndexCallback` (`findItemIndexCallback` on
/// `ListView.separated`) for rows keyed by what they show, so a row moves
/// with its item instead of handing its place, and its semantics node, to
/// whatever lands there.
///
/// Flutter resends a semantics node only when something besides its
/// identifier changed, so a node handed to another item by position keeps
/// the old item's identifier on the platform side, where e2e reads it. The
/// lookup is indexed once per list, on its first call; an item without a
/// key is matched by position.
ChildIndexGetter indexByKey<T>(List<T> items, Key? Function(T item) keyOf) {
  Map<Key, int>? index;
  return (key) => (index ??= <Key, int>{
    for (var i = 0; i < items.length; i++) ?keyOf(items[i]): i,
  })[key];
}
