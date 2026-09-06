//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/migration_options.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_create.g.dart';

/// A migration import to start.
///
/// Properties:
/// * [source_] - Where to pull from: `navidrome` and `subsonic` (a running server's Subsonic API), `audiobookshelf` (its REST API), `jellyfin` (its REST API), `lastfm` and `listenbrainz` (scrobbling history), or `spotify` (an account data export, staged first). An open string; unknown sources answer `invalid-request` naming the supported set. 
/// * [serverUrl] - The source server's base URL. Required for `navidrome`, `subsonic`, `audiobookshelf` and `jellyfin`; optional for `listenbrainz`, where it names a compatible server and defaults to `https://api.listenbrainz.org`. `lastfm` and `spotify` take none. 
/// * [accountId] - The account the imported state lands on. Defaults to the caller, which is what a household administrator moving their own library wants; naming another account is how the rest of the household is moved without knowing their passwords. The target must exist, be enabled, and not be a pending signup. 
/// * [username] - Login for Subsonic-API sources and Jellyfin; the account name to read for `lastfm` and `listenbrainz`. 
/// * [password] - Password for Subsonic-API sources and Jellyfin.
/// * [token] - API token for token-authenticated sources: an Audiobookshelf token, a Jellyfin API key (with `username` naming whose state to read), or a ListenBrainz user token. 
/// * [exportId] - A staged account export to read, from `stageMigrationExport`. Required for `spotify` and refused for every source that reads a server. 
/// * [options] 
/// * [dryRun] - Match and report without writing anything.
@BuiltValue()
abstract class MigrationCreate implements Built<MigrationCreate, MigrationCreateBuilder> {
  /// Where to pull from: `navidrome` and `subsonic` (a running server's Subsonic API), `audiobookshelf` (its REST API), `jellyfin` (its REST API), `lastfm` and `listenbrainz` (scrobbling history), or `spotify` (an account data export, staged first). An open string; unknown sources answer `invalid-request` naming the supported set. 
  @BuiltValueField(wireName: r'source')
  String get source_;

  /// The source server's base URL. Required for `navidrome`, `subsonic`, `audiobookshelf` and `jellyfin`; optional for `listenbrainz`, where it names a compatible server and defaults to `https://api.listenbrainz.org`. `lastfm` and `spotify` take none. 
  @BuiltValueField(wireName: r'serverUrl')
  String? get serverUrl;

  /// The account the imported state lands on. Defaults to the caller, which is what a household administrator moving their own library wants; naming another account is how the rest of the household is moved without knowing their passwords. The target must exist, be enabled, and not be a pending signup. 
  @BuiltValueField(wireName: r'accountId')
  String? get accountId;

  /// Login for Subsonic-API sources and Jellyfin; the account name to read for `lastfm` and `listenbrainz`. 
  @BuiltValueField(wireName: r'username')
  String? get username;

  /// Password for Subsonic-API sources and Jellyfin.
  @BuiltValueField(wireName: r'password')
  String? get password;

  /// API token for token-authenticated sources: an Audiobookshelf token, a Jellyfin API key (with `username` naming whose state to read), or a ListenBrainz user token. 
  @BuiltValueField(wireName: r'token')
  String? get token;

  /// A staged account export to read, from `stageMigrationExport`. Required for `spotify` and refused for every source that reads a server. 
  @BuiltValueField(wireName: r'exportId')
  String? get exportId;

  @BuiltValueField(wireName: r'options')
  MigrationOptions? get options;

  /// Match and report without writing anything.
  @BuiltValueField(wireName: r'dryRun')
  bool? get dryRun;

  MigrationCreate._();

  factory MigrationCreate([void updates(MigrationCreateBuilder b)]) = _$MigrationCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationCreateBuilder b) => b
      ..dryRun = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationCreate> get serializer => _$MigrationCreateSerializer();
}

class _$MigrationCreateSerializer implements PrimitiveSerializer<MigrationCreate> {
  @override
  final Iterable<Type> types = const [MigrationCreate, _$MigrationCreate];

  @override
  final String wireName = r'MigrationCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(String),
    );
    if (object.serverUrl != null) {
      yield r'serverUrl';
      yield serializers.serialize(
        object.serverUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.accountId != null) {
      yield r'accountId';
      yield serializers.serialize(
        object.accountId,
        specifiedType: const FullType(String),
      );
    }
    if (object.username != null) {
      yield r'username';
      yield serializers.serialize(
        object.username,
        specifiedType: const FullType(String),
      );
    }
    if (object.password != null) {
      yield r'password';
      yield serializers.serialize(
        object.password,
        specifiedType: const FullType(String),
      );
    }
    if (object.token != null) {
      yield r'token';
      yield serializers.serialize(
        object.token,
        specifiedType: const FullType(String),
      );
    }
    if (object.exportId != null) {
      yield r'exportId';
      yield serializers.serialize(
        object.exportId,
        specifiedType: const FullType(String),
      );
    }
    if (object.options != null) {
      yield r'options';
      yield serializers.serialize(
        object.options,
        specifiedType: const FullType(MigrationOptions),
      );
    }
    if (object.dryRun != null) {
      yield r'dryRun';
      yield serializers.serialize(
        object.dryRun,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.source_ = valueDes;
          break;
        case r'serverUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serverUrl = valueDes;
          break;
        case r'accountId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accountId = valueDes;
          break;
        case r'username':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.username = valueDes;
          break;
        case r'password':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.password = valueDes;
          break;
        case r'token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.token = valueDes;
          break;
        case r'exportId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.exportId = valueDes;
          break;
        case r'options':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationOptions),
          ) as MigrationOptions;
          result.options.replace(valueDes);
          break;
        case r'dryRun':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.dryRun = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationCreateBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

