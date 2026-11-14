import 'package:web/web.dart' as web;

/// Each time the browser says it is online again.
Stream<void> networkReturns() =>
    web.EventStreamProviders.onlineEvent.forTarget(web.window).map((_) {});
