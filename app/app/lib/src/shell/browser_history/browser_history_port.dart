import 'package:flutter/foundation.dart';

/// Where the browser's session history reaches the navigation history.
abstract interface class BrowserHistoryPort {
  /// Whether an entry this app made lies behind the one shown, so a step
  /// back stays in the app.
  bool get canStepBack;

  /// Whether an entry this app made lies ahead of the one shown, so a
  /// step forward stays in the app.
  bool get canStepForward;

  /// Whether the browser knows which entry is the app's newest, which
  /// [canStepForward] is read from: after a fresh load (the entry loaded
  /// on is the newest), once the engine has pushed one, or as kept across
  /// a reload. Not after a return to the document from another, nor after
  /// a reload that kept nothing, until the engine pushes: [canStepForward]
  /// then answers false for an entry with the app's ahead of it too.
  bool get newestKnown;

  /// Whether the tab holds a page before the app's first entry, which a
  /// step back from that entry leaves the app for: as counted when the
  /// tab first loaded the app (see [entriesBeforeApp]). A browser that
  /// has since dropped its oldest entries may hold none any more, and a
  /// step back then goes nowhere.
  bool get canLeave;

  /// Where the entry shown stands among the app's: one up from the entry
  /// before it, so two positions are as many entries apart as they
  /// differ. Read at a browser move it is the entry moved to.
  int get position;

  /// Where the entry the router is on stands: the one it last reported,
  /// or the last browser move it heard of. Read at a browser move it is
  /// the entry moved from.
  int get shown;

  /// The location of the entry shown. Read at a browser move it is the
  /// entry moved to.
  String get location;

  /// The locations pushed over [location] in the entry shown, bottom
  /// first: an entry's URL is its base's.
  List<String> get pushes;

  /// The page keys of [pushes], in the same order: what tells two pushes
  /// of one location apart, which an entry keeps where it drops an extra.
  List<String> get pushKeys;

  /// Steps back one entry, as the browser's own button does. The router
  /// hears of the entry it lands on later, as of any browser move.
  void back();

  /// Steps [entries] entries at once: forward, or back where negative.
  void forward(int entries);

  /// Hands the router the entry shown, where the last browser move was
  /// one [listen]'s listener took and nothing has moved since, as if it
  /// had not taken it; false, having done nothing, otherwise.
  bool handOn();

  /// Holds every entry the router's engine writes from here on, until
  /// [release] or [drop]: a step asked of the browser has it away from the
  /// entry the engine writes to until it lands, and a move [listen]'s
  /// listener takes keeps it there.
  void hold();

  /// Writes what [hold] held, in order, now the browser is on the
  /// engine's entry again; with [past], the first is pushed past the
  /// entry the browser is on instead, which never came back to the
  /// engine's; with [over], it is written over that entry, which shows
  /// nothing to keep. False, having written nothing, where nothing was
  /// held.
  bool release({bool past = false, bool over = false});

  /// Forgets what [hold] held: the browser moved elsewhere, and the router
  /// follows it there.
  void drop();

  /// Calls [onMove] at each browser back or forward, before the router
  /// hears of the entry it moved to. Where [onMove] answers true the move
  /// is the app's own and the router never hears of it. The function
  /// returned stops it.
  VoidCallback listen(bool Function() onMove);
}

/// How many of the tab's entries lie before the app's first, as the
/// app's document finds it while it loads: after a fresh navigation (its
/// Navigation Timing type, [load], is `navigate`) the document's entry is
/// the newest, every one ahead dropped, so the rest of the tab's [length]
/// lie before it; after a reload or a return to it the count holds the
/// app's own entries and any ahead too, so it is the one the tab [kept]
/// from the fresh navigation, or none where it kept none.
int entriesBeforeApp(String load, {required int length, required int? kept}) =>
    load == 'navigate' ? length - 1 : kept ?? 0;

/// The newest entry of the app's, kept from before the document loaded
/// by [load] (its Navigation Timing type), as [kept] was stored: the same
/// after a reload, which keeps the tab's entries as they were; unknown
/// after any other load, which the tab may have dropped entries ahead of.
int? newestAcrossLoad(String load, {required int? kept}) =>
    load == 'reload' ? kept : null;

/// The locations pushed in [state], the router's state for an entry as
/// go_router encodes it: its imperative matches in tree order, so the
/// last is on top. None where it holds none.
List<String> pushedLocations(Object? state) => switch (state) {
  {'imperativeMatches': final List<Object?> matches} => [
    for (final match in matches)
      if (match case {'location': final String location}) location,
  ],
  _ => const <String>[],
};

/// The page keys of the pushes in [state], as [pushedLocations] reads
/// their locations.
List<String> pushedKeys(Object? state) => switch (state) {
  {'imperativeMatches': final List<Object?> matches} => [
    for (final match in matches)
      if (match case {'pageKey': final String key}) key,
  ],
  _ => const <String>[],
};
