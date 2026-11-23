import '../../settings/client_settings/browser_settings_store.dart';

/// None: a native sign-out drops its token, and owes the server nothing.
BrowserStorage? owedRevokeStorage() => null;
