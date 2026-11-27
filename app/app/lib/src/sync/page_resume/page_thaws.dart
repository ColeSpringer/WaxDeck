import 'dart:async';

/// The page came back from a stop in which it ran nothing: [resumes] is
/// each Page Lifecycle `resume` (Chromium thawing a frozen page), [shows]
/// each `pageshow` and whether the page was restored from the
/// back/forward cache (Firefox and Safari, which fire no `resume`).
///
/// Listened to by each binder in turn, so every listen listens anew.
Stream<void> pageThaws({
  required Stream<void> resumes,
  required Stream<bool> shows,
}) => Stream<void>.multi((thaws) {
  final resumed = resumes.listen((_) => thaws.add(null));
  final shown = shows.listen((restored) {
    if (restored) thaws.add(null);
  });
  thaws.onCancel = () => Future.wait([resumed.cancel(), shown.cancel()]);
}, isBroadcast: true);
