//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/share.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'share_page.g.dart';

/// One page of share links, newest first.
///
/// Properties:
/// * [shares] 
/// * [nextCursor] - Opaque cursor for the next page; absent on the last page.
@BuiltValue()
abstract class SharePage implements Built<SharePage, SharePageBuilder> {
  @BuiltValueField(wireName: r'shares')
  BuiltList<Share> get shares;

  /// Opaque cursor for the next page; absent on the last page.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  SharePage._();

  factory SharePage([void updates(SharePageBuilder b)]) = _$SharePage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SharePageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SharePage> get serializer => _$SharePageSerializer();
}

class _$SharePageSerializer implements PrimitiveSerializer<SharePage> {
  @override
  final Iterable<Type> types = const [SharePage, _$SharePage];

  @override
  final String wireName = r'SharePage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SharePage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'shares';
    yield serializers.serialize(
      object.shares,
      specifiedType: const FullType(BuiltList, [FullType(Share)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SharePage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SharePageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'shares':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Share)]),
          ) as BuiltList<Share>;
          result.shares.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SharePage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SharePageBuilder();
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

