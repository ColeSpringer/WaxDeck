//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:waxdeck_api_gen/src/date_serializer.dart';
import 'package:waxdeck_api_gen/src/model/date.dart';

import 'package:waxdeck_api_gen/src/model/app_password.dart';
import 'package:waxdeck_api_gen/src/model/app_password_create.dart';
import 'package:waxdeck_api_gen/src/model/app_password_created.dart';
import 'package:waxdeck_api_gen/src/model/app_password_list.dart';
import 'package:waxdeck_api_gen/src/model/book_detail.dart';
import 'package:waxdeck_api_gen/src/model/book_part.dart';
import 'package:waxdeck_api_gen/src/model/book_resume.dart';
import 'package:waxdeck_api_gen/src/model/book_settings.dart';
import 'package:waxdeck_api_gen/src/model/bootstrap_request.dart';
import 'package:waxdeck_api_gen/src/model/bootstrap_status.dart';
import 'package:waxdeck_api_gen/src/model/cast_preflight.dart';
import 'package:waxdeck_api_gen/src/model/cast_preflight_base.dart';
import 'package:waxdeck_api_gen/src/model/catalog_sync_entry.dart';
import 'package:waxdeck_api_gen/src/model/catalog_sync_page.dart';
import 'package:waxdeck_api_gen/src/model/chapter_mark.dart';
import 'package:waxdeck_api_gen/src/model/device_session.dart';
import 'package:waxdeck_api_gen/src/model/discovery_list.dart';
import 'package:waxdeck_api_gen/src/model/download_file.dart';
import 'package:waxdeck_api_gen/src/model/download_info.dart';
import 'package:waxdeck_api_gen/src/model/episode.dart';
import 'package:waxdeck_api_gen/src/model/episode_page.dart';
import 'package:waxdeck_api_gen/src/model/episode_summary.dart';
import 'package:waxdeck_api_gen/src/model/error.dart';
import 'package:waxdeck_api_gen/src/model/health.dart';
import 'package:waxdeck_api_gen/src/model/item.dart';
import 'package:waxdeck_api_gen/src/model/item_page.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:waxdeck_api_gen/src/model/job.dart';
import 'package:waxdeck_api_gen/src/model/lastfm_connect_start.dart';
import 'package:waxdeck_api_gen/src/model/libraries.dart';
import 'package:waxdeck_api_gen/src/model/library_access.dart';
import 'package:waxdeck_api_gen/src/model/linked_identity.dart';
import 'package:waxdeck_api_gen/src/model/listen_brainz_connect.dart';
import 'package:waxdeck_api_gen/src/model/listen_ingest_result.dart';
import 'package:waxdeck_api_gen/src/model/listen_report.dart';
import 'package:waxdeck_api_gen/src/model/listen_session.dart';
import 'package:waxdeck_api_gen/src/model/login_request.dart';
import 'package:waxdeck_api_gen/src/model/login_response.dart';
import 'package:waxdeck_api_gen/src/model/lyrics.dart';
import 'package:waxdeck_api_gen/src/model/m3u_import.dart';
import 'package:waxdeck_api_gen/src/model/m3u_import_result.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:waxdeck_api_gen/src/model/model_library.dart';
import 'package:waxdeck_api_gen/src/model/notification_config.dart';
import 'package:waxdeck_api_gen/src/model/notification_config_update.dart';
import 'package:waxdeck_api_gen/src/model/oidc_exchange_request.dart';
import 'package:waxdeck_api_gen/src/model/oidc_provider.dart';
import 'package:waxdeck_api_gen/src/model/oidc_providers.dart';
import 'package:waxdeck_api_gen/src/model/opml_import.dart';
import 'package:waxdeck_api_gen/src/model/opml_import_entry.dart';
import 'package:waxdeck_api_gen/src/model/opml_import_result.dart';
import 'package:waxdeck_api_gen/src/model/password_change.dart';
import 'package:waxdeck_api_gen/src/model/play_info.dart';
import 'package:waxdeck_api_gen/src/model/play_state.dart';
import 'package:waxdeck_api_gen/src/model/play_state_list.dart';
import 'package:waxdeck_api_gen/src/model/play_state_query.dart';
import 'package:waxdeck_api_gen/src/model/play_state_update.dart';
import 'package:waxdeck_api_gen/src/model/playback_session.dart';
import 'package:waxdeck_api_gen/src/model/playback_session_create.dart';
import 'package:waxdeck_api_gen/src/model/playback_session_entry.dart';
import 'package:waxdeck_api_gen/src/model/playback_session_list.dart';
import 'package:waxdeck_api_gen/src/model/playback_session_transfer.dart';
import 'package:waxdeck_api_gen/src/model/player_endpoint.dart';
import 'package:waxdeck_api_gen/src/model/player_endpoint_list.dart';
import 'package:waxdeck_api_gen/src/model/playlist.dart';
import 'package:waxdeck_api_gen/src/model/playlist_create.dart';
import 'package:waxdeck_api_gen/src/model/playlist_entry.dart';
import 'package:waxdeck_api_gen/src/model/playlist_items_page.dart';
import 'package:waxdeck_api_gen/src/model/playlist_items_update.dart';
import 'package:waxdeck_api_gen/src/model/playlist_page.dart';
import 'package:waxdeck_api_gen/src/model/playlist_preview.dart';
import 'package:waxdeck_api_gen/src/model/playlist_update.dart';
import 'package:waxdeck_api_gen/src/model/podcast_detail.dart';
import 'package:waxdeck_api_gen/src/model/podcast_show.dart';
import 'package:waxdeck_api_gen/src/model/prefs.dart';
import 'package:waxdeck_api_gen/src/model/push_registration.dart';
import 'package:waxdeck_api_gen/src/model/push_registration_create.dart';
import 'package:waxdeck_api_gen/src/model/push_registration_list.dart';
import 'package:waxdeck_api_gen/src/model/radio_directory_entry.dart';
import 'package:waxdeck_api_gen/src/model/radio_directory_results.dart';
import 'package:waxdeck_api_gen/src/model/radio_play_info.dart';
import 'package:waxdeck_api_gen/src/model/radio_station.dart';
import 'package:waxdeck_api_gen/src/model/radio_station_edit.dart';
import 'package:waxdeck_api_gen/src/model/radio_station_list.dart';
import 'package:waxdeck_api_gen/src/model/rating_update.dart';
import 'package:waxdeck_api_gen/src/model/refresh_result.dart';
import 'package:waxdeck_api_gen/src/model/rejected_listen.dart';
import 'package:waxdeck_api_gen/src/model/role.dart';
import 'package:waxdeck_api_gen/src/model/rule_field.dart';
import 'package:waxdeck_api_gen/src/model/rule_fields.dart';
import 'package:waxdeck_api_gen/src/model/rule_node.dart';
import 'package:waxdeck_api_gen/src/model/rule_sort.dart';
import 'package:waxdeck_api_gen/src/model/rule_tag_key.dart';
import 'package:waxdeck_api_gen/src/model/scrobbler.dart';
import 'package:waxdeck_api_gen/src/model/scrobbler_list.dart';
import 'package:waxdeck_api_gen/src/model/search_hit.dart';
import 'package:waxdeck_api_gen/src/model/search_results.dart';
import 'package:waxdeck_api_gen/src/model/server_sync_event.dart';
import 'package:waxdeck_api_gen/src/model/server_sync_page.dart';
import 'package:waxdeck_api_gen/src/model/session_info.dart';
import 'package:waxdeck_api_gen/src/model/session_list.dart';
import 'package:waxdeck_api_gen/src/model/skip_map.dart';
import 'package:waxdeck_api_gen/src/model/skip_span.dart';
import 'package:waxdeck_api_gen/src/model/smart_rule.dart';
import 'package:waxdeck_api_gen/src/model/star_update.dart';
import 'package:waxdeck_api_gen/src/model/subscribe_request.dart';
import 'package:waxdeck_api_gen/src/model/subscription.dart';
import 'package:waxdeck_api_gen/src/model/subscription_page.dart';
import 'package:waxdeck_api_gen/src/model/subscription_settings.dart';
import 'package:waxdeck_api_gen/src/model/synced_line.dart';
import 'package:waxdeck_api_gen/src/model/timeline_boundary.dart';
import 'package:waxdeck_api_gen/src/model/timeline_create.dart';
import 'package:waxdeck_api_gen/src/model/timeline_info.dart';
import 'package:waxdeck_api_gen/src/model/transcript.dart';
import 'package:waxdeck_api_gen/src/model/transcript_cue.dart';
import 'package:waxdeck_api_gen/src/model/user.dart';
import 'package:waxdeck_api_gen/src/model/user_account.dart';
import 'package:waxdeck_api_gen/src/model/user_create.dart';
import 'package:waxdeck_api_gen/src/model/user_page.dart';
import 'package:waxdeck_api_gen/src/model/user_update.dart';
import 'package:waxdeck_api_gen/src/model/ws_ack_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_command_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_command_result_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_endpoint_command_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_error_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_event_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_ping_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_pong_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_register_endpoint_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_session_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_session_report_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_subscribe_frame.dart';
import 'package:waxdeck_api_gen/src/model/ws_watch_frame.dart';

part 'serializers.g.dart';

@SerializersFor([
  AppPassword,$AppPassword,
  AppPasswordCreate,
  AppPasswordCreated,
  AppPasswordList,
  BookDetail,
  BookPart,
  BookResume,
  BookSettings,
  BootstrapRequest,
  BootstrapStatus,
  CastPreflight,
  CastPreflightBase,
  CatalogSyncEntry,
  CatalogSyncPage,
  ChapterMark,
  DeviceSession,
  DiscoveryList,
  DownloadFile,
  DownloadInfo,
  Episode,
  EpisodePage,
  EpisodeSummary,$EpisodeSummary,
  Error,
  Health,
  Item,
  ItemPage,
  ItemSummary,$ItemSummary,
  Job,
  LastfmConnectStart,
  Libraries,
  LibraryAccess,
  LinkedIdentity,
  ListenBrainzConnect,
  ListenIngestResult,
  ListenReport,
  ListenSession,
  LoginRequest,
  LoginResponse,
  Lyrics,
  M3uImport,
  M3uImportResult,
  MediaType,
  ModelLibrary,
  NotificationConfig,
  NotificationConfigUpdate,
  OidcExchangeRequest,
  OidcProvider,
  OidcProviders,
  OpmlImport,
  OpmlImportEntry,
  OpmlImportResult,
  PasswordChange,
  PlayInfo,
  PlayState,
  PlayStateList,
  PlayStateQuery,
  PlayStateUpdate,
  PlaybackSession,
  PlaybackSessionCreate,
  PlaybackSessionEntry,
  PlaybackSessionList,
  PlaybackSessionTransfer,
  PlayerEndpoint,
  PlayerEndpointList,
  Playlist,
  PlaylistCreate,
  PlaylistEntry,
  PlaylistItemsPage,
  PlaylistItemsUpdate,
  PlaylistPage,
  PlaylistPreview,
  PlaylistUpdate,
  PodcastDetail,
  PodcastShow,
  Prefs,
  PushRegistration,
  PushRegistrationCreate,
  PushRegistrationList,
  RadioDirectoryEntry,
  RadioDirectoryResults,
  RadioPlayInfo,
  RadioStation,
  RadioStationEdit,
  RadioStationList,
  RatingUpdate,
  RefreshResult,
  RejectedListen,
  Role,
  RuleField,
  RuleFields,
  RuleNode,
  RuleSort,
  RuleTagKey,
  Scrobbler,
  ScrobblerList,
  SearchHit,
  SearchResults,
  ServerSyncEvent,
  ServerSyncPage,
  SessionInfo,
  SessionList,
  SkipMap,
  SkipSpan,
  SmartRule,
  StarUpdate,
  SubscribeRequest,
  Subscription,
  SubscriptionPage,
  SubscriptionSettings,
  SyncedLine,
  TimelineBoundary,
  TimelineCreate,
  TimelineInfo,
  Transcript,
  TranscriptCue,
  User,$User,
  UserAccount,
  UserCreate,
  UserPage,
  UserUpdate,
  WsAckFrame,
  WsCommandFrame,
  WsCommandResultFrame,
  WsEndpointCommandFrame,
  WsErrorFrame,
  WsEventFrame,
  WsPingFrame,
  WsPongFrame,
  WsRegisterEndpointFrame,
  WsSessionFrame,
  WsSessionReportFrame,
  WsSubscribeFrame,
  WsWatchFrame,
])
Serializers serializers = (_$serializers.toBuilder()
      ..add(AppPassword.serializer)
      ..add(EpisodeSummary.serializer)
      ..add(ItemSummary.serializer)
      ..add(User.serializer)
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer())
    ).build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
