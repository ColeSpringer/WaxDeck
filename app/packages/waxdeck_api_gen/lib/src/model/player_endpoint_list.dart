//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/player_endpoint.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'player_endpoint_list.g.dart';

/// The endpoints visible to the caller.
///
/// Properties:
/// * [endpoints] 
@BuiltValue()
abstract class PlayerEndpointList implements Built<PlayerEndpointList, PlayerEndpointListBuilder> {
  @BuiltValueField(wireName: r'endpoints')
  BuiltList<PlayerEndpoint> get endpoints;

  PlayerEndpointList._();

  factory PlayerEndpointList([void updates(PlayerEndpointListBuilder b)]) = _$PlayerEndpointList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayerEndpointListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayerEndpointList> get serializer => _$PlayerEndpointListSerializer();
}

class _$PlayerEndpointListSerializer implements PrimitiveSerializer<PlayerEndpointList> {
  @override
  final Iterable<Type> types = const [PlayerEndpointList, _$PlayerEndpointList];

  @override
  final String wireName = r'PlayerEndpointList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayerEndpointList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'endpoints';
    yield serializers.serialize(
      object.endpoints,
      specifiedType: const FullType(BuiltList, [FullType(PlayerEndpoint)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayerEndpointList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayerEndpointListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'endpoints':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlayerEndpoint)]),
          ) as BuiltList<PlayerEndpoint>;
          result.endpoints.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayerEndpointList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayerEndpointListBuilder();
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

