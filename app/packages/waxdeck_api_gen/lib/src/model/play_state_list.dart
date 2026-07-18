//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/play_state.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'play_state_list.g.dart';

/// The caller's playback states for a requested batch.
///
/// Properties:
/// * [states] - One entry per requested item with recorded state; items with zero state are absent. 
@BuiltValue()
abstract class PlayStateList implements Built<PlayStateList, PlayStateListBuilder> {
  /// One entry per requested item with recorded state; items with zero state are absent. 
  @BuiltValueField(wireName: r'states')
  BuiltList<PlayState> get states;

  PlayStateList._();

  factory PlayStateList([void updates(PlayStateListBuilder b)]) = _$PlayStateList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayStateListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayStateList> get serializer => _$PlayStateListSerializer();
}

class _$PlayStateListSerializer implements PrimitiveSerializer<PlayStateList> {
  @override
  final Iterable<Type> types = const [PlayStateList, _$PlayStateList];

  @override
  final String wireName = r'PlayStateList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayStateList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'states';
    yield serializers.serialize(
      object.states,
      specifiedType: const FullType(BuiltList, [FullType(PlayState)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayStateList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayStateListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'states':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlayState)]),
          ) as BuiltList<PlayState>;
          result.states.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayStateList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayStateListBuilder();
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

