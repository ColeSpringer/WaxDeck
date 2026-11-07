/// Hand-written repository layer over the generated WaxDeck API client.
///
/// App code imports this package only; the generated `waxdeck_api_gen`
/// package (dart-dio + built_value) is an implementation detail behind it,
/// so generator churn never ripples into feature code.
library;

export 'src/api/admin_api.dart';
export 'src/api/auth_api.dart';
export 'src/api/books_api.dart';
export 'src/api/discovery_api.dart';
export 'src/api/enrichment_api.dart';
export 'src/api/health_api.dart';
export 'src/api/library_api.dart';
export 'src/api/media_urls_api.dart';
export 'src/api/metadata_api.dart';
export 'src/api/notifications_api.dart';
export 'src/api/organize_api.dart';
export 'src/api/playback_api.dart';
export 'src/api/player_api.dart';
export 'src/api/playlists_api.dart';
export 'src/api/podcasts_api.dart';
export 'src/api/radio_api.dart';
export 'src/api/review_api.dart';
export 'src/api/scrobbling_api.dart';
export 'src/api/shares_api.dart';
export 'src/api/similarity_api.dart';
export 'src/api/stats_api.dart';
export 'src/api/sync_api.dart';
export 'src/api/system_api.dart';
export 'src/api/tools_api.dart';
export 'src/api/uploads_api.dart';
export 'src/api/users_api.dart';
export 'src/client.dart';
export 'src/models.dart';
export 'src/prefs_patch.dart';
export 'src/session_id.dart';
