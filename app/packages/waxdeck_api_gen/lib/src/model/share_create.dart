//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'share_create.g.dart';

/// A new share link.
///
/// Properties:
/// * [pid] - The track (`tr-`), album (`al-`), playlist (`pl-`), book (`bk-`), or episode (`ep-`) to share. An album share opens the album's tracks in order. Must be visible to the caller. 
/// * [expiresInHours] - Lifetime in hours from creation. Omitted means the link never expires (it can still be revoked). 
/// * [allowDownload] - Offer the original file on the landing page. Requires the caller's own download permission. 
/// * [positionMs] - Start position for copy-link-at-timestamp (episodes only; `invalid-request` on other kinds). 
@BuiltValue()
abstract class ShareCreate implements Built<ShareCreate, ShareCreateBuilder> {
  /// The track (`tr-`), album (`al-`), playlist (`pl-`), book (`bk-`), or episode (`ep-`) to share. An album share opens the album's tracks in order. Must be visible to the caller. 
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Lifetime in hours from creation. Omitted means the link never expires (it can still be revoked). 
  @BuiltValueField(wireName: r'expiresInHours')
  int? get expiresInHours;

  /// Offer the original file on the landing page. Requires the caller's own download permission. 
  @BuiltValueField(wireName: r'allowDownload')
  bool? get allowDownload;

  /// Start position for copy-link-at-timestamp (episodes only; `invalid-request` on other kinds). 
  @BuiltValueField(wireName: r'positionMs')
  int? get positionMs;

  ShareCreate._();

  factory ShareCreate([void updates(ShareCreateBuilder b)]) = _$ShareCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ShareCreateBuilder b) => b
      ..allowDownload = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<ShareCreate> get serializer => _$ShareCreateSerializer();
}

class _$ShareCreateSerializer implements PrimitiveSerializer<ShareCreate> {
  @override
  final Iterable<Type> types = const [ShareCreate, _$ShareCreate];

  @override
  final String wireName = r'ShareCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ShareCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    if (object.expiresInHours != null) {
      yield r'expiresInHours';
      yield serializers.serialize(
        object.expiresInHours,
        specifiedType: const FullType(int),
      );
    }
    if (object.allowDownload != null) {
      yield r'allowDownload';
      yield serializers.serialize(
        object.allowDownload,
        specifiedType: const FullType(bool),
      );
    }
    if (object.positionMs != null) {
      yield r'positionMs';
      yield serializers.serialize(
        object.positionMs,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ShareCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ShareCreateBuilder result,
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
        case r'expiresInHours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.expiresInHours = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ShareCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ShareCreateBuilder();
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

