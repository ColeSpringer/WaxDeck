//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rematch_result.g.dart';

/// The review entry a rematch opened.
///
/// Properties:
/// * [reviewEntryId] - The pending entry; candidates fill in asynchronously.
@BuiltValue()
abstract class RematchResult implements Built<RematchResult, RematchResultBuilder> {
  /// The pending entry; candidates fill in asynchronously.
  @BuiltValueField(wireName: r'reviewEntryId')
  String get reviewEntryId;

  RematchResult._();

  factory RematchResult([void updates(RematchResultBuilder b)]) = _$RematchResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RematchResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RematchResult> get serializer => _$RematchResultSerializer();
}

class _$RematchResultSerializer implements PrimitiveSerializer<RematchResult> {
  @override
  final Iterable<Type> types = const [RematchResult, _$RematchResult];

  @override
  final String wireName = r'RematchResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RematchResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'reviewEntryId';
    yield serializers.serialize(
      object.reviewEntryId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RematchResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RematchResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'reviewEntryId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reviewEntryId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RematchResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RematchResultBuilder();
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

