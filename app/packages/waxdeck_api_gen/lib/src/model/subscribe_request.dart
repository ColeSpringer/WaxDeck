//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'subscribe_request.g.dart';

/// A subscription request.
///
/// Properties:
/// * [url] - Feed URL, or a YouTube channel or playlist URL when `sourceType` is `youtube`. 
/// * [sourceType] - Source kind: `rss` (default) or `youtube`. Open set for forward compatibility; servers reject values they do not support with `source-unavailable`. 
/// * [username] - Basic-auth username for a private feed.
/// * [password] - Basic-auth password for a private feed. Stored sealed at rest; never returned by any endpoint. 
/// * [folder] - Initial folder path for the subscription.
@BuiltValue()
abstract class SubscribeRequest implements Built<SubscribeRequest, SubscribeRequestBuilder> {
  /// Feed URL, or a YouTube channel or playlist URL when `sourceType` is `youtube`. 
  @BuiltValueField(wireName: r'url')
  String get url;

  /// Source kind: `rss` (default) or `youtube`. Open set for forward compatibility; servers reject values they do not support with `source-unavailable`. 
  @BuiltValueField(wireName: r'sourceType')
  String? get sourceType;

  /// Basic-auth username for a private feed.
  @BuiltValueField(wireName: r'username')
  String? get username;

  /// Basic-auth password for a private feed. Stored sealed at rest; never returned by any endpoint. 
  @BuiltValueField(wireName: r'password')
  String? get password;

  /// Initial folder path for the subscription.
  @BuiltValueField(wireName: r'folder')
  String? get folder;

  SubscribeRequest._();

  factory SubscribeRequest([void updates(SubscribeRequestBuilder b)]) = _$SubscribeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SubscribeRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SubscribeRequest> get serializer => _$SubscribeRequestSerializer();
}

class _$SubscribeRequestSerializer implements PrimitiveSerializer<SubscribeRequest> {
  @override
  final Iterable<Type> types = const [SubscribeRequest, _$SubscribeRequest];

  @override
  final String wireName = r'SubscribeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SubscribeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    if (object.sourceType != null) {
      yield r'sourceType';
      yield serializers.serialize(
        object.sourceType,
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
    if (object.folder != null) {
      yield r'folder';
      yield serializers.serialize(
        object.folder,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SubscribeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SubscribeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'sourceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceType = valueDes;
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
        case r'folder':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.folder = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SubscribeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SubscribeRequestBuilder();
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

