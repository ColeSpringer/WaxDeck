//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'share.g.dart';

/// One public share link.
///
/// Properties:
/// * [pid] - Share PID.
/// * [url] - Origin-relative capability URL of the landing page. Anyone holding the full URL can open it; treat it as the secret it is. 
/// * [targetPid] - The shared track, album, playlist, book, or episode.
/// * [targetKind] - What kind of thing the share opens: `track`, `album`, `playlist`, `book`, or `episode`. A string, not a closed enum; clients must tolerate an unknown kind (render a generic label) rather than fail. 
/// * [targetTitle] - The target's display title at read time.
/// * [allowDownload] - Whether the landing page offers the original file.
/// * [positionMs] - Start position for copy-link-at-timestamp shares (episodes). Absent otherwise. 
/// * [createdAt] - When the share was created.
/// * [expiresAt] - When the link stops resolving. Absent for links without expiry. 
/// * [plays] - Anonymous plays through the link so far.
@BuiltValue()
abstract class Share implements Built<Share, ShareBuilder> {
  /// Share PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Origin-relative capability URL of the landing page. Anyone holding the full URL can open it; treat it as the secret it is. 
  @BuiltValueField(wireName: r'url')
  String get url;

  /// The shared track, album, playlist, book, or episode.
  @BuiltValueField(wireName: r'targetPid')
  String get targetPid;

  /// What kind of thing the share opens: `track`, `album`, `playlist`, `book`, or `episode`. A string, not a closed enum; clients must tolerate an unknown kind (render a generic label) rather than fail. 
  @BuiltValueField(wireName: r'targetKind')
  String get targetKind;

  /// The target's display title at read time.
  @BuiltValueField(wireName: r'targetTitle')
  String get targetTitle;

  /// Whether the landing page offers the original file.
  @BuiltValueField(wireName: r'allowDownload')
  bool get allowDownload;

  /// Start position for copy-link-at-timestamp shares (episodes). Absent otherwise. 
  @BuiltValueField(wireName: r'positionMs')
  int? get positionMs;

  /// When the share was created.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// When the link stops resolving. Absent for links without expiry. 
  @BuiltValueField(wireName: r'expiresAt')
  DateTime? get expiresAt;

  /// Anonymous plays through the link so far.
  @BuiltValueField(wireName: r'plays')
  int get plays;

  Share._();

  factory Share([void updates(ShareBuilder b)]) = _$Share;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ShareBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Share> get serializer => _$ShareSerializer();
}

class _$ShareSerializer implements PrimitiveSerializer<Share> {
  @override
  final Iterable<Type> types = const [Share, _$Share];

  @override
  final String wireName = r'Share';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Share object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    yield r'targetPid';
    yield serializers.serialize(
      object.targetPid,
      specifiedType: const FullType(String),
    );
    yield r'targetKind';
    yield serializers.serialize(
      object.targetKind,
      specifiedType: const FullType(String),
    );
    yield r'targetTitle';
    yield serializers.serialize(
      object.targetTitle,
      specifiedType: const FullType(String),
    );
    yield r'allowDownload';
    yield serializers.serialize(
      object.allowDownload,
      specifiedType: const FullType(bool),
    );
    if (object.positionMs != null) {
      yield r'positionMs';
      yield serializers.serialize(
        object.positionMs,
        specifiedType: const FullType(int),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.expiresAt != null) {
      yield r'expiresAt';
      yield serializers.serialize(
        object.expiresAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'plays';
    yield serializers.serialize(
      object.plays,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Share object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ShareBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'targetPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetPid = valueDes;
          break;
        case r'targetKind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetKind = valueDes;
          break;
        case r'targetTitle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetTitle = valueDes;
          break;
        case r'allowDownload':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.allowDownload = valueDes;
          break;
        case r'positionMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.positionMs = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        case r'plays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.plays = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Share deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ShareBuilder();
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

