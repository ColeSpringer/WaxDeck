//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'm3u_preview_request.g.dart';

/// An M3U8 document to match without importing it.
///
/// Properties:
/// * [content] - The M3U8 document text.
@BuiltValue()
abstract class M3uPreviewRequest implements Built<M3uPreviewRequest, M3uPreviewRequestBuilder> {
  /// The M3U8 document text.
  @BuiltValueField(wireName: r'content')
  String get content;

  M3uPreviewRequest._();

  factory M3uPreviewRequest([void updates(M3uPreviewRequestBuilder b)]) = _$M3uPreviewRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(M3uPreviewRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<M3uPreviewRequest> get serializer => _$M3uPreviewRequestSerializer();
}

class _$M3uPreviewRequestSerializer implements PrimitiveSerializer<M3uPreviewRequest> {
  @override
  final Iterable<Type> types = const [M3uPreviewRequest, _$M3uPreviewRequest];

  @override
  final String wireName = r'M3uPreviewRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    M3uPreviewRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'content';
    yield serializers.serialize(
      object.content,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    M3uPreviewRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required M3uPreviewRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'content':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.content = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  M3uPreviewRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = M3uPreviewRequestBuilder();
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


