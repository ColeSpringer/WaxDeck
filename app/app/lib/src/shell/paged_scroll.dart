import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Pages a screen's listing as its scroll nears the end, and once after a
/// layout that left nothing to scroll.
mixin PagedScroll<T extends StatefulWidget> on State<T> {
  /// The screen's scroll. A listener sees only the scroll it is attached
  /// to, so a horizontal shelf inside the page never reads as its end.
  final ScrollController pagedScroll = ScrollController();

  /// How close to the end a scroll asks for more.
  double get pageAhead => 400;

  /// The listing's next page; the notifier refuses a repeat.
  void loadMore();

  @override
  void initState() {
    super.initState();
    pagedScroll.addListener(_nearEnd);
  }

  @override
  void dispose() {
    pagedScroll.dispose();
    super.dispose();
  }

  void _nearEnd() {
    if (!pagedScroll.hasClients) return;
    final position = pagedScroll.position;
    if (position.pixels >= position.maxScrollExtent - pageAhead) loadMore();
  }

  /// The loaded list the fill last asked over.
  List<Object?>? _filledAt;

  /// From build: a list that does not reach past the viewport cannot
  /// scroll, so it asks once laid out, while [more]. Once per loaded list
  /// [at], by identity: a next page that fails keeps the list it had, so
  /// its retry is the screen's own or a scroll, never a read per frame,
  /// while a page that lands or a reload brings a new one, whatever its
  /// length.
  void fillViewportWhile(bool more, {required List<Object?>? at}) {
    if (!more || identical(at, _filledAt)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !pagedScroll.hasClients || identical(at, _filledAt)) {
        return;
      }
      final position = pagedScroll.position;
      if (position.maxScrollExtent > position.minScrollExtent) return;
      _filledAt = at;
      loadMore();
    });
  }
}
