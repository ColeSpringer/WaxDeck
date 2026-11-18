import 'browser_history_port.dart';

export 'browser_history_port.dart';

/// Native builds: no browser, so back is the app's own.
BrowserHistoryPort? createBrowserHistory() => null;
