import 'package:web/web.dart' as web;

import 'page_thaws.dart';

/// Each time the browser thaws this page: a frozen page resumed (the Page
/// Lifecycle `resume`), or one restored from the back/forward cache; not
/// a hidden tab shown again.
Stream<void> pageResumes() => pageThaws(
  resumes: const web.EventStreamProvider<web.Event>(
    'resume',
  ).forTarget(web.document).map((_) {}),
  shows: web.EventStreamProviders.pageShowEvent
      .forTarget(web.window)
      .map((event) => (event as web.PageTransitionEvent).persisted),
);
