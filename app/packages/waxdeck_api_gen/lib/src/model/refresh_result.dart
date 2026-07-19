//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refresh_result.g.dart';

/// Outcome of a feed refresh.
///
/// Properties:
/// * [newEpisodes] - Episodes that appeared in this refresh.
@BuiltValue()
abstract class RefreshResult implements Built<RefreshResult, RefreshResultBuilder> {
  /// Episodes that appeared in this refresh.
  @BuiltValueField(wireName: r'newEpisodes')
  int get newEpisodes;

  RefreshResult._();

  factory RefreshResult([void updates(RefreshResultBuilder b)]) = _$RefreshResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RefreshResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RefreshResult> get serializer => _$RefreshResultSerializer();
}

class _$RefreshResultSerializer implements PrimitiveSerializer<RefreshResult> {
  @override
  final Iterable<Type> types = const [RefreshResult, _$RefreshResult];

  @override
  final String wireName = r'RefreshResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RefreshResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'newEpisodes';
    yield serializers.serialize(
      object.newEpisodes,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RefreshResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RefreshResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'newEpisodes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.newEpisodes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RefreshResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RefreshResultBuilder();
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

