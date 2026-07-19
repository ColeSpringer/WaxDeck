//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'package:dio/dio.dart';
import 'package:built_value/serializer.dart';
import 'package:waxdeck_api_gen/src/serializers.dart';
import 'package:waxdeck_api_gen/src/auth/api_key_auth.dart';
import 'package:waxdeck_api_gen/src/auth/basic_auth.dart';
import 'package:waxdeck_api_gen/src/auth/bearer_auth.dart';
import 'package:waxdeck_api_gen/src/auth/oauth.dart';
import 'package:waxdeck_api_gen/src/api/admin_api.dart';
import 'package:waxdeck_api_gen/src/api/auth_api.dart';
import 'package:waxdeck_api_gen/src/api/books_api.dart';
import 'package:waxdeck_api_gen/src/api/library_api.dart';
import 'package:waxdeck_api_gen/src/api/notifications_api.dart';
import 'package:waxdeck_api_gen/src/api/playback_api.dart';
import 'package:waxdeck_api_gen/src/api/playlists_api.dart';
import 'package:waxdeck_api_gen/src/api/podcasts_api.dart';
import 'package:waxdeck_api_gen/src/api/radio_api.dart';
import 'package:waxdeck_api_gen/src/api/scrobbling_api.dart';
import 'package:waxdeck_api_gen/src/api/sync_api.dart';
import 'package:waxdeck_api_gen/src/api/system_api.dart';
import 'package:waxdeck_api_gen/src/api/users_api.dart';

class WaxdeckApiGen {
  static const String basePath = r'/api/v1';

  final Dio dio;
  final Serializers serializers;

  WaxdeckApiGen({
    Dio? dio,
    Serializers? serializers,
    String? basePathOverride,
    List<Interceptor>? interceptors,
  })  : this.serializers = serializers ?? standardSerializers,
        this.dio = dio ??
            Dio(BaseOptions(
              baseUrl: basePathOverride ?? basePath,
              connectTimeout: const Duration(milliseconds: 5000),
              receiveTimeout: const Duration(milliseconds: 3000),
            )) {
    if (interceptors == null) {
      this.dio.interceptors.addAll([
        OAuthInterceptor(),
        BasicAuthInterceptor(),
        BearerAuthInterceptor(),
        ApiKeyAuthInterceptor(),
      ]);
    } else {
      this.dio.interceptors.addAll(interceptors);
    }
  }

  void setOAuthToken(String name, String token) {
    if (this.dio.interceptors.any((i) => i is OAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is OAuthInterceptor) as OAuthInterceptor).tokens[name] = token;
    }
  }

  void setBearerAuth(String name, String token) {
    if (this.dio.interceptors.any((i) => i is BearerAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BearerAuthInterceptor) as BearerAuthInterceptor).tokens[name] = token;
    }
  }

  void setBasicAuth(String name, String username, String password) {
    if (this.dio.interceptors.any((i) => i is BasicAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BasicAuthInterceptor) as BasicAuthInterceptor).authInfo[name] = BasicAuthInfo(username, password);
    }
  }

  void setApiKey(String name, String apiKey) {
    if (this.dio.interceptors.any((i) => i is ApiKeyAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((element) => element is ApiKeyAuthInterceptor) as ApiKeyAuthInterceptor).apiKeys[name] = apiKey;
    }
  }

  /// Get AdminApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  AdminApi getAdminApi() {
    return AdminApi(dio, serializers);
  }

  /// Get AuthApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  AuthApi getAuthApi() {
    return AuthApi(dio, serializers);
  }

  /// Get BooksApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  BooksApi getBooksApi() {
    return BooksApi(dio, serializers);
  }

  /// Get LibraryApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  LibraryApi getLibraryApi() {
    return LibraryApi(dio, serializers);
  }

  /// Get NotificationsApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  NotificationsApi getNotificationsApi() {
    return NotificationsApi(dio, serializers);
  }

  /// Get PlaybackApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  PlaybackApi getPlaybackApi() {
    return PlaybackApi(dio, serializers);
  }

  /// Get PlaylistsApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  PlaylistsApi getPlaylistsApi() {
    return PlaylistsApi(dio, serializers);
  }

  /// Get PodcastsApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  PodcastsApi getPodcastsApi() {
    return PodcastsApi(dio, serializers);
  }

  /// Get RadioApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  RadioApi getRadioApi() {
    return RadioApi(dio, serializers);
  }

  /// Get ScrobblingApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  ScrobblingApi getScrobblingApi() {
    return ScrobblingApi(dio, serializers);
  }

  /// Get SyncApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  SyncApi getSyncApi() {
    return SyncApi(dio, serializers);
  }

  /// Get SystemApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  SystemApi getSystemApi() {
    return SystemApi(dio, serializers);
  }

  /// Get UsersApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  UsersApi getUsersApi() {
    return UsersApi(dio, serializers);
  }
}
