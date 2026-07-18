//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'play_state_query.g.dart';

/// A batch play-state read request.
///
/// Properties:
/// * [pids] - Items to read the caller's state for.
@BuiltValue()
abstract class PlayStateQuery implements Built<PlayStateQuery, PlayStateQueryBuilder> {
  /// Items to read the caller's state for.
  @BuiltValueField(wireName: r'pids')
  BuiltList<String> get pids;

  PlayStateQuery._();

  factory PlayStateQuery([void updates(PlayStateQueryBuilder b)]) = _$PlayStateQuery;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayStateQueryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayStateQuery> get serializer => _$PlayStateQuerySerializer();
}

class _$PlayStateQuerySerializer implements PrimitiveSerializer<PlayStateQuery> {
  @override
  final Iterable<Type> types = const [PlayStateQuery, _$PlayStateQuery];

  @override
  final String wireName = r'PlayStateQuery';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayStateQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pids';
    yield serializers.serialize(
      object.pids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayStateQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayStateQueryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.pids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayStateQuery deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayStateQueryBuilder();
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

